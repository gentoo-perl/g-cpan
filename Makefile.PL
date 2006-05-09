use 5.008008;
use ExtUtils::MakeMaker;

my @programs_to_install = qw ( g-cpan );
# See lib/ExtUtils/MakeMaker.pm for details of how to influence
# the contents of the Makefile that is written.
WriteMakefile(
    NAME              => 'Gentoo',
    VERSION_FROM      => 'lib/Gentoo.pm', # finds $VERSION
	EXE_FILES         => [ map "bin/$_", @programs_to_install ],
    PREREQ_PM         => {
						'File::Spec'       => 0,
						'File::Path'       => 0,
						'File::Basename'   => 0,
						'File::Copy'       => 0,
						'Term::ANSIColor'  => 0,
						'YAML'             => 0,
	                    'YAML::Node'       => 0,
						}, # e.g., Module::Name => 1.1
    ($] >= 5.005 ?     ## Add these new keywords supported since 5.005
      (ABSTRACT_FROM  => 'lib/Gentoo.pm', # retrieve abstract from module
       AUTHOR         => 'A. U. Thor <mcummings@datanode.net>') : ()),
    LIBS              => [''], # e.g., '-lm'
    DEFINE            => '', # e.g., '-DHAVE_SOMETHING'
    INC               => '-I.', # e.g., '-I. -I/usr/include/other'
	# Un-comment this if you add C files to link with later:
    # OBJECT            => '$(O_FILES)', # link all the C files too
);
