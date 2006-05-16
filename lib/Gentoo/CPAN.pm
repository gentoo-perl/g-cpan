package Gentoo::CPAN;

use 5.008007;
use strict;
use warnings;
use File::Spec;
use CPAN;
use File::Path;
use YAML;
use YAML::Node;
use Memoize;
use Cwd qw(getcwd abs_path cwd);
use File::Basename;

memoize('transformCPANname');
memoize('FindDeps');

# These libraries were influenced and largely written by
# Christian Hartmann <ian@gentoo.org> originally. All of the good
# parts are ian's - the rest is mcummings messing around.

require Exporter;

our @ISA = qw(Exporter Gentoo );

our @EXPORT = qw( getCPANInfo makeCPANstub unpackModule transformCPANname
);

our $VERSION = '0.01';

##### CPAN CONFIG #####
use constant CPAN_CFG_DIR  => '.cpan/CPAN';
use constant CPAN_CFG_NAME => 'MyConfig.pm';

# defaults tools for CPAN Config
use constant DEF_FTP_PROG      => '/usr/bin/ftp';
use constant DEF_GPG_PROG      => '/usr/bin/gpg';
use constant DEF_GZIP_PROG     => '/bin/gzip';
use constant DEF_LYNX_PROG     => '/usr/bin/lynx';
use constant DEF_MAKE_PROG     => '/usr/bin/make';
use constant DEF_NCFTPGET_PROG => '/usr/bin/ncftpget';
use constant DEF_LESS_PROG     => '/usr/bin/less';
use constant DEF_TAR_PROG      => '/bin/tar';
use constant DEF_UNZIP_PROG    => '/usr/bin/unzip';
use constant DEF_WGET_PROG     => '/usr/bin/wget';
use constant DEF_BASH_PROG     => '/bin/bash';

unless ( $ENV{TMPDIR} ) { $ENV{TMPDIR} = '/var/tmp/g-cpan' }

sub new {
    my $proto = shift;
    my %args  = @_;
    my $class = ref($proto) || $proto;
    my $self  = {};

    $self->{modules}            = {};
    $self->{portage_categories} = @{ $args{portage_categories} };
    $self->{DEBUG}              = $args{debug};
    $self->{portdir}            = $args{portdir};

    bless( $self, $class );
    return $self;
}

sub getCPANInfo {
    my $self        = shift;
    my $find_module = shift;
    my @tmp_v       = ();

    unless ($find_module) 
    {
        croak("No module supplied")
    }
        
    if ( $self->{cpan_reload} ) {
        # - User forced reload of the CPAN index >
        CPAN::Index->force_reload();
    }
    
    my $mod = CPAN::Shell->expand( "Module", $find_module ) ; 
# - Fetch CPAN-filename and cut out the filename of the tarball.
#   We are not using $mod->id here because doing so would end up
#   missing a lot of our ebuilds/packages >
# Addendum. Appears we are missing items both ways - have to test both the name in cpan_file and the mod->id. :/
            next unless ($mod->id);
            $self->{'cpan'}{lc($find_module)}{'description'} = $mod->{RO}{'description'}||"No description available";
            $self->{'cpan'}{lc($find_module)}{'src_uri'} = $mod->{RO}{'CPAN_FILE'};
            $self->{'cpan'}{lc($find_module)}{'name'} = $mod->id;
            $self->{'cpan'}{lc($find_module)}{'version'} = $mod->{RO}{'CPAN_VERSION'}|| "0";
    return;
}

