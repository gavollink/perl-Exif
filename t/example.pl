#!/usr/bin/perl
use strict;
use Exif;

use Data::Dumper;

my $opts;

MAIN: {
    opts(@ARGV);

    my $fn = $opts->{'filename'};
    if ( ! -f $fn ) {
        die "File not found: $fn";
    }

    my $res = Exif->new($opts);

    print "Filename: $fn\n";

    if ( $opts->{'verbose'} ) {
        print $Exif::ERROR;
        print $Exif::DEBUG;

        $res->dumpAll();
    }
    else {
        $res->dump();
    }
}

sub opts
{
    my @args = @_;

    if ( !$opts ) {
        $opts = {};
    }
    $opts->{'verbose'} = 0;

    my $help = 0;

    for ( my $cx = 0; $cx < scalar(@args); $cx++ ) {
        if ( q{-f} eq $args[$cx] ) {
            $opts->{'filename'} = $args[++$cx];
        }
        elsif ( q{--filename} eq $args[$cx] ) {
            $opts->{'filename'} = $args[++$cx];
        }
        elsif ( q{-v} eq $args[$cx] ) {
            $opts->{'verbose'}++;
        }
        elsif ( q{--verbose} eq $args[$cx] ) {
            $opts->{'verbose'}++;
        }
        elsif ( q{-h} eq $args[$cx] ) {
            $help = 1;
        }
        elsif ( q{--help} eq $args[$cx] ) {
            $help = 1;
        }
    }

    if ( ! $opts->{'filename'} || 0 == length( $opts->{'filename'} ) ) {
        print {*STDERR} "ERROR: No filename supplied.\n";
        $help = 1;
    }

    if ( $help ) {
        showhelp();
        exit(0);
    }
}

sub showhelp
{
    print <<'ENDHELP';
example.pl -- Exif.pm example script.

  --filename
  -f
        Name of JPEG file to read Exif info from.

  --verbose
  -v
        Show all Exif data, even if unknown.
ENDHELP
}
