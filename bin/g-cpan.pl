#!/usr/bin/perl -w
# Copyright 1999-2005 Gentoo Foundation
# Distributed under the terms of the GNU General Public License v2
#

# modules to use - these will need to be marked as
# dependencies, and installable by portage
use strict;
use File::Spec;
use File::Path;
use File::Basename;
use File::Copy;
use Term::ANSIColor;
use Digest::MD5;
use Cwd qw(getcwd abs_path cwd);
use YAML;
use YAML::Node;

use constant MAKE_CONF         => '/etc/make.conf';
use constant PATH_PKG_VAR      => '/var/db/pkg/';
##### CPAN CONFIG #####
use constant CPAN_CFG_DIR      => '.cpan/CPAN';
use constant CPAN_CFG_NAME     => 'MyConfig.pm';
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

##### ERRORS constants (easy internationalisation ;-) #####
use constant ERR_FILE_NOTFOUND   => "Couldn't find file '%s'";              # filename
use constant ERR_FOLDER_NOTFOUND => "Couldn't find folder '%s'";            # foldername
use constant ERR_OPEN_READ       => "Couldn't open (read) file '%s' : %s";   # filename, $!
use constant ERR_OPEN_WRITE      => "Couldn't open (write) file '%s' : %s";  # filename, $!
use constant ERR_FOLDER_OPEN     => "Couldn't open folder '%s', %s";        # foldername, $!
use constant ERR_FOLDER_CREATE   => "Couldn't create folder '%s' : %s";     # foldername, $!

my $VERSION = "0.13.02";
my $prog = basename($0);

my %dep_list = ();
my @perl_dirs = (
    "dev-perl",   "perl-core", "perl-gcpan", "perl-text",
    "perl-tools", "perl-xml",  "perl-dev"
);

###############################
# Command line interpretation #
###############################

# Module load & configure
use Getopt::Long;
Getopt::Long::Configure("bundling");

# Init all options (has to be done to perform the 'sum test' later)
my ( $verbose, $search, $install, $upgrade, $generate, $list, $pretend, $ask  ) = ( 0, 0, 0, 0, 0, 0, 0, 0 );


# Set colors here so we can use them at will anywhere :)
my $green = color("bold green");
my $white = color ("bold white");
my $cyan = color("bold cyan");
my $reset = color("reset");

#Get & Parse them
GetOptions(
    'verbose|v' => \$verbose,
    'search|s'  => \$search,
    'install|i' => \$install,
    'upgrade|u' => \$upgrade,
    'list|l'    => \$list,
    'pretend|p' => \$pretend,
    'ask|a'     => \$ask,
    'generate|g'   => \$generate,
    'help|h'    => sub { exit_usage(); }
  )
  or exit_usage();


# Output error if more than one switch is activated
#
if ( $search + $list + $install + $generate + $upgrade + $ask > 1 ) {
    print_err(
"You can't combine actions with each other.\n");
	print "${white}Please consult ${cyan}$prog ${green}--help${reset} or ${cyan}man $prog${reset} for more information\n\n";
	exit();
}

if ( $search + $list + $install + $generate + $upgrade + $pretend + $ask == 0 ) {
    print_err("You haven't told $prog what to do.\n");
	print "${white}Please consult ${cyan}$prog ${green}--help${reset} or ${cyan}man $prog${reset} for more information\n\n";

    exit();
    }

# Output error if no arguments
if ( (scalar(@ARGV) == 0 ) and !(defined($upgrade) or defined($list))  ) {
    print_err ("Not even one module name or expression given !\n");
    print "${white}Please consult ${cyan}$prog ${green}--help${reset} for more information\n\n";
	exit();
} 

######################
# CPAN Special Stuff #
######################

# Do we need to generate a config ?
eval 'use CPAN::Config;';
my $needs_cpan_stub = $@ ? 1 : 0;

# Don't do autointalls via ExtUtils::AutoInstall

$ENV{PERL_EXTUTILS_AUTOINSTALL}="--skipdeps";
# Test Replacement - ((A&B)or(C&B)) should be the same as ((A or C) and B)
if (   ( ($needs_cpan_stub) || ( $> > 0 ) )
    && ( !-f "$ENV{HOME}/.cpan/CPAN/MyConfig.pm" ) )
{

    # In case match comes from the UID test
    $needs_cpan_stub = 1;

    # Generate a fake config for CPAN
    cpan_stub();
}
else {
    $needs_cpan_stub = 0;
}

use CPAN;

##########
# main() #
##########

