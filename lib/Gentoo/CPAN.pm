package Gentoo::CPAN;


use 5.008007;
use strict;
use warnings;
use CPAN;

# These libraries were influenced and largely written by
# Christian Harmann <ian@gentoo.org> originally. All of the good
# parts are ian's - the rest is mcummings messing around.

require Exporter;

our @ISA = qw(Exporter );

our @EXPORT = qw( getCPANPackages	
);

our $VERSION = '0.01';

sub new {
	 my $proto = shift;
	 my %args = @_;
	 my $class = ref($proto) || $proto;
	 my $self = {};

	 $self->{modules} = {};
	 $self->{portage_categories} = @{$args{portage_categories}};
	 $self->{DEBUG} = $args{debug};
	 $self->{portdir} = $args{portdir};

	 bless( $self, $class );
	 return $self;
}

sub getCPANPackages {
	my $self = shift;
    my $force_cpan_reload = shift;
    my $cpan_pn           = "";
    my @tmp_v             = ();

    if ($force_cpan_reload) {

        # - User forced reload of the CPAN index >
        CPAN::Index->force_reload();
    }

    for my $mod ( CPAN::Shell->expand( "Module", "/./" ) ) {
        if ( defined $mod->cpan_version ) {

            # - Fetch CPAN-filename and cut out the filename of the tarball.
            #   We are not using $mod->id here because doing so would end up
            #   missing a lot of our ebuilds/packages >
            $cpan_pn = $mod->cpan_file;
            $cpan_pn =~ s|.*/||;

            if ( $mod->cpan_version eq "undef"
                && ( $cpan_pn =~ m/ / || $cpan_pn eq "" || !$cpan_pn ) )
            {

                # - invalid line - skip that one >
                next;
            }

            # - Right now both are "MODULE-FOO-VERSION-EXT" >
            my $cpan_version = $cpan_pn;

			$cpan_pn =~ s/\.pm//;    # e.g. CGI.pm
            # - Drop "-VERSION-EXT" from cpan_pn >
            $cpan_pn =~
              s/(?:-?)?(?:v?[\d\.]+[a-z]?)?\.(?:tar|tgz|zip|bz2|gz|tar\.gz)?$//;

			if ( $cpan_pn =~ m|.*/(.*)-v?[0-9]+\.| )        { $cpan_pn = $1; }
			if ( $cpan_pn =~ m|.*/([a-zA-Z-]*)v?[0-9]+\.| ) { $cpan_pn = $1; }
			if ( $cpan_pn =~ m|.*/([a-zA-Z-]*)\-v?\.[0-9]+\.| ) { $cpan_pn = $1; }
		    if ( $cpan_pn =~ m|.*/([^.]*)\.| )            { $cpan_pn = $1; }
			$cpan_pn =~ s/_$//;

            if ( length( lc($cpan_version) ) >= length( lc($cpan_pn) ) ) {

                # - Drop "MODULE-FOO-" from version >
                if ( length( lc($cpan_version) ) == length( lc($cpan_pn) ) ) {
                    $cpan_version = 0;
                }
                else {
                    $cpan_version = substr(
                        $cpan_version,
                        length( lc($cpan_pn) ) + 1,
                        length( lc($cpan_version) ) - length( lc($cpan_pn) ) - 1
                    );
                }
                if ( defined $cpan_version ) {
                    $cpan_version =~ s/\.(?:tar|tgz|zip|bz2|gz|tar\.gz)?$//;

    # - Remove any leading/trailing stuff (like "v" in "v5.2.0") we don't want >
                    $cpan_version =~ s/^[a-zA-Z]+//;
                    $cpan_version =~ s/[a-zA-Z]+$//;

                    # - Convert CPAN version >
                    @tmp_v = split( /\./, $cpan_version );
                    if ( $#tmp_v > 1 ) {
                        if ($self->{DEBUG}) {
                            print " converting version -> " . $cpan_version;
                        }
                        $cpan_version = $tmp_v[0] . ".";
                        for ( 1 .. $#tmp_v ) { $cpan_version .= $tmp_v[$_]; }
                        if ($self->{DEBUG}) { print " -> " . $cpan_version . "\n"; }
                    }

                    if ( $cpan_version eq "" ) { $cpan_version = 0; }

					# Going on the theory we don't track items without 0's
					next if ($cpan_version == 0);
                    $self->{modules}{'cpan'}{$cpan_pn} = $cpan_version;
                    $self->{modules}{'cpan_lc'}{ lc($cpan_pn) } = $cpan_version;
                }
            }
        }
    }
    return 0;
}

1;
