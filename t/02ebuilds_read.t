#!/usr/bin/env perl

use strict;
use warnings;

use Test::More qw(no_plan);
#tests => 5;

BEGIN { use_ok('Gentoo'); }

my $GC = new_ok('Gentoo');

my $portdir;
# Can we get the PORTDIR value?
ok(  $portdir = $GC->getEnv("PORTDIR"), 'getEnv("PORTDIR") worked' );

# test getting the contents of a category directory
my $category = 'dev-perl';
$GC->getAvailableEbuilds( $portdir, $category );
ok( $GC->{packagelist}, "Grabbed '$category'" );

# test getting information for package
$GC->{portage_categories} = [$category];
my $package = 'URI';
$GC->getAvailableVersions( $portdir, $package );
ok( $GC->{portage}, "Digested available versions for '$package'" );

foreach my $pn ( keys %{ $GC->{portage} } ) {
    ok( $pn,                           '$pn has value' );
    ok( $GC->{portage}{$pn},           '$pn has version' );
    ok( $GC->{portage}{$pn}{name},     "'$pn' name check" );
    ok( $GC->{portage}{$pn}{category}, "'$pn' category check" );
}
