use 5.008007;
use ExtUtils::MakeMaker;

my @programs_to_install = qw ( g-cpan );
# See lib/ExtUtils/MakeMaker.pm for details of how to influence
# the contents of the Makefile that is written.
WriteMakefile(
    NAME              => 'g-cpan',
    VERSION_FROM      => 'bin/g-cpan', # finds $VERSION
	EXE_FILES         => [ map "bin/$_", @programs_to_install ],
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

						}, # e.g., Module::Name => 1.1
    ($] >= 5.005 ?     ## Add these new keywords supported since 5.005
      (ABSTRACT  =>      'Install modules from CPAN in a portage friendly way', 
       AUTHOR         => 'Michael Cummings <mcummings@gentoo.org>') : ()),
    LIBS              => [''], # e.g., '-lm'
    DEFINE            => '', # e.g., '-DHAVE_SOMETHING'
    INC               => '-I.', # e.g., '-I. -I/usr/include/other'
);

# PERL_DL_NONLAZY=1 /usr/bin/perl5.8.8 "-MExtUtils::Command::MM" "-e" "test_harness(0, 'lib')" t/*.t
