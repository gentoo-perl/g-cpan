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
        plan tests => 5;
    }
}

use strict;
use warnings;

use_ok('Gentoo');
my $GC = new_ok('Gentoo');

ok( $GC->getEnv('PORTDIR'), 'getEnv("PORTDIR") worked' );
ok( $GC->getEnv('DISTDIR'), 'getEnv("DISTDIR") worked' );

my $module = 'Module::Build';
subtest "retrieve and check information for $module", sub {
    $GC->getCPANInfo($module);
    my $module_lc = lc($module);
    ok( $GC->{cpan}{$module_lc},              'information obtained' );
    ok( $GC->{cpan}{$module_lc}{version},     'has version' );
    ok( $GC->{cpan}{$module_lc}{name},        'has a name' );
    ok( $GC->{cpan}{$module_lc}{src_uri},     'has src_uri' );
    ok( $GC->{cpan}{$module_lc}{description}, 'has a description' );
};
