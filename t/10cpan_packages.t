#
#===============================================================================
#
#         FILE:  10cpan_packages.t
#
#  DESCRIPTION:  Test Gentoo::CPAN Functionality
#
#        FILES:  ---
#         BUGS:  ---
#        NOTES:  ---
#       AUTHOR:  Michael Cummings (), <mcummings@gentoo.org>
#      COMPANY:  Gentoo
#      VERSION:  1.0
#      CREATED:  05/09/06 14:36:47 EDT
#     REVISION:  ---
#===============================================================================

eval 'use CPAN::Config;';
my $needs_cpan_stub = $@ ? 1 : 0;
use Test::More;

if (   ( ($needs_cpan_stub) || ( $> > 0 ) )
    && ( !-f "$ENV{HOME}/.cpan/CPAN/MyConfig.pm" ) )
{
	plan skip_all => 'Tests impossible without a configured CPAN::Config';
}
else {
    if ( $> > 0 )
    {
        plan skip_all => 'Root needed for these tests, sorry';
    }
    else
    {
        plan tests => 9;
    }
}

use strict;
use warnings;

my $module = "Module::Build";

use_ok('Gentoo');
my $GC = new_ok('Gentoo');

ok( $GC->getEnv('PORTDIR'), 'getEnv("PORTDIR") worked' );
ok( $GC->getEnv('DISTDIR'), 'getEnv("DISTDIR") worked' );

$GC->getCPANInfo($module);
# Test getting the contents of a directory
ok( $GC->{cpan}, 'Information for $module obtained' );
ok($GC->{cpan}{lc($module)}{'version'}, '$module has version');
ok($GC->{cpan}{lc($module)}{'name'}, '$module has a name');
ok($GC->{cpan}{lc($module)}{'src_uri'}, '$module has src_uri');
ok($GC->{cpan}{lc($module)}{'description'}, '$module has a description');

#MPC $GC->debug;
