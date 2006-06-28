package Gentoo::UI::Console;

use 5.008007;
use strict;
use warnings;
use Term::ANSIColor;
use Log::Agent;

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

sub new {
    my $proto = shift;
    my %args  = @_;
    my $class = ref($proto) || $proto;
    my $self  = {};
    bless( $self, $class );
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
    logsay "@_";
    return;
}

sub print_info {
    my $prog = shift;
    print " ", color("bold cyan"), "* ", color("reset"), "$prog: ", @_, "\n";
    logsay "@_";
    return;
}

sub print_warn {
    my $prog = shift;
    print " ", color("bold yellow"), "* ", color("reset"), "$prog: ", @_, "\n";
    logerr "@_";
    return;
}

sub print_err {
    my $prog = shift;
    print " ", color("bold red"), "* ", color("reset"), "$prog: ", @_, "\n";
    logerr "@_";
    return;
}

# For the occasional freeform text
sub print_out {
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

__END__

=pod

=head1 NAME

Gentoo::UI::Console - Console based display methods

=head1 SYNOPSIS

    use File::Basename;
    use Gentoo::UI::Console;
    my $prog_name = basename($0);
    print_ok($prog_name,"Everything looks good");
    print_err($prog_name,"Danger, danger Will Robinson!");
    fatal(print_info($prog_name,"Dieing was never so sweet"));

=head1 DESCRIPTION

C<Gentoo::UI::Console> is intended as the first in a series of methods for
returning text to the user.

=head1 INVOCATION

All of C<Gentoo::UI::Console> functions except for fatal take two paramaters,
the name of the program calling the function, and the message to be displayed.
fatal() is simple a short cut to passing text and exiting the program
gracefully.

=head1 Methods

=over 4

=item print_ok($prog, $message)

Print a message with a green indicator.

=item print_info($prog, $message)

Print a message with a cyan indicator.

=item print_warn($prog, $message)

Print a message with a yellow indicator.

=item print_err($prog, $message)

Print a message with a red indicator

=item print_out($message)

Print a message to STDOUT, no indicator. This function is intended for
messages that shouldn't be marked with an indicator, such as free form text.

=item fatal($message)

Print passed message (including calling another C<Gentoo::UI::Console>
message) and exiting the program.

=cut
