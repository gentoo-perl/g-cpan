#!/usr/bin/env perl

use strict;
use warnings;

use Test::More tests => 6;


# Verify we can load Gentoo name space
BEGIN { use_ok('Gentoo'); }

my $GC = new_ok('Gentoo');

# Can we get the PORTDIR value?
ok( $GC->getEnv("PORTDIR"), 'getEnv("PORTDIR") worked' );

# Can we get the PORTDIR_OVERLAY?
ok( $GC->getEnv("PORTDIR_OVERLAY"), 'Got PORTDIR_OVERLAY' );

# Can we grab USE flags?
ok( $GC->getEnv("USE"), 'Got USE flags' );

# What if we try to grab something bogus? This is to eliminate that
# we've gotten false positives up to this point.
ok( ! $GC->getEnv("BOGUS"), 'Fake data test' );
