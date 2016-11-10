package App::gcpan;

=head1 NAME

App::gcpan - install CPAN-provided Perl modules using Gentoo's Portage

=head1 SYNOPSIS

    use App::gcpan;

=head1 DESCRIPTION

App::gcpan is a base for L<g-cpan> script, that installs a CPAN module (including its dependencies) using Gentoo's Portage.
See L<g-cpan> for more information.

=head2 CURRENT STATE

At the moment module is under heavy development. Slowly move all code from C<g-cpan> script into here.

=cut

use strict;
use warnings;

use Gentoo::Portage::Q;


=head1 METHODS

=head2 run()

Only stub now, for future usage.

=cut

sub run {
    my $class = shift;

    my $env = $class->setup_env();

    return 1;
}


=head2 setup_env()

Initialize and setup all environment vars required for C<g-cpan> work
Returns hashref with C<env> variables.

=cut

sub setup_env {
    my $class = shift;

    my $portageq = Gentoo::Portage::Q->new();

    my %env = (
        ACCEPT_KEYWORDS => $portageq->envvar('ACCEPT_KEYWORDS'),
        GCPAN_CAT       => $portageq->envvar('GCPAN_CAT') || 'perl-gcpan',
        GCPAN_OVERLAY   => $portageq->envvar('GCPAN_OVERLAY'),
        DISTDIR         => $portageq->envvar('DISTDIR'),
        PORTDIR         => $portageq->envvar('PORTDIR'),
        PORTDIR_OVERLAY => $portageq->envvar('PORTDIR_OVERLAY'),
    );

    return \%env;
}


1;

__END__

=head1 SEE ALSO

L<g-cpan>

=head1 BUGS

Please report bugs via L<https://github.com/gentoo-perl/g-cpan/issues> or L<https://bugs.gentoo.org/>.

=head1 AUTHOR

Sergiy Borodych <bor@cpan.org>

For original authors of original C<g-cpan> script please look into it.

=head1 COPYRIGHT AND LICENSE

Copyright 1999-2016 Gentoo Foundation.

Distributed under the terms of the GNU General Public License v2.

=cut
