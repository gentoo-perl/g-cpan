#!/usr/bin/perl -w
# Copyright 1999-2004 Gentoo Foundation
# Distributed under the terms of the GNU General Public License v2
# $Header: /var/cvsroot/gentoo/users/mcummings/g-cpan/g-cpan-0.12/bin/g-cpan.pl,v 1.1 2005/04/30 21:44:15 mcummings Exp $
#

# modules to use - these will need to be marked as
# dependencies, and installable by portage
use strict;
use File::Spec;
use File::Path;
use List::Util qw(first);
use CPAN;
eval 'use Digest::MD5;';
my $have_digestmd5 = $@ ? 0 : 1;

my $VERSION="0.12";

# output error if no arguments
unless (@ARGV) {
    print "Usage: g-cpan.pl [-v] MODULENAME ...\n";
    exit;
}
my $VERBOSE = 0;
if ($ARGV[0] eq '-v') {
	shift @ARGV;
	$VERBOSE = 1;
}
# Set our temporary overlay directory for the scope of this run. By setting an overlay directory,
# we bypass the predefined portage directory and allow portage to build a package outside of its
# normal tree.
my $tmp_overlay_dir = "/tmp/perl-modules_$$";
my @ebuild_list;

# Set up global paths
my $TMP_DEV_PERL_DIR = '/var/db/pkg/dev-perl';
my $MAKECONF         = '/etc/make.conf';
my ( $OVERLAY_DIR, $PORTAGE_DIR, $PORTAGE_DEV_PERL, $PORTAGE_DISTDIR ) = get_globals();

# Create the ebuild in PORTDIR_OVERLAY, if it is defined and exists
$tmp_overlay_dir = $OVERLAY_DIR unless $OVERLAY_DIR eq "";

my $arches = join( ' ', map { chomp; $_ } `cat $PORTAGE_DIR/profiles/arch.list` );

#this should never find the dir, but just to be safe
unless ( -d $tmp_overlay_dir ) {
    mkpath( [$tmp_overlay_dir], 1, 0755 )
      or die "Couldn't create '$tmp_overlay_dir': $|";
}

# Now we cat our dev-perl directory onto our overlay directory.
# This is done so that portage records the appropriate path, i.e. dev-perl/package
my $perldev_overlay = File::Spec->catfile( $tmp_overlay_dir, 'dev-perl' );

unless ( -d $perldev_overlay ) {
    # create perldev overlay dir if not present
    mkpath( [$perldev_overlay], 1, 0755 )
      or die "Couldn't create '$perldev_overlay': $|";
}

# Now we export our overlay directory into the session's env vars
$ENV{'PORTDIR_OVERLAY'} = $tmp_overlay_dir;

# jrray printing functions
sub printbig {
    print '*' x 72, "\n";
    print '*',   "\n";
    print '*',   "\n";
    print '*  ', @_;
    print '*',   "\n";
    print '*',   "\n";
    print '*' x 72, "\n";
}

sub ebuild_exists {
    my ($dir) = @_;

    # need to try harder here - see &portage_dir comments.
    # should return an ebuild name from this, as case matters.

    # see if an ebuild for $dir exists already. If so, return its name.
    my $found = '';

    foreach my $sdir (grep {-d $_} ($PORTAGE_DEV_PERL, $perldev_overlay, $TMP_DEV_PERL_DIR)) {
        opendir PDIR,$sdir;
        my @dirs = readdir(PDIR);
        closedir PDIR;
        $found ||= first {lc($_) eq lc($dir)} (@dirs);
	if (($found)&&($VERBOSE)) {
        print "$0: Looking for ebuilds in $sdir, found $found so far.\n"; }
    }

    # check for ebuilds that have been created by g-cpan.pl
    for my $ebuild ( @ebuild_list ) {
        $found = $ebuild if ( $ebuild eq $dir );
    }

    return $found;
}

sub module_check {

    # module_check evaluates whether a module can be loaded from @INC.
    # This allows us to assure that if a module has been manually installed, we know about it.
    my $check = shift;
    eval "use $check;";
    return $@ ? 0 : 1;
}

sub portage_dir {
    my $obj  = shift;
    my $file = $obj->cpan_file;

    # need to try harder here than before (bugs 64403 74149 69464 23951 +more?)

    # remove ebuild-incompatible characters
    $file =~ tr/a-zA-Z0-9\.\//-/c;

    $file =~ s/\.pm//;  # e.g. CGI.pm

    # turn this into a directory name suitable for portage tree
    # at least one module omits the hyphen between name and version.
    # these two regexps are 'better' matches than previously.
    if ( $file =~ m|.*/(.*)-[0-9]+\.| ) { return $1; }
    if ( $file =~ m|.*/([a-zA-Z-]*)[0-9]+\.| ) { return $1; }
    if ( $file =~ m|.*/([^.]*)\.| ) { return $1; }
    
    warn "$0: Unable to coerce $file into a portage dir name";
    
    return;
}

