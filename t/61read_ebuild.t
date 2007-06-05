do "t/load_env.pl";

use strict;
use warnings;

#use Smart::Comments '###', '####';

use Test::More tests => 5;

BEGIN { use_ok('Gentoo::Ebuild') }

my $ebuild = Gentoo::Ebuild->new();
ok(defined $ebuild, 'new() works');

$ebuild->read_ebuild(["./t/overlay", "dev-perl", "AxKit", "AxKit-1.6-r2.ebuild"]);
### $ebuild
ok(grep(/Axkit/i, $ebuild->{"axkit"}{"AxKit-1.6-r2.ebuild"}{DESCRIPTION}), "AxKit DESCRIPTION found");

$ebuild->read_ebuild("./t/overlay", "dev-perl", "FARK", "FARK-1.ebuild");
# Are we really getting results?
ok(!$ebuild->{FARK}, "Fake data test");

$ebuild->read_ebuild(["./t/overlay", "dev-perl", "module-build", "module-build-0.28.06.ebuild"]);
ok(grep(/module/i, $ebuild->{"module-build"}{"module-build-0.28.06.ebuild"}{DESCRIPTION}), "module-build DESCRIPTION found");
