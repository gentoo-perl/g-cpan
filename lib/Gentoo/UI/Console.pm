package Gentoo::UI::Console;

use 5.008007;
use strict;
use warnings;
use Term::ANSIColor;

#
#===============================================================================
#
#         FILE:  Console.pm
#
#  DESCRIPTION:  Console related functions
#
#        FILES:  ---
#         BUGS:  ---
#        NOTES:  ---
#       AUTHOR:  Michael Cummings (), <mcummings@gentoo.org>
#      COMPANY:  Gentoo
#      VERSION:  1.0
#      CREATED:  05/10/06 12:11:37 EDT
#     REVISION:  ---
#===============================================================================

require Exporter;

our @ISA = qw(Exporter Gentoo );

our @EXPORT = qw( print_ok print_info print_warn print_err print_out fatal );

our $VERSION = '0.01';

sub new
{
    my $proto = shift;
    my %args  = @_;
    my $class = ref($proto) || $proto;
    my $self  = {};
    bless($self, $class);
    return $self;
}


################
# Display subs #
################

# cab - four (very fast) subs to help formating text output. Guess they could be improved a lot
# maybe i should add a FIXME - Sniper around here.. :)
# anyway, they expect a string and add a colored star at the beginning and the CR/LF
# at the end of the line. oh, shiny world ;)
sub print_ok {
    my $prog = shift;
	print " ", color("bold green"), "* ", color("reset"), "$prog: ", @_, "\n";
    return;
}
sub print_info {
    my $prog = shift;
	print " ", color("bold cyan"), "* ", color("reset"), "$prog: ", @_, "\n";
    return;
}
sub print_warn {
    my $prog = shift;
	print " ", color("bold yellow"), "* ", color("reset"), "$prog: ", @_, "\n";
    return;
}
sub print_err{
    my $prog = shift;
	print " ", color("bold red"), "* ", color("reset"), "$prog: ", @_, "\n";
    return;
}

# For the occasional freeform text
sub print_out{
    print @_;
    return;
}


#################################################
# NAME  : fatal
# AUTHOR: David "Sniper" Rigaudiere
# OBJECT: die like with pattern format
#
# IN: 0 scalar pattern sprintf format
#     x LIST   variables filling blank in pattern
#################################################
sub fatal { 
	exit();
 }


1;