# Taking care of Searches. This has to be improved a lot, since it uses a call to
# CPAN Shell to do the job, thus making it impossible to have a clean output..
if ($search) {
    foreach my $expr (@ARGV) {

        # Assume they gave us module-name instead of module::name
        # which is bad, because CPAN can't convert it ;p

        print_ok ("Searching for $expr on CPAN");
        unless (CPAN::Shell->i("/$expr/")) {
		$expr =~ s/-/::/g;
		CPAN::Shell->i("/$expr/");
	}
    }

    clean_up();
    exit;
}

# Confirm that there is an /etc/portage/categories file
# and that we have an entry for perl-gcpan in it.
my $cat_file = "/etc/portage/categories";
if ( -f "$cat_file" ) {
   #
   #  Use braces to localize the $/ assignment, so we don't get bitten later.
   #
   my $data;
      local $/ = undef;
      open (FH, "/etc/portage/categories") || die;
      $data = <FH>;
      close FH;
   unless (grep "gcpan", $data ) 
    {

	if (open(CATEG,">/etc/portage/categories")) {
		print CATEG "perl-gcpan";
		close(CATEG);
	} else {
		print_err("Insufficient permissions to edit /etc/portage/categories");
		print_err("Please run $prog as a user with sufficient permissions");
		exit;
	}
   }

	
} else {
	if (open(CATEG,">/etc/portage/categories")) {
		print CATEG "perl-gcpan";
		close(CATEG);
	} else {
		print_err("Insufficient permissions to edit /etc/portage/categories");
		print_err("Please run $prog as a user with sufficient permissions");
		exit;
	}
}
# Set our temporary overlay directory for the scope of this run.
# By setting an overlay directory, we bypass the predefined portage
# directory and allow portage to build a package outside of its
# normal tree.
my $tmp_overlay_dir;

my @ebuild_list; #this array needs to be seriously observed.

# Set up global paths
# my $TMP_DEV_PERL_DIR = '/var/db/pkg/dev-perl';
my ( $PORTAGE_DISTDIR, $PORTAGE_DIR, @OVERLAYS ) = get_globals();

unless (scalar(@OVERLAYS) > 0) {
	if ( $generate or $pretend )
		{ print_err("The option you have chosen isn't supported without a configured overlay.\n");
		  exit();
		}
	unless($ENV{TMPDIR}) { $ENV{TMPDIR} = '/tmp' }
	$tmp_overlay_dir = "$ENV{TMPDIR}/perl-modules_$$";

	# Create the tmp_overlay_dir in the even that it is a 'real' temp dir
	if(not -d $tmp_overlay_dir) {
		mkpath($tmp_overlay_dir, 1, 0755) or fatal(ERR_FOLDER_CREATE, $tmp_overlay_dir, $!);
	}
	push @OVERLAYS, $tmp_overlay_dir;
}

# o_reset will be used to catch if went through all of the overlay dirs successfully - 
# open to better ways :) mcummings
my $o_reset = 1;

foreach my $o_dir (@OVERLAYS) {
    # See if we can create a file
    next if ($o_dir =~ m/^$/);
    if (open (TMP,">$o_dir/g-cpan-test") ) {
    	close(TMP);
	unlink("$o_dir/g-cpan-test");
    	$tmp_overlay_dir = $o_dir;
	$o_reset = 0;
    	if ($verbose) { print_info ("Setting $tmp_overlay_dir as the PORTDIR_OVERLAY for this session.") }
	last;
    }
}
if ($o_reset > 0) { 
	print_err("You don't have permission to work in any of the portage overlays.");
	print_err("Please run $prog as a user with sufficient permissions.\n");
	exit();
}


my @OVERLAY_PERLS;
my @PORTAGE_DEV_PERL;
my @TMP_DEV_PERL_DIRS;

foreach my $pdir (@perl_dirs) {
    my $tmp_dir = File::Spec->catdir( $PORTAGE_DIR, $pdir );
    push @PORTAGE_DEV_PERL, $tmp_dir;
    foreach my $odir (@OVERLAYS) {
        my $otmp = File::Spec->catdir( $odir, $pdir );
        push @OVERLAY_PERLS, $otmp;
    }
    my $vtmp_dir = File::Spec->catdir(PATH_PKG_VAR, $pdir );
    push @TMP_DEV_PERL_DIRS, $vtmp_dir;
}

# Create the ebuild in PORTDIR_OVERLAY, if it is defined and exists
# Part of this is to find an overlay the user running this session can actually write to

# Grab the whole available arches list, to include them later in ebuilds
print_info ("Grabbing arch list") if $verbose;
my $arches = do {
        open my $tmp, "<$PORTAGE_DIR/profiles/arch.list"
          or fatal(ERR_OPEN_READ, "$PORTAGE_DIR/profiles/arch.list", $!);
        join " ", map { chomp; $_ } <$tmp>;
};

