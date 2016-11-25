package Gentoo::CPAN;

use 5.008007;
use strict;
use warnings;
use File::Spec;
use CPAN;
use File::Path;
use YAML ();
use Memoize;
use Cwd qw( abs_path cwd );
use File::Basename;

memoize('transformCPAN');
memoize('FindDeps');

# These libraries were influenced and largely written by
# Christian Hartmann <ian@gentoo.org> originally. All of the good
# parts are ian's - the rest is mcummings messing around.

require Exporter;

our @ISA = qw( Exporter Gentoo );

our @EXPORT = qw( getCPANInfo makeCPANstub unpackModule transformCPAN );

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
    my $class = shift;
    return bless {}, $class;
}

##### - CPAN OVERRIDE - #####
#
#############################

*CPAN::myprint = sub {
	my ($self, $text) = @_;
    #spinner_start();
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
};

*CPAN::mywarn = sub {
    return;
};

*CPAN::mydie = sub {
    my ($self,$what) = @_;
    print STDOUT "$what";
    die "\n";
};


########################
#
########################


sub getCPANInfo {
    my $self        = shift;
    my $find_module = shift;
    my @tmp_v       = ();

    unless ($find_module) {
        croak("No module supplied");
    }

    if ( $self->{cpan_reload} ) {

        # - User forced reload of the CPAN index >
        CPAN::Index->force_reload();

        # Reset so we don't run it for every module after the initial reload
        $self->{cpan_reload} = 0;
    }

    my $mod;

    unless (($mod = CPAN::Shell->expand("Module",$find_module)) ||
        ($mod = CPAN::Shell->expand("Bundle",$find_module)) ||
        ($mod = CPAN::Shell->expand("Distribution",$find_module)) ||
        ($mod = CPAN::Shell->expandany($find_module)) )
        { return }

# - Fetch CPAN-filename and cut out the filename of the tarball.
#   We are not using $mod->id here because doing so would end up
#   missing a lot of our ebuilds/packages >
# Addendum. Appears we are missing items both ways - have to test both the name in cpan_file and the mod->id. :/
    next unless ( $mod->id );
    # manpage_headline spews a bunch of warnings, and is not always valid.
    # If this is a # CPAN::Bundle, manual work is needed anyway.
    sub manpage_title {
        my $mod = shift;
		# Force the calculation of contents.
		$mod->as_string();
        my $module_name = shift;
        my $desc = $mod->{MANPAGE};
		return $desc unless $desc;
		return $desc unless $module_name;
        $desc =~ s/^$module_name - //g;
        return $desc;
    }

    my $dist_info = $self->{cpan}{ lc($find_module) };
    $dist_info->{description} =
      $mod->{RO}{description} || manpage_title( $mod, $find_module ) || 'No description available';
    $dist_info->{src_uri}             = $mod->{RO}{CPAN_FILE};
    $dist_info->{name}                = $mod->id;
    $dist_info->{version}             = $mod->{RO}{CPAN_VERSION} || '0';
    $self->{cpan}{ lc($find_module) } = $dist_info;

    return;
}

sub unpackModule {
    my $self        = shift;
    my $module_name = shift;
    unless (defined($module_name)) { return }
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
    $CPAN::Config->{inactivity_timeout}   = 10;

    my $pack = $CPAN::META->instance( 'CPAN::Distribution', $file );
    if ( $pack->can('called_for') ) {
        $pack->called_for( $obj->id );
    }

    # Grab the tarball and unpack it
    unless (defined($pack->{build_dir})) {
        $pack->get or die "Insufficient permissions!";
    }
    my $tmp_dir = $pack->{build_dir};

    # Set our starting point
    my $localf = $pack->{localfile};
    $self->{'cpan'}{ lc($module_name) }{'cpan_tarball'} = $pack->{localfile};
    my ($startdir) = &cwd;

    # chdir to where we were unpacked
    chdir($tmp_dir) or die "Unable to enter dir $tmp_dir:$!\n";

    # If we have a Makefile.PL, run it to generate Makefile
    if ( -f 'Makefile.PL' ) {
        system('perl Makefile.PL </dev/null');
    }

    # If we have a Build.PL, run it to generate the Build script
    if ( -f 'Build.PL' ) {
        system('perl Build.PL </dev/null');

        # most modules don't list Module::Build as a dep, but we need it due to perl-module.eclass requirements
        $self->{cpan}{ lc($module_name) }{depends}{'Module::Build'} = 0;
    }

    # Return whence we came
    chdir($startdir);

    $pack->unforce if $pack->can("unforce") && exists $obj->{'force_update'};
    delete $obj->{'force_update'};

    # While we're at it, get the ${S} dir for the ebuld ;)
    $self->{'cpan'}{ lc($module_name) }{'portage_sdir'} = $pack->{build_dir};
    $self->{'cpan'}{ lc($module_name) }{'portage_sdir'} =~ s{.*/}{}xmsg;
    # If name is bundle::, then scan the bundle's deps, otherwise findep it
    if (lc($module_name) =~ m{^bundle\::})
    {
        UnBundle( $self, $tmp_dir, $module_name );
    } else {
        FindDeps( $self, $tmp_dir, $module_name );
    }

    # Final measure - if somehow we got an undef along the way, set to 0
    foreach my $dep ( keys %{ $self->{'cpan'}{ lc($module_name) }{'depends'} } )
    {
        unless (
            defined( $self->{'cpan'}{ lc($module_name) }{'depends'}{$dep} ) ||
         ($self->{'cpan'}{ lc($module_name) }{'depends'}{$dep}   eq "undef" )
         )
        {
            $self->{'cpan'}{ lc($module_name) }{'depends'}{$dep} = "0";
        }
    }
    return ($self);
}

