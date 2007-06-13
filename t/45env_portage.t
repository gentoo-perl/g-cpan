#
#===============================================================================
#
#         FILE:  45env_portage.t
#
#  DESCRIPTION:  
#
#        FILES:  ---
#         BUGS:  ---
#        NOTES:  ---
#       AUTHOR:  Michael Cummings (), <mcummings@gentoo.org>
#      COMPANY:  Gentoo
#      VERSION:  1.0
#      CREATED:  06/13/07 06:00:44 EDT
#     REVISION:  ---
#===============================================================================
do "t/load_env.pl";

use strict;
use warnings;
#use Smart::Comments '###', '####';

use Test::More tests => 8;                      # last test to print

BEGIN { use_ok('Gentoo::Tree') }

my $tree = Gentoo::Tree->new();
ok(defined $tree, 'new() works');

# Get PORTDIR
my $PORTDIR = $tree->get_env('PORTDIR');
isnt($tree->{E},defined,"No error returned");
### $PORTDIR
ok(-d $PORTDIR, "PORTDIR found");

# Get PORTDIR_OVERLAY
my $OVERLAY = $tree->get_env('PORTDIR_OVERLAY');
isnt($tree->{E},defined,"No error returned");
### $OVERLAY
ok(-d $OVERLAY, "OVERLAY found");

# Get USE
my $USE = $tree->get_env('USE');
isnt($tree->{E},defined,"No error returned");
ok($USE =~ /\w+/, "USE found");
exit(0);

