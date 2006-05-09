package Gentoo;

use 5.008007;
use strict;
use warnings;

# These libraries were influenced and largely written by
# Christian Harmann <ian@gentoo.org> originally. All of the good
# parts are ian's - the rest is mcummings messing around.

require Exporter;

our @ISA = qw(Exporter);

our @EXPORT = qw( getAvailableEbuilds 
	getCPANPackages	
);

our $VERSION = '0.01';

sub new {
     my $self  = shift;
     my $class = ref($self) || $self;
     return bless {}, $class;
}

sub getPerlPackages
{
	my %excludeDirs			= ("." => 1, ".." => 1, "metadata" => 1, "licenses" => 1, "eclass" => 1, "distfiles" => 1, "virtual" => 1, "profiles" => 1);
	my @matches			= ();
	my $dhp;
	my $tc;
	my $tp;
	
	foreach $tc (@scan_portage_categories)
	{
		$dhp = new DirHandle($portdir."/".$tc);
		while (defined($tp = $dhp->read))
		{
			# - not excluded and $_ is a dir?
			if (! $excludeDirs{$tp} && -d $portdir."/".$tc."/".$tp)
			{
				@tmp_availableVersions=();
				my @tmp_availableEbuilds = getAvailableEbuilds($portdir,$tc."/".$tp);
				foreach (@tmp_availableEbuilds)
				{
					push(@tmp_availableVersions,getEbuildVersionSpecial($_));
				}
				
				# - get highest version >
				if ($#tmp_availableVersions>-1)
				{
					$modules{'portage_lc_realversion'}{lc($tp)}=(sort(@tmp_availableVersions))[$#tmp_availableVersions];
					$modules{'portage_lc'}{lc($tp)}=$modules{'portage_lc_realversion'}{lc($tp)};
					
					# - get rid of -rX >
					$modules{'portage_lc'}{lc($tp)}=~s/([a-zA-Z0-9\-_\/]+)-r[0-9+]/$1/;
					$modules{'portage_lc'}{lc($tp)}=~s/([a-zA-Z0-9\-_\/]+)-rc[0-9+]/$1/;
					$modules{'portage_lc'}{lc($tp)}=~s/([a-zA-Z0-9\-_\/]+)_p[0-9+]/$1/;
					$modules{'portage_lc'}{lc($tp)}=~s/([a-zA-Z0-9\-_\/]+)_pre[0-9+]/$1/;
					
					# - get rid of other stuff we don't want >
					$modules{'portage_lc'}{lc($tp)}=~s/([a-zA-Z0-9\-_\/]+)_alpha[0-9+]?/$1/;
					$modules{'portage_lc'}{lc($tp)}=~s/([a-zA-Z0-9\-_\/]+)_beta[0-9+]?/$1/;
					$modules{'portage_lc'}{lc($tp)}=~s/[a-zA-Z]+$//;

					$modules{'portage'}{lc($tp)}{'name'}=$tp;
					$modules{'portage'}{lc($tp)}{'category'}=$tc;
				}
			}
		}
		undef $dhp;
	}
}

# Description:
# @listOfEbuilds = getAvailableEbuilds($PORTDIR, category/packagename);
sub getAvailableEbuilds {
	my $self = shift;
    my $PORTDIR     = shift;
    my $catPackage  = shift;
    my @packagelist = ();

    if ( -e $PORTDIR . "/" . $catPackage ) {

        # - get list of ebuilds >
        my $dh = new DirHandle( $PORTDIR . "/" . $catPackage );
        while ( defined( $_ = $dh->read ) ) {
            if ( $_ =~ m/(.+)\.ebuild$/ ) {
                push( @packagelist, $_ );
            }
        }
    }

    return @packagelist;
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

sub getCPANPackages {
    my $force_cpan_reload = shift;
    my $cpan_pn           = "";
    my @tmp_v             = ();

    if ($force_cpan_reload) {

        # - User forced reload of the CPAN index >
        CPAN::Index->force_reload();
    }

    for my $mod ( CPAN::Shell->expand( "Module", "/./" ) ) {
        if ( defined $mod->cpan_version ) {

            # - Fetch CPAN-filename and cut out the filename of the tarball.
            #   We are not using $mod->id here because doing so would end up
            #   missing a lot of our ebuilds/packages >
            $cpan_pn = $mod->cpan_file;
            $cpan_pn =~ s|.*/||;

            if ( $mod->cpan_version eq "undef"
                && ( $cpan_pn =~ m/ / || $cpan_pn eq "" || !$cpan_pn ) )
            {

                # - invalid line - skip that one >
                next;
            }

            # - Right now both are "MODULE-FOO-VERSION-EXT" >
            my $cpan_version = $cpan_pn;

            # - Drop "-VERSION-EXT" from cpan_pn >
            $cpan_pn =~
              s/(?:-?)?(?:v?[\d\.]+[a-z]?)?\.(?:tar|tgz|zip|bz2|gz|tar\.gz)?$//;

            if ( length( lc($cpan_version) ) >= length( lc($cpan_pn) ) ) {

                # - Drop "MODULE-FOO-" from version >
                if ( length( lc($cpan_version) ) == length( lc($cpan_pn) ) ) {
                    $cpan_version = 0;
                }
                else {
                    $cpan_version = substr(
                        $cpan_version,
                        length( lc($cpan_pn) ) + 1,
                        length( lc($cpan_version) ) - length( lc($cpan_pn) ) - 1
                    );
                }
                if ( defined $cpan_version ) {
                    $cpan_version =~ s/\.(?:tar|tgz|zip|bz2|gz|tar\.gz)?$//;

    # - Remove any leading/trailing stuff (like "v" in "v5.2.0") we don't want >
                    $cpan_version =~ s/^[a-zA-Z]+//;
                    $cpan_version =~ s/[a-zA-Z]+$//;

                    # - Convert CPAN version >
                    @tmp_v = split( /\./, $cpan_version );
                    if ( $#tmp_v > 1 ) {
                        if ($main::DEBUG) {
                            print " converting version -> " . $cpan_version;
                        }
                        $cpan_version = $tmp_v[0] . ".";
                        for ( 1 .. $#tmp_v ) { $cpan_version .= $tmp_v[$_]; }
                        if ($main::DEBUG) { print " -> " . $cpan_version . "\n"; }
                    }

                    if ( $cpan_version eq "" ) { $cpan_version = 0; }

                    $main::modules{'cpan'}{$cpan_pn} = $cpan_version;
                    $main::modules{'cpan_lc'}{ lc($cpan_pn) } = $cpan_version;
                }
            }
        }
    }
    return 0;
}

# Preloaded methods go here.

# Autoload methods go after =cut, and are processed by the autosplit program.

1;
__END__
# Below is stub documentation for your module. You'd better edit it!

=head1 NAME

Gentoo - Perl extension for blah blah blah

=head1 SYNOPSIS

  use Gentoo;
  blah blah blah

=head1 DESCRIPTION

Stub documentation for Gentoo, created by h2xs. It looks like the
author of the extension was negligent enough to leave the stub
unedited.

Blah blah blah.

=head2 EXPORT

None by default.



=head1 SEE ALSO

Mention other useful documentation such as the documentation of
related modules or operating system documentation (such as man pages
in UNIX), or any relevant external documentation such as RFCs or
standards.

If you have a mailing list set up for your module, mention it here.

If you have a web site set up for your module, mention it here.

=head1 AUTHOR

A. U. Thor, E<lt>mcummings@datanode.netE<gt>

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2006 by A. U. Thor

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.8.8 or,
at your option, any later version of Perl 5 you may have available.


=cut
