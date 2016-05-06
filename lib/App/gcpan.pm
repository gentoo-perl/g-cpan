package App::gcpan;

use strict;
use warnings;

use Carp;
use Cwd qw( getcwd abs_path cwd );
use DirHandle;
use File::Basename;
use File::Path;
use File::Spec;
use File::Copy;
use Gentoo;
use Gentoo::UI::Console;
use Getopt::Long;
use IO::File;
use Log::Agent;
use Log::Agent::Driver::File;
use Log::Agent::Driver::Silent;
use Term::ANSIColor;
use YAML;
use YAML::Node;

Getopt::Long::Configure('bundling');

our $VERSION = "0.16.6";
my $prog = basename($0);

##### Establish our tmpdir
unless ($ENV{TMPDIR}) { $ENV{TMPDIR} = '/var/tmp/g-cpan' }

my %dep_list = ();
my @perl_dirs = (qw( dev-perl perl-core perl-gcpan dev-lang ));

###############################
# Command line interpretation #
###############################

# Declare options
# First, the main switches
my @main_switches = \my ($search, $list, $install, $generate, $buildpkgonly);

# Then, additional switches
my @additional_switches = \my ($upgrade, $pretend, $buildpkg, $ask, $cpan_reload);

# Then, the normal options
my ($debug, $verbose, $log);

# Set colors here so we can use them at will anywhere :)
my $green = color("bold green");
my $white = color("bold white");
my $cyan  = color("bold cyan");
my $reset = color("reset");

# declare some variables (need to rework to avoid them in the future)
my ( $GCPAN_CAT, $GCPAN_OVERLAY );
my ( $gcpan_run, $keywords, $overlay );
my %passed_to_install;    # containing the original values passed for installing
my %really_install;       # will contain the portage friendly version of the values passed to install

