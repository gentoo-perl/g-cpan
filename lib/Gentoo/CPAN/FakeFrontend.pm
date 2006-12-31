package Gentoo::CPAN::FakeFrontend;

use 5.008000;
use strict;
use warnings;

require Exporter;

our @ISA = qw(Exporter Gentoo::CPAN );

our @EXPORT = qw( myprint mywarn );

our $VERSION = "0.02";

sub myprint {
	my ($self, $text) = @_;
	my @fake_results;
	# if there is only one result, the string is different
	if ( $text =~ m{Module id} )
	{
		$text =~ s{Module id = }{\n};
		$text =~ s{\n\n}{}gmx;
		push @fake_results, $text;
		return (@fake_results) ;
	}
}

sub mywarn {
    return;
}
1;

