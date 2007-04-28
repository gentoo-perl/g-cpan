package Gentoo::UI::Console;

use 5.008007;
use strict;
use warnings;
use Term::ANSIColor;
use Log::Agent;

require Exporter;

our @ISA = qw(Exporter Gentoo );

our @EXPORT = qw( print_ok print_info print_warn print_err print_out fatal spinner_start spinner_stop $green $white $cyan $reset);

our $VERSION = '0.02';

our $spin = 0;

our $green = color("bold green");
our $white = color("bold white");
our $cyan  = color("bold cyan");
our $reset = color("reset");

sub new {
    my $proto = shift;
    my %args  = @_;
    my $class = ref($proto) || $proto;
    bless {}, $class;
}

################
# Display subs #
################

# cab - four (very fast) subs to help formating text output. Guess they could be improved a lot
# maybe i should add a FIXME - Sniper around here.. :)
# anyway, they expect a string and add a colored star at the beginning and the CR/LF
# at the end of the line. oh, shiny world ;)
#
# dams - bit of factorization

sub print_colored { print ' ' . color(shift) . '* ' . color("reset") . shift() , "\n" }

# These methods take as args  :
# - the program name (1 string)
# - additional args to be printed

sub print_ok {
    print_colored('bold green', shift, @_);
    logsay "@_";
}

sub print_info {
    print_colored('bold cyan',  shift, @_);
    logsay "[INFO] @_";
}

sub print_warn {
    print_colored('bold yellow', shift, @_);
    logerr "[WARNING] @_";
}

sub print_err {
    print_colored('bold red', shift, @_);
    logerr "[ERROR] @_";
}

# For the occasional freeform text
sub print_out { print @_ }


#################################################
# NAME  : fatal
# AUTHOR: David "Sniper" Rigaudiere
# OBJECT: die like with pattern format
#
# IN: 0 scalar pattern sprintf format
#     x LIST   variables filling blank in pattern
#################################################
sub fatal { exit }
 
sub spinner_start {
    print "\r".('/', '-', '\\', '|')[$spin++%4];
}

sub spinner_stop { print "\r\r" }


1;

__END__

=pod

=head1 NAME

Gentoo::UI::Console - Console based display methods

=head1 SYNOPSIS

    use File::Basename;
    use Gentoo::UI::Console;
    print_ok("Everything looks good");
    print_err("Danger, danger Will Robinson!");
    fatal(print_info("Dieing was never so sweet"));

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

=item print_ok($message)

Print a message with a green indicator.

=item print_info($message)

Print a message with a cyan indicator.

=item print_warn($message)

Print a message with a yellow indicator.

=item print_err($message)

Print a message with a red indicator

=item print_out($message)

Print a message to STDOUT, no indicator. This function is intended for
messages that shouldn't be marked with an indicator, such as free form text.

=item fatal($message)

Print passed message (including calling another C<Gentoo::UI::Console>
message) and exiting the program.

=cut
