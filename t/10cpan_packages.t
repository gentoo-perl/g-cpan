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

if ( ( $needs_cpan_stub || ( $> > 0 ) ) and not _init_cpan_config() ) {
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


sub _init_cpan_config {
    my $cpan_home = "$ENV{HOME}/.cpan";
    my $configpm  = "$cpan_home/CPAN/MyConfig.pm";
    unless ( -f $configpm ) {
        # NOTE: such code doesn't work due to a weird bug in CPAN::FirstTime::init
        #       - didn't resolve %args correctly
        # ensure to exists due to respect for CPAN detecting mechanism
        #mkdir $cpan_home unless -d $cpan_home;
        #require CPAN;
        #require CPAN::FirstTime;
        #$configpm = CPAN::HandleConfig::make_new_config();
        #CPAN::FirstTime::init( $configpm, autoconfig => 1 );

        # so try to use our stub
        require Gentoo::CPAN;
        eval { Gentoo::CPAN->makeCPANstub(); };
    }
    return -f $configpm;
}
