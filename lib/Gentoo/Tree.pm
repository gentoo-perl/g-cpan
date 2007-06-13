package Gentoo::Tree;
#
#===============================================================================
#
#         FILE:  Tree.pm
#
#  DESCRIPTION:  Abstract out the dealing with the Gentoo tree from the particular packagemanager in use. The goal is to seperate into this module those aspects of dealing with the Gentoo tree that are UNIVERSAL* regardless of the packagemanger being employed.
#
#        FILES:  ---
#         BUGS:  ---
#        NOTES:  ---
#       AUTHOR:  Michael Cummings (), <mcummings@gentoo.org>
#      COMPANY:  Gentoo
#      VERSION:  1.0
#      CREATED:  06/13/07 06:05:45 EDT
#     REVISION:  ---
#===============================================================================

use strict;
use warnings;
#use Smart::Comments '###', '####';
use Shell::EnvImporter;

require Exporter;
use base qw(Exporter);

our @EXPORT_OK = qw( get_env );
our %EXPORT_TAGS = (all => [qw(&get_env)]);

our $VERSION = '0.01';

sub new
{
    my $proto = shift;
    my %args  = @_;
    my $class = ref($proto) || $proto;
    my $self  = {};
    foreach my $arg (keys %args)
    {
        $self->{$arg} = $args{$arg};
    }
    return bless($self, $class);
}

sub get_env
{

	use Gentoo::Util;
    #IMPORT VARIABLES
    my $self   = shift;
    my $envvar = shift;
    my $filter = sub {
        my ($var, $value, $change) = @_;
        return ($var =~ /^$envvar$/);
    };
	my $env_file;

    foreach my $file ("$ENV{HOME}/.gcpanrc", "/etc/make.conf", "/etc/make.globals")
    {
        if (-f $file)
        {
			$env_file++;
            my $importer = Shell::EnvImporter->new(
                file          => $file,
                shell         => 'bash',
                import_filter => $filter,
            );
            $importer->shellobj->envcmd('set');
            $importer->run();
            if (defined($ENV{$envvar}) && ($ENV{$envvar} =~ m{\W*}))
            {
                my $tm = Gentoo::Util->strip_env($ENV{$envvar});
                $importer->restore_env;
				if ($tm =~ m{\w\s+\w}) 
				{
					my @components = split / /, $tm;
					foreach my $possible_path (@components)
					{
						if (-d $possible_path)
						{
							return $possible_path
						}
					}
				}
                return $tm;
            }

        }
    }
	if ( ! $env_file ) { return $self->{E} = "No environment files found! Failed to find .gcpanrc, /etc/make.conf, or /etc/make.globals" }
	return;
}


return 1;
