#!/usr/bin/env perl

use strict;
use warnings;

use Test::More tests => 7;

use_ok('Gentoo');
my $GC = new_ok('Gentoo');

ok( !$GC->getEnv('BOGUS'), 'Fake data test' );

ok( $GC->getEnv('DISTDIR'),         'getEnv("DISTDIR")' );
ok( $GC->getEnv('PORTDIR'),         'getEnv("PORTDIR")' );
ok( $GC->getEnv('PORTDIR_OVERLAY'), 'Got PORTDIR_OVERLAY' );
ok( $GC->getEnv('USE'),             'Got USE flags' );
