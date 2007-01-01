package Gentoo::CPAN::FakeFrontend;

use 5.008000;
use strict;
use warnings;
use Gentoo::UI::Console;

require Exporter;

our @ISA = qw(Exporter Gentoo::CPAN );

our @EXPORT = qw( myprint mywarn );

our $VERSION = "0.02";

sub myprint {
	my ($self, $text) = @_;
    spinner_start();
	my @fake_results;
	# if there is only one result, the string is different
    chomp($text);
	if ( $text =~ m{Module } )
	{
	$text =~ s{Module id = }{\n};
        if ($text =~ m{\n})  { 
            $text =~ s{\d+ items found}{};
            @fake_results = split (/\n/, $text);
            return(@fake_results);
        
        }
		$text =~ s{\n\n}{}gmx;
		push @fake_results, $text;
		return (@fake_results) ;
	}
}

sub mywarn {
    return;
}
1;

