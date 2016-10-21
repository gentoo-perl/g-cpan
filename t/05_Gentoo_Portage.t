#!/usr/bin/env perl

use strict;
use warnings;

use Test::More tests => 2;

use_ok('Gentoo::Portage');

my $portage = new_ok('Gentoo::Portage');
