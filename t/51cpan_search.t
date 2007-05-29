do "t/load_env.pl";


use strict;
use warnings;
#use Smart::Comments '###', '####';

use Test::More tests => 7;

use_ok('Gentoo::CPAN');

my $cpan = Gentoo::CPAN->new();

my $search_for = "Bigtop";
#my $search_for = "CGI";


# Test getting CPAN Info

$cpan->getCPANInfo($search_for);
ok(! $cpan->{E}, "Error returned!");
ok( defined $cpan->{src_uri} , 'Source URI defined');
ok( defined $cpan->{name}, 'Name defined');
ok( defined $cpan->{description}, 'Description defined');
ok( defined $cpan->{version}, 'Version defined');
### $cpan

my $search = Gentoo::CPAN->new();
my @results = $search->CPANSearch($search_for);
ok(scalar(@results) > 0, "Results found!");
### @results

# Test searching
