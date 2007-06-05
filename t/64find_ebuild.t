do "t/load_env.pl";
use strict;
use warnings;

#use Smart::Comments '###', '####';

use Test::More  qw(no_plan);

$ENV{PORTDIR} = "/usr/portage";

BEGIN { use_ok('Gentoo::Ebuild') }

my @categories = [ "dev-perl", "perl-gcpan", "perl-core" ];
my @portage_dirs = [ "/usr/portage", $ENV{PORTDIR_OVERLAY} ];
my @ebuilds = ( "Cgi-Simple", "Test-WWW-Mechanize", "Math-BigInt", "perltidy", "knockknock", "POE" );


foreach my $module (@ebuilds) {
my $ebuild = Gentoo::Ebuild->new(portage_categories => @categories,
								portage_bases => @portage_dirs,
							);
	$ebuild->scan_tree("$module");
	if ($module ne "knockknock") {
	#### $ebuild
		foreach my $eb (@{$ebuild->{packagelist}}) 
		{
			ok($ebuild->{lc($module)}{$eb}{DESCRIPTION}, "DESCRIPTION exists for $eb");
				ok($ebuild->{lc($module)}{$eb}{HOMEPAGE}, "HOMEPAGE defined for $eb");
				ok($ebuild->{lc($module)}{$eb}{KEYWORDS}, "KEYWORDS filled for $eb");
				ok($ebuild->{lc($module)}{$eb}{DEPEND}, "DEPEND populated for $eb");
		}
	} else {
		ok($ebuild->{E}, "ERROR found for knockknock");
	}
}

# Locate an ebuild in the tree :)
