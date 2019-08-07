#!/usr/bin/env perl
# check if your MANIFEST matches your distro

use strict;
use warnings;

use ExtUtils::Manifest;
use Test::More tests => 2;

# skip if doing a regular tests
plan skip_all => "Developer's tests not required for installation"
  unless $ENV{DEV_TESTING};

is_deeply [ ExtUtils::Manifest::manicheck() ], [], 'no missing files';
is_deeply [ ExtUtils::Manifest::filecheck() ], [], 'no extra files';
