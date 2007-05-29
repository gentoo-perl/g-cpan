do "t/load_env.pl";

use strict;
use warnings;

use Test::More tests => 3;                      # last test to print


use_ok('Gentoo::CPAN');

my $cpan = Gentoo::CPAN->new();

ok( defined $cpan, 'new() works');

$cpan->need_cpan();

ok( -f "t/.cpan/CPAN/MyConfig.pm", 'Config file generated');
