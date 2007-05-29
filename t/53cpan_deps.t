do "t/load_env.pl";


use strict;
use warnings;
#use Smart::Comments '###', '####';

use Test::More tests => 5;

use_ok('Gentoo::CPAN');

my @modules = ("Bigtop", "Module::Build");
# Test getting CPAN Info

foreach my $search_for (@modules) {
diag("Errors from CPAN are expected here");
my $cpan = Gentoo::CPAN->new();
#$cpan->getCPANInfo($search_for);
$cpan->unpackModule($search_for);
ok($cpan->{lc($search_for)}{depends}, "Dependencies found for $search_for");
### $cpan
}

my $search_for = "NOTREAL";
my $cpan = Gentoo::CPAN->new();
$cpan->getCPANInfo($search_for);
$cpan->unpackModule($search_for);
ok(! $cpan->{NOTREAL}, "NOTREAL not found");
ok( $cpan->{E}, "ERROR message found");
### $cpan
