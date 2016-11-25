#!/usr/bin/env perl

use strict;
use warnings;

use Test::More tests => 8;

use_ok('Gentoo::Portage');

my $portage = new_ok('Gentoo::Portage');

use_ok('Gentoo::Portage::Q');
my $portageq = new_ok('Gentoo::Portage::Q');

my $portdir = $portageq->envvar('PORTDIR') || $portageq->get_repo_path( $portageq->envvar('EROOT'), 'gentoo' );
ok( $portdir, 'detect PORTDIR value' )
  and $portage->{portage_bases}{$portdir} = 1;

subtest 'getAvailableEbuilds($portdir, $package)', sub {
    my $ebuilds = $portage->getAvailableEbuilds( $portdir, 'non_existen/package' );
    is_deeply( $ebuilds, [], 'list of ebuilds is empty for non_existen/package' );

    my $category = 'dev-perl';
    my $package  = 'YAML';
    $ebuilds = $portage->getAvailableEbuilds( $portdir, "$category/$package" );
    is( ref $ebuilds, 'ARRAY', "retrieve ebuilds for '$category/$package' (as arrayref)" );
    like( $ebuilds->[0], qr/^YAML-[\d\.]+(?:-\w+)?\.ebuild$/, '  and contains element like ebuild' );
};

subtest 'getAvailableVersions($portdir, $find_package)', sub {
    my $find_package = 'YAML';
    my $category     = 'dev-perl';
    $portage->{portage_categories} = [$category];
    $portage->getAvailableVersions( $portdir, $find_package );
    ok( $portage->{portage}, "retrieve OK for '$find_package'" );
    is( ref $portage->{portage}{ lc($find_package) },       'HASH',    "  and contains hashref with '$find_package'" );
    is( $portage->{portage}{ lc($find_package) }{category}, $category, "  and 'category' is proper also" );
    like(
        $portage->{portage}{ lc($find_package) }{DESCRIPTION},
        qr/^YAML Aint Markup Language/,
        "  and contains proper 'DESCRIPTION' for '$find_package'"
    );
};

subtest 'getBestVersion($find_ebuild, $portdir, $cat, $eb)', sub {
    my $find_package = 'Test-Simple';
    my $category     = 'perl-core';
    my $package      = 'Test-Simple';
    $portage->getBestVersion( $find_package, $portdir, $category, $package );
    ok( $portage->{portage}, "retrieve OK for '$find_package'" );
    is( ref $portage->{portage},                            'HASH',    '  and it is an hashref' );
    is( ref $portage->{portage}{ lc($find_package) },       'HASH',    "  and contains hashref with '$find_package'" );
    is( $portage->{portage}{ lc($find_package) }{category}, 'virtual', "  and 'category' is proper also" );
    like(
        $portage->{portage}{ lc($find_package) }{DESCRIPTION},
        qr/^Basic utilities for writing tests/,
        "  and contains proper 'DESCRIPTION' for '$find_package'"
    );
};
