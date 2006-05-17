package Gentoo::Portage;

use 5.008007;
use strict;
use warnings;

use Cwd qw(getcwd abs_path cwd);
use File::Find ();

# Set the variable $File::Find::dont_use_nlink if you're using AFS,
# since AFS cheats.

# for the convenience of &wanted calls, including -eval statements:
use vars qw/*name *dir *prune/;
*name   = *File::Find::name;
*dir    = *File::Find::dir;
*prune  = *File::Find::prune;

my @store_found_dirs;
my @store_found_ebuilds;
sub wanted;

# These libraries were influenced and largely written by
# Christian Hartmann <ian@gentoo.org> originally. All of the good
# parts are ian's - the rest is mcummings messing around.

require Exporter;

our @ISA = qw(Exporter Gentoo);

our @EXPORT = qw( getAvailableEbuilds getAvailableVersions );

our $VERSION = '0.01';

# Description:
# @listOfEbuilds = getAvailableEbuilds($PORTDIR, category/packagename);
sub getAvailableEbuilds
{
    my $self        = shift;
	my $portdir     = shift;
    my $catPackage  = shift;
    my @packagelist = ();
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
                    chdir($portdir . "/" . $catPackage . "/" . $_ );
                    @store_found_ebuilds = [];
                    File::Find::find({wanted => \&wanted_ebuilds},  "." );
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
            if ($self->{debug}) {
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

sub getAvailableVersions
{
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
        return if ( $self->{ebuilds}{'found_ebuild'}{lc($find_ebuild)} );
    }
    foreach my $tc (@{$self->{portage_categories}})
    {
		next if  ( ! -d "$portdir/$tc" );
        @store_found_dirs = [];
		# Where we started
        my $startdir = &cwd;
		# chdir to our target dir
        chdir($portdir . "/" . $tc);
        # Traverse desired filesystems
        File::Find::find({wanted => \&wanted_dirs}, "." );
		# Return to where we started
        chdir($startdir);
        foreach my $tp (sort @store_found_dirs)
        {
            $tp =~ s{^\./}{}xms;

            # - not excluded and $_ is a dir?
            if (!$excludeDirs{$tp} && -d $portdir . "/" . $tc . "/" . $tp)
            {
				if ($find_ebuild) { next unless (lc($find_ebuild) eq lc($tp)) }
                getAvailableEbuilds($self, $portdir, $tc . "/" . $tp);
                foreach (@{$self->{packagelist}})
                {
                    my @tmp_availableVersions = ();
                    push(@tmp_availableVersions, getEbuildVersionSpecial($_));

                    # - get highest version >
                    if ($#tmp_availableVersions > -1)
                    {
                        $self->{ebuilds}{'portage_lc'}{lc($tp)}             = (sort(@tmp_availableVersions))[$#tmp_availableVersions];

                        # - get rid of -rX >
                        $self->{ebuilds}{'portage_lc'}{lc($tp)} =~ s/([a-zA-Z0-9\-_\/]+)-r[0-9+]/$1/;
                        $self->{ebuilds}{'portage_lc'}{lc($tp)} =~ s/([a-zA-Z0-9\-_\/]+)-rc[0-9+]/$1/;
                        $self->{ebuilds}{'portage_lc'}{lc($tp)} =~ s/([a-zA-Z0-9\-_\/]+)_p[0-9+]/$1/;
                        $self->{ebuilds}{'portage_lc'}{lc($tp)} =~ s/([a-zA-Z0-9\-_\/]+)_pre[0-9+]/$1/;

                        # - get rid of other stuff we don't want >
                        $self->{ebuilds}{'portage_lc'}{lc($tp)} =~ s/([a-zA-Z0-9\-_\/]+)_alpha[0-9+]?/$1/;
                        $self->{ebuilds}{'portage_lc'}{lc($tp)} =~ s/([a-zA-Z0-9\-_\/]+)_beta[0-9+]?/$1/;
                        $self->{ebuilds}{'portage_lc'}{lc($tp)} =~ s/[a-zA-Z]+$//;

                        $self->{ebuilds}{'portage'}{lc($tp)}{'name'}     = $tp;
                        $self->{ebuilds}{'portage'}{lc($tp)}{'category'} = $tc;
						if ($find_ebuild) {
							if ($self->{ebuilds}{'portage_lc'}{lc($find_ebuild)})
							{
								$self->{ebuilds}{'found_ebuild'}{lc($find_ebuild)} = 1;
								last;
							}
						}
                    }
                }
            }
        }
    }
}

sub wanted_dirs {
    my ($dev,$ino,$mode,$nlink,$uid,$gid);
    (($dev,$ino,$mode,$nlink,$uid,$gid) = lstat($_)) &&
    -d _ &&
    ($name !~ m|/files|) &&
    ($name !~ m|/CVS|) &&
    push @store_found_dirs, $name;
}

sub wanted_ebuilds {
    /\.ebuild\z/s
    && push @store_found_ebuilds, $name;
}

sub DESTROY
{
    my ($self) = @_;
    return if $self->{DESTROY}{__PACKAGE__}++;
}

1;
