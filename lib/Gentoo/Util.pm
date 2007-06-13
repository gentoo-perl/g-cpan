package Gentoo::Util;

use strict;
use warnings;
use Cwd qw(getcwd abs_path cwd);

require Exporter;
use base qw(Exporter);

our @EXPORT_OK = qw( check_access make_path strip_env );
our %EXPORT_TAGS = (all => [qw(&check_access &make_path &strip_env)]);

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
sub make_path
{
    my $self = shift;
    my $components = shift;
    my @path;
    #my $perms      = "0755";

    if (ref($components) eq "ARRAY" || ref($components) eq "LIST")
    {
        for (@{$components}) { push @path, $_ }
    }
    elsif ( !ref($components) && grep ("/", $components ))
    {
        @path = split("/", $components)
    }
    else
    {
        return $self->{"E"} = "Failed to pass an ARRAY, LIST, or SCALAR for a path";
    }

    my $startdir = &cwd;
    for (@path)
    {
        if ( ! -d $_ ) { mkdir $_ or return $self->{"E"} = "Unable to create directory: $!" }
        chdir($_);
    }
    chdir($startdir);
    return;
}

sub check_access{
    my $self       = shift;
    my $components = shift;
    my $path;
    if (ref($components) eq "ARRAY" || ref($components) eq "LIST")
    {
        for (@{$components}) { $path .= "/$_" }
    }
    elsif (!ref($components))
    {
        $path = $components;
    }
    else
    {
        return $self->{"E"} = "Failed to pass an ARRAY, LIST, or SCALAR for a path";
    }
    if (-d $path)
    {
        if (!-w $path)
        {
            $self->{"W"} = "Path $path not writeable";
        }
            return $self->{"PATH"} = $path;
    }
    return;
}

sub strip_env
{
    my $self = shift;
    my $key  = shift;
    if (!$key) {  return }
    if (defined $ENV{$key})
    {
        $ENV{$key} = clean_text($ENV{$key});
        return $ENV{$key};
    }
    else
    {
        $key = clean_text($key);
        return $key;
    }
}

sub clean_text
{
    my $string = shift;
    $string =~ s{\\t}{ }gxms;
    $string =~ s{\\n}{ }gxms;
    $string =~ s{(\'|\\|\\'|\$|\s*$)}{}gmxs;
    $string =~ s{\s+}{ }gmxs;
    $string =~ s{^\s}{}gmxs;
    $string =~ s{\s$}{}gmxs;
    return $string;
}

1;
