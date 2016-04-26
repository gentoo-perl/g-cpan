#!/usr/bin/env perl

use strict;
use warnings;

use Test::More;

use_ok('App::gcpan');

TODO: {
    todo_skip 'need a lot of refatoring', 1;
    #ok( App::gcpan->run(), 'run() OK' );
}

done_testing();
