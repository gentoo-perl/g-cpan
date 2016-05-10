#!/usr/bin/env perl
# check for spelling errors in POD

use strict;
use warnings;

use Test::More;

# skip if doing a regular tests
plan skip_all => "Developer's tests not required for installation"
  unless $ENV{DEV_TESTING};

eval { require Test::Spelling; Test::Spelling->VERSION(0.11); }; ## no critic (ErrorHandling::RequireCheckingReturnValueOfEval)
plan skip_all => 'Test::Spelling (>=0.11) required' if $@;

Test::Spelling::add_stopwords(<DATA>);

Test::Spelling::all_pod_files_spelling_ok(qw( bin lib ));

__DATA__
CPAN
Gentoo
Gentoo's
buildpkg
buildpkgonly
ebuild
ebuilds
g-cpan
namespace
