#
#===============================================================================
#
#         FILE:  01config.t
#
#  DESCRIPTION:  Test Gentoo::Config
#
#        FILES:  ---
#         BUGS:  ---
#        NOTES:  ---
#       AUTHOR:  Michael Cummings (), <mcummings@gentoo.org>
#      COMPANY:  Gentoo
#      VERSION:  1.0
#      CREATED:  05/09/06 14:03:26 EDT
#     REVISION:  ---
#===============================================================================

use strict;
use warnings;

use Test::More tests => 6;


# Verify we can load Gentoo name space
BEGIN { use_ok('Gentoo'); }

# Can we call new?
my $GC = Gentoo->new();
ok( defined($GC), 'new() works' );

# Can we get the PORTDIR value?
ok( $GC->getEnv("PORTDIR"), 'getEnv("PORTDIR") worked' );

# Can we get the PORTDIR_OVERLAY?
ok( $GC->getEnv("PORTDIR_OVERLAY"), 'Got PORTDIR_OVERLAY' );

# Can we grab USE flags?
ok( $GC->getEnv("USE"), 'Got USE flags' );

# What if we try to grab something bogus? This is to eliminate that
# we've gotten false positives up to this point.
ok( ! $GC->getEnv("BOGUS"), 'Fake data test' );

exit(0);
# last test to print
