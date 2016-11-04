#!/usr/bin/env perl

use strict;
use warnings;

use Test::More;

use_ok('App::gcpan');

ok( App::gcpan->run(), 'run() OK' );

done_testing();
