use 5.008007;
use strict;
use warnings;

use ExtUtils::MakeMaker;

# WriteMakefile arguments
my %args = (
    NAME         => 'g-cpan',
    ABSTRACT     => 'Install modules from CPAN in a portage friendly way',
    AUTHOR       => 'Michael Cummings <mcummings@gentoo.org>, Robin H. Johnson <robbat2@gentoo.org>',
    VERSION_FROM => 'bin/g-cpan',
    LICENSE      => 'gpl',
    EXE_FILES    => ['bin/g-cpan'],
    PREREQ_PM    => {
        'Log::Agent'         => 0,
        'Shell::EnvImporter' => 0,
        'Test::More'         => 0.94,
        'YAML'               => 0,
    },
);

WriteMakefile(%args);
