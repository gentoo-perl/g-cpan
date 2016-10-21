#!/usr/bin/env perl

use lib 'lib';
use strict;
use warnings;

use Test::More;

use_ok('Gentoo::Portage::Q');

my $portageq = new_ok('Gentoo::Portage::Q');

subtest 'envvar($variable)', sub {
    is( $portageq->envvar('EROOT'), '/', 'EROOT' );
    ok( $portageq->envvar('DISTDIR'), 'DISTDIR' );
    like( $portageq->envvar('USE'), qr/^\w[\w\s\-]*$/, 'USE' );
    ok( !$portageq->envvar('SOME_BOGUS_VAR'), 'fake var' );

    subtest 'real Gentoo Linux', sub {
        plan skip_all => 'nope' unless -e '/etc/gentoo-release';
        like( $portageq->envvar('ARCH'),            qr/^~?[\w\-]+$/, 'ARCH' );
        like( $portageq->envvar('ACCEPT_KEYWORDS'), qr/^~?[\w\-]+$/, 'ACCEPT_KEYWORDS' );
        ok( $portageq->envvar('MAKEOPTS'), 'MAKEOPTS' );
    };
};

subtest 'get_repo_path( $eroot, $repo_id )', sub {
    my $eroot = 't/data';
    is( $portageq->get_repo_path( $eroot, 'gentoo' ), '/usr/portage',       "trying for ('$eroot','gentoo')" );
    is( $portageq->get_repo_path( $eroot, 'local' ),  '/usr/local/portage', "trying for ('$eroot','local')" );
    is( $portageq->get_repo_path( $eroot, 'bogus' ),  undef,                "trying for ('$eroot','bogus')" );

    subtest 'real Gentoo Linux', sub {
        plan skip_all => 'nope' unless -e '/etc/gentoo-release';
        $eroot = '/';
        is( $portageq->get_repo_path( $eroot, 'gentoo' ), '/usr/portage', "trying for ('$eroot','gentoo')" );
    };
};

subtest 'get_repos($eroot)', sub {
    my $eroot = 't/data';
    is_deeply( $portageq->get_repos($eroot), [ 'local', 'gentoo' ], "trying for ('$eroot')" );
};

done_testing();
