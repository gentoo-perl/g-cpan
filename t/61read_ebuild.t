require "t/SET_ENV";

use Test::More tests => 5;

BEGIN { use_ok('Gentoo::Ebuild') }

my $ebuild = Gentoo::Ebuild->new();

ok(defined $ebuild, 'new() works');

$ebuild->read_ebuild("./t/overlay", "dev-perl", "AxKit", "AxKit-1.6-r2.ebuild");

#use Data::Dumper; print Dumper($ebuild);
ok(grep(/Axkit/i, $ebuild->{DESCRIPTION}), "AxKit DESCRIPTION found");

# Are we really getting results?
ok(!$ebuild->{FARK}, "Fake data test");

$ebuild->read_ebuild("./t/overlay", "dev-perl", "module-build", "module-build-0.28.06.ebuild");
#use Data::Dumper; print Dumper($ebuild);
ok(grep(/module/i, $ebuild->{DESCRIPTION}), "module-build DESCRIPTION found");
