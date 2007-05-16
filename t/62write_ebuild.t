require "t/SET_ENV";

use strict;
use warnings;

use Test::More tests => 3;                      # last test to print

BEGIN { use_ok('Gentoo::Ebuild') }

#my $ebuild = Gentoo::Ebuild->new();

my $ebuild = Gentoo::Ebuild->new( 'VERSION' => "16.0",
			'prog' => "g-cpan",
			'ebuild' => "gtest-1.0.ebuild",
			'portage_sdir' => "GTest",
			cpan_name => 'GTest',
			'src_uri' => "M/MC/MCUMMINGS/GTest-1.0.tar.gz",
			'keywords' => "~amd64 ~x86 ~sparc",
			'depends' => [ "perl-core/CGI","dev-perl/module-build" ],
			'path' => "t/overlay/perl-gcpan/gtest",
			'description' => "Mikes fancy module",
		);

$ebuild->write_ebuild();
#use Data::Dumper; print Dumper($ebuild);
ok(-f "t/overlay/perl-gcpan/gtest/gtest-1.0.ebuild", "File created successfully");
# Again - make sure we are warned away
$ebuild->write_ebuild();
ok(defined $ebuild->{W}, "Appropriate warning found");