sub unpackModule {
    my $self        = shift;
    my $module_name = shift;
    if ( $module_name !~ m|::| ) {
        $module_name =~ s{-}{::}xmsg;
    }    # Assume they gave us module-name instead of module::name

    my $obj = CPAN::Shell->expandany($module_name);
    unless ( ( ref $obj eq "CPAN::Module" )
        || ( ref $obj eq "CPAN::Bundle" )
        || ( ref $obj eq "CPAN::Distribution" ) )
    {
        warn("Don't know what '$module_name' is\n");
        return;
    }
    my $file = $obj->cpan_file;

    $CPAN::Config->{prerequisites_policy} = "";
    $CPAN::Config->{inactivity_timeout}   = 30;

    my $pack = $CPAN::META->instance( 'CPAN::Distribution', $file );
    if ( $pack->can('called_for') ) {
        $pack->called_for( $obj->id );
    }

    #$pack->called_for( $obj->id );
    # Initiate a perl Makefile.PL process - necessary to generate the deps
    $pack->make;
    $pack->unforce if $pack->can("unforce") && exists $obj->{'force_update'};
    delete $obj->{'force_update'};
    my $tmp_dir = -d $ENV{TMPDIR} ? defined( $ENV{TMPDIR} ) : $ENV{HOME};
    $tmp_dir = $pack->{build_dir};
    FindDeps( $self, $tmp_dir, $module_name );

    # Most modules don't list module-build as a dep - so we force it if there
    # is a Build.PL file
    if ( -f "Build.PL" ) {
        $self->{'cpan'}{ lc($module_name) }{'depends'}
          {"Module::Build"} = '0';
    }

    # Final measure - if somehow we got an undef along the way, set to 0
    foreach my $dep (
        keys %{ $self->{'cpan'}{ lc($module_name) }{'depends'} } )
    {
        unless (
            defined(
                $self->{'cpan'}{ lc($module_name) }{'depends'}{$dep}
            )
          )
        {
            $self->{'cpan'}{ lc($module_name) }{'depends'}{$dep} = "0";
        }
    }
    return ($self);
}

