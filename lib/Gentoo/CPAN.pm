package Gentoo::CPAN;

use 5.008007;
use strict;
use warnings;
use File::Spec;
use CPAN;
use File::Path;

# These libraries were influenced and largely written by
# Christian Hartmann <ian@gentoo.org> originally. All of the good
# parts are ian's - the rest is mcummings messing around.

require Exporter;

our @ISA = qw(Exporter Gentoo );

our @EXPORT = qw( getCPANPackages makeCPANstub
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

unless ($ENV{TMPDIR}) { $ENV{TMPDIR} = '/var/tmp/g-cpan' }

sub new
{
    my $proto = shift;
    my %args  = @_;
    my $class = ref($proto) || $proto;
    my $self  = {};

    $self->{modules}            = {};
    $self->{portage_categories} = @{$args{portage_categories}};
    $self->{DEBUG}              = $args{debug};
    $self->{portdir}            = $args{portdir};

    bless($self, $class);
    return $self;
}

sub getCPANPackages
{
    my $self        = shift;
    my $find_module = shift;
    my $cpan_pn     = "";
    my @tmp_v       = ();

    if ($find_module)
    {
        return
          if ($self->{modules}{'found_module'}{lc($find_module)});
    }
    if ($self->{cpan_reload})
    {

        # - User forced reload of the CPAN index >
        CPAN::Index->force_reload();
    }

    for my $mod (CPAN::Shell->expand("Module", "/./"))
    {
        if (defined $mod->cpan_version)
        {

            # - Fetch CPAN-filename and cut out the filename of the tarball.
            #   We are not using $mod->id here because doing so would end up
            #   missing a lot of our ebuilds/packages >
            my $cpan_desc;
            my $cpan_src_uri = $cpan_pn = $mod->cpan_file;
            $cpan_pn =~ s|.*/||;
            $cpan_src_uri =~ m{(\(.*\))}xms;
            if ($mod->description) {
                $cpan_desc = $mod->description
            } else {
                $cpan_desc = "";
            }

            if ($mod->cpan_version eq "undef"
                && ($cpan_pn =~ m/ / || $cpan_pn eq "" || !$cpan_pn))
            {

                # - invalid line - skip that one >
                next;
            }

            # - Right now both are "MODULE-FOO-VERSION-EXT" >
            my $cpan_version = $cpan_pn;

            $cpan_pn =~ s/\.pm//;                                                            # e.g. CGI.pm
                                                                                             # - Drop "-VERSION-EXT" from cpan_pn >
            $cpan_pn =~ s/(?:-?)?(?:v?[\d\.]+[a-z]?)?\.(?:tar|tgz|zip|bz2|gz|tar\.gz)?$//;

            if ($cpan_pn =~ m|.*/(.*)-v?[0-9]+\.|)            { $cpan_pn = $1; }
            if ($cpan_pn =~ m|.*/([a-zA-Z-]*)v?[0-9]+\.|)     { $cpan_pn = $1; }
            if ($cpan_pn =~ m|.*/([a-zA-Z-]*)\-v?\.[0-9]+\.|) { $cpan_pn = $1; }
            if ($cpan_pn =~ m|.*/([^.]*)\.|)                  { $cpan_pn = $1; }
            $cpan_pn =~ s/_$//;

            if (length(lc($cpan_version)) >= length(lc($cpan_pn)))
            {

                # - Drop "MODULE-FOO-" from version >
                if (length(lc($cpan_version)) == length(lc($cpan_pn)))
                {
                    $cpan_version = 0;
                }
                else
                {
                    $cpan_version = substr($cpan_version, length(lc($cpan_pn)) + 1, length(lc($cpan_version)) - length(lc($cpan_pn)) - 1);
                }
                if (defined $cpan_version)
                {
                    $cpan_version =~ s/\.(?:tar|tgz|zip|bz2|gz|tar\.gz)?$//;

                    # - Remove any leading/trailing stuff (like "v" in "v5.2.0") we don't want >
                    $cpan_version =~ s/^[a-zA-Z]+//;
                    $cpan_version =~ s/[a-zA-Z]+$//;

                    # - Convert CPAN version >
                    @tmp_v = split(/\./, $cpan_version);
                    if ($#tmp_v > 1)
                    {
                        if ($self->{DEBUG})
                        {
                            print " converting version -> " . $cpan_version;
                        }
                        $cpan_version = $tmp_v[0] . ".";
                        for (1 .. $#tmp_v) { $cpan_version .= $tmp_v[$_]; }
                        if ($self->{DEBUG}) { print " -> " . $cpan_version . "\n"; }
                    }

                    if ($cpan_version eq "") { $cpan_version = 0; }

                    # Going on the theory we don't track items without 0's
                    next if ($cpan_version == 0);
                    $self->{modules}{'cpan'}{$cpan_pn} = $cpan_version;
                    $self->{modules}{'cpan_lc'}{lc($cpan_pn)} = $cpan_version;
                    $self->{modules}{'cpan_description'}{lc($cpan_pn)} =
                        $cpan_desc;
                    $self->{modules}{'cpan_src_uri'}{lc($cpan_pn)} =
                        $cpan_src_uri;
                    if ($find_module)
                    {
                        if ($self->{modules}{'cpan_lc'}{lc($find_module)})
                        {
                            $self->{modules}{'found_module'}{lc($find_module)} = $self->{modules}{'cpan_lc'}{lc($cpan_pn)};
                            last;
                        }
                    }
                }
            }
        }
    }
    return 0;
}

sub makeCPANstub
{
    my $self          = shift;
    my $cpan_cfg_dir  = File::Spec->catfile($ENV{HOME}, CPAN_CFG_DIR);
    my $cpan_cfg_file = File::Spec->catfile($cpan_cfg_dir, CPAN_CFG_NAME);

    if (not -d $cpan_cfg_dir)
    {
        mkpath($cpan_cfg_dir, 1, 0755) or fatal($Gentoo::ERR_FOLDER_CREATE, $cpan_cfg_dir, $!);
    }

    my $tmp_dir       = -d $ENV{TMPDIR}      ? defined($ENV{TMPDIR})     : $ENV{HOME};
    my $ftp_proxy     = $ENV{ftp_proxy}      ? defined($ENV{ftp_proxy})  : '';
    my $http_proxy    = $ENV{http_proxy}     ? defined($ENV{http_proxy}) : '';
    my $user_shell    = -x $ENV{SHELL}       ? defined($ENV{SHELL})      : DEF_BASH_PROG;
    my $ftp_prog      = -x DEF_FTP_PROG      ? DEF_FTP_PROG              : '';
    my $gpg_prog      = -x DEF_GPG_PROG      ? DEF_GPG_PROG              : '';
    my $gzip_prog     = -x DEF_GZIP_PROG     ? DEF_GZIP_PROG             : '';
    my $lynx_prog     = -x DEF_LYNX_PROG     ? DEF_LYNX_PROG             : '';
    my $make_prog     = -x DEF_MAKE_PROG     ? DEF_MAKE_PROG             : '';
    my $ncftpget_prog = -x DEF_NCFTPGET_PROG ? DEF_NCFTPGET_PROG         : '';
    my $less_prog     = -x DEF_LESS_PROG     ? DEF_LESS_PROG             : '';
    my $tar_prog      = -x DEF_TAR_PROG      ? DEF_TAR_PROG              : '';
    my $unzip_prog    = -x DEF_UNZIP_PROG    ? DEF_UNZIP_PROG            : '';
    my $wget_prog     = -x DEF_WGET_PROG     ? DEF_WGET_PROG             : '';

    open CPANCONF, ">$cpan_cfg_file" or fatal($Gentoo::ERR_FOLDER_CREATE, $cpan_cfg_file, $!);
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
  'inhibit_startup_message' => q[0],
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
