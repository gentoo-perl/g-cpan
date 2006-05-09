#
#===============================================================================
#
#         FILE:  10cpan_packages.t
#
#  DESCRIPTION:  Test Gentoo::Ebuild Functionality
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
	plan qw(no_plan);
}

use strict;
use warnings;

# Verify we can load Gentoo name space
BEGIN { use_ok(' Gentoo'); }

# Can we call new?
my $GC = Gentoo->new();
ok( defined($GC), 'new() works' );


# Can we get the PORTDIR value?
ok( $GC->getValue("PORTDIR"), 'getValue("PORTDIR") worked' );

$GC->getCPANPackages();
# Test getting the contents of a directory
ok( $GC->{modules}, 'Digested available versions' );
ok( $GC->{modules}{cpan}, 'Portage_lc check' );
ok( $GC->{modules}{cpan_lc}, 'Digested available versions' );
foreach my $mod (keys %{$GC->{moduels}{cpan}} ) {
	ok($mod, '$mod has value');
	ok($GC->{modules}{cpan}{$mod}, '$mod has version');
}
foreach my $mod (keys %{$GC->{modules}{cpan_lc}} ) {
	ok($mod, '$mod has value');
	ok($GC->{modules}{cpan_lc}{$mod}, "$mod name check");
}

#MPC $GC->debug;