sub create_ebuild {
    my ( $module, $dir, $file, $build_dir, $prereq_pm, $md5 ) = @_;

    # First, make the directory
    my $fulldir  = File::Spec->catdir( $perldev_overlay, $dir );
    my $filesdir = File::Spec->catdir( $fulldir,         'files' );
    mkdir $fulldir,  0755 or die "Couldn't create '$fulldir': $!";
    mkdir $filesdir, 0755 or die "Couldn't create '$filesdir': $!";

    unless ( -d $fulldir ) { die "$fulldir not created!!\n" }
    unless ( -d $filesdir ) { die "$fulldir not created!!\n" }
    # What to call this ebuild?
    # CGI::Builder's '1.26+' version breaks portage
    unless ( $file =~ m/(.*)\/(.*?)(-?)([0-9\.]+).*\.(?:tar|tgz|zip|bz2|gz)/ ) {
        warn("Couldn't turn '$file' into an ebuild name\n");
        return;
    }

    my ( $modpath, $filename, $filenamever ) = ( $1, $2, $4 );

    # remove underscores
    $filename =~ tr/A-Za-z0-9\./-/c;
    $filename =~ s/\.pm//;  # e.g. CGI.pm

    # Remove double .'s - happens on occasion with odd packages
    $filenamever =~ s/\.$//;

    my $ebuild = File::Spec->catdir( $fulldir,  "$filename-$filenamever.ebuild" );
    my $digest = File::Spec->catdir( $filesdir, "digest-$filename-$filenamever" );

    my $desc = $module->description || 'No description available.';

    print "Writing to $ebuild\n" if ($VERBOSE);
    open EBUILD, ">$ebuild" or die "Could not write to '$ebuild': $!";
    print EBUILD <<"HERE";


# Copyright 1999-2004 Gentoo Foundation
# Distributed under the terms of the GNU General Public License v2

inherit perl-module

S=\${WORKDIR}/$build_dir
DESCRIPTION="$desc"
SRC_URI="mirror://cpan/authors/id/$file"
HOMEPAGE="http://www.cpan.org/modules/by-authors/id/$modpath/\${P}.readme"

IUSE=""

SLOT="0"
LICENSE="|| ( Artistic GPL-2 )"
KEYWORDS="$arches"

HERE

    if ( $prereq_pm && keys %$prereq_pm ) {

        print EBUILD q|DEPEND="|;
        #MPC print EBUILD q|DEPEND="dev-perl/module-build |;

        my $first = 1;
        my %dup_check;
        for ( keys %$prereq_pm ) {

            my $obj = CPAN::Shell->expandany($_);
            my $dir = portage_dir($obj);
    	    if ( $dir eq "Module-Build" ) { $dir = "module-build" }
            next if $dir eq "perl";
            if ( ( !$dup_check{$dir} ) && ( !module_check($dir) ) ) {
                $dup_check{$dir} = 1;
		# remove trailing .pm to fix emerge breakage.
		$dir =~ s/.pm$//;
                print EBUILD "\n\t" unless $first;
                print EBUILD "dev-perl/$dir";
            }
            $first = 0;
        }
        print EBUILD qq|"\n\n|;
    }

    close EBUILD;

    # write the digest too
    open DIGEST, ">$digest" or die "Could not write to '$digest': $!";
    print DIGEST $md5, "\n";
    close DIGEST;
}

