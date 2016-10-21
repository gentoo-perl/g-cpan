#!/usr/bin/env perl

use strict;
use warnings;

use Test::More tests => 2;

BEGIN {
    use_ok('Gentoo') or BAIL_OUT("Can't load Gentoo module");
    new_ok('Gentoo') or BAIL_OUT("Can't load create Gentoo object");
}
