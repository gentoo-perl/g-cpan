#!/usr/bin/env perl
# validation of the Changes file

use strict;
use warnings;

use Test::More;

# skip if doing a regular tests
plan skip_all => "Developer's tests not required for installation"
  unless $ENV{DEV_TESTING};

eval { require Test::CPAN::Changes; };    ## no critic (ErrorHandling::RequireCheckingReturnValueOfEval)
plan skip_all => 'Test::CPAN::Changes required' if $@;

Test::CPAN::Changes::changes_ok();
