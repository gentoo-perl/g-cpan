package Gentoo::Portage;

use 5.008007;
use strict;
use warnings;

use Cwd qw( cwd );
use File::Find ();
use Shell::EnvImporter;

#use Memoize;
#memoize('getAvailableVersions');

# for the convenience of &wanted calls, including -eval statements:
use vars qw/*name *dir *prune/;
*name  = *File::Find::name;
*dir   = *File::Find::dir;
*prune = *File::Find::prune;

my @store_found_dirs;
my @store_found_ebuilds;

# These libraries were influenced and largely written by
# Christian Hartmann <ian@gentoo.org> originally. All of the good
# parts are ian's - the rest is mcummings messing around.

require Exporter;

our @ISA = qw(Exporter Gentoo);

our @EXPORT = qw( getAvailableEbuilds getAvailableVersions generate_digest emerge_ebuild );

our $VERSION = '0.01';


sub new {
    my $class = shift;
    return bless {}, $class;
}


sub _strip_env {
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

sub getAvailableEbuilds {
    my ( $self, $portdir, $catPackage ) = @_;
    my @ebuilds;

    if ( -e $portdir . "/" . $catPackage ) {

        # - get list of ebuilds >
        my $startdir = &cwd;
        chdir( $portdir . "/" . $catPackage );
        @store_found_ebuilds = [];
        File::Find::find( { wanted => \&_wanted_ebuilds }, '.' );
        chdir($startdir);
        foreach (@store_found_ebuilds) {
            $_ =~ s{^\./}{}xms;
            if ( $_ =~ m/(.+)\.ebuild$/ ) {
                next if ( $_ eq "skel.ebuild" );
                push @ebuilds, $_;
            }
            else {
                if ( -d $portdir . "/" . $catPackage . "/" . $_ ) {
                    $_ =~ s{^\./}{}xms;
                    my $startdir = &cwd;
                    chdir( $portdir . "/" . $catPackage . "/" . $_ );
                    @store_found_ebuilds = [];
                    File::Find::find( { wanted => \&_wanted_ebuilds }, '.' );
                    chdir($startdir);
                    foreach (@store_found_ebuilds) {
                        if ( $_ =~ m/(.+)\.ebuild$/ ) {
                            next if ( $_ eq "skel.ebuild" );
                            push @ebuilds, $_;
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

    return \@ebuilds;
}

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
    my ( $self, $find_ebuild, $portdir, $tc, $tp ) = @_;

    my $ebuilds = $self->getAvailableEbuilds( $portdir, "$tc/$tp" )
      or return;

    foreach ( @$ebuilds ) {
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

    return 1;
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
        File::Find::find( { wanted => \&_wanted_dirs }, '.' );

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
                        $self->{portage}{ lc($find_ebuild) }{DESCRIPTION} = _strip_env( $ENV{DESCRIPTION} );
                        $self->{portage}{ lc($find_ebuild) }{HOMEPAGE}    = _strip_env( $ENV{HOMEPAGE} );
                        $e_import->restore_env;

                    }

sub emerge_ebuild {
    my $self  = shift;
    my @call = @_;
    # emerge forks and returns, which confuses this process. So
    # we call it the old fashioned way :(
    system( "emerge", @call );
}

sub _wanted_dirs {
    my ( $dev, $ino, $mode, $nlink, $uid, $gid );
    ( ( $dev, $ino, $mode, $nlink, $uid, $gid ) = lstat($_) )
      && -d _
      && ( $name !~ m|/files| )
      && ( $name !~ m|/CVS| )
      && push @store_found_dirs, $name;
}

sub _wanted_ebuilds {
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

    use Gentoo::Portage;
    my $portage_obj = Gentoo::Portage->new();

=head1 DESCRIPTION

The C<Gentoo::Portage> class provides access to portage tools and tree
information.

=head1 METHODS

=over 4

=item new()

Returns a new C<Gentoo::Portage> object.

=item getAvailableEbuilds( $portdir, "$category/$package" );

Providing the C<PORTDIR> you want to investigate and the name of
category/package you are interested.
Returns a list (arrayref) of available ebuilds.

=item getAvailableVersions( $portdir, $package_name )

Given the portage directory and the name of a package, try to find
if any ebuild exists and which versions are available for this name.

=item $obj->getEbuildVersionSpecial($ebuild)

Given the full name of an ebuild (C<foo-1.3.4-rc5.ebuild>), this function will
return the actual version of the ebuild after stripping out the portage
related syntax.

=item $obj->generate_digest($path_to_ebuild)

Given the full path to an ebuild, generate a digest via C<ebuild PKG digest>

=item $obj->emerge_ebuild($pkg, @flags)

Given the name of a package and any optional flags, emerge the package with
portage.

=back

=head1 SEE ALSO

See L<Gentoo>.

=cut

# Reformat the below with: sprintf("%-12s %-28s %s\n",...)
__DATA__
dev-perl     Ace                          AcePerl
dev-perl     Authen-NTLM                  NTLM
dev-perl     Boulder                      Stone
dev-perl     DelimMatch                   Text-DelimMatch
dev-perl     Locale-gettext               gettext
dev-perl     Net-SSLeay                   Net_SSLeay
dev-perl     Net-SSLeay                   Net_SSLeay.pm
dev-perl     OLE-StorageLite              OLE-Storage_Lite
dev-perl     PDF-Create                   perl-pdf
dev-perl     SGMLSpm                      SGMLSpmii
dev-perl     extutils-pkgconfig           ExtUtils-PkgConfig
dev-perl     frontier-rpc                 Frontier-RPC
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
media-gfx    imagemagick                  PerlMagick
virtual      perl-File-Spec               File-Spec
