#!/usr/bin/env perl
# check the correct line endings

use strict;
use warnings;

use Test::More;

# skip if doing a regular tests
plan skip_all => "Developer's tests not required for installation"
  unless $ENV{DEV_TESTING};

eval { require Test::EOL; };    ## no critic (ErrorHandling::RequireCheckingReturnValueOfEval)
plan skip_all => 'Test::EOL required' if $@;

Test::EOL::all_perl_files_ok( { trailing_whitespace => 1 }, qw( bin lib t ) );
