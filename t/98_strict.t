#!/usr/bin/env perl
# check syntax, presence of 'use strict' & 'use warnings'

use strict;
use warnings;

use Test::More;

# skip if doing a regular tests
plan skip_all => "Developer's tests not required for installation"
  unless $ENV{DEV_TESTING};

eval { require Test::Strict; };    ## no critic (ErrorHandling::RequireCheckingReturnValueOfEval)
plan skip_all => 'Test::Strict required' if $@;

{
	no warnings 'once';            ## no critic (TestingAndDebugging::ProhibitNoWarnings)
	$Test::Strict::TEST_WARNINGS = 1;
}

Test::Strict::all_perl_files_ok(qw( bin lib t ));
