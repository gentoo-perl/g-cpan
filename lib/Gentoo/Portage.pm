package Gentoo::Portage;

use 5.008007;
use strict;
use warnings;
#use Shell qw(ebuild emerge);
#use Memoize;
#memoize('getAvailableVersions');
use Cwd qw(getcwd abs_path cwd);
use File::Find ();
use Shell::EnvImporter;


# Set the variable $File::Find::dont_use_nlink if you're using AFS,
# since AFS cheats.

# for the convenience of &wanted calls, including -eval statements:
use vars qw/*name *dir *prune/;
*name  = *File::Find::name;
*dir   = *File::Find::dir;
*prune = *File::Find::prune;

my @store_found_dirs;
my @store_found_ebuilds;
sub wanted;

# These libraries were influenced and largely written by
# Christian Hartmann <ian@gentoo.org> originally. All of the good
# parts are ian's - the rest is mcummings messing around.

require Exporter;

our @ISA = qw(Exporter Gentoo);

our @EXPORT =
  qw( getEnv getAltName getAvailableEbuilds getAvailableVersions generate_digest emerge_ebuild import_fields );

our $VERSION = '0.01';


sub getEnv {
#IMPORT VARIABLES
    my $self = shift;
    my $envvar = shift;
    my $filter = sub {
        my ($var, $value, $change ) = @_;
        return($var =~ /^$envvar$/ );
    };

foreach my $file ( "$ENV{HOME}/.gcpanrc", '/etc/portage/make.conf', '/etc/make.conf', '/etc/make.globals' ) {
    if ( -f $file) {
    	my $importer = Shell::EnvImporter->new(
    		file => $file,
    		shell => 'bash',
            import_filter => $filter,
    	);
    $importer->shellobj->envcmd('set');
    $importer->run();
    if (defined($ENV{$envvar}) && ($ENV{$envvar} =~ m{\W*}))
    { 
        my $tm = strip_env($ENV{$envvar}); 
        $importer->restore_env; 
        return $tm;
    }

}
  }
}

sub strip_env {
    my $key = shift;
    return $key unless defined($key);
    if (defined($ENV{$key})) {
        $ENV{$key} =~ s{\\n|\\t}{ }gxms;
        $ENV{$key} =~ s{\\|\'|\\'|\$|\s*$}{}gmxs;
        $key =~ s{\s+}{ }gmxs;
        return $ENV{$key};
    }
    else
    {
        $key =~ s{\\n|\\t}{ }gxms;
        $key =~ s{(\'|\\|\\'|\$|\s*$)}{}gmxs;
        $key =~ s{\s+}{ }gmxs;
        return $key;
    }
}
# Description:
# @listOfEbuilds = getAvailableEbuilds($PORTDIR, category/packagename);
sub getAvailableEbuilds {
    my $self        = shift;
    my $portdir     = shift;
    my $catPackage  = shift;
    @{$self->{packagelist}} = ();
    if ( -e $portdir . "/" . $catPackage ) {

        # - get list of ebuilds >
        my $startdir = &cwd;
        chdir( $portdir . "/" . $catPackage );
        @store_found_ebuilds = [];
        File::Find::find( { wanted => \&wanted_ebuilds }, "." );
        chdir($startdir);
        foreach (@store_found_ebuilds) {
            $_ =~ s{^\./}{}xms;
            if ( $_ =~ m/(.+)\.ebuild$/ ) {
                next if ( $_ eq "skel.ebuild" );
                push( @{ $self->{packagelist} }, $_ );
            }
            else {
                if ( -d $portdir . "/" . $catPackage . "/" . $_ ) {
                    $_ =~ s{^\./}{}xms;
                    my $startdir = &cwd;
                    chdir( $portdir . "/" . $catPackage . "/" . $_ );
                    @store_found_ebuilds = [];
                    File::Find::find( { wanted => \&wanted_ebuilds }, "." );
                    chdir($startdir);
                    foreach (@store_found_ebuilds) {
                        if ( $_ =~ m/(.+)\.ebuild$/ ) {
                            next if ( $_ eq "skel.ebuild" );
                            push( @{ $self->{packagelist} }, $_ );
                        }
                    }
                }
            }
        }
    }
    else {
        if ( -d $portdir ) {
            if ( $self->{debug} ) {
                warn(
                    "\n" . $portdir . "/" . $catPackage . " DOESN'T EXIST\n" );
            }
        }
        else {
            die("\nPORTDIR hasn't been defined!\n\n");
        }
    }

}

# Description:
# Returns version of an ebuild. (Without -rX string etc.)
# $version = getEbuildVersionSpecial("foo-1.23-r1.ebuild");
sub getEbuildVersionSpecial {
    my $ebuildVersion = shift;
    $ebuildVersion = substr( $ebuildVersion, 0, length($ebuildVersion) - 7 );
    $ebuildVersion =~
s/^([a-zA-Z0-9\-_\/\+]*)-([0-9\.]+[a-zA-Z]?)([\-r|\-rc|_alpha|_beta|_pre|_p]?)/$2$3/;

    return $ebuildVersion;
}

sub getBestVersion {
    my $self = shift;
    my ( $find_ebuild, $portdir, $tc, $tp ) = @_;
     getAvailableEbuilds( $self, $portdir, $tc . "/" . $tp );

                foreach ( @{ $self->{packagelist} } ) {
                    my @tmp_availableVersions = ();
                    push( @tmp_availableVersions, getEbuildVersionSpecial($_) );

                    # - get highest version >
                    if ( $#tmp_availableVersions > -1 ) {
                        $self->{'portage'}{ lc($find_ebuild) }{'version'} =
                          ( sort(@tmp_availableVersions) )
                          [$#tmp_availableVersions];

                        read_ebuild($self,$find_ebuild,$portdir,$tc,$tp,$_);
                        # - get rid of -rX >
                        $self->{'portage'}{ lc($find_ebuild) }{'version'} =~
                          s/([a-zA-Z0-9\-_\/]+)-r[0-9+]/$1/;
                        $self->{'portage'}{ lc($find_ebuild) }{'version'} =~
                          s/([a-zA-Z0-9\-_\/]+)-rc[0-9+]/$1/;
                        $self->{'portage'}{ lc($find_ebuild) }{'version'} =~
                          s/([a-zA-Z0-9\-_\/]+)_p[0-9+]/$1/;
                        $self->{'portage'}{ lc($find_ebuild) }{'version'} =~
                          s/([a-zA-Z0-9\-_\/]+)_pre[0-9+]/$1/;

                        # - get rid of other stuff we don't want >
                        $self->{'portage'}{ lc($find_ebuild) }{'version'} =~
                          s/([a-zA-Z0-9\-_\/]+)_alpha[0-9+]?/$1/;
                        $self->{'portage'}{ lc($find_ebuild) }{'version'} =~
                          s/([a-zA-Z0-9\-_\/]+)_beta[0-9+]?/$1/;
                        $self->{'portage'}{ lc($find_ebuild) }{'version'} =~
                          s/[a-zA-Z]+$//;

                        if ( $tc eq "perl-core"
                            and ( keys %{ $self->{'portage_bases'} } ) )
                        {

          # We have a perl-core module - can we satisfy it with a virtual/perl-?
                            foreach my $portage_root (
                                keys %{ $self->{'portage_bases'} } )
                            {
                                if ( -d $portage_root ) {
                                    if ( -d "$portage_root/virtual/perl-$tp" ) {
                                        $self->{'portage'}{ lc($find_ebuild) }
                                          {'name'} = "perl-$tp";
                                        $self->{'portage'}{ lc($find_ebuild) }
                                          {'category'} = "virtual";
                                        last;
                                    }
                                }
                            }

                        }
                        else {
                            $self->{'portage'}{ lc($find_ebuild) }{'name'} =
                              $tp;
                            $self->{'portage'}{ lc($find_ebuild) }{'category'} =
                              $tc;
                        }

                    }
                }
            }

# This is strictly so we can seek back to __DATA__
( my $data_pos = tell DATA) >= 0 or die "DATA not seekable"; 
use IO::Seekable qw(SEEK_SET);

sub getAvailableVersions {
    my $self        = shift;
    my $portdir     = shift;
    my $find_ebuild = shift;
    return if ($find_ebuild =~ m{::} );
    my %excludeDirs = (
        "."         => 1,
        ".."        => 1,
        "metadata"  => 1,
        "licenses"  => 1,
        "eclass"    => 1,
        "distfiles" => 1,
        "virtual"   => 1,
        "profiles"  => 1
    );

    if ($find_ebuild) {
        return if ( defined($self->{portage}{ lc($find_ebuild) }{'found'} ));
    }
    seek DATA, $data_pos, SEEK_SET;
    while (my $line = <DATA>) {
        chomp $line;
        next unless $line =~ /^.+/;
        my ($cat,$eb,$cpan_file) = split(/\s+|\t+/, $line);
        if ( $cpan_file =~ m{^$find_ebuild$}i ) {
            getBestVersion($self,$find_ebuild,$portdir,$cat,$eb);
            $self->{portage}{ lc($find_ebuild) }{'found'}    = 1;
            $self->{portage}{ lc($find_ebuild) }{'category'} = $cat;
            $self->{portage}{ lc($find_ebuild) }{'name'}     = $eb;
           return;
        }
    }

    unless(defined($self->{'portage'}{lc($find_ebuild)}{'name'})) {
    
    foreach my $tc ( @{ $self->{portage_categories} } ) {
        next if ( !-d "$portdir/$tc" );
        @store_found_dirs = [];

        # Where we started
        my $startdir = &cwd;

        # chdir to our target dir
        chdir( $portdir . "/" . $tc );

        # Traverse desired filesystems
        File::Find::find( { wanted => \&wanted_dirs }, "." );

        # Return to where we started
        chdir($startdir);
        foreach my $tp ( sort @store_found_dirs ) {
            $tp =~ s{^\./}{}xms;

            # - not excluded and $_ is a dir?
            if ( !$excludeDirs{$tp} && -d $portdir . "/" . $tc . "/" . $tp ) { #STARTS HERE
                if ($find_ebuild) {
                    next
                      unless ( lc($find_ebuild) eq lc($tp) );
                }
                getBestVersion($self,$find_ebuild,$portdir,$tc,$tp);
            } #Ends here
        }
    }
}
                            if ($find_ebuild) {
                            if ( defined($self->{'portage'}{ lc($find_ebuild) }{'name'}) )
                            {
                                $self->{portage}{ lc($find_ebuild) }{'found'} = 1;
                                return;
                            }
                        }
    return ($self);
}

sub generate_digest {
    my $self = shift;

    # Full path to the ebuild file in question
    my $ebuild = shift;
    system( "ebuild", $ebuild, "digest" );
}

sub read_ebuild {
    my $self = shift;
    my ($find_ebuild,$portdir,$tc,$tp,$file) = @_;
    my $e_file = "$portdir/$tc/$tp/$file";
     # Grab some info for display
                        my $e_import = Shell::EnvImporter->new(
                            file => $e_file,
                            shell => 'bash',
                            auto_run => 1,
                            auto_import => 1,
                        );
                        $e_import->shellobj->envcmd('set');
                        $e_import->run();
                        $e_import->env_import();
                        $self->{'portage'}{lc($find_ebuild)}{'DESCRIPTION'} = strip_env($ENV{DESCRIPTION});
                        $self->{'portage'}{lc($find_ebuild)}{'HOMEPAGE'} = strip_env($ENV{HOMEPAGE});
                        $e_import->restore_env;

                    }

sub emerge_ebuild {
    my $self  = shift;
    my @call = @_;
    # emerge forks and returns, which confuses this process. So
    # we call it the old fashioned way :(
    system( "emerge", @call );
}

sub wanted_dirs {
    my ( $dev, $ino, $mode, $nlink, $uid, $gid );
    ( ( $dev, $ino, $mode, $nlink, $uid, $gid ) = lstat($_) )
      && -d _
      && ( $name !~ m|/files| )
      && ( $name !~ m|/CVS| )
      && push @store_found_dirs, $name;
}

sub wanted_ebuilds {
    /\.ebuild\z/s
      && push @store_found_ebuilds, $name;
}

sub DESTROY {
    my ($self) = @_;
    return if $self->{DESTROY}{__PACKAGE__}++;
}

1;

=pod

=head1 NAME

Gentoo::Portage - perl access to portage information and commands

=head1 SYNOPSIS

    use Gentoo;
    my $obj = Gentoo->new();
    $obj->getAvailableEbuilds($portdir,'category');
    $obj->getAvailableVersions($portdir);
    
=head1 DESCRIPTION

The C<Gentoo::Portage> class provides access to portage tools and tree
information.

=head1 METHODS

=over 4

=item $obj->getAvailableEbuilds($portdir, $package);

Providing the PORTDIR you want to invesitage, and either the name of the
category or the category/package you are interested, this will populate an
array in $obj->{packagelist} of the available ebuilds.

=item $obj->getAvailableVersions($portdir,[$ebuildname])

Given the portage directory and the name of a package (optional), check
portage to see if the ebuild exists and which versions are available.

=item $obj->getEbuildVersionSpecial($ebuild)

Given the full name of an ebuild (foo-1.3.4-rc5.ebuild), this function will
return the actual version of the ebuild after stripping out the portage
related syntax.

=item $obj->generate_digest($path_to_ebuild)

Given the full path to an ebuild, generate a digest via C<ebuild PKG digest>

=item $obj->emerge_ebuild($pkg, @flags)

Given the name of a package and any optional flags, emerge the package with
portage.

=cut


# Reformat the below with: sprintf("%-12s %-28s %s\n",...)
__DATA__
dev-perl     Ace                          AcePerl
dev-perl     Authen-NTLM                  NTLM
dev-perl     Boulder                      Stone
dev-perl     CPAN-Mini-Phalanx            CPAN-Mini-Phalanx100
dev-perl     Cgi-Simple                   CGI-Simple
dev-perl     DateManip                    Date-Manip
dev-perl     DelimMatch                   Text-DelimMatch
dev-perl     ImageInfo                    Image-Info
dev-perl     ImageSize                    Image-Size
dev-perl     Locale-gettext               gettext
dev-perl     Net-SSLeay                   Net_SSLeay
dev-perl     Net-SSLeay                   Net_SSLeay.pm
dev-perl     OLE-StorageLite              OLE-Storage_Lite
dev-perl     PDF-Create                   perl-pdf
dev-perl     SGMLSpm                      SGMLSpmii
dev-perl     SpeedyCGI                    CGI-SpeedyCGI
dev-perl     Template-Latex               Template-Plugin-Latex
dev-perl     TextToHTML                   txt2html
dev-perl     XML-Sablot                   XML-Sablotron
dev-perl     cache-mmap                   Cache-Mmap
dev-perl     class-loader                 Class-Loader
dev-perl     class-returnvalue            Class-ReturnValue
dev-perl     config-general               Config-General
dev-perl     convert-ascii-armour         Convert-ASCII-Armour
dev-perl     convert-pem                  Convert-PEM
dev-perl     crypt-cbc                    Crypt-CBC
dev-perl     crypt-des-ede3               Crypt-DES_EDE3
dev-perl     crypt-dh                     Crypt-DH
dev-perl     crypt-dsa                    Crypt-DSA
dev-perl     crypt-idea                   Crypt-IDEA
dev-perl     crypt-primes                 Crypt-Primes
dev-perl     crypt-random                 Crypt-Random
dev-perl     crypt-rsa                    Crypt-RSA
dev-perl     data-buffer                  Data-Buffer
dev-perl     dbix-searchbuilder           DBIx-SearchBuilder
dev-perl     digest-bubblebabble          Digest-BubbleBabble
dev-perl     digest-md2                   Digest-MD2
dev-perl     extutils-depends             ExtUtils-Depends
dev-perl     extutils-pkgconfig           ExtUtils-PkgConfig
dev-perl     frontier-rpc                 Frontier-RPC
dev-perl     gimp-perl                    Gimp
dev-perl     glib-perl                    Glib
dev-perl     gnome2-canvas                Gnome2-Canvas
dev-perl     gnome2-gconf                 Gnome2-GConf
dev-perl     gnome2-perl                  Gnome2
dev-perl     gnome2-print                 Gnome2-Print
dev-perl     gnome2-vfs-perl              Gnome2-VFS
dev-perl     gnome2-wnck                  Gnome2-Wnck
dev-perl     gtk2-ex-formfactory          Gtk2-Ex-FormFactory
dev-perl     gtk2-fu                      Gtk2Fu
dev-perl     gtk2-gladexml                Gtk2-GladeXML
dev-perl     gtk2-perl                    Gtk2
dev-perl     gtk2-spell                   Gtk2-Spell
dev-perl     gtk2-trayicon                Gtk2-TrayIcon
dev-perl     gtk2-traymanager             Gtk2-TrayManager
dev-perl     inline-files                 Inline-Files
dev-perl     locale-maketext-fuzzy        Locale-Maketext-Fuzzy
dev-perl     locale-maketext-lexicon      Locale-Maketext-Lexicon
dev-perl     log-dispatch                 Log-Dispatch
dev-perl     math-pari                    Math-Pari
dev-perl     module-info                  Module-Info
dev-perl     mogilefs-server              MogileFS-Server
dev-perl     net-server                   Net-Server
dev-perl     net-sftp                     Net-SFTP
dev-perl     net-ssh-perl                 Net-SSH-Perl
dev-perl     ogg-vorbis-header            Ogg-Vorbis-Header
dev-perl     perl-tk                      Tk
dev-perl     perltidy                     Perl-Tidy
dev-perl     regexp-common                Regexp-Common
dev-perl     sdl-perl                     SDL_Perl
dev-perl     set-scalar                   Set-Scalar
dev-perl     string-crc32                 String-CRC32
dev-perl     text-autoformat              Text-Autoformat
dev-perl     text-reform                  Text-Reform
dev-perl     text-template                Text-Template
dev-perl     text-wrapper                 Text-Wrapper
dev-perl     tie-encryptedhash            Tie-EncryptedHash
dev-perl     wxperl                       Wx
dev-perl     yaml                         YAML
media-gfx    imagemagick                  PerlMagick
perl-core    CGI                          CGI.pm
perl-core    File-Spec                    PathTools
perl-core    PodParser                    Pod-Parser
perl-core    Term-ANSIColor               ANSIColor
perl-core    digest-base                  Digest
perl-core    i18n-langtags                I18N-LangTags
perl-core    locale-maketext              Locale-Maketext
perl-core    net-ping                     Net-Ping
