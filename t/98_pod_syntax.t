#!/usr/bin/env perl
# check for POD errors

use strict;
use warnings;

use Test::More;

# skip if doing a regular tests
plan skip_all => "Developer's tests not required for installation"
  unless $ENV{DEV_TESTING};

eval { require Test::Pod; Test::Pod->VERSION(1.40); };    ## no critic (ErrorHandling::RequireCheckingReturnValueOfEval)
plan skip_all => "Test::Pod 1.40 required for testing POD" if $@;

my @files = Test::Pod::all_pod_files(qw( bin lib ));
Test::Pod::all_pod_files_ok(@files);                      # in v1.42 you can put dir here
