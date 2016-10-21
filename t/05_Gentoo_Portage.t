#!/usr/bin/env perl

use strict;
use warnings;

use Test::More tests => 3;

use_ok('Gentoo::Portage');

my $portage = new_ok('Gentoo::Portage');

subtest 'getEnv($envvar)', sub {
    ok( !$portage->getEnv('BOGUS'),          'fake data test' );
    ok( $portage->getEnv('DISTDIR'),         'get DISTDIR' );
    ok( $portage->getEnv('PORTDIR'),         'get PORTDIR' );
    ok( $portage->getEnv('PORTDIR_OVERLAY'), 'get PORTDIR_OVERLAY' );
    ok( $portage->getEnv('USE'),             'get USE flags' );
};
