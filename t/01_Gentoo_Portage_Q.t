#!/usr/bin/env perl

use lib 'lib';
use strict;
use warnings;

use Path::Tiny;
use Test::More tests => 5;

use_ok('Gentoo::Portage::Q');

my ( $portageq, $portageq_prefix, $portageq_real );

subtest 'new' => sub {
    $portageq        = new_ok('Gentoo::Portage::Q');
    $portageq_prefix = do {
        local $ENV{ROOT}    = Path::Tiny->cwd;
        local $ENV{EPREFIX} = '/t/data';
        new_ok( 'Gentoo::Portage::Q' => [], 'new with EPREFIX' );
    };
    if ( -e '/etc/gentoo-release' ) {
        $portageq_real = new_ok( 'Gentoo::Portage::Q' => [], 'new for real Gentoo instance' );
    }
};

subtest 'envvar($variable)', sub {
    is( $portageq->envvar('EROOT'), '/', 'EROOT' );
    ok( $portageq->envvar('DISTDIR'), 'DISTDIR' );
    like( $portageq->envvar('USE'), qr/^\w[\w\s\-]*$/, 'USE' );
    ok( !$portageq->envvar('SOME_BOGUS_VAR'), 'fake var' );

    subtest 'with EPREFIX', sub {
        is( $portageq_prefix->envvar('EPREFIX'), '/t/data', 'EPREFIX' );
        like( $portageq_prefix->envvar('EROOT'), qr%^/.+?/t/data\z%, 'EROOT' );
    };

    subtest 'real Gentoo Linux', sub {
        plan skip_all => 'nope' unless $portageq_real;
        like( $portageq_real->envvar('ARCH'),            qr/^~?[\w\-]+$/, 'ARCH' );
        like( $portageq_real->envvar('ACCEPT_KEYWORDS'), qr/^~?[\w\-]+$/, 'ACCEPT_KEYWORDS' );
        ok( $portageq_real->envvar('MAKEOPTS'), 'MAKEOPTS' );
    };
};

subtest 'get_repo_path( $eroot, $repo_id )', sub {
    my $eroot = 't/data';
    is( $portageq->get_repo_path( $eroot, 'gentoo' ), '/usr/portage',       "trying for ('$eroot','gentoo')" );
    is( $portageq->get_repo_path( $eroot, 'local' ),  '/usr/local/portage', "trying for ('$eroot','local')" );
    is( $portageq->get_repo_path( $eroot, 'bogus' ),  undef,                "trying for ('$eroot','bogus')" );

    subtest 'with EPREFIX', sub {
        $eroot = $portageq_prefix->envvar('EROOT');
        is( $portageq_prefix->get_repo_path( $eroot, 'gentoo' ), '/usr/portage', "('$eroot','gentoo')" );
    };

    subtest 'real Gentoo Linux', sub {
        plan skip_all => 'nope' unless $portageq_real;
        $eroot = '/';
        like(
            $portageq_real->get_repo_path( $eroot, 'gentoo' ),
            qr%(/usr/portage|/var/db/repos/gentoo)%,
            "trying for ('$eroot','gentoo')"
        );
    };
};

subtest 'get_repos($eroot)', sub {
    my $eroot = 't/data';
    is_deeply( $portageq->get_repos($eroot), [ 'local', 'gentoo' ], "trying for ('$eroot')" );
};