sub run {

#Get & Parse them
GetOptions(
    'verbose|v'      => \$verbose,
    'search|s'       => \$search,
    'install|i'      => \$install,
    'upgrade|u'      => \$upgrade,
    'list|l'         => \$list,
    'log|L'          => \$log,
    'pretend|p'      => \$pretend,
    'buildpkg|b'     => \$buildpkg,
    'buildpkgonly|B' => \$buildpkgonly,
    'ask|a'          => \$ask,
    'generate|g'     => \$generate,
    'debug|d'        => \$debug,
    'cpan_reload'    => \$cpan_reload,
    'help|h'         => sub { exit_usage(); }
) or exit_usage();

if ($log)
{
    open my $log_test, q{>>}, "/var/log/$prog/$prog.err"
      or fatal(print_err("You don't have permission to perform logging to /var/log/$prog/$prog.err: $!"));
    close($log_test);

    my $log_driver = Log::Agent::Driver::File->make(
        -prefix     => "$prog",
        -magic_open => 0,
        -stampfmt   => 'date',
        -channels   => {
            'error'  => "/var/log/$prog/$prog.err",
            'output' => "/var/log/$prog/$prog.log",
        }
    );
    logconfig(-driver => $log_driver);
}
else
{
    my $log_driver = Log::Agent::Driver::Silent->make();
    logconfig(-driver => $log_driver);
}

print_warn("*WARNING* - logging debug output can create large logs") if ($log && $debug);

if (($install || $ask || $buildpkg || $buildpkgonly || $upgrade) && $> > 0 && !$pretend)
{
    print_err("INSUFFICIENT PERMISSIONS TO RUN EMERGE");
    logerr("ERROR - INSUFFICIENT PERMISSIONS TO RUN EMERGE");
    exit();
}

if (!$install && defined($ask))
{
    $install = 1;
}

@ARGV > 0
  and %passed_to_install = map { $_ => 1 } @ARGV;

# Output error if more than one main switch is activated
#

if ((grep { defined $$_ } @main_switches) > 1)
{
    print_err("You can't combine actions with each other.\n");
    print_out("${white}Please consult ${cyan}$prog ${green}--help${reset} or ${cyan}man $prog${reset} for more information\n\n");
    exit();
}

if (!grep { defined $$_ } @main_switches, @additional_switches)
{
    print_err("You haven't told $prog what to do.\n");
    print_out("${white}Please consult ${cyan}$prog ${green}--help${reset} or ${cyan}man $prog${reset} for more information\n\n");
    exit();
}

# Output error if no arguments
if (@ARGV == 0 && !(defined $upgrade || defined $list || defined $cpan_reload))
{
    print_err("Not even one module name or expression given!\n");
    print_out("${white}Please consult ${cyan}$prog ${green}--help${reset} for more information\n\n");
    exit();
}

######################
# CPAN Special Stuff #
######################

my $GentooCPAN = Gentoo->new();

# Don't do autointalls via ExtUtils::AutoInstall
$ENV{PERL_EXTUTILS_AUTOINSTALL} = "--skipdeps";
$ENV{PERL_MM_USE_DEFAULT}       = 1;

# Do we need to generate a config ?
eval "use CPAN::Config;";
my $needs_cpan_stub = $@ ? 1 : 0;

# Test Replacement - ((A&B)or(C&B)) should be the same as ((A or C) and B)
if (($needs_cpan_stub || $> > 0) && !-f "$ENV{HOME}/.cpan/CPAN/MyConfig.pm")
{

    # In case match comes from the UID test
    $needs_cpan_stub = 1;

    print_warn("No CPAN Config found, auto-generating a basic one");

    # Generate a fake config for CPAN
    $GentooCPAN->makeCPANstub();
}
else
{
    $needs_cpan_stub = 0;
}

use CPAN;

{
    foreach (qw[build sources])
    {
        if (-d "$ENV{TMPDIR}/.cpan/$_")
        {
            my $test_file = $ENV{TMPDIR} . "/.cpan/$_/test";
            my $test_tmp = IO::File->new($test_file, '>');
            if (defined($test_tmp))
            {
                undef $test_tmp;
                unlink($test_file);
            }
            else
            {
                print_err("No WRITE permissions in $ENV{TMPDIR}/.cpan/$_!!");
                print_err("Please run $prog as a user with sufficient permissions");
                print_err("or correct permissions in $ENV{TMPDIR}");
                exit;
            }
        }
    }
}
##########
# main() #
##########

$gcpan_run = Gentoo->new(
    'cpan_reload' => $cpan_reload,
    'DEBUG'       => $debug,
);

# Grab some configuration options for g-cpan
$GCPAN_CAT = $gcpan_run->getEnv('GCPAN_CAT');
$GCPAN_CAT = 'perl-gcpan' unless defined($GCPAN_CAT) and length($GCPAN_CAT) > 0;
# Push back to the env so we can use during cleanup
$ENV{GCPAN_CAT} = $GCPAN_CAT;

$GCPAN_OVERLAY = $gcpan_run->getEnv('GCPAN_OVERLAY') || 0;
# Ensure it's in the category list
if(length(grep {/$GCPAN_CAT/} @perl_dirs) == 0) {
	push @perl_dirs, $GCPAN_CAT;
}

# Confirm that there is an /etc/portage/categories file
# and that we have an entry for perl-gcpan in it.
my $cat_file = "/etc/portage/categories";
if (-f "$cat_file")
{

    #
    #  Use braces to localize the $/ assignment, so we don't get bitten later.
    #
    local $/ = undef;
    my $cat_read = IO::File->new($cat_file, '<');
    if (defined $cat_read)
    {
        my $data = <$cat_read>;
        undef $cat_read;
        autoflush STDOUT 1;
        unless ($data =~ m{$GCPAN_CAT}gmxi)
        {
            my $cat_write = IO::File->new($cat_file, '>>');
            if (defined $cat_write)
            {
                print $cat_write "$GCPAN_CAT\n";
                undef $cat_write;
                autoflush STDOUT 1;
            }
            else
            {
                print_err("Insufficient permissions to edit /etc/portage/categories");
                print_err("Please run $prog as a user with sufficient permissions");
                exit;
            }
        }
    }
}
else
{
    my $cat_write = IO::File->new($cat_file, '>');
    if (defined $cat_write)
    {
        print $cat_write "$GCPAN_CAT\n";
	undef $cat_write;
    }
    else
    {
        print_err("Insufficient permissions to edit /etc/portage/categories");
        print_err("Please run $prog as a user with sufficient permissions");
        exit;
    }
}

# Reset the object in case we created a new category.
$gcpan_run = Gentoo->new(
    'cpan_reload' => $cpan_reload,
    'DEBUG'       => $debug,
);

# If passed --cpan_reload and nothing else, just reload and exit.
if (@ARGV == 0 && defined $cpan_reload) {
	CPAN::Index->force_reload();
	exit;
}

# Get the main portdir
my $PORTAGE_DIR = $gcpan_run->getEnv('PORTDIR');
$gcpan_run->{portage_bases}{$PORTAGE_DIR} = 1;

# Grab the keywords - we'll need these when we build the ebuild
$keywords = $gcpan_run->getEnv('ACCEPT_KEYWORDS');
if ($keywords =~ m{ACCEPT_KEYWORDS}) { $keywords="" }
$keywords ||= do
{
    open my $tmp, '<', "$PORTAGE_DIR/profiles/arch.list"
      or fatal(print_err("ERROR READING $PORTAGE_DIR/profiles/arch.list: $!"));
    join ' ', map { chomp; s/^#.*$//g; $_ } <$tmp>;
};

$ENV{ACCEPT_KEYWORDS} = $keywords;
# Get the DISTDIR - we'd like store the tarballs in here the one time
$gcpan_run->{sources} = ($gcpan_run->getEnv('DISTDIR'));

# Make sure we have write access to the DISTDIR
if (   $generate
    || $install
    || $pretend
    || $buildpkg
    || $buildpkgonly
    || $ask
    || $upgrade)
{
    my $test_dist_writes = $gcpan_run->{sources} . '/test-gcpan';
    my $test_distdir = IO::File->new($test_dist_writes, '>');
    if ($test_distdir)
    {
        undef $test_distdir;
        unlink $test_dist_writes;
    }
    else
    {
        undef $test_distdir;
        fatal(print_err("No write access to DISTDIR: $!"));
    }
}

# Get the overlays
$overlay = $gcpan_run->getEnv('PORTDIR_OVERLAY');
if ($overlay)
{
    if ($overlay =~ m{\S*\s+\S*}x)
    {
        my @overlays = split ' ', $overlay;
        foreach (@overlays)
        {
            $gcpan_run->{portage_bases}{$_} = 1 if (-d $_);
        }
    }
    else
    {
        if (-d $overlay) { $gcpan_run->{portage_bases}{$overlay} = 1 }
    }
    unless (keys %{$gcpan_run->{portage_bases}} > 1)
    {
        fatal(print_err("DEFINED OVERLAYS DON'T EXIST!"));
    }

}
elsif ($generate || $list || $pretend)
{
    print_err("The option you have chosen isn't supported without a configured overlay.\n");
    exit();
}

# Set portage_categories to our defined list of perl_dirs
$gcpan_run->{portage_categories} = \@perl_dirs;

# Taking care of Searches.
if ($search)
{
    foreach my $expr (@ARGV)
    {
        my $tree_expr = $expr;
        $tree_expr =~ s/::/-/gxms;
        scanTree(lc($tree_expr));
        if (defined($gcpan_run->{portage}{lc($tree_expr)}{found}))
        {
            print_info("$gcpan_run->{portage}{lc($tree_expr)}{category}/$gcpan_run->{portage}{lc($tree_expr)}{name}");
            my $tdesc = strip_ends($gcpan_run->{portage}{lc($tree_expr)}{DESCRIPTION});
            my $thp   = strip_ends($gcpan_run->{portage}{lc($tree_expr)}{HOMEPAGE});
            print_info("DESCRIPTION: $tdesc");
            print_info("HOMEPAGE: $thp");
        }
        else
        {
            print_info("No ebuild exists, pulling up CPAN listings for $expr");
            my @search_results;

            # Assume they gave us module-name instead of module::name
            # which is bad, because CPAN can't convert it ;p

            $verbose and print_info("Searching for $expr on CPAN");

            # Let's define a CPAN::Frontend to use our printing methods

            spinner_start();
            if (!@search_results)
            {
                $expr =~ s{-}{::}gx;
				my @hold = CPAN::Shell->i("/$expr/");
				#if (grep { /\S{2,}/ } @hold)
				#{
				#   push @search_results, @hold;
				#}
            }

            # remove the spin
            spinner_stop();

			# UPDATE - this block doesn't work; the call to CPAN::Shell above doesn't return anything
            # now, @search_results should contain the matching modules strings, if any
			#if (@search_results)
			#{
				#print_info("Result(s) found :");
				#foreach (@search_results)
				#{
					#print_out("$_\n");
					#}
				#}
			#else
			#{
				#print_warn('no result found.');
				#}

        }
    }

    exit;
}

if ($list || $upgrade)
{
    if ($upgrade && @ARGV > 0)
    {
        %passed_to_install = map { $_ => 1 } @ARGV;
    }
    else
    {
        my @overlays = split ' ', $overlay;
        foreach my $overlay_dir (@overlays)
        {
            next unless -d $overlay_dir;
            my $gcpan_dir = File::Spec->catdir( $overlay_dir, $GCPAN_CAT );
            next unless -d $gcpan_dir;

            print_info("OVERLAY: $gcpan_dir");
            if (opendir PDIR, $gcpan_dir)
            {
                while (my $file = readdir PDIR)
                {
                    next if ($file eq '.' || $file eq '..');
                    $list and print_info("$GCPAN_CAT/$file");
                    $upgrade and $passed_to_install{$file} = 1;
                }
                closedir PDIR;
            }
            else
            {
                print_warn("Couldn't open folder $gcpan_dir: $!");
            }
        }
    }
}

if (   $generate
    || $install
    || $pretend
    || $buildpkg
    || $buildpkgonly
    || $ask
    || $upgrade)
{
	if (keys (%passed_to_install)) {
		generatePackageInfo($_) foreach (keys %passed_to_install);
	}
}

if (($install || $pretend || $buildpkg || $buildpkgonly || $upgrade || $ask)
	&& !( $generate))
{
    if (keys %really_install)
    {

        my @ebuilds = (keys %really_install);
        $verbose and print_info("Calling emerge for @ebuilds\n");
        my @flags;
        if ($pretend      && $pretend > 0)      { push @flags, '--pretend' }
        if ($ask          && $ask > 0)          { push @flags, '--ask' }
        if ($buildpkg     && $buildpkg > 0)     { push @flags, '--buildpkg' }
        if ($buildpkgonly && $buildpkgonly > 0) { push @flags, '--buildpkgonly' }
		if ($upgrade && $upgrade > 0) { push @flags, '--update' }

        $verbose and print_info("Calling: emerge @flags @ebuilds");
        $gcpan_run->emerge_ebuild(@ebuilds, @flags);

    }
    else
    {
        if ($upgrade)
        {
            print_info('Everything was up to date, nothing to do!');
        }
        else
        {
            print_err('Nothing to install!!');
        }
    }
}

}


sub generatePackageInfo
{

    # Since all we are concerned with is the final name of the package, this
    # should be a safe substitution
    my ($ebuild_wanted) = @_;
    $ebuild_wanted =~ m{ExtUtils(::|-)MakeMaker}ix
      and print_info('Skipping ExtUtils::MakeMaker dependency'), next;

    #In the event this is an upgrade, go ahead and do the lame s/-/::/
    $upgrade and $ebuild_wanted =~ s/-/::/gxms;

    # Grab specific info for this module
    spinner_start();
    unless (defined($gcpan_run->{portage}{lc($ebuild_wanted)}{found}))
    {

            # First, check to see if this came with the core perl install
            my $pkgdbdir = "/var/db/pkg/dev-lang/";
            my $s_perl   = new DirHandle($pkgdbdir);
            my $eb       = $ebuild_wanted;
            $eb =~ s{::}{/}gxs;
            $eb = '/' . $eb;
            # match entries like:
            # /usr/lib??/perl5/5.??.??/JSON/PP.pm
            # /usr/lib??/perl5/5.??.??/x86_64-linux/IO.pm
            my $file_wanted_re = qr/(?:5\.[\d\.]+)(?:\/x[\w-]+)?\Q$eb\E\.(?:[A-Za-z]{1,3})$/;
            while (defined(my $read = $s_perl->read))
            {
                if ((-d $pkgdbdir . "/" . $read) and ($read =~ m{^perl}x))
                {
                    open(FH, "<$pkgdbdir/$read/CONTENTS") || die("Cannot open $read\'s CONTENTS");
                    my @data = <FH>;
                    close(FH);
                    foreach (@data)
                    {
                        my ( $type, $file ) = split( / /, $_ );
                        next unless $type eq 'obj';
                        if ( $file =~ $file_wanted_re and not $passed_to_install{$eb} )
                        {
                            spinner_stop();
                            print_info("$ebuild_wanted is part of the core perl install (located: $file)");
                            return;
                        }
                    }
    				spinner_stop();
                    last;
                }
            }

        unless (defined($upgrade) or defined($passed_to_install{$ebuild_wanted}))
        {

            # If we're still here, then we didn't come with perl
            $gcpan_run->getCPANInfo($ebuild_wanted);
        }
    }
    spinner_stop();
    if (!$gcpan_run->{cpan}{lc($ebuild_wanted)} && !defined($gcpan_run->{portage}{lc($ebuild_wanted)}{found}))
    {

        # Fallback to trying the /-/::/ trick - we avoid this the first time
        # in case the module actually employs a - in its name
        $ebuild_wanted =~ s/-/::/gxms;
        $verbose and print_info("Getting CPAN Info for $ebuild_wanted");
        spinner_start();
        $gcpan_run->getCPANInfo($ebuild_wanted);
        spinner_stop();
    }

    # If we found something on cpan, transform the portage_name
    # It's possible to not find something on cpan at this point - we're just
    # trying to pre-seed the portage_name
    if ($gcpan_run->{cpan}{lc($ebuild_wanted)})
    {
        spinner_start();
        $gcpan_run->{cpan}{lc($ebuild_wanted)}{portage_name}    = $gcpan_run->transformCPAN($gcpan_run->{cpan}{lc($ebuild_wanted)}{src_uri}, 'n');
        $gcpan_run->{cpan}{lc($ebuild_wanted)}{portage_version} = $gcpan_run->transformCPAN($gcpan_run->{cpan}{lc($ebuild_wanted)}{src_uri}, 'v');
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
    if (   ($upgrade && !defined($passed_to_install{$ebuild_wanted}))
        || (!$upgrade && defined($passed_to_install{$ebuild_wanted}))
        || (!$upgrade && !defined($gcpan_run->{portage}{lc($ebuild_wanted)}{found})))
    {

        # Ebuild wasn't found - scan for the nice version of the module name
        if (lc($gcpan_run->{cpan}{lc($original_ebuild)}{portage_name}) eq 'perl') { return }
        scanTree($gcpan_run->{cpan}{lc($original_ebuild)}{portage_name});

        # We had success in finding this module under a different name
        if (defined($gcpan_run->{portage}{lc($gcpan_run->{cpan}{lc($original_ebuild)}{portage_name})}{found}))
        {
            $verbose and print_info('Found ebuild for CPAN name ' . $gcpan_run->{cpan}{lc($original_ebuild)}{portage_name});
            $ebuild_wanted = $gcpan_run->{cpan}{lc($original_ebuild)}{portage_name};
        }
    }
    else
    {
        $gcpan_run->{cpan}{lc($original_ebuild)}{portage_name} = $ebuild_wanted;
    }

    # Second round - we've looked for the package in portage two different
    # ways now, time to get serious and create it ourselves
    if (!defined($gcpan_run->{portage}{lc($ebuild_wanted)}{found}))
    {

        # Generate info - nothing found currently in the tree
        $debug and $gcpan_run->debug;
        if ($gcpan_run->{cpan}{lc($original_ebuild)}{portage_name}
            && lc($gcpan_run->{cpan}{lc($original_ebuild)}{portage_name}) ne 'perl')
        {

            # We have a cpan package that matches the request.
            # Let's unpack it and get all the deps out of it.
            spinner_start();
            $gcpan_run->unpackModule($gcpan_run->{cpan}{lc($original_ebuild)}{name});
            # Force re-compute of the information, as MANPAGE is now valid.
            $gcpan_run->getCPANInfo($original_ebuild);
            spinner_stop();

            foreach my $dep (keys %{$gcpan_run->{cpan}{lc($original_ebuild)}{depends}})
            {
                defined $dep && $dep ne '' or next;
				#next if (defined $dep && $dep ne '');
                $dep eq 'perl' and delete $gcpan_run->{cpan}{lc($original_ebuild)}{depends}{$dep};

                $dep =~ m{ExtUtils(::|-)MakeMaker}ix and print_info("Skipping ExtUtils::MakeMaker dependency"), next;

                # Make sure we have information relevant to each of the deps
                $verbose and print_info("Checking on dependency $dep for $original_ebuild");
                $passed_to_install{$dep} or generatePackageInfo($dep);

                # Remove dep from list of modules to install later on - no
                # more dup'd installs!
                defined $passed_to_install{$dep} and delete $really_install{$dep};

                # Reindex one last time for anything we build after the fact
                scanTree($gcpan_run->{cpan}{lc($dep)}{portage_name});
            }

            # Write ebuild here?
            $debug and $gcpan_run->debug;
            my @overlays;
            if ($GCPAN_OVERLAY)
            {
                push @overlays, $GCPAN_OVERLAY
            }
            elsif ($overlay)
            {
                @overlays = split ' ', $overlay
            }
            else
            {
                push @overlays, "/var/tmp/g-cpan"
                  and $ENV{PORTDIR_OVERLAY} = "/var/tmp/g-cpan";
            }
            foreach my $target_dir (@overlays)
            {
                if (-d $target_dir)
                {
                    my $gcpan_dir = File::Spec->catdir($target_dir, $GCPAN_CAT);
                    if (!-d $gcpan_dir)
                    {
                        $verbose and print_info("Create directory '$gcpan_dir'");
                        mkdir($gcpan_dir, 0755)
                          or fatal(print_err("Couldn't create folder $gcpan_dir: $!"));
                    }
                    my $ebuild_dir = File::Spec->catdir($gcpan_dir, $gcpan_run->{cpan}{lc($original_ebuild)}{portage_name});
                    if (!-d $ebuild_dir)
                    {
                        $verbose and print_info("Create directory '$ebuild_dir'");
                        mkdir($ebuild_dir, 0755)
                          or fatal(print_err("Couldn't create folder $gcpan_dir: $!"));
                    }
                    my $files_dir = File::Spec->catdir($ebuild_dir, 'files');
                    if (!-d $files_dir)
                    {
                        $verbose and print_info("Create directory '$files_dir'");
                        mkdir($files_dir, 0755)
                          or fatal(print_err("Couldn't create folder $gcpan_dir: $!"));
                    }
                    my $ebuild = File::Spec->catdir($ebuild_dir,
                        $gcpan_run->{cpan}{lc($original_ebuild)}{portage_name} . '-' . $gcpan_run->{cpan}{lc($original_ebuild)}{portage_version} . '.ebuild');

                    # Break out if we already have an ebuild (upgrade or
                    # mistake in the code)
                    if (!-f $ebuild)
                    {
                        print_info('Generating ebuild for ' . $gcpan_run->{cpan}{lc($original_ebuild)}{name});
                        my $EBUILD = IO::File->new($ebuild, '>')
                          or fatal(print_err("Couldn't open(write) file $ebuild: $!"));
                        my $module_author = $gcpan_run->{'cpan'}{lc($original_ebuild)}{'src_uri'};
                        $module_author =~ s/.\/..\/(.*)\/[^\/]+$/$1/g;
                        my $module_section = '';
                        if($module_author =~ /\//) {
                            $module_section = $module_author;
                            my @module_bits = split /\//, $module_author, 2;
                            $module_author = $module_bits[0];
                            $module_section = sprintf "MODULE_SECTION=\"%s\"\n", $module_bits[1];
                        }

                        # Detect the file extension, upstream usually uses .tar.gz, but not always
                        my $module_a_ext = '';
                        foreach my $ext (qw( tgz tbz2 tar.bz2 tar.xz tar.Z zip )) {
                            if ( $gcpan_run->{'cpan'}{lc($original_ebuild)}{'src_uri'} =~ m/\.\Q$ext\E$/ ) {
                                $module_a_ext = sprintf 'MODULE_A_EXT="%s"', $ext;
                            }
                        }

                        my $module_version = $gcpan_run->{cpan}{lc($original_ebuild)}{version};
                        my $description = $gcpan_run->{'cpan'}{lc($original_ebuild)}{'description'};
                        $description =~ s/"/\\"/g;

                        print $EBUILD <<"HERE";
# Copyright 1999-2016 Gentoo Foundation
# Distributed under the terms of the GNU General Public License v2
# This ebuild generated by $prog $VERSION

EAPI=5

MODULE_AUTHOR="$module_author"
MODULE_VERSION="$module_version"
$module_a_ext
$module_section
inherit perl-module

DESCRIPTION="$description"

LICENSE="|| ( Artistic GPL-1 GPL-2 GPL-3 )"
SLOT="0"
KEYWORDS="$keywords"
IUSE=""

HERE

                        if (my @deps = keys %{$gcpan_run->{cpan}{lc($original_ebuild)}{depends}})
                        {
                            print $EBUILD "DEPEND=\"";
                            my %seen_deps;
                            foreach my $dep (@deps)
                            {
                                defined $dep && $dep ne '' or next;
                                my $portage_name = $gcpan_run->{cpan}{lc($dep)}{portage_name};
                                next unless defined $portage_name;
                                $portage_name = lc($portage_name);
                                $portage_name =~ m{\S}x or next;

                                # Last ditch call to scanTree to make sure we
                                # have info
                                scanTree($portage_name);
                                next if ( defined($seen_deps{$portage_name}) && $seen_deps{$portage_name} > 0 );
                                $seen_deps{$portage_name} = 1;
                                next
                                  unless (defined($gcpan_run->{portage}{$portage_name}{category})
                                    && defined($gcpan_run->{portage}{$portage_name}{name}) && ($gcpan_run->{portage}{$portage_name}{name} =~ m/\S/));
                                $portage_name eq 'perl' || lc($portage_name) eq lc($gcpan_run->{cpan}{lc($original_ebuild)}{portage_name})
                                  and next;
                                my ($eb_version, $cpan_version) =
                                  stripdown($gcpan_run->{portage}{lc($portage_name)}{version}, $gcpan_run->{cpan}{lc($dep)}{portage_version});

                      #my $eb_version = stripdown($gcpan_run->{portage}{lc($portage_name)}{version});
                      #my $cpan_version = defined($gcpan_run->{cpan}{lc($dep)}{portage_version})? stripdown($gcpan_run->{cpan}{lc($dep)}{portage_version}): "0";
                                if ( $gcpan_run->{portage}{$portage_name}{name} eq "module-build")
                                {
                                    print $EBUILD ""
                                      . "virtual/perl-Module-Build\n";
                                }
                                elsif (   defined($gcpan_run->{cpan}{lc($dep)}{portage_version})
                                    && $gcpan_run->{cpan}{lc($original_ebuild)}{depends}{$dep} ne '0'
                                    && int($eb_version) >= int($cpan_version)
                                    && $gcpan_run->{cpan}{lc($original_ebuild)}{depends}{$dep} =~ m{\d}gx
                                    && $gcpan_run->{portage}{$portage_name}{name} ne "module-build")
                                {
                                    print $EBUILD "\>\="
                                      . $gcpan_run->{portage}{$portage_name}{category} . '/'
                                      . $gcpan_run->{portage}{$portage_name}{name} . '-';
                                    if (defined($eb_version))
                                    {
                                        print $EBUILD $gcpan_run->{portage}{lc($portage_name)}{version};
                                    }
                                    else
                                    {
                                        print $EBUILD $gcpan_run->{cpan}{lc($dep)}{portage_version};
                                    }
                                    print $EBUILD "\n\t";
                                }
                                else
                                {
                                    print $EBUILD ""
                                      . $gcpan_run->{portage}{$portage_name}{category} . "/"
                                      . $gcpan_run->{portage}{$portage_name}{name} . "\n\t";
                                }
                            }
                            print $EBUILD "dev-lang/perl\"\n";
                            if (defined($buildpkg) or defined($buildpkgonly)) {
                                print $EBUILD "\npkg_postinst() {\n";
                                print $EBUILD "elog \"If you redistribute this package, please remember to\"\n";
                                print $EBUILD "elog \"update /etc/portage/categories with an entry for perl-gpcan\"\n";

                                print $EBUILD "}\n";
                            }
                            undef $EBUILD;
                            autoflush STDOUT 1;
                        }
                        if (-f $gcpan_run->{cpan}{lc($original_ebuild)}{cpan_tarball})
                        {
                            $verbose and print_ok("Copying $gcpan_run->{cpan}{lc($original_ebuild)}{cpan_tarball} to $gcpan_run->{sources}");
                            copy($gcpan_run->{cpan}{lc($original_ebuild)}{cpan_tarball}, $gcpan_run->{sources});
                        }
                        print_info("Ebuild generated for $ebuild_wanted");
                        $gcpan_run->generate_digest($ebuild);
                        if (
                            !$upgrade
                            || ($upgrade
                                && defined($passed_to_install{$gcpan_run->{'cpan'}->{lc($original_ebuild)}->{'name'}}))
                          )
                        {
                            my $portage_name = $gcpan_run->{'cpan'}->{lc($original_ebuild)}->{'portage_name'};
                            $really_install{$portage_name} = 1;
                        }
                        last;
                    }
                    else
                    {
                        $upgrade and print_info("$ebuild_wanted already up to date") and last;
                        my $portage_name = $gcpan_run->{'cpan'}->{lc($original_ebuild)}->{'portage_name'};
                        $really_install{$portage_name} = 1;
                    }
                }
            }
        }
    }
    else
    {
        print_ok("Ebuild already exists for $ebuild_wanted (".$gcpan_run->{'portage'}{lc($ebuild_wanted)}{'category'}."/".$gcpan_run->{'portage'}{lc($ebuild_wanted)}{'name'}.")");
        if ( defined $passed_to_install{$ebuild_wanted} || defined $passed_to_install{$original_ebuild} )
		{ $really_install{$gcpan_run->{portage}{lc($ebuild_wanted)}{'name'}} = 1 }
    }
    return;
}

sub scanTree
{
    my ($module) = @_;
    $module or return;

    if ($module =~ /pathtools/gimx) { $module = "File-Spec" }
    foreach my $portage_root (keys %{$gcpan_run->{portage_bases}})
    {
        if (-d $portage_root)
        {
            $verbose and print_ok("Scanning $portage_root for $module");
            $gcpan_run->getAvailableVersions($portage_root, $module);
        }

        # Pop out of the loop if we've found the module
        defined($gcpan_run->{portage}{lc($module)}{found}) and last;
    }
	return;
}

sub strip_ends
{
    my $key = shift;
    if (defined($ENV{$key}))
    {
        $ENV{$key} =~ s{\\n}{ }gxms;
        $ENV{$key} =~ s{\\|\'|\\'|\$|\s*$}{}gmxs;

        #$ENV{$key} =~ s{\'|^\\|\$|\s*\\.\s*|\\\n$}{}gmxs;
        return $ENV{$key};
    }
    else
    {
        $key =~ s{\\n}{ }gxms;

        #$key =~ s{\'|^\\|\$|\s*\\.\s*|\\\n$}{}gmxs;
        $key =~ s{(\'|\\|\\'|\$|\s*$)}{}gmxs;

        return $key;
    }
}

sub stripdown
{
    my ($eb, $mod) = @_;
    $eb  =~ s{_|-|\D+}{}gmxi;
    $mod =~ s{_|-|\D+}{}gmxi;

    if ($eb  =~ m{^\.}x) { $eb  = "00$eb" }
    if ($mod =~ m{^\.}x) { $mod = "00$mod" }
    my $e_in = "";
    my $m_in = "";

    my (@eb_ver)  = split(/\./, $eb);
    my (@mod_ver) = split(/\./, $mod);

    my $num_e = @eb_ver;
    my $num_m = @mod_ver;

    if ($num_e == $num_m)
    {
        for (my $x = 0; $x <= ($num_e - 1); $x++)
        {
            if (length($eb_ver[$x]) > length($mod_ver[$x]))
            {
                while (length($eb_ver[$x]) > length($mod_ver[$x]))
                {
                    $mod_ver[$x] .= "0";
                }
            }
            if (length($mod_ver[$x]) > length($eb_ver[$x]))
            {
                while (length($mod_ver[$x]) > length($eb_ver[$x]))
                {
                    $eb_ver[$x] .= "0";
                }
            }
            $e_in .= "$eb_ver[$x]";
            $m_in .= "$mod_ver[$x]";
        }
    }
    elsif ($num_e > $num_m)
    {
        for (my $x = 0; $x <= ($num_e - 1); $x++)
        {
            unless ($mod_ver[$x])
            {
                $mod_ver[$x] = "00";
            }
            if (length($eb_ver[$x]) > length($mod_ver[$x]))
            {
                while (length($eb_ver[$x]) > length($mod_ver[$x]))
                {
                    $mod_ver[$x] .= "0";
                }
            }
            if (length($mod_ver[$x]) > length($eb_ver[$x]))
            {
                while (length($mod_ver[$x]) > length($eb_ver[$x]))
                {
                    $eb_ver[$x] .= "0";
                }
            }
            $e_in .= "$eb_ver[$x]";
            $m_in .= "$mod_ver[$x]";
        }
    }
    elsif ($num_e < $num_m)
    {
        for (my $x = 0; $x <= ($num_m - 1); $x++)
        {
            unless ($eb_ver[$x])
            {
                $eb_ver[$x] = "00";
            }
            if (length($eb_ver[$x]) > length($mod_ver[$x]))
            {
                while (length($eb_ver[$x]) > length($mod_ver[$x]))
                {
                    $mod_ver[$x] .= "0";
                }
            }
            if (length($mod_ver[$x]) > length($eb_ver[$x]))
            {
                while (length($mod_ver[$x]) > length($eb_ver[$x]))
                {
                    $eb_ver[$x] .= "0";
                }
            }
            $e_in .= "$eb_ver[$x]";
            $m_in .= "$mod_ver[$x]";
        }
    }
    $e_in =~ s{\.$}{}x;
    $m_in =~ s{\.$}{}x;
    return ($eb, $mod);
}

# cab - Takes care of system's sanity
END
{

    #Clean out the /tmp tree we were using
    #I know this looks weird, but since clean_up is invoked on a search, where OVERLAYS isn't ever defined,
    # we first need to see if it exists, then need to remove only if it has content (the old exists vs. defined)

    if (defined($ENV{TMPDIR}))
    {
        $verbose and print_ok('Cleaning temporary space');
        my ($startdir) = cwd();
		my $GCPAN_CAT = $ENV{GCPAN_CAT};
        chdir("$ENV{TMPDIR}/.cpan");
        opendir(CURD, '.');
        my @dirs = readdir(CURD);
        closedir(CURD);
        foreach my $dir (@dirs)
        {
            $dir eq '.'       and next;
            $dir eq '..'      and next;
            $dir eq 'sources' and next;
            -d $dir and rmtree(["$ENV{TMPDIR}/.cpan/$dir"]);
        }
		rmtree(["$ENV{TMPDIR}/perl-gcpan"]) if (-d "$ENV{TMPDIR}/perl-gcpan");
		rmtree(["$ENV{TMPDIR}/$GCPAN_CAT"]) if (defined($GCPAN_CAT) and -d "$ENV{TMPDIR}/$GCPAN_CAT");
    }
}

# cab - nice help message ! ;)
sub exit_usage
{
    print <<"USAGE";
${white}Usage : ${cyan}$prog ${green}<Switch(es)> ${cyan}Module Name(s)${reset}

${green}--generate,-g${reset}
    Generate ebuilds only (Requires working overlays)

${green}--install,-i${reset}
    Try to generate ebuild for the given module name
    and, if successful, emerge it. Important : installation
    requires exact CPAN Module Name.

${green}--list,-l${reset}
    This command generates a list of the Perl modules and ebuilds
    handled by $prog.

${green}--log,-L${reset}
    Log the output of $prog.

${green}--search,-s${reset}
    Search CPAN for the given expression (similar to
    the "m /EXPR/" from the CPAN Shell). Searches are
    case insensitive.

${green}--upgrade,-u${reset}
    Try to list and upgrade all Perl modules managed by $prog.
    It generate up-to-date ebuilds, then emerge then.

${green}--verbose,-v${reset}
    Enable (some) verbose output.

${green}--cpan_reload${reset}
    Reload the CPAN index

${white}Portage related options${reset}

${green}--ask,-a${reset}
    Ask before installing

${green}--buildpkg,-b${reset}
    Tells  emerge to build binary packages for all ebuilds processed
    in addition to actually merging the packages.

${green}--buildpkgonly,-B${reset}
    Creates  binary packages for all ebuilds processed without actu-
    ally merging the packages.

${green}--pretend,-p${reset}
    Pretend (show actions, but don't emerge). This still generates
    new ebuilds.


USAGE

    exit;
}

1;

__END__

=head1 NAME

App::gcpan - install CPAN-provided Perl modules using Gentoo's Portage

=head1 SYNOPSIS

    use App::gcpan;
    App::gcpan->run();

=head1 DESCRIPTION

App::gcpan is a base for L<g-cpan> script, that installs a CPAN module (including its dependencies) using Gentoo's Portage.
See L<g-cpan> for more information.

=head1 SEE ALSO

L<g-cpan>

=head1 BUGS

Please report bugs via L<https://github.com/gentoo-perl/g-cpan/issues> or L<https://bugs.gentoo.org/>.

=head1 COPYRIGHT AND LICENSE

Copyright 1999-2016 Gentoo Foundation.
Distributed under the terms of the GNU General Public License v2.

=cut
