do "t/load_env.pl";
use strict;
use warnings;

use Test::More tests => 1;                      # last test to print


BEGIN { use_ok('Gentoo::Ebuild') }

my $ebuild = Gentoo::Ebuild->new();

$ebuild->check_ebuild("t/overlay/perl-gcpan/gtest/gtest-1.0.ebuild");
# Check Keywords
# Check DEP's
# Check SRC_URI
#

#ok(defined($ebuild->{DESCRIPTION}), "Description found");
#ok(defined($ebuild->{KEYWORDS}), "Keywords found");