# Now we cat our dev-perl directory onto our overlay directory.
# This is done so that portage records the appropriate path
#i.e. dev-perl/package
my $perldev_overlay = File::Spec->catfile( $tmp_overlay_dir, 'perl-gcpan' );
if(not -d $perldev_overlay) {
    # create perldev overlay dir if not present
    mkpath($perldev_overlay, 1, 0755) or fatal(ERR_FOLDER_CREATE, $perldev_overlay, $!);
}

# Now we export our overlay directory into the session's env vars
$ENV{PORTDIR_OVERLAY} = $tmp_overlay_dir;


# Take care of List requests. This should return all the ebuilds managed by g-cpan
if ($list) {
    print_ok ("Generating list of modules managed by g-cpan");
    my @managed = get_gcpans();
    exit();
}

if ($generate) {
    install_module($_) for (@ARGV);
}
if ($install) {
    install_module($_) for (@ARGV);
    emerge_module();
}

if ($upgrade) {
    if (@ARGV) {
        upgrade_module($_)   for (@ARGV);
        emerge_module($_);
    }
    else {
        my @GLIST = get_gcpans();
        upgrade_module($_) for (@GLIST);
        emerge_module(@GLIST);
    }
}

clean_up();

exit;

##############
# Big subs ! #
##############

sub ebuild_exists {
    my ($dir) = $_[0];

    # need to try harder here - see &portage_dir comments.
    # should return an ebuild name from this, as case matters.

    # see if an ebuild for $dir exists already. If so, return its name.
    my $found = '';
    # FIXME mcummings
    # Still not nice, but here's the deal. The way it was before, when this was being invoked multiple times,
    # it was passing through smaller and smaller sets of dirs each pass until it wasn't checking anything
    # Broken for some reason - foreach my $sdir (@PORTAGE_DEV_PERL, @OVERLAY_PERLS, @TMP_DEV_PERL_DIRS, $perldev_overlay) {
    my @dir_list;
    push @dir_list, @PORTAGE_DEV_PERL;
    push @dir_list, @OVERLAY_PERLS;
    push @dir_list, @TMP_DEV_PERL_DIRS;
    push @dir_list, $perldev_overlay;
  SOURCE_FOLDER:
    foreach my $sdir (@dir_list) {
        next if not -d $sdir;
        opendir PDIR, $sdir or fatal(ERR_FOLDER_OPEN, $sdir, $!);
        while(my $file = readdir PDIR) {
            if(lc $file eq lc $dir) {
	    	my $cat = basename($sdir);
                $found = "$cat/$file";
                print_info ("$prog: Looking for ebuilds in $sdir, found $found so far.") if $verbose;
                close PDIR;
                last SOURCE_FOLDER;
            }
        }
        closedir PDIR;
    }

    # check for ebuilds that have been created by g-cpan.pl - in THIS session
    for my $ebuild (@ebuild_list) {
        if($ebuild eq $dir) {
            $found = $ebuild;
            last;
        }
    }

    return $found;
}

sub get_gcpans {
    my @g_list;
    foreach my $sdir ( grep { -d $_ } ( @PORTAGE_DEV_PERL, @OVERLAY_PERLS ) ) {
        if ( basename($sdir) eq "perl-gcpan" ) {
    	    print_info ("OVERLAY: $sdir") if $list;
            # FIXME Sniper
            # maybee replace fatal by "warn and next folder" ?
            opendir PDIR, $sdir or fatal(ERR_FOLDER_OPEN, $sdir, $!);
            while(my $file = readdir PDIR) {
                next if $file eq '.'
                     or $file eq '..';
		print_info ("perl-gcpan/$file") if $list;
                push @g_list, $file;
            }
            closedir PDIR;
        }
    }
    return @g_list;
}

sub portage_dir {
    my $obj  = shift;
    my $file = $obj->cpan_file;

    # need to try harder here than before (bugs 64403 74149 69464 23951 +more?)

    # remove ebuild-incompatible characters
    $file =~ tr/a-zA-Z0-9\.\//-/c;

    $file =~ s/\.pm//;    # e.g. CGI.pm

    # turn this into a directory name suitable for portage tree
    # at least one module omits the hyphen between name and version.
    # these two regexps are 'better' matches than previously.
    if ( $file =~ m|.*/(.*)-v?[0-9]+\.| )        { return $1; }
    if ( $file =~ m|.*/([a-zA-Z-]*)v?[0-9]+\.| ) { return $1; }
	if ( $file =~ m|.*/([a-zA-Z-]*)\-v?\.[0-9]+\.| ) { return $1; }
    if ( $file =~ m|.*/([^.]*)\.| )            { return $1; }

    warn "$prog: Unable to coerce $file into a portage dir name";
    return;
}

