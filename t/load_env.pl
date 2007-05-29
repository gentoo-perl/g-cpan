#!/usr/bin/perl 
#===============================================================================
#
#         FILE:  load_env.pl
#
#        USAGE:  ./load_env.pl 
#
#  DESCRIPTION:  
#
#      OPTIONS:  ---
# REQUIREMENTS:  ---
#         BUGS:  ---
#        NOTES:  ---
#       AUTHOR:  Michael Cummings (), <mcummings@gentoo.org>
#      COMPANY:  Gentoo
#      VERSION:  1.0
#      CREATED:  05/26/07 10:40:52 EDT
#     REVISION:  ---
#===============================================================================

use strict;
use warnings;

use Shell::EnvImporter;
my $import = Shell::EnvImporter->new(
		file => "t/SET_ENV",
		shell => 'bash',
		auto_run => 1,
		auto_import=>1,
		import_modified => 1,
		import_added => 1,
		import_removed =>1,
	) or die "Import failed: $!";
$import->shellobj->envcmd('set');
$import->run();
$import->env_import();
