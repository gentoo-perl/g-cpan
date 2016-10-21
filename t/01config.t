#!/usr/bin/env perl

use strict;
use warnings;

use Test::More tests => 2;

use_ok('Gentoo');
my $GC = new_ok('Gentoo');