sub create_ebuild {
    my ( $module, $dir, $file, $build_dir, $md5, $prereq_pm ) = @_;

    # First, make the directory
    my $fulldir  = File::Spec->catdir( $perldev_overlay, $dir );
    my $filesdir = File::Spec->catdir( $fulldir,         'files' );
    unless ( -d $fulldir ) {
        print_info ("Create folder '$fulldir'") if $verbose;
        mkdir($fulldir, 0755) or fatal(ERR_FOLDER_CREATE, $fulldir, $!);
    }
    unless ( -d $filesdir ) {
        print_info ("Create folder '$filesdir'") if $verbose;
        mkdir($filesdir, 0755) or fatal(ERR_FOLDER_CREATE, $filesdir, $!);
    }


    # What to call this ebuild?
    # CGI::Builder's '1.26+' version breaks portage
    #unless ( $file =~ m/(.*)\/(.*?)(-?)([0-9\.]+).*\.(?:tar|tgz|zip|bz2|gz)/ ) { MPC
    unless ( $file =~ m/.*\/.*?-?[0-9\.]+.*\.?:tar|tgz|zip|bz2|gz/ ) {
        warn("Couldn't turn '$file' into an ebuild name");
        return;
    }

    my $re_path = '(?:.*)?';
    my $re_pkg = '(?:.*)?';
    my $re_ver = '(?:v?[\d\.]+[a-z]?)?';
    my $re_suf = '(?:_(?:alpha|beta|pre|rc|p)(?:\d+)?)?';
    my $re_rev = '(?:\-r\d+)?';
    my $re_ext = '(?:(?:tar|tgz|zip|bz2|gz|tar\.gz))?';
    my $re_file = qr/($re_path)\/($re_pkg)-($re_ver)($re_suf)($re_rev)\.($re_ext)/;
    my ( $modpath, $filename, $filenamever, $filesuf, $filerev, $fileext ) = $file =~ /^$re_file/;
    #my ( $modpath, $filename, $filenamever ) = ( $1, $2, $4 ); MPC

    # remove underscores
    $filename =~ tr/A-Za-z0-9\./-/c;
    $filename =~ s/\.pm//;             # e.g. CGI.pm

    # Remove double .'s - happens on occasion with odd packages
    $filenamever =~ s/\.$//;

	# Some modules don't use the /\d\.\d\d/ convention, and portage goes
	# berserk if the ebuild is called ebulldname-.02.ebuild -- so we treat
	# this special case
    if (substr($filenamever, 0, 1) eq '.') {
      $filenamever = 0 . $filenamever;
    }


    my $ebuild = File::Spec->catdir( $fulldir, "$filename-$filenamever.ebuild" );
    my $digest = File::Spec->catdir( $filesdir, "digest-$filename-$filenamever" );

    my $desc = $module->description || 'No description available.';

    print_ok ("Writing to $ebuild") if ($verbose);
    open EBUILD, ">$ebuild" or fatal(ERR_OPEN_WRITE, $ebuild, $!);
    print EBUILD <<"HERE";
# Copyright 1999-2005 Gentoo Foundation
# Distributed under the terms of the GNU General Public License v2
# This ebuild generated by $prog $VERSION

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

    if ( $prereq_pm && keys %{$prereq_pm} ) {

        print EBUILD q|DEPEND="|;

        my $first = 1;
        my %dup_check;
        for ( keys %{$prereq_pm} ) {
			next if ($_ eq "perl" );
            my $obj = CPAN::Shell->expandany($_);
            my $dir = portage_dir($obj);
            if ( $dir =~ m/Module-Build/ ) {
                $dir =~ s/Module-Build/module-build/;
            }
            if ( $dir =~ m/PathTools/i ) {
                $dir = ">=perl-core/File-Spec-3.01";
            } # Will need to fix once File-Spec is moved to perl-core - mcummings
            if ( ( !$dup_check{$dir} ) && ( !module_check($dir) ) ) {
                $dup_check{$dir} = 1;

                # remove trailing .pm to fix emerge breakage.
                $dir =~ s/.pm$//;
                $dir = ebuild_exists($dir);
                print EBUILD "\n\t" unless $first;
                print EBUILD "$dir";
            }
            $first = 0;
        }
        print EBUILD qq|"\n\n|;
    }

    print EBUILD "src_compile() {
        export PERL_EXTUTILS_AUTOINSTALL=\"--skipdeps\"
        perl-module_src_compile
    }";
    close EBUILD;

    # write the digest too
    open DIGEST, ">$digest" or fatal(ERR_OPEN_WRITE, $digest, $!);
    print DIGEST $md5, "\n";
    close DIGEST;
}

