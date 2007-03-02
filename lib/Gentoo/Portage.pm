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

our @EXPORT =
  qw( getEnv getAvailableEbuilds getAvailableVersions generate_digest emerge_ebuild import_fields );

our $VERSION = '0.01';


sub getEnv {
#IMPORT VARIABLES
    my $self = shift;
    my $envvar = shift;
    my $filter = sub {
        my ($var, $value, $change ) = @_;
        return($var =~ /^$envvar$/ );
    };

foreach my $file ( "$ENV{HOME}/.gcpanrc", "/etc/make.conf", "/etc/make.globals" ) {
    if ( -f $file) {
    	my $importer = Shell::EnvImporter->new(
    		file => $file,
    		shell => 'bash',
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

sub strip_env {
    my $key = shift;
    if (defined($ENV{$key})) {
        $ENV{$key} =~ s{\\n}{ }gxms;
        $ENV{$key} =~ s{\\|\'|\\'|\$|\s*$}{}gmxs;
        $key =~ s{\s+}{ }gmxs;
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
# Description:
# @listOfEbuilds = getAvailableEbuilds($PORTDIR, category/packagename);
sub getAvailableEbuilds {
    my $self        = shift;
    my $portdir     = shift;
    my $catPackage  = shift;
    @{$self->{packagelist}} = ();
    if ( -e $portdir . "/" . $catPackage ) {

        # - get list of ebuilds >
        my $startdir = &cwd;
        chdir( $portdir . "/" . $catPackage );
        @store_found_ebuilds = [];
        File::Find::find( { wanted => \&wanted_ebuilds }, "." );
        chdir($startdir);
        foreach (@store_found_ebuilds) {
            $_ =~ s{^\./}{}xms;
            if ( $_ =~ m/(.+)\.ebuild$/ ) {
                next if ( $_ eq "skel.ebuild" );
                push( @{ $self->{packagelist} }, $_ );
            }
            else {
                if ( -d $portdir . "/" . $catPackage . "/" . $_ ) {
                    $_ =~ s{^\./}{}xms;
                    my $startdir = &cwd;
                    chdir( $portdir . "/" . $catPackage . "/" . $_ );
                    @store_found_ebuilds = [];
                    File::Find::find( { wanted => \&wanted_ebuilds }, "." );
                    chdir($startdir);
                    foreach (@store_found_ebuilds) {
                        if ( $_ =~ m/(.+)\.ebuild$/ ) {
                            next if ( $_ eq "skel.ebuild" );
                            push( @{ $self->{packagelist} }, $_ );
                        }
                    }
                }
            }
        }
    }
    else {
        if ( -d $portdir ) {
            if ( $self->{debug} ) {
                warn(
                    "\n" . $portdir . "/" . $catPackage . " DOESN'T EXIST\n" );
            }
        }
        else {
            die("\nPORTDIR hasn't been defined!\n\n");
        }
    }

}

# Description:
# Returns version of an ebuild. (Without -rX string etc.)
# $version = getEbuildVersionSpecial("foo-1.23-r1.ebuild");
sub getEbuildVersionSpecial {
    my $ebuildVersion = shift;
    $ebuildVersion = substr( $ebuildVersion, 0, length($ebuildVersion) - 7 );
    $ebuildVersion =~
s/^([a-zA-Z0-9\-_\/\+]*)-([0-9\.]+[a-zA-Z]?)([\-r|\-rc|_alpha|_beta|_pre|_p]?)/$2$3/;

    return $ebuildVersion;
}

sub getAvailableVersions {
    my $self        = shift;
    my $portdir     = shift;
    my $find_ebuild = shift;
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

    if ($find_ebuild) {
        return if ( defined($self->{portage}{ lc($find_ebuild) }{'found'} ));
    }
    foreach my $tc ( @{ $self->{portage_categories} } ) {
        next if ( !-d "$portdir/$tc" );
        @store_found_dirs = [];

        # Where we started
        my $startdir = &cwd;

        # chdir to our target dir
        chdir( $portdir . "/" . $tc );

        # Traverse desired filesystems
        File::Find::find( { wanted => \&wanted_dirs }, "." );

        # Return to where we started
        chdir($startdir);
        foreach my $tp ( sort @store_found_dirs ) {
            $tp =~ s{^\./}{}xms;

            # - not excluded and $_ is a dir?
            if ( !$excludeDirs{$tp} && -d $portdir . "/" . $tc . "/" . $tp ) {
                if ($find_ebuild) {
                    next
                      unless ( lc($find_ebuild) eq lc($tp) );
                }
                getAvailableEbuilds( $self, $portdir, $tc . "/" . $tp );

                foreach ( @{ $self->{packagelist} } ) {
                    my @tmp_availableVersions = ();
                    push( @tmp_availableVersions, getEbuildVersionSpecial($_) );

                    # - get highest version >
                    if ( $#tmp_availableVersions > -1 ) {
                        $self->{'portage'}{ lc($tp) }{'version'} =
                          ( sort(@tmp_availableVersions) )
                          [$#tmp_availableVersions];

                        my $e_file= "$portdir/$tc/$tp/$_";
                        # Grab some info for display
                        my $e_import = Shell::EnvImporter->new(
                            file => $e_file,
                            shell => 'bash',
                            auto_run => 1,
                            auto_import => 1,
                        );
                        $e_import->shellobj->envcmd('set');
                        $e_import->run();
                        $e_import->env_import();
                        $self->{'portage'}{lc($tp)}{'DESCRIPTION'} = strip_env($ENV{DESCRIPTION});
                        $self->{'portage'}{lc($tp)}{'HOMEPAGE'} = strip_env($ENV{HOMEPAGE});
                        $e_import->restore_env;


                        # - get rid of -rX >
                        $self->{'portage'}{ lc($tp) }{'version'} =~
                          s/([a-zA-Z0-9\-_\/]+)-r[0-9+]/$1/;
                        $self->{'portage'}{ lc($tp) }{'version'} =~
                          s/([a-zA-Z0-9\-_\/]+)-rc[0-9+]/$1/;
                        $self->{'portage'}{ lc($tp) }{'version'} =~
                          s/([a-zA-Z0-9\-_\/]+)_p[0-9+]/$1/;
                        $self->{'portage'}{ lc($tp) }{'version'} =~
                          s/([a-zA-Z0-9\-_\/]+)_pre[0-9+]/$1/;

                        # - get rid of other stuff we don't want >
                        $self->{'portage'}{ lc($tp) }{'version'} =~
                          s/([a-zA-Z0-9\-_\/]+)_alpha[0-9+]?/$1/;
                        $self->{'portage'}{ lc($tp) }{'version'} =~
                          s/([a-zA-Z0-9\-_\/]+)_beta[0-9+]?/$1/;
                        $self->{'portage'}{ lc($tp) }{'version'} =~
                          s/[a-zA-Z]+$//;

                        if ( $tc eq "perl-core"
                            and ( keys %{ $self->{'portage_bases'} } ) )
                        {

          # We have a perl-core module - can we satisfy it with a virtual/perl-?
                            foreach my $portage_root (
                                keys %{ $self->{'portage_bases'} } )
                            {
                                if ( -d $portage_root ) {
                                    if ( -d "$portage_root/virtual/perl-$tp" ) {
                                        $self->{'portage'}{ lc($tp) }
                                          {'name'} = "perl-$tp";
                                        $self->{'portage'}{ lc($tp) }
                                          {'category'} = "virtual";
                                        last;
                                    }
                                }
                            }

                        }
                        else {
                            $self->{'portage'}{ lc($tp) }{'name'} =
                              $tp;
                            $self->{'portage'}{ lc($tp) }{'category'} =
                              $tc;
                        }
                        if ($find_ebuild) {
                            if ( defined($self->{'portage'}{ lc($tp) }{'name'}) )
                            {
                                $self->{portage}{ lc($tp) }{'found'} = 1;
                                last;
                            }
                        }
                    }
                }
            }
        }
    }
    return ($self);
}

sub generate_digest {
    my $self = shift;

    # Full path to the ebuild file in question
    my $ebuild = shift;
    system( "ebuild", $ebuild, "digest" );
}

sub emerge_ebuild {
    my $self  = shift;
    my @call = @_;
    # emerge forks and returns, which confuses this process. So
    # we call it the old fashioned way :(
    system( "emerge", @call );
}

sub wanted_dirs {
    my ( $dev, $ino, $mode, $nlink, $uid, $gid );
    ( ( $dev, $ino, $mode, $nlink, $uid, $gid ) = lstat($_) )
      && -d _
      && ( $name !~ m|/files| )
      && ( $name !~ m|/CVS| )
      && push @store_found_dirs, $name;
}

sub wanted_ebuilds {
    /\.ebuild\z/s
      && push @store_found_ebuilds, $name;
}

sub DESTROY {
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
