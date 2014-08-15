use 5.008007;
use strict;
use warnings;
use ExtUtils::MakeMaker;

WriteMakefile(
    NAME              => 'g-cpan',
    ABSTRACT          => 'Install modules from CPAN in a portage friendly way', 
    AUTHOR            => 'Michael Cummings <mcummings@gentoo.org>, Robin H. Johnson <robbat2@gentoo.org>',
    VERSION_FROM      => 'bin/g-cpan', # finds $VERSION
    LICENSE           => 'gpl',
    EXE_FILES         => [ 'bin/g-cpan' ],
    PREREQ_PM         => {
                        'File::Basename'   => 0,
                        'File::Copy'       => 0,
                        'File::Find'       => 0,
                        'File::Path'       => 0,
                        'File::Spec'       => 0,
                        'Log::Agent'       => 0,
                        'Memoize'          => 0,
                        'IO::File'         => 0,
                        'Shell::EnvImporter' => 0,
                        'Term::ANSIColor'  => 0,
                        'Test::More'       => 0,
                        'YAML'             => 0,
                        'YAML::Node'       => 0,
    },
    NO_META   => 1,    # suppresses the generation and addition to the MANIFEST of the META.yml and META.json
    NO_MYMETA => 1,    # suppresses the generation of MYMETA.yml and MYMETA.json
);
