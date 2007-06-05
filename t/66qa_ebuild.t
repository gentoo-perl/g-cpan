do "t/load_env.pl";
use strict;
use warnings;

use Smart::Comments '###', '####';

use Test::More tests => 6;                      # last test to print


BEGIN { use_ok('Gentoo::Ebuild') }

my $ebuild = Gentoo::Ebuild->new();
my $path = "t/overlay/perl-gcpan/gtest/gtest-1.0.ebuild";
my $keyword = "x86";
my $package = "gtest";
diag("Running keyword tests");
test_nokeyword($path);
test_keyword($keyword,$path);
test_haskeyword($keyword,$path);
test_bestkeyword($keyword,$path);
diag("Running dep tests");

sub test_nokeyword {
    my $path = @_;
    my $ebuild = Gentoo::Ebuild->new();
    $ebuild->check_ebuild($path);
    isnt($ebuild->{E},undef, "Test no keyword present errors out");
}

sub test_keyword {
    my ($keyword, $path) = @_;
    my $ebuild = Gentoo::Ebuild->new(keyword =>$keyword);
    $ebuild->check_ebuild($path);
    is($ebuild->{E},undef, "Keyword available tested");
}

sub test_haskeyword {
    my ($keyword, $path) = @_;
    my $ebuild = Gentoo::Ebuild->new();
    $ebuild->read_ebuild($path);
    $ebuild->has_keyword($keyword, "gtest", "gtest-1.0.ebuild");
    isnt($ebuild->{E},undef, "Keyword $keyword not usable");
    $ebuild->{E} = undef;
    $ebuild->has_keyword("~x86", "gtest", "gtest-1.0.ebuild");
    is($ebuild->{E},undef, "Keyword ~x86 is usable");
}

sub test_bestkeyword {
	my ($keyword, $path) = @_;
	my $ebuild = Gentoo::Ebuild->new(keyword => $keyword,);
	$ebuild->read_ebuild($path);
	my $target = $ebuild->best_keyword("gtest","gtest-1.0.ebuild");
	is($target, "~x86", "Best keyword found");
}

# Check Keywords - has_keyword("~x86") would be the ideal way to run t his
# Check DEP's - check that deps exist in the tree
# Check dep_keywords - sort through the deps, see if their keywords match $KEYWORD?
# Check SRC_URI - check that this is filled? Not sure here - never had a case of a bad src_uri that i know of
# Check 
#

#ok(defined($ebuild->{DESCRIPTION}), "Description found");
#ok(defined($ebuild->{KEYWORDS}), "Keywords found");