sub FindDeps {
    my $self        = shift;
    my ($workdir)   = shift;
    my $module_name = shift;
    my ($startdir)  = &cwd;
    chdir($workdir) or die "Unable to enter dir $workdir:$!\n";
    opendir( CURD, "." );
    my @dirs = readdir(CURD);
    closedir(CURD);
    my %req_list = ();

    foreach my $object (@dirs) {
        next if ( $object eq "." );
        next if ( $object eq ".." );
        if ( -f $object ) {
            my $abs_path = abs_path($object);
            if ( $object =~ m{META.yml}i ) {

                # Do YAML parsing if you can
                my $b_n = dirname($abs_path);
                $b_n = basename($b_n);
                my $arr = YAML::LoadFile($abs_path);
                foreach my $type qw(requires build_requires recommends) {
                    if ( my $ar_type = $arr->{$type} ) {
                        foreach my $module ( keys %{$ar_type} ) {
                            next if ( $module eq "" );
                            next if ( $module =~ /Cwd/i );
                            next unless ($module);
                            $self->{'cpan'}{ lc($module_name) }
                              {'depends'}{ $module } = $ar_type->{$module};
                        }
                    }
                }
            }
            if ( $object =~ m/^Makefile$/ ) {

                # Do some makefile parsing
                # RIPPED from CPAN.pm ;)
                use FileHandle;

                my $b_dir    = dirname($abs_path);
                my $makefile = File::Spec->catfile( $b_dir, "Makefile" );

                my $fh;
                my (%p) = ();
                if ( $fh = FileHandle->new("<$makefile\0") ) {
                    local ($/) = "\n";
                    while (<$fh>) {
                        chomp;
                        last if /MakeMaker post_initialize section/;
                        my ($p) = m{^[\#]
       \s{0,}PREREQ_PM\s+=>\s+(.+)
       }x;
                        next unless $p;
                        while ( $p =~ m/(?:\s)([\w\:]+)=>q\[(.*?)\],?/g ) {
                            my $module  = $1;
                            my $version = $2;
                            $self->{'cpan'}{ lc($module_name) }
                              {'depends'}{ $module } = $version;
                        }

                        last;
                    }
                }
            }
            if ( $object eq "Build.PL" ) {

                # Do some Build file parsing
                use FileHandle;
                my $b_dir = dirname($abs_path);
                my $b_n   = dirname($abs_path);
                $b_n = basename($b_n);
                my $makefile = File::Spec->catfile( $b_dir, "Build.PL" );
                my (%p) = ();
                my $fh;

                foreach my $type qw(requires recommends build_requires) {
                    if ( $fh = FileHandle->new("<$makefile\0") ) {
                        local ($/) = "";
                        while (<$fh>) {
                            chomp;
                            my ($p) = m/^\s+$type\s+=>\s+\{(.*?)\}/smx;
                            next unless $p;
                            undef($/);

                            #local($/) = "\n";
                            my @list = split( ',', $p );
                            foreach my $pa (@list) {
                                $pa =~ s/\n|\s+|\'//mg;
                                if ($pa) {
                                    my ( $module, $vers ) = split( /=>/, $pa );
                                    $self->{'cpan'}{ lc($module_name) }
                                      {'depends'}{ $module } = $vers;
                                }
                            }
                            last;

                        }
                    }
                }

            }

        }
        elsif ( -d $object ) {
            FindDeps( $self, $object, $module_name );
            next;
        }

    }
    chdir($startdir) or die "Unable to change to dir $startdir:$!\n";
    return ($self);

}

sub transformCPANVersion
{
    my $self = shift;
    my $name = shift;
    return unless ( defined($name) );
    my $re_path = '(?:.*)?';
    my $re_pkg  = '(?:.*)?';
    my $re_ver  = '(?:v?[\d\.]+[a-z]?)?';
    my $re_suf  = '(?:_(?:alpha|beta|pre|rc|p)(?:\d+)?)?';
    my $re_rev  = '(?:\-r\d+)?';
    my $re_ext  = '(?:(?:tar|tgz|zip|bz2|gz|tar\.gz))?';
    my $re_file =
      qr/($re_path)\/($re_pkg)-($re_ver)($re_suf)($re_rev)\.($re_ext)/;
    my ( $modpath, $filename, $filenamever, $filesuf, $filerev, $fileext ) =
      $name =~ /^$re_file/;

    # remove underscores
    return unless ($filename);
    unless ($filename) { print STDERR "$name yielded $filename\n"; sleep(4); }
    $filename =~ tr/A-Za-z0-9\./-/c;
    $filename =~ s/\.pm//;             # e.g. CGI.pm

    # We don't want to try and handle the package perl itself
    return if ( $filename eq "perl" );

    # Remove double .'s - happens on occasion with odd packages
    $filenamever =~ s/\.$//;

    # Remove leading v's - happens on occasion
    $filenamever =~ s{^v}{}i;

    # Some modules don't use the /\d\.\d\d/ convention, and portage goes
    # berserk if the ebuild is called ebulldname-.02.ebuild -- so we treat
    # this special case
    if ( substr( $filenamever, 0, 1 ) eq '.' ) {
        $filenamever = 0 . $filenamever;
    }
    return ( $filenamever );
}


sub transformCPANname {
    my $self = shift;
    my $name = shift;
    return unless ( defined($name) );
    my $re_path = '(?:.*)?';
    my $re_pkg  = '(?:.*)?';
    my $re_ver  = '(?:v?[\d\.]+[a-z]?)?';
    my $re_suf  = '(?:_(?:alpha|beta|pre|rc|p)(?:\d+)?)?';
    my $re_rev  = '(?:\-r\d+)?';
    my $re_ext  = '(?:(?:tar|tgz|zip|bz2|gz|tar\.gz))?';
    my $re_file =
      qr/($re_path)\/($re_pkg)-($re_ver)($re_suf)($re_rev)\.($re_ext)/;
    my ( $modpath, $filename, $filenamever, $filesuf, $filerev, $fileext ) =
      $name =~ /^$re_file/;

    # remove underscores
    return unless ($filename);
    unless ($filename) { print STDERR "$name yielded $filename\n"; sleep(4); }
    $filename =~ tr/A-Za-z0-9\./-/c;
    $filename =~ s/\.pm//;             # e.g. CGI.pm

    # We don't want to try and handle the package perl itself
    return if ( $filename eq "perl" );

    # Remove double .'s - happens on occasion with odd packages
    $filenamever =~ s/\.$//;

    # Remove leading v's - happens on occasion
    $filenamever =~ s{^v}{}i;

    # Some modules don't use the /\d\.\d\d/ convention, and portage goes
    # berserk if the ebuild is called ebulldname-.02.ebuild -- so we treat
    # this special case
    if ( substr( $filenamever, 0, 1 ) eq '.' ) {
        $filenamever = 0 . $filenamever;
    }
    return ( $filename );
}

sub makeCPANstub {
    my $self          = shift;
    my $cpan_cfg_dir  = File::Spec->catfile( $ENV{HOME}, CPAN_CFG_DIR );
    my $cpan_cfg_file = File::Spec->catfile( $cpan_cfg_dir, CPAN_CFG_NAME );

    if ( not -d $cpan_cfg_dir ) {
        mkpath( $cpan_cfg_dir, 1, 0755 )
          or fatal( $Gentoo::ERR_FOLDER_CREATE, $cpan_cfg_dir, $! );
    }

    my $tmp_dir   = -d $ENV{TMPDIR} ? defined( $ENV{TMPDIR} )    : $ENV{HOME};
    my $ftp_proxy = $ENV{ftp_proxy} ? defined( $ENV{ftp_proxy} ) : '';
    my $http_proxy = $ENV{http_proxy} ? defined( $ENV{http_proxy} ) : '';
    my $user_shell = -x $ENV{SHELL}   ? defined( $ENV{SHELL} ) : DEF_BASH_PROG;
    my $ftp_prog   = -x DEF_FTP_PROG  ? DEF_FTP_PROG           : '';
    my $gpg_prog   = -x DEF_GPG_PROG  ? DEF_GPG_PROG           : '';
    my $gzip_prog  = -x DEF_GZIP_PROG ? DEF_GZIP_PROG          : '';
    my $lynx_prog  = -x DEF_LYNX_PROG ? DEF_LYNX_PROG          : '';
    my $make_prog  = -x DEF_MAKE_PROG ? DEF_MAKE_PROG          : '';
    my $ncftpget_prog = -x DEF_NCFTPGET_PROG ? DEF_NCFTPGET_PROG : '';
    my $less_prog     = -x DEF_LESS_PROG     ? DEF_LESS_PROG     : '';
    my $tar_prog      = -x DEF_TAR_PROG      ? DEF_TAR_PROG      : '';
    my $unzip_prog    = -x DEF_UNZIP_PROG    ? DEF_UNZIP_PROG    : '';
    my $wget_prog     = -x DEF_WGET_PROG     ? DEF_WGET_PROG     : '';

    open CPANCONF, ">$cpan_cfg_file"
      or fatal( $Gentoo::ERR_FOLDER_CREATE, $cpan_cfg_file, $! );
    print CPANCONF <<"SHERE";

# This is CPAN.pm's systemwide configuration file. This file provides
# defaults for users, and the values can be changed in a per-user
# configuration file. The user-config file is being looked for as
# ~/.cpan/CPAN/MyConfig\.pm. This was generated by g-cpan for temporary usage

\$CPAN::Config = {
  'build_cache' => q[10],
  'build_dir' => q[$tmp_dir/.cpan/build],
  'cache_metadata' => q[1],
  'cpan_home' => q[$tmp_dir/.cpan],
  'dontload_hash' => {  },
  'ftp' => q[$ftp_prog],
  'ftp_proxy' => q[$ftp_proxy],
  'getcwd' => q[cwd],
  'gpg' => q[$gpg_prog],
  'gzip' => q[$gzip_prog],
  'histfile' => q[$tmp_dir/.cpan/histfile],
  'histsize' => q[100],
  'http_proxy' => q[$http_proxy],
  'inactivity_timeout' => q[0],
  'index_expire' => q[1],
  'inhibit_startup_message' => q[1],
  'keep_source_where' => q[$tmp_dir/.cpan/sources],
  'lynx' => q[$lynx_prog],
  'make' => q[$make_prog],
  'make_arg' => q[],
  'make_install_arg' => q[],
  'makepl_arg' => q[],
  'ncftpget' => q[$ncftpget_prog],
  'no_proxy' => q[],
  'pager' => q[$less_prog],
  'prerequisites_policy' => q[follow],
  'scan_cache' => q[atstart],
  'shell' => q[$user_shell],
  'tar' => q[$tar_prog],
  'term_is_latin' => q[1],
  'unzip' => q[$unzip_prog],
  'urllist' => [q[http://search.cpan.org/CPAN],],
  'wget' => q[$wget_prog],
};
1;
__END__

SHERE

    close CPANCONF;
}

1;