sub install_module {
    my ( $module_name, $module_version, $recursive ) = @_;
	unless (defined($module_version)){$module_version = 0};
    if ( $module_name !~ m|::| ) {
        $module_name =~ s/-/::/g;
    }    # Assume they gave us module-name instead of module::name

    my $obj = CPAN::Shell->expandany($module_name);
    unless ( ( ref $obj eq "CPAN::Module" ) || ( ref $obj eq "CPAN::Bundle" ) )
    {
        warn("Don't know what '$module_name' is\n");
        return;
    }

    my $file = $obj->cpan_file;
    my $dir  = portage_dir($obj);
    print_info ("$prog: portage_dir returned $dir") if ($verbose);
    unless ($dir) {
        print_err ("Couldn't turn '$file' into a directory name\n");
        return;
    }
	my $dir2 = $module_name;
	$dir2   =~ s/::/-/g;

    if ( my $exists = ebuild_exists($dir) || ebuild_exists($dir2) ) {

	# Print simple found message unless verbose -verbose already got a long version
	print_info("Existing ebuild found for $exists\n") unless $verbose;
	# Just because an ebuild exists, doesn't mean we don't want to pass it on ;)
	push @ebuild_list, "$exists";
        return;
    }
    elsif ( !defined $recursive && module_check($module_name) ) {
        print_warn ("Module already installed for '$module_name'");
        return;
    }
    elsif ( $dir eq 'perl' ) {
        print_warn ("Module '$module_name' is part of the base perl install");
        return;
    }

    print_ok ("Need to create ebuild for '$module_name': $dir");

    # check depends ... with CPAN have to make the module
    # before it can tell us what the depends are, this stinks

    $CPAN::Config->{prerequisites_policy} = "";
    $CPAN::Config->{inactivity_timeout}   = 30;

    my $pack = $CPAN::META->instance( 'CPAN::Distribution', $file );
    $pack->called_for( $obj->id );
    $pack->make;

    # A cheap ploy, but this lets us add module-build as needed
    # instead of forcing it on everyone
    my $add_mb = 0;
    if ( -f "Build.PL" ) { $add_mb = 1 }
    $pack->unforce if $pack->can("unforce") && exists $obj->{'force_update'};
    delete $obj->{'force_update'};

    # grab the MD5 checksum for the source file now

    my $localfile = $pack->{localfile};
    ( my $base = $file ) =~ s/.*\/(.*)/$1/;

    my $md5string = sprintf "MD5 %s %s %d", file_md5sum($localfile), $base, -s $localfile;

    # make ebuilds for all the prereqs
    #my $prereq_pm = $pack->prereq_pm;
    #if ($add_mb) { $prereq_pm->{'Module::Build'} = "0" }
    #install_module( $_, 1 ) for ( keys %$prereq_pm );
		my $curdir = ".";
		&FindDeps($curdir, $module_name);
		
    	if ($add_mb) { $dep_list{$module_name}{'Module::Build'} = "0" }
    	install_module( $_, $dep_list{$module_name}{$_}, 1 ) for ( keys %{$dep_list{$module_name}} );

    # get the build dir from CPAN, this will tell us definitively
    # what we should set S to in the ebuild
    # strip off the path element
    ( my $build_dir = $pack->{build_dir} ) =~ s|.*/||;

    create_ebuild( $obj, $dir, $file, $build_dir, $md5string, \%dep_list );

    unless ( -f "$PORTAGE_DISTDIR/$localfile" ) {
       move("$localfile", "$PORTAGE_DISTDIR");
    }
    print_info("perl-gcpan/$dir created in $ENV{PORTDIR_OVERLAY}");
    push @ebuild_list, "perl-gcpan/$dir";
}

