do "t/load_env.pl";
use strict;
use warnings;

#use Smart::Comments '###', '####';

use Test::More tests => 1;                      # last test to print


BEGIN { use_ok('Gentoo::Ebuild') }

my @categories = [ "dev-perl", "perl-gcpan", "perl-core" ];
my @portage_dirs = [ "/usr/portage", $ENV{PORTDIR_OVERLAY} ];
my @ebuilds = ( "Cgi-Simple", "Test-WWW-Mechanize", "Math-BigInt", "perltidy", "knockknock", "POE" );


foreach my $module (@ebuilds) {
my $ebuild = Gentoo::Ebuild->new(portage_categories => @categories,
								portage_bases => @portage_dirs,
							);
	$ebuild->scan_tree("$module");
	#### $ebuild
}

# Locate an ebuild in the tree :)
