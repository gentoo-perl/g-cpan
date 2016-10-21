#!/usr/bin/env perl

use strict;
use warnings;

use Test::More tests => 6;

use_ok('Gentoo::Portage');

my $portage = new_ok('Gentoo::Portage');

my $portdir;

subtest 'getEnv($envvar)', sub {
    ok( !$portage->getEnv('BOGUS'),  'fake data test' );
    ok( $portage->getEnv('DISTDIR'), 'get DISTDIR' );
    ok( $portdir = $portage->getEnv('PORTDIR'), 'get PORTDIR' )
      and $portage->{portage_bases}{$portdir} = 1;
    ok( $portage->getEnv('PORTDIR_OVERLAY'), 'get PORTDIR_OVERLAY' );
    ok( $portage->getEnv('USE'),             'get USE flags' );
};

subtest 'getAvailableEbuilds($portdir, $package)', sub {
    $portage->getAvailableEbuilds( $portdir, 'non_existen/package' );
    ok( !@{ $portage->{packagelist} }, 'list of ebuilds is empty for non_existen/package' );

    my $category = 'dev-perl';
    my $package  = 'YAML';
    $portage->getAvailableEbuilds( $portdir, "$category/$package" );
    ok( $portage->{packagelist}, "retrieve OK for '$category/$package'" );
    is( ref $portage->{packagelist}, 'ARRAY', '  and it is an arrayref' );
    like( $portage->{packagelist}[0], qr/^YAML-[\d\.]+\.ebuild$/, '  and contains element like ebuild' );
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