sub upgrade_module {

# My counter intuituve function - this time we *want* there to be an ebuild, because we want to track versions to make sure the ebuild is >= the module on cpan
    my ( $module_name, $recursive ) = @_;
    if ( $module_name !~ m|::| ) {
        $module_name =~ s/-/::/g;
    }    # Assume they gave us module-name instead of module::name
    print_info ("Looking for $module_name...");
    my $obj = CPAN::Shell->expandany($module_name);
    unless ( ( ref $obj eq "CPAN::Module" ) || ( ref $obj eq "CPAN::Bundle" ) )
    {
        warn("Don't know what '$module_name' is\n");
        return;
    }

    my $file = $obj->cpan_file;
    my $dir  = portage_dir($obj);
    print_info ("$prog: portage_dir returned $dir") if ($verbose);
    unless ($dir) {
        warn("Couldn't turn '$file' into a directory name\n");
        return;
    }

    unless ( ebuild_exists($dir) ) {
        print_warn ("No ebuild available for '$module_name': " . &ebuild_exists($dir));
        return;
    }
    elsif ( defined $recursive && !module_check($module_name) ) {
        print_warn ("No module installed for '$module_name'");
        return;
    }
    elsif ( $dir eq 'perl' ) {
        print_err
("Module '$module_name' is part of the base perl install - we don't touch perl here");
        return;
    }

    print_info ("Checking ebuild for '$module_name': $dir");
    my $fullname = ebuild_exists($dir);

    if (dirname($fullname) eq "perl-gcpan") {
		
    	# check depends ... with CPAN have to make the module
    	# before it can tell us what the depends are, this stinks

	    $CPAN::Config->{prerequisites_policy} = "";
   		$CPAN::Config->{inactivity_timeout}   = 30;

	    my $pack = $CPAN::META->instance( 'CPAN::Distribution', $file );
    	$pack->called_for( $obj->id );
    	$pack->make;

    	# A cheap ploy, but this lets us add module-build as needed
    	# instead of forcing it on everyone
    	my $add_mb = 0;
    	if ( -f "Build.PL" ) { $add_mb = 1 }
    	$pack->unforce if $pack->can("unforce") && exists $obj->{'force_update'};
    	delete $obj->{'force_update'};

    	# grab the MD5 checksum for the source file now

    	my $localfile = $pack->{localfile};
    	( my $base = $file ) =~ s/.*\/(.*)/$1/;

    	my $md5string = sprintf "MD5 %s %s %d", file_md5sum($localfile), $base, -s $localfile;

		#HERE - replace this call to $pack->prereq_pm with the new code, then cycle to get versions
    	# make ebuilds for all the prereqs

		my $curdir = ".";

		&FindDeps($curdir, $module_name);

    	#my $prereq_pm = $pack->prereq_pm;
    	#if ($add_mb) { $prereq_pm->{'Module::Build'} = "0" }
    	if ($add_mb) { $dep_list{$module_name}{'Module::Build'} = "0" }
    	#install_module( $_, 1 ) for ( keys %$prereq_pm );
    	install_module( $_, $dep_list{$module_name}{$_}, 1 ) for ( keys %{$dep_list{$module_name}} );

    	# get the build dir from CPAN, this will tell us definitively
    	# what we should set S to in the ebuild
    	# strip off the path element
    	( my $build_dir = $pack->{build_dir} ) =~ s|.*/||;

    	create_ebuild( $obj, $dir, $file, $build_dir, $md5string, \%dep_list );
    	unless ( -f "$PORTAGE_DISTDIR/$localfile" ) {
       		move("$localfile", "$PORTAGE_DISTDIR");
    	}
        push @ebuild_list, "perl-gcpan/$dir";
    }
	else { 
		push @ebuild_list, "$fullname";
	}

}

sub emerge_module {
	my @flags;
	push @flags, "-p" if $pretend > 0;
	push @flags, "-u" if $upgrade > 0;
	push @flags,  "--ask" if $ask > 0;
	print_info ("Calling: emerge --oneshot --digest @ebuild_list") if ($verbose);
    # FIXME Sniper
    # check return values
    if (@ebuild_list) {
    system( "emerge", @flags, "--oneshot", "--digest", @ebuild_list );
    	# Portage apparently 'returns' with a status that is being interpreted as a failure even on success :(
	#or die "Emerge failed: $!";
    } else {
	print_err ("No ebuilds generated for emerge.");
    }
}

sub get_globals {

    # Setting default configs
    my %conf;
    # FIXME Sniper
    # use constants
    $conf{PORTDIR} = "/usr/portage";
    $conf{DISTDIR} = "/usr/portage/distfiles";
    my @OVERLAYS = ();

    # Opening make.conf to find real user settings
    open CONF, MAKE_CONF or fatal(ERR_OPEN_READ, MAKE_CONF, $!);

    # And parsing it :)
    while ( defined( my $line = <CONF> ) ) {

        # Improving speed by ignoring comments
        next if ( substr( $line, 0, 1 ) eq '#' );
        chomp $line;

        $line =~ tr/\"\'//d;    # Remove quotes to be safe

        # Now replacing defaults, if other values are set
        if ( $line =~ m/^PORTDIR\s*=\s*(.+)$/ ) {
            $conf{PORTDIR} = $1;
        }
        if ( $line =~ m/^DISTDIR\s*=\s*(.+)$/ ) {
            $conf{DISTDIR} = $1;
        }
        if ( $line =~ m/^PORTDIR_OVERLAY\s*=\s*(.+)$/ ) {
            my $hold_overlay = $1;
            if ( $hold_overlay =~
                m/\b\s*/ )    # make.conf contains multiple overlay options
            {
                my @hold_ov = split( ' ', $hold_overlay );
                foreach my $hold_o (@hold_ov) { push @OVERLAYS, $hold_o }
            }
            else {
                push @OVERLAYS, $hold_overlay;
            }
        }
    }
    close CONF;

  # If the PORTDIR_OVERLAY is an env var, test to see if it is multiples are not
    if ( $ENV{PORTDIR_OVERLAY} ) {
        if ( $ENV{PORTDIR_OVERLAY} =~ m/\b\s*/ )   # At least 2, space seperated
        {
            my @tmp_overlays = split( ' ', $ENV{PORTDIR_OVERLAY} );
            foreach my $tmp_o (@tmp_overlays) {
                if ( $tmp_o =~ m/\w+/ ) { push @OVERLAYS, $tmp_o }
            }
        }
        else {
            push @OVERLAYS, $ENV{PORTDIR_OVERLAY};
        }
    }

    $conf{DISTDIR} = clean_vars( $conf{DISTDIR}, %conf );
    my $count_o = @OVERLAYS;
    for ( my $i = 0 ; $i < $count_o ; $i++ ) {
        $OVERLAYS[$i] = clean_vars( $OVERLAYS[$i], %conf );
	print_info("Adding $OVERLAYS[$i] to overlay list\n") if $verbose;
    }

    return ( $conf{DISTDIR}, $conf{PORTDIR}, @OVERLAYS );
}

