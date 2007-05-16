package Gentoo::Util;

use strict;
use warnings;
use Cwd qw(getcwd abs_path cwd);

require Exporter;
use base qw(Exporter);

our @EXPORT_OK = qw( check_access make_path strip_env );
our %EXPORT_TAGS = (all => [qw(&check_access &make_path &strip_env)]);

our $VERSION = '0.01';

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
            return $self->{"W"} = "Path $path not writeable";
        }
        else
        {
            return $self->{"PATH"} = $path;
        }
    }
    return;
}

sub strip_env
{
    my $self = shift;
    my $key  = shift;
    if (defined $ENV{$key})
    {
        $ENV{$key} =~ s{\\t}{ }gxms;
        $ENV{$key} =~ s{\\n}{ }gxms;
        $ENV{$key} =~ s{\\|\'|\\'|\$|\s*$}{}gmxs;
        $key       =~ s{\s+}{ }gmxs;
        return $ENV{$key};
    }
    else
    {
        $key =~ s{\\t}{ }gxms;
        $key =~ s{\\n}{ }gxms;
        $key =~ s{(\'|\\|\\'|\$|\s*$)}{}gmxs;
        $key =~ s{\s+}{ }gmxs;
        return $key;
    }
}

1;
