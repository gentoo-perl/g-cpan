package Gentoo;

use 5.008007;
use strict;
use warnings;
use Data::Dumper;
use Log::Agent;

#### Load the other namespaces.
#### Gentoo.pm is the primary if these aren't accessed directly.

use Gentoo::Portage;
use Gentoo::CPAN;

# These libraries were influenced and largely written by
# Christian Hartmann <ian@gentoo.org> originally. All of the good
# parts are ian's - the rest is mcummings messing around.

require Exporter;
our @ISA = qw( Exporter UNIVERSAL );

our $VERSION = '0.01';

##### ERRORS constants (easy internationalisation ;-) #####
use constant ERR_FILE_NOTFOUND   => "Couldn't find file '%s'";      # filename
use constant ERR_FOLDER_NOTFOUND => "Couldn't find folder '%s'";    # foldername
use constant ERR_OPEN_READ       =>
  "Couldn't open (read) file '%s' : %s";    # filename, $!
use constant ERR_OPEN_WRITE =>
  "Couldn't open (write) file '%s' : %s";    # filename, $!
use constant ERR_FOLDER_OPEN =>
  "Couldn't open folder '%s', %s";           # foldername, $!
use constant ERR_FOLDER_CREATE =>
  "Couldn't create folder '%s' : %s";        # foldername, $!

sub _init {
    my ( $self, %args ) = @_;
    return if $self->{_init}{__PACKAGE__}++;
    $self->Gentoo::Portage::_init(%args);
}

sub UNIVERSAL::debug {
    my ( $package, $file, $line ) = caller();
    my $subroutine = ( caller(1) )[3] || $package;
    print STDERR "In $subroutine ($file:$line):\n",
      Data::Dumper->Dump( [ $_[0] ] );
    logerr("In $subroutine ($file:$line:\n".Data::Dumper->Dump( [ $_[0]]));
}

sub new {
    my ( $class, %args ) = @_;
    my $self = {
        cpan_reload        => $args{cpan_reload},    # used in Gentoo::CPAN only
        debug              => $args{debug},
        modules            => {},
        portage_categories => [],
        portage_bases      => {},
    };
    return bless $self, $class;
}

sub DESTROY {
    my ($self) = @_;
    return if $self->{DESTROY}{__PACKAGE__}++;

    $self->Gentoo::Portage::DESTROY();
}

1;
__END__

=head1 NAME

Gentoo - Base perl class for working with the Gentoo:: namespace.

=head1 SYNOPSIS

  use Gentoo;
  my $gentoo_obj = Gentoo->new( cpan_reload => 1 );

=head1 DESCRIPTION

Base class for the Gentoo namespace, providing access to the rest of the
Gentoo::modules.

=head1 METHODS

=head2 new(%args)

Create an object.

=head1 SEE ALSO

See L<Gentoo::Portage>, L<Gentoo::CPAN>.

=cut
