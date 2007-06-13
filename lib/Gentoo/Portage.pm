package Gentoo::Portage;

use 5.008007;
use strict;
use warnings;

#use Shell qw(ebuild emerge);
#use Memoize;
#memoize('getAvailableVersions');
use Cwd qw(getcwd abs_path cwd);
use File::Find ();
use Shell::EnvImporter;

# Set the variable $File::Find::dont_use_nlink if you're using AFS,
# since AFS cheats.

# for the convenience of &wanted calls, including -eval statements:
use vars qw/*name *dir *prune/;
*name  = *File::Find::name;
*dir   = *File::Find::dir;
*prune = *File::Find::prune;

my @store_found_dirs;
my @store_found_ebuilds;
sub wanted;

# These libraries were influenced and largely written by
# Christian Hartmann <ian@gentoo.org> originally. All of the good
# parts are ian's - the rest is mcummings messing around.

require Exporter;

our @ISA = qw(Exporter Gentoo);

our @EXPORT = qw( generatePackageInfo getEnv getAltName getAvailableEbuilds getAvailableVersions generate_digest emerge_ebuild import_fields scanTree );

our $VERSION = '0.05';

sub JB {
    my $self = shift;
    return;
}
sub getEnv
{

    #IMPORT VARIABLES
    my $self   = shift;
    my $envvar = shift;
    my $filter = sub {
        my ($var, $value, $change) = @_;
        return ($var =~ /^$envvar$/);
    };

    foreach my $file ("$ENV{HOME}/.gcpanrc", "/etc/make.conf", "/etc/make.globals")
    {
        if (-f $file)
        {
            my $importer = Shell::EnvImporter->new(
                file          => $file,
                shell         => 'bash',
                import_filter => $filter,
            );
            $importer->shellobj->envcmd('set');
            $importer->run();
            if (defined($ENV{$envvar}) && ($ENV{$envvar} =~ m{\W*}))
            {
                my $tm = strip_env($ENV{$envvar});
                $importer->restore_env;
                return $tm;
            }

        }
    }
}

sub checkpath
{
    my $self       = shift;
    my $components = shift;
    my $path;
    if (ref($components) eq "ARRAY" || ref($components) eq "LIST")
    {
        for (@$components) { $path .= "/$_" }
    }
    elsif (!ref($components))
    {
        $path = $components;
    }
    else
    {
        return {"E" => "Failed to pass an ARRAY, LIST, or SCALAR for a path"}
    }
    if (-d $path)
    {
        if (!-w $path)
        {
            return {
                "PATH" => $path,
                "W"    => "Path not writeable",
            };
        }
        else
        {
            return {"PATH" => $path,};
        }
    }
    return;
}

sub strip_env
{
    my $key = shift;
    if (defined($ENV{$key}))
    {
        $ENV{$key} =~ s{\\n}{ }gxms;
        $ENV{$key} =~ s{\\|\'|\\'|\$|\s*$}{}gmxs;
        $key       =~ s{\s+}{ }gmxs;
        return $ENV{$key};
    }
    else
    {
        $key =~ s{\\n}{ }gxms;
        $key =~ s{(\'|\\|\\'|\$|\s*$)}{}gmxs;
        $key =~ s{\s+}{ }gmxs;
        return $key;
    }
}

sub generatePackageInfo
{

    my $self = shift;

    # Since all we are concerned with is the final name of the package, this
    # should be a safe substitution
    my ($ebuild_wanted) = @_;
    $ebuild_wanted =~ m{ExtUtils(::|-)MakeMaker}ixm
      and print_info('Skipping ExtUtils::MakeMaker dependency'), next;

    #In the event this is an upgrade, go ahead and do the lame s/-/::/
    $self->{upgrade} and $ebuild_wanted =~ s/-/::/gxms;

    # Grab specific info for this module
    spinner_start();
    if (!defined $self->{portage}{lc($ebuild_wanted)}{found})
    {

        # First, check to see if this came with the core perl install
        my $pkgdbdir = '/var/db/pkg/dev-lang/';
        my $s_perl   = new DirHandle($pkgdbdir);
        my $eb       = $ebuild_wanted;
        $eb =~ s{::}{/}gmxs;
        while (my $read = $s_perl->read)
        {
            if ((-d qq{$pkgdbdir/$read}) and ($read =~ m{^perl}xm))
            {
                open FH, '<', qq{$pkgdbdir/$read/CONTENTS} || die('Cannot open $read\'s CONTENTS');
                my @data = <FH>;
                close(FH);
                foreach (@data)
                {
                    my $thisfile = (split(/ /, $_))[1];
                    $thisfile =~ s{\.([A-Za-z]{1,3})$}{};
                    if (($thisfile =~ m{$eb}x) && !defined $self->{$passed_to_install{$eb}})
                    {
                        spinner_stop();
                        print_info("$ebuild_wanted is part of the core perl install");
                        return;
                    }
                }
                spinner_stop();
                last;
            }
        }

        unless (defined $upgrade or defined $passed_to_install{$ebuild_wanted})
        {

            # If we're still here, then we didn't come with perl
            $self->getCPANInfo($ebuild_wanted);
        }
    }
    spinner_stop();
    if (!$self->{cpan}{lc($ebuild_wanted)} && !defined $self->{portage}{lc($ebuild_wanted)}{found})
    {

        # Fallback to trying the /-/::/ trick - we avoid this the first time
        # in case the module actually employs a - in its name
        $ebuild_wanted =~ s/-/::/gxms;
        $verbose and print_info("Getting CPAN Info for $ebuild_wanted");
        spinner_start();
        $self->getCPANInfo($ebuild_wanted);
        spinner_stop();
    }

    # If we found something on cpan, transform the portage_name
    # It's possible to not find something on cpan at this point - we're just
    # trying to pre-seed the portage_name
    if ($self->{cpan}{lc($ebuild_wanted)})
    {
        spinner_start();
        $self->{cpan}{lc($ebuild_wanted)}{portage_name}    = $self->transformCPAN($self->{cpan}{lc($ebuild_wanted)}{src_uri}, 'n');
        $self->{cpan}{lc($ebuild_wanted)}{portage_version} = $self->transformCPAN($self->{cpan}{lc($ebuild_wanted)}{src_uri}, 'v');
        spinner_stop();
    }
    else
    {
        print_err("$ebuild_wanted is not a CPAN module!");
    }

    # Save a copy of the originally requested name for later use
    my $original_ebuild = $ebuild_wanted;

    # Simple transform of name to something portage friendly
    $ebuild_wanted =~ s/::/-/gxms;

    # Scan portage for the ebuild name
    if (   ($upgrade && !defined $passed_to_install{$ebuild_wanted})
        || (!$upgrade && defined $passed_to_install{$ebuild_wanted})
        || (!$upgrade && !defined $self->{portage}{lc($ebuild_wanted)}{found}))
    {

        # Ebuild wasn't found - scan for the nice version of the module name
        if (lc($self->{cpan}{lc($original_ebuild)}{portage_name}) eq 'perl') { return }
        scanTree($self->{cpan}{lc($original_ebuild)}{portage_name});

        # We had success in finding this module under a different name
        if (defined $self->{portage}{lc($self->{cpan}{lc($original_ebuild)}{portage_name})}{found})
        {
            $verbose and print_info('Found ebuild for CPAN name ' . $self->{cpan}{lc($original_ebuild)}{portage_name});
            $ebuild_wanted = $self->{cpan}{lc($original_ebuild)}{portage_name};
        }
    }
    else
    {
        $self->{cpan}{lc($original_ebuild)}{portage_name} = $ebuild_wanted;
    }

    # Second round - we've looked for the package in portage two different
    # ways now, time to get serious and create it ourselves
    if (!defined $self->{portage}{lc($ebuild_wanted)}{found})
    {

        # Generate info - nothing found currently in the tree
        $debug and $self->debug;
        if ($self->{cpan}{lc($original_ebuild)}{portage_name}
            && lc($self->{cpan}{lc($original_ebuild)}{portage_name}) ne 'perl')
        {

            # We have a cpan package that matches the request.
            # Let's unpack it and get all the deps out of it.
            spinner_start();
            $self->unpackModule($self->{cpan}{lc($original_ebuild)}{name});
            spinner_stop();

            foreach my $dep (keys %{$self->{cpan}{lc($original_ebuild)}{depends}})
            {
                defined $dep && $dep ne q{} or next;

                #next if (defined $dep && $dep ne '');
                $dep eq 'perl' and delete $self->{cpan}{lc($original_ebuild)}{depends}{$dep};

                $dep =~ m{ExtUtils(::|-)MakeMaker}imx and print_info('Skipping ExtUtils::MakeMaker dependency'), next;

                # Make sure we have information relevant to each of the deps
                $verbose and print_info("Checking on dependency $dep for $original_ebuild");
                $passed_to_install{$dep} or generatePackageInfo($dep);

                # Remove dep from list of modules to install later on - no
                # more dup'd installs!
                defined $passed_to_install{$dep} and delete $really_install{$dep};

                # Reindex one last time for anything we build after the fact
                scanTree($self->{cpan}{lc($dep)}{portage_name});
            }

            # Write ebuild here?
            $debug and $self->debug;

           #            my @overlays;
           #            if ($overlay) { @overlays = split q{ }, $overlay }
           #            else
           #            {
           #                push @overlays, '/var/tmp/g-cpan'
           #                  and $ENV{PORTDIR_OVERLAY} = '/var/tmp/g-cpan';
           #            }
           #            foreach my $target_dir (@overlays)
           #            {
           #                if (-d $target_dir)
           #                {
           #                    my $gcpan_dir = File::Spec->catdir($target_dir, 'perl-gcpan');
           #                    if (!-d $gcpan_dir)
           #                    {
           #                        $verbose and print_info("Create directory '$gcpan_dir'");
           #                        mkdir $gcpan_dir, 0755
           #                          or fatal(print_err("Couldn't create folder $gcpan_dir: $!"));
           #                    }
           #                    my $ebuild_dir = File::Spec->catdir($gcpan_dir, $self->{cpan}{lc($original_ebuild)}{portage_name});
           #                    if (!-d $ebuild_dir)
           #                    {
           #                        $verbose and print_info("Create directory '$ebuild_dir'");
           #                        mkdir $ebuild_dir, 0755
           #                          or fatal(print_err("Couldn't create folder $gcpan_dir: $!"));
           #                    }
           #                    my $files_dir = File::Spec->catdir($ebuild_dir, 'files');
           #                    if (!-d $files_dir)
           #                    {
           #                        $verbose and print_info("Create directory '$files_dir'");
           #                        mkdir $files_dir, 0755
           #                          or fatal(print_err("Couldn't create folder $gcpan_dir: $!"));
           #                    }
           #                    my $ebuild = File::Spec->catdir($ebuild_dir,
           #                        $self->{cpan}{lc($original_ebuild)}{portage_name} . '-' . $self->{cpan}{lc($original_ebuild)}{portage_version} . '.ebuild');
           #
           #                    # Break out if we already have an ebuild (upgrade or
           #                    # mistake in the code)
           #                    if (!-f $ebuild)
           #                    {
           #                        print_info('Generating ebuild for ' . $self->{cpan}{lc($original_ebuild)}{name});
           #                        my $EBUILD = IO::File->new($ebuild, '>')
           #                          or fatal(print_err("Couldn't open(write) file $ebuild: $!"));
           #                        print {$EBUILD} <<"HERE";
## Copyright 1999-2006 Gentoo Foundation
## Distributed under the terms of the GNU General Public License v2
## This ebuild generated by $prog $VERSION
            #
            #inherit perl-module
            #
            #S=\${WORKDIR}/$self->{'cpan'}{lc($original_ebuild)}{'portage_sdir'}
            #
            #DESCRIPTION="$self->{'cpan'}{lc($original_ebuild)}{'description'}"
            #HOMEPAGE="http://search.cpan.org/search?query=$self->{cpan}{lc($original_ebuild)}{portage_name}\&mode=dist"
            #SRC_URI="mirror://cpan/authors/id/$self->{'cpan'}{lc($original_ebuild)}{'src_uri'}"
            #
            #
            #IUSE=""
            #
            #SLOT="0"
            #LICENSE="|| ( Artistic GPL-2 )"
            #KEYWORDS="$keywords"
            #
            #HERE
            #
            #                        if (my @deps = keys %{$self->{cpan}{lc($original_ebuild)}{depends}})
            #                        {
            #                            print {$EBUILD} 'DEPEND=\"';
            #                            my %seen_deps;
            #                            foreach my $dep (@deps)
            #                            {
            #                                defined $dep && $dep ne q{} or next;
            #                                my $portage_name = lc($self->{cpan}{lc($dep)}{portage_name});
            #                                $portage_name =~ m{\S}mx or next;
            #
            #                                # Last ditch call to scanTree to make sure we
            #                                # have info
            #                                scanTree($portage_name);
            #                                next if ( defined $seen_deps{$portage_name} && $seen_deps{$portage_name} > 0 );
            #                                $seen_deps{$portage_name} = 1;
            #                                next
            #                                  unless (defined $self->{portage}{$portage_name}{category}
            #                                    && defined $self->{portage}{$portage_name}{name}) && ($self->{portage}{$portage_name}{name} =~ m/\S/);
            #                                $portage_name eq 'perl' || lc($portage_name) eq lc($self->{cpan}{lc($original_ebuild)}{portage_name})
            #                                  and next;
            #                                my ($eb_version, $cpan_version) =
            #                                  stripdown($self->{portage}{lc($portage_name)}{version}, $self->{cpan}{lc($dep)}{portage_version});
            #                                if (   defined $self->{cpan}{lc($dep)}{portage_version}
            #                                    && $self->{cpan}{lc($original_ebuild)}{depends}{$dep} ne '0'
            #                                    && int($eb_version) >= int($cpan_version)
            #                                    && $self->{cpan}{lc($original_ebuild)}{depends}{$dep} =~ m{\d}gx
            #                                    && $self->{portage}{$portage_name}{name} ne qq{module-build})
            #                                {
            #                                    print {$EBUILD} qq{>=$self->{portage}{$portage_name}{category}/$self->{portage}{$portage_name}{name}-};
            #                                    if (defined $eb_version)
            #                                    {
            #                                        print {$EBUILD} $self->{portage}{lc($portage_name)}{version};
            #                                    }
            #                                    else
            #                                    {
            #                                        print {$EBUILD} $self->{cpan}{lc($dep)}{portage_version};
            #                                    }
            #                                    print {$EBUILD} "\n\t";
            #                                }
            #                                else
            #                                {
            #                                    print {$EBUILD} qq{$self->{portage}{$portage_name}{category}/$self->{portage}{$portage_name}{name}\n\t};
            #                                }
            #                            }
            #                            print {$EBUILD} qq{dev-lang/perl\n};
            #                            if (defined $buildpkg or defined $buildpkgonly) {
            #                                print {$EBUILD} qq{\npkg_postinst() \{\n};
            #                                print {$EBUILD} qq{elog "If you redistribute this package, please remember to"\n};
            #                                print {$EBUILD} qq{elog "update /etc/portage/categories with an entry for perl-gpcan"\n};
            #
            #                                print {$EBUILD} qq{\}\n};
            #                            }
            #                            undef $EBUILD;
            #                            autoflush STDOUT 1;
            #                        }
            #                        if (-f $self->{cpan}{lc($original_ebuild)}{cpan_tarball})
            #                        {
            #                            $verbose and print_ok("Copying $self->{cpan}{lc($original_ebuild)}{cpan_tarball} to $self->{sources}");
            #                            copy($self->{cpan}{lc($original_ebuild)}{cpan_tarball}, $self->{sources});
            #                        }
            #                        print_info("Ebuild generated for $ebuild_wanted");
            #                        $self->generate_digest($ebuild);
            #                        if (
            #                            !$upgrade
            #                            || ($upgrade
            #                                && defined $passed_to_install{$self->{'cpan'}->{lc($original_ebuild)}->{'name'}})
            #                          )
            #                        {
            #                            my $portage_name = $self->{'cpan'}->{lc($original_ebuild)}->{'portage_name'};
            #                            $really_install{$portage_name} = 1;
            #                        }
            #                        last;
            #                    }
            #                    else
            #                    {
            #                        $upgrade and print_info("$ebuild_wanted already up to date") and last;
            #                        my $portage_name = $self->{'cpan'}->{lc($original_ebuild)}->{'portage_name'};
            #                        $really_install{$portage_name} = 1;
            #                    }
            #                }
            #            }
        }
    }
    else
    {
        print_ok("Ebuild already exists for $ebuild_wanted ("
              . $self->{'portage'}{lc($ebuild_wanted)}{'category'} . "/"
              . $self->{'portage'}{lc($ebuild_wanted)}{'name'}
              . ")");
        if (defined $passed_to_install{$ebuild_wanted} || defined $passed_to_install{$original_ebuild})
        {
            $really_install{$self->{portage}{lc($ebuild_wanted)}{'name'}} = 1;
        }
    }
    return;
}

sub stripdown
{
    my ($eb, $mod) = @_;
    $eb  =~ s{_|-|\D+}{}gmxi;
    $mod =~ s{_|-|\D+}{}gmxi;

    if ($eb  =~ m{^\.}mx) { $eb  = "00$eb" }
    if ($mod =~ m{^\.}xm) { $mod = "00$mod" }
    my $e_in = q{};
    my $m_in = q{};

    my (@eb_ver)  = split /\./, $eb;
    my (@mod_ver) = split /\./, $mod;

    my $num_e = @eb_ver;
    my $num_m = @mod_ver;
    my $counter;

    if   ($num_e > $num_m) { $counter = $num_e }
    else                   { $counter = $num_m }
    $counter--;

    for (0 .. $counter)
    {
        if (!$mod_ver[$_])
        {
            $mod_ver[$_] = qq{00};
        }
        if (!$eb_ver[$_])
        {
            $eb_ver[$_] = qq{00};
        }
        if (length($eb_ver[$_]) > length($mod_ver[$_]))
        {
            while (length($eb_ver[$_]) > length($mod_ver[$_]))
            {
                $mod_ver[$_] .= qq{0};
            }
        }
        if (length($mod_ver[$_]) > length($eb_ver[$_]))
        {
            while (length($mod_ver[$_]) > length($eb_ver[$_]))
            {
                $eb_ver[$_] .= qq{0};
            }
        }
        $e_in .= "$eb_ver[$_]";
        $m_in .= "$mod_ver[$_]";

    }

    $e_in =~ s{\.$}{}xm;
    $m_in =~ s{\.$}{}xm;
    return ($eb, $mod);
}

sub scanTree
{
    my $self = shift;
    my ($module) = @_;
    $module or return;

    if ($module =~ /pathtools/gimx) { $module = "File-Spec" }
    foreach my $portage_root (keys %{$self->{portage_bases}})
    {
        if (-d $portage_root)
        {
            $verbose and print_ok("Scanning $portage_root for $module");
            $self->getAvailableVersions($self, $portage_root, $module);
        }

        # Pop out of the loop if we've found the module
        defined $self->{portage}{lc($module)}{found} and last;
    }
    return;
}

# Description:
# @listOfEbuilds = getAvailableEbuilds($PORTDIR, category/packagename);
sub getAvailableEbuilds
{
    my $self       = shift;
    my $portdir    = shift;
    my $catPackage = shift;
    @{$self->{packagelist}} = ();
    if (-e $portdir . "/" . $catPackage)
    {

        # - get list of ebuilds >
        my $startdir = &cwd;
        chdir($portdir . "/" . $catPackage);
        @store_found_ebuilds = [];
        File::Find::find({wanted => \&wanted_ebuilds}, ".");
        chdir($startdir);
        foreach (@store_found_ebuilds)
        {
            $_ =~ s{^\./}{}xms;
            if ($_ =~ m/(.+)\.ebuild$/)
            {
                next if ($_ eq "skel.ebuild");
                push(@{$self->{packagelist}}, $_);
            }
            else
            {
                if (-d $portdir . "/" . $catPackage . "/" . $_)
                {
                    $_ =~ s{^\./}{}xms;
                    my $startdir = &cwd;
                    chdir($portdir . "/" . $catPackage . "/" . $_);
                    @store_found_ebuilds = [];
                    File::Find::find({wanted => \&wanted_ebuilds}, ".");
                    chdir($startdir);
                    foreach (@store_found_ebuilds)
                    {

                        if ($_ =~ m/(.+)\.ebuild$/)
                        {
                            next if ($_ eq "skel.ebuild");
                            push(@{$self->{packagelist}}, $_);
                        }
                    }
                }
            }
        }
    }
    else
    {
        if (-d $portdir)
        {
            if ($self->{debug})
            {
                warn("\n" . $portdir . "/" . $catPackage . " DOESN'T EXIST\n");
            }
        }
        else
        {
            die("\nPORTDIR hasn't been defined!\n\n");
        }
    }

}

# Description:
# Returns version of an ebuild. (Without -rX string etc.)
# $version = getEbuildVersionSpecial("foo-1.23-r1.ebuild");
sub getEbuildVersionSpecial
{
    my $ebuildVersion = shift;
    $ebuildVersion = substr($ebuildVersion, 0, length($ebuildVersion) - 7);
    $ebuildVersion =~ s/^([a-zA-Z0-9\-_\/\+]*)-([0-9\.]+[a-zA-Z]?)([\-r|\-rc|_alpha|_beta|_pre|_p]?)/$2$3/;

    return $ebuildVersion;
}

sub getBestVersion
{
    my $self = shift;
    my ($find_ebuild, $portdir, $tc, $tp) = @_;
    getAvailableEbuilds($self, $portdir, $tc . "/" . $tp);

    foreach (@{$self->{packagelist}})
    {
        my @tmp_availableVersions = ();
        push(@tmp_availableVersions, getEbuildVersionSpecial($_));

        # - get highest version >
        if ($#tmp_availableVersions > -1)
        {
            $self->{'portage'}{lc($find_ebuild)}{'version'} = (sort(@tmp_availableVersions))[$#tmp_availableVersions];

            read_ebuild($self, $find_ebuild, $portdir, $tc, $tp, $_);

            # - get rid of -rX >
            $self->{'portage'}{lc($find_ebuild)}{'version'} =~ s/([a-zA-Z0-9\-_\/]+)-r[0-9+]/$1/;
            $self->{'portage'}{lc($find_ebuild)}{'version'} =~ s/([a-zA-Z0-9\-_\/]+)-rc[0-9+]/$1/;
            $self->{'portage'}{lc($find_ebuild)}{'version'} =~ s/([a-zA-Z0-9\-_\/]+)_p[0-9+]/$1/;
            $self->{'portage'}{lc($find_ebuild)}{'version'} =~ s/([a-zA-Z0-9\-_\/]+)_pre[0-9+]/$1/;

            # - get rid of other stuff we don't want >
            $self->{'portage'}{lc($find_ebuild)}{'version'} =~ s/([a-zA-Z0-9\-_\/]+)_alpha[0-9+]?/$1/;
            $self->{'portage'}{lc($find_ebuild)}{'version'} =~ s/([a-zA-Z0-9\-_\/]+)_beta[0-9+]?/$1/;
            $self->{'portage'}{lc($find_ebuild)}{'version'} =~ s/[a-zA-Z]+$//;

            if ($tc eq "perl-core"
                and (keys %{$self->{'portage_bases'}}))
            {

                # We have a perl-core module - can we satisfy it with a virtual/perl-?
                foreach my $portage_root (keys %{$self->{'portage_bases'}})
                {
                    if (-d $portage_root)
                    {
                        if (-d "$portage_root/virtual/perl-$tp")
                        {
                            $self->{'portage'}{lc($find_ebuild)}{'name'}     = "perl-$tp";
                            $self->{'portage'}{lc($find_ebuild)}{'category'} = "virtual";
                            last;
                        }
                    }
                }

            }
            else
            {
                $self->{'portage'}{lc($find_ebuild)}{'name'}     = $tp;
                $self->{'portage'}{lc($find_ebuild)}{'category'} = $tc;
            }

        }
    }
}

sub getAvailableVersions
{
    my $self        = shift;
    my $portdir     = shift;
    my $find_ebuild = shift;
    return if ($find_ebuild =~ m{::});
    my %excludeDirs = (
        "."         => 1,
        ".."        => 1,
        "metadata"  => 1,
        "licenses"  => 1,
        "eclass"    => 1,
        "distfiles" => 1,
        "virtual"   => 1,
        "profiles"  => 1
    );

    if ($find_ebuild)
    {
        return if (defined($self->{portage}{lc($find_ebuild)}{'found'}));
    }
    while (<DATA>)
    {
        my ($cat, $eb, $cpan_file) = split(/\s+|\t+/, $_);
        if ($cpan_file =~ m{^$find_ebuild$}i)
        {
            getBestVersion($self, $find_ebuild, $portdir, $cat, $eb);
            $self->{portage}{lc($find_ebuild)}{'found'}    = 1;
            $self->{portage}{lc($find_ebuild)}{'category'} = $cat;
            $self->{portage}{lc($find_ebuild)}{'name'}     = $eb;
            return;
        }
    }

    unless (defined($self->{'portage'}{lc($find_ebuild)}{'name'}))
    {

        foreach my $tc (@{$self->{portage_categories}})
        {
            next if (!-d "$portdir/$tc");
            @store_found_dirs = [];

            # Where we started
            my $startdir = &cwd;

            # chdir to our target dir
            chdir($portdir . "/" . $tc);

            # Traverse desired filesystems
            File::Find::find({wanted => \&wanted_dirs}, ".");

            # Return to where we started
            chdir($startdir);
            foreach my $tp (sort @store_found_dirs)
            {
                $tp =~ s{^\./}{}xms;

                # - not excluded and $_ is a dir?
                if (!$excludeDirs{$tp} && -d $portdir . "/" . $tc . "/" . $tp)
                {    #STARTS HERE
                    if ($find_ebuild)
                    {
                        next
                          unless (lc($find_ebuild) eq lc($tp));
                    }
                    getBestVersion($self, $find_ebuild, $portdir, $tc, $tp);
                }    #Ends here
            }
        }
    }
    if ($find_ebuild)
    {
        if (defined($self->{'portage'}{lc($find_ebuild)}{'name'}))
        {
            $self->{portage}{lc($find_ebuild)}{'found'} = 1;
            return;
        }
    }
    return ($self);
}

sub generate_digest
{
    my $self = shift;

    # Full path to the ebuild file in question
    my $ebuild = shift;
    system("ebuild", $ebuild, "digest");
}


sub emerge_ebuild
{
    my $self = shift;
    my @call = @_;

    # emerge forks and returns, which confuses this process. So
    # we call it the old fashioned way :(
    system("emerge", @call);
}

sub wanted_dirs
{
    my ($dev, $ino, $mode, $nlink, $uid, $gid);
    (($dev, $ino, $mode, $nlink, $uid, $gid) = lstat($_))
      && -d _
      && ($name !~ m|/files|)
      && ($name !~ m|/CVS|)
      && push @store_found_dirs, $name;
}

sub wanted_ebuilds
{
    /\.ebuild\z/s
      && push @store_found_ebuilds, $name;
}

sub DESTROY
{
    my ($self) = @_;
    return if $self->{DESTROY}{__PACKAGE__}++;
}

1;

=pod

=head1 NAME

Gentoo::Portage - perl access to portage information and commands

=head1 SYNOPSIS

    use Gentoo;
    my $obj = Gentoo->new();
    $obj->getAvailableEbuilds($portdir,'category');
    $obj->getAvailableVersions($portdir);
    
=head1 DESCRIPTION

The C<Gentoo::Portage> class provides access to portage tools and tree
information.

=head1 METHODS

=over 4

=item $obj->getAvailableEbuilds($portdir, $package);

Providing the PORTDIR you want to invesitage, and either the name of the
category or the category/package you are interested, this will populate an
array in $obj->{packagelist} of the available ebuilds.

=item $obj->getAvailableVersions($portdir,[$ebuildname])

Given the portage directory and the name of a package (optional), check
portage to see if the ebuild exists and which versions are available.

=item $obj->getEbuildVersionSpecial($ebuild)

Given the full name of an ebuild (foo-1.3.4-rc5.ebuild), this function will
return the actual version of the ebuild after stripping out the portage
related syntax.

=item $obj->generate_digest($path_to_ebuild)

Given the full path to an ebuild, generate a digest via C<ebuild PKG digest>

=item $obj->emerge_ebuild($pkg, @flags)

Given the name of a package and any optional flags, emerge the package with
portage.

=cut

__DATA__
dev-perl    XML-Sablot		XML-Sablotron
dev-perl    CPAN-Mini-Phalanx	CPAN-Mini-Phalanx100
perl-core   PodParser		Pod-Parser
dev-perl    Boulder			Stone
dev-perl    crypt-des-ede3		Crypt-DES_EDE3
dev-perl    DateManip		Date-Manip
dev-perl    DelimMatch		Text-DelimMatch
perl-core   File-Spec		PathTools
dev-perl    gimp-perl		Gimp
dev-perl    glib-perl		Glib
dev-perl    gnome2-perl		Gnome2
dev-perl    gnome2-vfs-perl		Gnome2-VFS
dev-perl    gtk2-perl		Gtk2
dev-perl    ImageInfo		Image-Info
dev-perl    ImageSize		Image-Size
dev-perl    Locale-gettext		gettext
dev-perl    Net-SSLeay		Net_SSLeay
dev-perl    OLE-StorageLite		OLE-Storage_Lite
dev-perl    PDF-Create      perl-pdf
dev-perl    perl-tk			Tk
dev-perl    perltidy		Perl-Tidy
dev-perl    RPM			Perl-RPM
dev-perl    sdl-perl		SDL_perl
dev-perl    SGMLSpm			SGMLSpmii
dev-perl    Term-ANSIColor		ANSIColor
perl-core   CGI			CGI.pm
dev-perl    Net-SSLeay		Net_SSLeay.pm
perl-core   digest-base		Digest
dev-perl    gtk2-fu			Gtk2Fu
dev-perl    Test-Builder-Tester	Test-Simple
dev-perl    wxperl			Wx
media-gfx   imagemagick        PerlMagick