sub install_module {
    my ($module_name, $recursive) = @_;

    my $obj = CPAN::Shell->expandany($module_name);
    unless (( ref $obj eq "CPAN::Module" ) || ( ref $obj eq "CPAN::Bundle" )) {
        warn("Don't know what '$module_name' is\n");
        return;
    }

    my $file = $obj->cpan_file;
    my $dir  = portage_dir($obj);
    print "$0: portage_dir returned $dir\n" if ($VERBOSE);
    unless ($dir) {
        warn("Couldn't turn '$file' into a directory name\n");
        return;
    }

    if ( ebuild_exists($dir) ) {
        printbig "Ebuild already exists for '$module_name': ".&ebuild_exists($dir)."\n";
        return;

    }
    elsif ( !defined $recursive && module_check($module_name) ) {
        printbig "Module already installed for '$module_name'\n";
        return;
    }
    elsif ( $dir eq 'perl' ) {
        printbig "Module '$module_name' is part of the base perl install\n";
        return;
    }

    printbig "Need to create ebuild for '$module_name': $dir\n";

    # check depends ... with CPAN have to make the module
    # before it can tell us what the depends are, this stinks

    $CPAN::Config->{prerequisites_policy} = "";
    $CPAN::Config->{inactivity_timeout}   = 30;

    my $pack = $CPAN::META->instance( 'CPAN::Distribution', $file );
    $pack->called_for( $obj->id );
    $pack->make;
    # A cheap ploy, but this lets us add module-build as needed instead of forcing it on everyone
    my $add_mb = 0;
    if (-f "Build.PL") { $add_mb = 1 }
    $pack->unforce if $pack->can("unforce") && exists $obj->{'force_update'};
    delete $obj->{'force_update'};

    # grab the MD5 checksum for the source file now

    my $localfile = $pack->{localfile};
    ( my $base = $file ) =~ s/.*\/(.*)/$1/;

    my $md5digest;
    if ($have_digestmd5) {
    open( DIGIFILE, $localfile ) or die "Can't open '$file': $!";
    binmode(DIGIFILE);
    $md5digest = Digest::MD5->new->addfile(*DIGIFILE)->hexdigest;
    close(DIGIFILE);
    } else {
        ($md5digest = qx(/usr/bin/md5sum $localfile)) =~ s/^(.*?)\s.*$/$1/s;
    }

    my $md5string = sprintf "MD5 %s %s %d", $md5digest, $base,
      -s $localfile;

    # make ebuilds for all the prereqs
    my $prereq_pm = $pack->prereq_pm;
    if ($add_mb) {$prereq_pm->{'Module::Build'} = "0" }
    install_module($_, 1) for ( keys %$prereq_pm );

    # get the build dir from CPAN, this will tell us definitively
    # what we should set S to in the ebuild
    # strip off the path element
    (my $build_dir = $pack->{build_dir}) =~ s|.*/||;

    create_ebuild( $obj, $dir, $file, $build_dir, $prereq_pm, $md5string );

    system('/bin/mv', '-f', $localfile, $PORTAGE_DISTDIR);

    push @ebuild_list, $dir;
}

sub clean_up {

    #Probably don't need to do this, but for sanity's sake, we reset this var
    $ENV{'PORTDIR_OVERLAY'} = $OVERLAY_DIR;

    #Clean out the /tmp tree we were using
    rmtree( ["$tmp_overlay_dir"] ) if $OVERLAY_DIR eq "";
}

sub emerge_module {
    foreach my $ebuild_name (@ebuild_list) {
        $ebuild_name =~ m/.*\/(.*)-[^-]+\./;
        print "$0: emerging $ebuild_name\n";
#       system("emerge $ebuild_name");
	system( "emerge", "--oneshot", "--digest", $ebuild_name );

    }
}

sub get_globals {

    my ( $OVERLAY_DIR, $PORTAGE_DIR, $PORTAGE_DEV_PERL, $PORTAGE_DISTDIR );

    # let's not beat around the bush here, make.conf isn't the
    # only place these variables can be defined

    $OVERLAY_DIR=qx(/usr/lib/portage/bin/portageq portdir_overlay);
    $PORTAGE_DIR=qx(/usr/lib/portage/bin/portageq portdir);
    $PORTAGE_DISTDIR=qx(/usr/lib/portage/bin/portageq distdir);

    chomp $OVERLAY_DIR;
    chomp $PORTAGE_DIR;
    chomp $PORTAGE_DISTDIR;
    
    unless ( length $OVERLAY_DIR && -d $OVERLAY_DIR ) {
        $OVERLAY_DIR = "";
    }

    unless ( length $PORTAGE_DIR && -d $PORTAGE_DIR ) {
        $PORTAGE_DIR = "/usr/portage";
    }

    unless ( length $PORTAGE_DISTDIR && -d $PORTAGE_DISTDIR ) {
        $PORTAGE_DISTDIR = "/usr/portage/distfiles";
    }

    # Finally, set the dev-perl dir explicitly
    $PORTAGE_DEV_PERL = "$PORTAGE_DIR/dev-perl";

    return ( $OVERLAY_DIR, $PORTAGE_DIR, $PORTAGE_DEV_PERL, $PORTAGE_DISTDIR );

}

install_module($_) for (@ARGV);
emerge_module($_) for  (@ARGV);
clean_up();