sub UnBundle {
    my $self        = shift;
    my ($workdir)   = shift;
    my $module_name = shift;
    my ($startdir)  = &cwd;
    chdir($workdir) or die "Unable to enter dir $workdir:$!\n";
    opendir( CURD, "." );
    my @dirs = readdir(CURD);
    closedir(CURD);
    foreach my $object (@dirs) {
        next if ( $object eq "." );
        next if ( $object eq ".." );
        if ( -f $object ) {
            if ($object =~ m{\.pm$} )
                {
                    my $fh;
                    my $in_cont = 0;
                    open ($fh, "$object");
                    while (<$fh>) {
                        $in_cont = m/^=(?!head1\s+CONTENTS)/ ? 0 :
                        m/^=head1\s+CONTENTS/ ? 1 : $in_cont;
                        next unless $in_cont;
                        next if /^=/;
                        s/\#.*//;
                        next if /^\s+$/;
                        chomp;
                        my $module;
                        my $ver = 0;
                        my $junk;
                        if (m{ }) {
                            ($module,$ver,$junk) = (split " ", $_);
                            if ($ver !~ m{^\d+}) { $ver = 0}
                        } else {
                            $module = (split " ", $_, 2)[0];
                        }

                        next if ($self->{'cpan'}{ lc($module_name)
                            }{'depends'}{$module});
                        next if (lc($module_name) eq lc($module));
                       $self->{'cpan'}{ lc($module_name) }{'depends'}{$module} = $ver;
                   }
               }
           }
              elsif ( -d $object ) {
            UnBundle( $self, $object, $module_name );
            next;
        }

    }
    chdir($startdir) or die "Unable to change to dir $startdir:$!\n";
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
            if ( $object eq "META\.yml" ) {
                # Do YAML parsing if you can
                if ( my $arr = yaml_load($abs_path) ) {
                foreach my $type (qw( configure_requires requires build_requires recommends )) {
                    if ( my $ar_type = $arr->{$type} ) {
                        foreach my $module ( keys %{$ar_type} ) {
                            next if ( $module eq "" );
                            next if ( $module =~ /Cwd/i );
                            #next if ( lc($module) eq "perl" );
                            next unless ($module);
                            next if (lc($module_name) eq lc($module));
                            $self->{'cpan'}{ lc($module_name) }{'depends'}
                              {$module} = $ar_type->{$module};
                        }
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
                            my $module = $1;
                            next if ( $module eq "" );
                            next if ( $module =~ /Cwd/i );
                            #next if ( lc($module) eq "perl" );
                            next unless ($module);
                            next if (lc($module_name) eq lc($module));
                            my $version = $2;
                            $self->{'cpan'}{ lc($module_name) }{'depends'}
                              {$module} = $version;
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

                foreach my $type (qw( requires configure_requires build_requires )) {
                    if ( $fh = FileHandle->new("<$makefile\0") ) {
                        local ($/) = "";
                        while (<$fh>) {
                            chomp;
                            my ($p) = m/^\s+$type\s+=>\s+\{(.*?)(?:\#.*)?\}/smx;
                            next unless $p;
                            undef($/);

                            #local($/) = "\n";
                            my @list = split( ',', $p );
                            foreach my $pa (@list) {
                                $pa =~ s/\n|\s+|\'//mg;
                                if ( $pa =~ /=~|\?\(/ ) {
                                    my ($module, $version ) = eval $pa;
                                    next if ((!defined($module)) or
                                            ( $module eq "" ) or
                                            ( $module =~ /Cwd/i ) );
                                    #next if ( lc($module) eq "perl" );
                                    next unless ($module);
                                    next if (lc($module_name) eq lc($module));
                                    $self->{'cpan'}{ lc($module_name) }
                                      {'depends'}{$module} = $version;
                                }
                                elsif ($pa) {
                                    my ( $module, $version ) = split( /=>/, $pa );
                                    next if ( $module eq "" );
                                    next if ( $module =~ /Cwd/i );
                                    #next if ( lc($module) eq "perl" );
                                    next unless ($module);
                                    $self->{'cpan'}{ lc($module_name) }
                                      {'depends'}{$module} = $version;
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

sub yaml_load {
    my $filepath = shift;
    my $yaml = eval { YAML::LoadFile($filepath); };
    return if $@;
    return $yaml;
}

sub transformCPAN {
    my ( $self, $name, $req ) = @_;
    return unless $name;

    my $re_path = '(?:.*)?';
    my $re_pkg  = '(?:.*)?';
    my $re_ver  = '(?:v?[\d\.]+[a-z]?\d*)?';
    my $re_suf  = '(?:_(?:alpha|beta|pre|rc|p)(?:\d+)?)?';
    my $re_rev  = '(?:\-r?\d+)?';
    my $re_ext  = '(?:(?:tar|tgz|zip|bz2|gz|tar\.gz))?';

    my $filename = $name;
    my($modpath, $filenamever, $fileext);
    $fileext = $1 if $filename =~ s/\.($re_ext)$//;
    $modpath = $1 if $filename =~ s/^($re_path)\///;
    $filenamever = $1 if $filename =~ s/-($re_ver$re_suf$re_rev)$//;

    # Alphanumeric version numbers? (http://search.cpan.org/~pip/)
    if ($filename =~ s/-(\d\.\d\.\d)([A-Za-z0-9]{6})$//) {
        $filenamever = $1;
        $filenamever .= ('.'.ord($_)) foreach split(//, $2);
    }

    # remove invalid characters
    return unless ($filename);
    $filename =~ tr/_A-Za-z0-9\./-/c;
    $filename =~ s/\.pm//;             # e.g. CGI.pm

    # Remove double .'s - happens on occasion with odd packages
    $filenamever =~ s/\.$//;

    # rename a double version -0.55-7 to ebuild style -0.55-r7
    $filenamever =~ s/([0-9.]+)-([0-9.]+)$/$1\.$2/;

    # Remove leading v's - happens on occasion
    $filenamever =~ s{^v}{}i;

    # Some modules don't use the /\d\.\d\d/ convention, and portage goes
    # berserk if the ebuild is called ebulldname-.02.ebuild -- so we treat
    # this special case
    if ( substr( $filenamever, 0, 1 ) eq '.' ) {
        $filenamever = 0 . $filenamever;
    }

    return ( $req eq 'v' ) ? $filenamever : $filename;
}

sub makeCPANstub {
    my $self          = shift;
    my $cpan_cfg_dir  = File::Spec->catfile( $ENV{HOME}, CPAN_CFG_DIR );
    my $cpan_cfg_file = File::Spec->catfile( $cpan_cfg_dir, CPAN_CFG_NAME );

    if ( not -d $cpan_cfg_dir ) {
        mkpath( $cpan_cfg_dir, 1, 0755 )
          or fatal( $Gentoo::ERR_FOLDER_CREATE, $cpan_cfg_dir, $! );
    }

    my $tmp_dir   = -d $ENV{TMPDIR}            ? $ENV{TMPDIR}    : $ENV{HOME};
    my $ftp_proxy = defined( $ENV{ftp_proxy} ) ? $ENV{ftp_proxy} : '';
    my $http_proxy = defined( $ENV{http_proxy} ) ? $ENV{http_proxy} : '';
    my $user_shell = defined( $ENV{SHELL} ) ? $ENV{SHELL}   : DEF_BASH_PROG;
    my $ftp_prog   = -f DEF_FTP_PROG        ? DEF_FTP_PROG  : '';
    my $gpg_prog   = -f DEF_GPG_PROG        ? DEF_GPG_PROG  : '';
    my $gzip_prog  = -f DEF_GZIP_PROG       ? DEF_GZIP_PROG : '';
    my $lynx_prog  = -f DEF_LYNX_PROG       ? DEF_LYNX_PROG : '';
    my $make_prog  = -f DEF_MAKE_PROG       ? DEF_MAKE_PROG : '';
    my $ncftpget_prog = -f DEF_NCFTPGET_PROG ? DEF_NCFTPGET_PROG : '';
    my $less_prog     = -f DEF_LESS_PROG     ? DEF_LESS_PROG     : '';
    my $tar_prog      = -f DEF_TAR_PROG      ? DEF_TAR_PROG      : '';
    my $unzip_prog    = -f DEF_UNZIP_PROG    ? DEF_UNZIP_PROG    : '';
    my $wget_prog     = -f DEF_WGET_PROG     ? DEF_WGET_PROG     : '';

    open CPANCONF, ">$cpan_cfg_file"
      or fatal( $Gentoo::ERR_FOLDER_CREATE, $cpan_cfg_file, $! );
    print CPANCONF <<"SHERE";

# This is CPAN.pm's systemwide configuration file. This file provides
# defaults for users, and the values can be changed in a per-user
# configuration file. The user-config file is being looked for as
# ~/.cpan/CPAN/MyConfig\.pm. This was generated by g-cpan for temporary usage

\$CPAN::Config = {
  'auto_commit' => 'no',
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
  'make_install_make_command' => q[/usr/bin/make],
  'makepl_arg' => q[],
  'mbuild_arg' => q[],
  'mbuild_install_arg' => q[],
  'mbuild_install_build_command' => q[./Build],
  'mbuildpl_arg' => q[],
  'ncftpget' => q[$ncftpget_prog],
  'no_proxy' => q[],
  'pager' => q[$less_prog],
  'prerequisites_policy' => q[follow],
  'scan_cache' => q[atstart],
  'shell' => q[$user_shell],
  'tar' => q[$tar_prog],
  'term_is_latin' => q[1],
  'unzip' => q[$unzip_prog],
  'urllist' => [qw[http://search.cpan.org/CPAN http://www.cpan.org/pub/CPAN ],],
  'wget' => q[$wget_prog],
};
1;
__END__

SHERE

    close CPANCONF;
}

1;

=pod

=head1 NAME

Gentoo::CPAN - Perform CPAN calls, emulating some functionality where possible
for a portage friendly environment

=head1 SYNOPSIS

    use Gentoo::CPAN;
    my $obj = Gentoo::CPAN->new();
    $obj->getCPANInfo("Module::Build");
    my $version = $obj->{cpan}->{lc("Module::Build")}->{'version'};
    my $realname = $obj->{cpan}->{lc($module)}->{'name'};
    my $srcuri = $obj->{cpan}->{lc($module)}->{'src_uri'};
    my $desc = $obj->{cpan}->{lc($module)}->{'description'};

=head1 DESCRIPTION

The C<Gentoo::CPAN> class gives us a method of working with CPAN modules. In
part it emulates the behavior of L<CPAN> itself, in other parts it simply
relies on L<CPAN> to do the work for us.

=head1 METHODS

=over 4

=item my $obj = Gentoo::CPAN->new();

Create a new Gentoo CPAN object.

=item $obj->getCPANInfo($somemodule);

Given the name of a CPAN module, extract the information from CPAN on this
object and populate the $obj hash. Provides:

=over 4

=item $obj->{cpan}{lc($module)}{'version'}

Version number

=item $obj->{cpan}{lc($module)}{'name'}

CPAN's name for the distribution

=item $obj->{cpan}{lc($module)}{'src_uri'}

The context path on CPAN for the module source

=item $obj->{cpan}{lc($module)}{'description'}

Description, if available

=back

=item $obj->unpackModule($somemodule)

Grabs the module from CPAN and unpacks it. It then proceeds to scan for
dependencies, filling in $obj->{'cpan'}{lc($somemodule)}{'depends'} with and
deeps that were found (hash).

=item $obj->transformCPAN($somemodule, 'v')

=item $obj->transformCPAN($somemodule, 'n')

Returns a portage friend version or module name from the name that is used on
CPAN. Useful for modules that use names or versions that would break as a
portage ebuild.

=item $obj->makeCPANstub()

Generates a default CPAN stub file if none exists in the user's environment

=back

=head1 SEE ALSO

See L<Gentoo>.

=cut
