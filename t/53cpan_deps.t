do "t/load_env.pl";


use strict;
use warnings;
#use Smart::Comments '###', '####';

use Test::More tests => 1;

use_ok('Gentoo::CPAN');

my @modules = ("Bigtop", "Module::Build", "Catalyst");
# Test getting CPAN Info

foreach my $search_for (@modules) {
my $cpan = Gentoo::CPAN->new();
$cpan->getCPANInfo($search_for);
$cpan->unpackModule($search_for);
### $cpan
}

my $search_for = "NOTREAL";
my $cpan = Gentoo::CPAN->new();
$cpan->getCPANInfo($search_for);
$cpan->unpackModule($search_for);
### $cpan
system("emerge", "-av", "module-build");
