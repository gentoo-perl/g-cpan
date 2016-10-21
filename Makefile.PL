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
        'Config::Tiny'       => 0,
        'Log::Agent'         => 0,
        'Path::Tiny'         => 0,
        'Shell::EnvImporter' => 0,
        'YAML'               => 0,
    },
);

if ( ExtUtils::MakeMaker->VERSION >= 6.64 ) {
    $args{TEST_REQUIRES} = {
        'Test::More' => 0.94,
        # for developer tests
        #'Test::CPAN::Changes' => 0,
        #'Test::CheckManifest' => 0,
        #'Test::EOL'           => 0,
        #'Test::Pod'           => 1.40,
        #'Test::Spelling'      => 0.11,
    };
}

WriteMakefile(%args);
