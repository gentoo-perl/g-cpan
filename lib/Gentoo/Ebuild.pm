package Gentoo::Ebuild;

use 5.008007;
use strict;
use warnings;

use DirHandle;

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
    my $catPackage  = shift;
    my @packagelist = ();

    if (-e $self->{portdir} . "/" . $catPackage)
    {

        # - get list of ebuilds >
        my $_cat_handle = new DirHandle($self->{portdir} . "/" . $catPackage);
        while (defined($_ = $_cat_handle->read))
        {
            if ($_ =~ m/(.+)\.ebuild$/)
            {
                next if ($_ eq "skel.ebuild");
                push(@{$self->{packagelist}}, $_);
            }
            else
            {
                if (-d $self->{portdir} . "/" . $catPackage . "/" . $_)
                {
                    my $_ebuild_dh = new DirHandle($self->{portdir} . "/" . $catPackage . "/" . $_);
                    while (defined($_ = $_ebuild_dh->read))
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
        if (-d $self->{portdir})
        {
            die("\n" . $self->{portdir} . "/" . $catPackage . " DOESNT EXIST\n");
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
    my @matches = ();
    my $dhp;
    my $tc;
    my $tp;

    foreach $tc (@{$self->{portage_categories}})
    {
        $dhp = new DirHandle($self->{portdir} . "/" . $tc);
        while (defined($tp = $dhp->read))
        {

            # - not excluded and $_ is a dir?
            if (!$excludeDirs{$tp} && -d $self->{portdir} . "/" . $tc . "/" . $tp)
            {
                getAvailableEbuilds($self, $tc . "/" . $tp);
                foreach (@{$self->{packagelist}})
                {
                    my @tmp_availableVersions = ();
                    push(@tmp_availableVersions, getEbuildVersionSpecial($_));

                    # - get highest version >
                    if ($#tmp_availableVersions > -1)
                    {
                        $self->{modules}{'portage_lc_realversion'}{lc($tp)} = (sort(@tmp_availableVersions))[$#tmp_availableVersions];
                        $self->{modules}{'portage_lc'}{lc($tp)}             = $self->{modules}{'portage_lc_realversion'}{lc($tp)};

                        # - get rid of -rX >
                        $self->{modules}{'portage_lc'}{lc($tp)} =~ s/([a-zA-Z0-9\-_\/]+)-r[0-9+]/$1/;
                        $self->{modules}{'portage_lc'}{lc($tp)} =~ s/([a-zA-Z0-9\-_\/]+)-rc[0-9+]/$1/;
                        $self->{modules}{'portage_lc'}{lc($tp)} =~ s/([a-zA-Z0-9\-_\/]+)_p[0-9+]/$1/;
                        $self->{modules}{'portage_lc'}{lc($tp)} =~ s/([a-zA-Z0-9\-_\/]+)_pre[0-9+]/$1/;

                        # - get rid of other stuff we don't want >
                        $self->{modules}{'portage_lc'}{lc($tp)} =~ s/([a-zA-Z0-9\-_\/]+)_alpha[0-9+]?/$1/;
                        $self->{modules}{'portage_lc'}{lc($tp)} =~ s/([a-zA-Z0-9\-_\/]+)_beta[0-9+]?/$1/;
                        $self->{modules}{'portage_lc'}{lc($tp)} =~ s/[a-zA-Z]+$//;

                        $self->{modules}{'portage'}{lc($tp)}{'name'}     = $tp;
                        $self->{modules}{'portage'}{lc($tp)}{'category'} = $tc;
                    }
                }
            }
        }
        undef $dhp;
    }
}

sub DESTROY
{
    my ($self) = @_;
    return if $self->{DESTROY}{__PACKAGE__}++;
}

1;