sub cpan_stub {
    my $cpan_cfg_dir  = File::Spec->catfile($ENV{HOME},    CPAN_CFG_DIR);
    my $cpan_cfg_file = File::Spec->catfile($cpan_cfg_dir, CPAN_CFG_NAME);

    print_warn ("No CPAN Config found, auto-generating a basic one in $cpan_cfg_dir");
    if(not -d $cpan_cfg_dir) {
        mkpath($cpan_cfg_dir, 1, 0755 ) or fatal(ERR_FOLDER_CREATE, $cpan_cfg_dir, $!);
    }

    my $tmp_dir       = -d $ENV{TMPDIR}      ? defined($ENV{TMPDIR})      : $ENV{HOME};
    my $ftp_proxy     =    $ENV{ftp_proxy}   ? defined($ENV{ftp_proxy})   : '';
    my $http_proxy    =    $ENV{http_proxy}  ? defined($ENV{http_proxy})  : '';
    my $user_shell    = -x $ENV{SHELL}       ? defined($ENV{SHELL})       : DEF_BASH_PROG;
    my $ftp_prog      = -x DEF_FTP_PROG      ? DEF_FTP_PROG      : '';
    my $gpg_prog      = -x DEF_GPG_PROG      ? DEF_GPG_PROG      : '';
    my $gzip_prog     = -x DEF_GZIP_PROG     ? DEF_GZIP_PROG     : '';
    my $lynx_prog     = -x DEF_LYNX_PROG     ? DEF_LYNX_PROG     : '';
    my $make_prog     = -x DEF_MAKE_PROG     ? DEF_MAKE_PROG     : '';
    my $ncftpget_prog = -x DEF_NCFTPGET_PROG ? DEF_NCFTPGET_PROG : '';
    my $less_prog     = -x DEF_LESS_PROG     ? DEF_LESS_PROG     : '';
    my $tar_prog      = -x DEF_TAR_PROG      ? DEF_TAR_PROG      : '';
    my $unzip_prog    = -x DEF_UNZIP_PROG    ? DEF_UNZIP_PROG    : '';
    my $wget_prog     = -x DEF_WGET_PROG     ? DEF_WGET_PROG     : '';

    open CPANCONF, ">$cpan_cfg_file" or fatal(ERR_FOLDER_CREATE, $cpan_cfg_file, $!);
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



sub FindDeps
{
    my ($workdir)  = shift;
    my $module_name = shift;
    my ($startdir) = &cwd;
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
            if ( $object =~ m/\.yml/ ) {

                # Do YAML parsing if you can
                    my $b_n = dirname($abs_path);
                    $b_n = basename($b_n);
                    my $arr  = YAML::LoadFile($abs_path);
                    foreach my $type qw(requires build_requires recommends) {
                        my %ar_type = $arr->{$type};
                     if (keys %ar_type  ) {
                        foreach my $module ( keys %ar_type ) {
                            next if ($module eq "");
                            next if ( $module =~ /Cwd/i );
                            $dep_list{$module_name}{$module} = $arr->{$type}{$module};
                        }
                     }
                    }
            }
            if ( $object =~ m/^Makefile$/ ) {

                # Do some makefile parsing
                # RIPPED from CPAN.pm ;)
                use FileHandle;

                my $b_dir = dirname($abs_path);
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
                            $dep_list{$module_name}{$1} = $2;
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
                                    $dep_list{$module_name}{$module} = "$vers";
                                }
                            }
                            last;

                        }
                    }
                }

            }

        }
        elsif ( -d $object ) {
            &FindDeps($object, $module_name);
            next;
        }

    }
    chdir($startdir) or die "Unable to change to dir $startdir:$!\n";

}

################
# Display subs #
################

