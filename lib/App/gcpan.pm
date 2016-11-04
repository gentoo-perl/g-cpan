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

=head1 METHODS

=head2 run()

Only stub now, for future usage.

=cut

sub run { return 1; }


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
