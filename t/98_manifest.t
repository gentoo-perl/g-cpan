#!/usr/bin/env perl
# check if your Manifest matches your distro

use strict;
use warnings;

use Test::More;

# skip if doing a regular tests
plan skip_all => "Developer's tests not required for installation"
  unless $ENV{DEV_TESTING};

eval { require Test::CheckManifest; };    ## no critic (ErrorHandling::RequireCheckingReturnValueOfEval)
plan skip_all => 'Test::CheckManifest required' if $@;

Test::CheckManifest::ok_manifest();