# cab - four (very fast) subs to help formating text output. Guess they could be improved a lot
# maybe i should add a FIXME - Sniper around here.. :)
# anyway, they expect a string and add a colored star at the beginning and the CR/LF
# at the end of the line. oh, shiny world ;)
sub print_ok {
	print " ", color("bold green"), "* ", color("reset"), "$prog: ", @_, "\n";
}
sub print_info {
	print " ", color("bold cyan"), "* ", color("reset"), "$prog: ", @_, "\n";
}
sub print_warn {
	print " ", color("bold yellow"), "* ", color("reset"), "$prog: ", @_, "\n";
}
sub print_err{
	print " ", color("bold red"), "* ", color("reset"), "$prog: ", @_, "\n";
}

#################################################
# NAME  : fatal
# AUTHOR: David "Sniper" Rigaudiere
# OBJECT: die like with pattern format
#
# IN: 0 scalar pattern sprintf format
#     x LIST   variables filling blank in pattern
#################################################
sub fatal { my $femfat =  sprintf(shift, @_);
	print_err($femfat) and exit();
 }


##############
# Tools subs #
##############

# cab - Simple useful sub. returns md5 hexdigest of the given argument.
# awaits a file name.
sub file_md5sum {
    my ($file) = @_;
    if (-f $file) {
    print_info ("Computing MD5 Sum of $file") if $verbose;

    open DIGIFILE, $file or fatal(ERR_OPEN_READ, $file, $!);
    my $md5digest = Digest::MD5->new->addfile(*DIGIFILE)->hexdigest;
    close DIGIFILE;
    return $md5digest if $md5digest;
    }
}

# In order to parse strange but allowed constructions,
# (i.e. DISTDIR=${PORTDIR}/disfiles), we are cycling some times
# (3 should be enough) on DISTDIR and PORTDIR_OVERLAY settings,
# using a nice regexp (thx Sniper - sniper@mongueurs.net)
sub clean_vars {
    my ( $toclean, %conf ) = @_;
    foreach my $i ( 1 .. 3 ) { $toclean =~ s/\$\{ ( [^}]+ ) \}/$conf{$1}/egx }
    return ($toclean);
}

# mcummings - module_check evaluates whether a module can be loaded from @INC.
# This allows us to assure that if a module has been manually installed, we know about it.
sub module_check {
    my $check = shift;
    print_info("Checking to see if $check is installed already\n") if $verbose;
    eval "use $check;";
    return $@ ? 0 : 1;
}

###############
# Ending subs #
###############

# cab - Takes care of system's sanity
# should try to see if it can be merged with clean_up()
# TODO Sniper
# maybee put this in END {} block
sub clean_up {

    #Clean out the /tmp tree we were using
    #I know this looks weird, but since clean_up is invoked on a search, where OVERLAYS isn't ever defined,
    # we first need to see if it exists, then need to remove only if it has content (the old exists vs. defined)
    
    if ( (defined($ENV{TMPDIR}) ) and ( defined($tmp_overlay_dir) && ($tmp_overlay_dir =~ m/^$ENV{TMPDIR}/) ) ) { 
        print_info("Cleaning temporary overlay\n") if $verbose;
        rmtree( ["$tmp_overlay_dir"] );
    }
    #if ($tmp_overlay_dir =~ m/^$ENV{TMPDIR}/) { rmtree( ["$tmp_overlay_dir"] ) }
    #print_info("Removing cpan build dir") if $verbose;
    # Removing this block for now - it's causing weird errors, and the default config we setup for CPAN allows CPAN
    # to remove contents from this directory as needed anyway. We never manually do anything in .cpan/build - its strictly CPAN's domain
    #if ( -d "$ENV{HOME}/.cpan/build" ) { rmtree( ["$ENV{HOME}/.cpan/build"]) }
}

# cab - nice help message ! ;)
sub exit_usage {
    print <<"USAGE";
${white}Usage : ${cyan}$prog ${green}<Switch(es)> ${cyan}Module Name(s)${reset}

${green}--ask,-a${reset}
    Ask before installing

${green}--generate,-g${reset}
    Generate ebuilds only (Requires working overlays)

${green}--install,-i${reset}
    Try to generate ebuild for the given module name
    and, if successful, emerge it. Important : installation
    requires exact CPAN Module Name.

${green}--list,-l${reset}
    This command generates a list of the Perl modules and ebuilds
    handled by $prog.

${green}--pretend,-p${reset}
    Pretend (show actions, but don't emerge). This still generates
    new ebuilds.

${green}--search,-s${reset}
    Search CPAN for the given expression (similar to
    the "m /EXPR/" from the CPAN Shell). Searches are
    case insensitive.

${green}--upgrade,-u${reset}
    Try to list and upgrade all Perl modules managed by $prog.
    It generate up-to-date ebuilds, then emerge then.

${green}--verbose,-v${reset}
    Enable (some) verbose output.

USAGE

    exit;
}
