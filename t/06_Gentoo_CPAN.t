#!/usr/bin/env perl

use strict;
use warnings;

use Test::More;

eval { require CPAN::Config; };
my $needs_cpan_stub = $@ ? 1 : 0;

my $cpan_home = "$ENV{HOME}/.cpan";
my $configpm  = "$cpan_home/CPAN/MyConfig.pm";
$needs_cpan_stub = 0 if -f $configpm;

if ( $needs_cpan_stub and $ENV{NO_NETWORK_TESTING} ) {
    plan skip_all => 'since network activity is disabled (NO_NETWORK_TESTING is set)';
}
elsif ( $needs_cpan_stub and not _init_cpan_config() ) {
    plan skip_all => 'Tests impossible without a configured CPAN::Config';
}
else {
    plan tests => 4;
}

use_ok('Gentoo::CPAN');
my $cpan = new_ok('Gentoo::CPAN');

my $module    = 'Module::Build';
my $module_lc = lc($module);

subtest "getCPANInfo('$module')", sub {
    $cpan->getCPANInfo($module);
    ok( $cpan->{cpan}{$module_lc},              'information obtained' );
    ok( $cpan->{cpan}{$module_lc}{version},     'has version' );
    ok( $cpan->{cpan}{$module_lc}{name},        'has a name' );
    ok( $cpan->{cpan}{$module_lc}{src_uri},     'has src_uri' );
    ok( $cpan->{cpan}{$module_lc}{description}, 'has a description' );
};

subtest "transformCPAN('$cpan->{cpan}{$module_lc}{src_uri}', 'n'|'v')", sub {
    my $name = $cpan->transformCPAN( $cpan->{cpan}{$module_lc}{src_uri}, 'n' );
    is( $name, 'Module-Build', '"name" is OK' );
    my $version = $cpan->transformCPAN( $cpan->{cpan}{$module_lc}{src_uri}, 'v' );
    like( $version, qr/^\d[\d\.]+\d$/, '"version" is OK' );
};

sub _init_cpan_config {

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

    return -f $configpm;
}
