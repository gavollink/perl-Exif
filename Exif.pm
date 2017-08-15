####
# Exif.pm
# Some comments are cut/paste from here:
#    https://www.media.mit.edu/pia/Research/deepview/exif.html
package Exif;
use warnings;
use strict;

use Carp;
use IO::Handle;
use bignum;

use constant {
    JPEG0   => 0xFF,
    JPEG1   => 0xD8,
    JPEGZ   => 0xD9,
    APP1    => 0xE1,
};

our $ERROR = q{};
our $DEBUG = q{};
my $VERBOSE = 0;


sub new
{
    my $class = shift;
    my $self = { };
    bless $self, ref($class) || $class || 'Exif';

    $self->{'m_endian'} = _local_endian();

    STDERR->autoflush();

    my @args = @_;

    $self->init( @args );

    return $self;
}


sub init
{
    my $self = shift;
    my @args = @_;
    my $opts = {};

    if ( ! exists $self->{'opts'} ) {
        $self->{'opts'} = {};
    }

    my $buffer;
    my $filename;

    if ( 0 == scalar(@args) ) {
        return;
    }
    elsif ( 1 == scalar(@args) ) {
        # Deal with inbound hash
        if ( q{HASH} eq ref($args[0]) ) {
            $opts = $args[0];

            if ( exists $opts->{'verbose'} ) {
                $VERBOSE++;
                info("Set verbose");
            }
            if ( exists $opts->{'filename'} ) {
                $filename = $opts->{'filename'};
            }
            if ( exists $opts->{'buffer'} ) {
                $buffer = $opts->{'buffer'};
            }
        }
        elsif ( q{ARRAY} eq ref($args[0]) ) {
            # De-reference inbound array ref
            return $self->init(@{$args[0]});
        }
        else {
            if ( -f $args[0] ) {
                $filename = $args[0];
            }
            elsif ( 30 < length($args[0]) ) {
                $buffer = $args[0];
            }
            else {
                return;
            }

            return;
        }

    }

    # Deal with inbound ARRAY
    for ( my $cx = 0; $cx < $#args; $cx++ ) {
        if ( q{verbose} eq $args[$cx] ) {
            $VERBOSE++;
            info("Setting verbose");
        }
        elsif ( q{buffer} eq $args[$cx] ) {
            $buffer = $args[++$cx];
        }
        elsif (q{filename} eq $args[$cx]) {
            $filename = $args[++$cx];
        }
        else {
            my $nm = ref($self) || $self || 'Exif';
            $nm .= '->init()';
            critical( "$nm: Invalid parameters." );
        }
    }

    if ( $buffer ) {
        info("Setting buffer");
        $self->buffer($buffer);
    }
    elsif ( $filename ) {
        info("Setting filename");
        $self->filename($filename);
    }
}


sub buffer
{
    my $self = shift;
    my $buffer = shift;
    my $name = ref($self) || $self || 'Exif';
    $name .= q{->buffer()};

    if ( ! defined($buffer) ) {
        critical( "$name: No buffer supplied.");
    }
    if ( 30 > length($buffer) ) {
        critical( "$name: Supplied buffer too small.");
    }

    $self->{'raw_buffer'} = $buffer;
    $self->{'buf_len'} = length($buffer);
    $self->{'buf_max'} = $self->{'buf_len'} - 1;
    $self->read();
}


sub filename
{
    my $self = shift;
    my $fn = shift;
    my $name = ref($self) || $self || 'Exif';
    $name .= q{->filename()};

    if ( 0 == length($fn) ) {
        critical( "$name: called with no filename.\n");
        return;
    }
    if ( ! -f $fn ) {
        critical( "$name: file $fn not found.\n");
        return;
    }
    $self->{'opt'}->{'filename'} = $fn;

    my $fh = undef;
    open( $fh, '<', $fn ) || critical( "$name: Unable to open: $!");
    binmode $fh;

    my $tenK = q{};
    read( $fh, $tenK, 11000, 0 ) || critical( "$name: Unable to read: $!");
    close ( $fh );

    if ( length($tenK) ) {
        $self->buffer($tenK);
    }
    else {
        critical( "$name: No data read from filename $fn." );
    }
}



sub read
{
    my $self = shift;
    my $buff = shift || $self->{'raw_buffer'};
    my $name = ref($self) || $self || 'Exif';
    $name .= q{->read()};

    if ( exists( $self->{'Exif_read'} ) && 0 < $self->{'Exif_read'} ) {
        return;
    }

    if ( ! defined ( $buff ) ) {
        critical( "$name: Nothing in buffer.");
    }

    # The raw buffer is copied entirely into a huge array called split.
    my @split = ();
    foreach my $cx ( 0 .. length($buff)-1 ) {
        $split[$cx] = vec($buff,$cx,8);
    }

    if ( ( JPEG0 == ($split[0]) )
        && ( JPEG1 == ($split[1]) ) ) {
        $self->jpegRead(\@split);
    }
    else {
        critical( "$name: No JPEG header in buffer.");
    }
}


sub jpegRead
{
    my $self = shift;
    my $buff = shift;

    my $name = ref($self) || $self || 'Exif';
    $name .= q{->jpegRead()};

    if ( ! defined ( $buff ) ) {
        critical( "$name: Nothing in buffer.");
    }
    if ( 'ARRAY' ne ref($buff) ) {
        critical( "$name: buffer is not an array.");
    }

    $self->{'Exif_read'} = 2;
    my $border = 0;
    my $app1 = 0;
    my $cx = -1;

BY: foreach my $byte ( @$buff ) {
        $cx++; # 0 on the first run...
        if ( 1 == $border ) {
            if ( JPEGZ == $byte ) {
                # END of JPEG file
                $border = 0;
                last BY;
            }
            elsif ( JPEG1 == $byte ) {
                # better be cx 1
                if ( $cx != 1 ) {
                    debug( "JPEG start marker found at byte $cx.\n" );
                    $border = 0;
                }
            }
            elsif ( APP1 == $byte ) {
                # Start of Exif ... probably (or JFIF)
                $app1 = 1;

                # Remove everything before the start of the EXIF
                splice(@$buff, 0, $cx-1);

                $self->readExifEnvelope($buff);

                return;
            }
        }
        if ( JPEG0 == $byte ) {
            $border = 1;
        }
        else {
            $border = 0;
        }
    }
}


sub readExifEnvelope
{
    my $self = shift;
    my $buff = shift;

    my $name = ref($self) || $self || 'Exif';
    $name .= q{->readExifEnvelope()};

    if ( ! defined ( $buff ) ) {
        critical( "$name: Nothing in buffer.");
    }
    if ( 'ARRAY' ne ref($buff) ) {
        critical( "$name: buffer is not an array.");
    }

    my $endian = undef;

    $self->{'Exif_offset'} = [];
    $self->{'Exif_titles'} = [];
    $self->{'Exif_read'} = 3;
    if ( ! exists $self->{'Exif_cnt'} ) {
        $self->{'Exif_cnt'} = 0;
    }

TP: for ( my $cx = 0; $cx<$#{$buff}; $cx++ ) {
        if ( ! defined $endian ) {
            # 49492a00 (Little Endian)
            if ( ( 0x49 == ($buff->[$cx]) )
                && ( 0x49 == ($buff->[$cx+1]) )
                && ( 0x2a == ($buff->[$cx+2]) )
                && ( 0x00 == ($buff->[$cx+3]) ) ) {
                #$cx += 4;
                $endian = 'I';
            }
            elsif ( ( 0x4d == ($buff->[$cx]) )
                && ( 0x4d == ($buff->[$cx+1]) )
                && ( 0x00 == ($buff->[$cx+2]) )
                && ( 0x2a == ($buff->[$cx+3]) ) ) {
                #$cx += 4;
                $endian = 'M';
            }
            else {
                next TP;
            }

            info( "$name: Exif endian is $endian.\n" );

            # Popping all pre-Exif header from buff.
            splice( @$buff, 0, $cx );
            $self->{'Exif_buff'} = $buff;
            $cx = 0;

            # Header was just found
            my $offset = _bytesToInt( $buff, $endian, $cx+4, 4 );
            if ( 8 > $offset ) {
                my $err = sprintf (
                    qq{%s: Tiff Header Offset too small (%s %d)},
                    $name,
                    $endian,
                    $offset,
                );
                critical( $err);
            }
            debug("Pushing offset, $offset");
            push @{$self->{'Exif_offset'}}, ( $offset );
            debug("Pushing title, IFD0");
            push @{$self->{'Exif_titles'}}, ( "IFD0" );
            $cx += $offset;

            $self->{'Exif_endian'} = $endian;

            $cx--; # For incrementor
            next TP;
        } # If header does exist (starting at this else)
        else {
            # header does exist IFD comes after
            if ( ! exists( $self->{'Exif_IFD'} ) ) {
                $self->{'Exif_IFD'} = {};
                my $tmp = $self->{'Exif_titles'}->[$self->{'Exif_cnt'}];
                $self->{'Exif_IFD'}->{$self->{'Exif_cnt'}} = {
                        'comment' =>    $tmp,
                    };
                debug( "TITLE: ", $tmp );
            }
            else {
                my $tmp = $self->{'Exif_titles'}->[$self->{'Exif_cnt'}];
                $self->{'Exif_IFD'}->{$self->{'Exif_cnt'}} = {
                        'comment' =>    $tmp,
                    };
                debug( "TITLE: ", $tmp );
                if ( $tmp =~ m{^GPS} ) {
                    $self->{'Exif_IFD'}->{$self->{'Exif_cnt'}}->{'Type'} = q{GPS};
                }
                elsif ( $tmp =~ m{^MakerNote} && $self->{'Make'} eq q{Canon} ) {
                    $self->{'Exif_IFD'}->{$self->{'Exif_cnt'}}->{'Type'} = q{MakerCanon};
                }
            }

            if ( $cx == $self->{'Exif_offset'}->[$self->{'Exif_cnt'}] ) {

                debug( sprintf(
                    qq{%s: IFD offset (%d) identified, reading\n},
                    $name,
                    $cx
                ));

                $cx = $self->readIFD(
                    $buff,
                    $cx,
                    $self->{'Exif_IFD'}->{$self->{'Exif_cnt'}}
                );

                $self->{'Exif_cnt'}++;

                debug( q{Exif count is now: }
                    . $self->{'Exif_cnt'}
                    . qq{\n}
                );

                if ( defined( $cx ) ) {
                    debug("Pushing offset, $cx");
                    push @{$self->{'Exif_offset'}}, ( $cx );
                    debug("Pushing title, ",  "IFD" . $self->{'Exif_cnt'} );
                    push @{$self->{'Exif_titles'}}, ( "IFD" . $self->{'Exif_cnt'} );
                }

                # Must POP these in order (even though elsif seems appropriate)
                if ( exists $self->{'Exif_offset'}->[$self->{'Exif_cnt'}] ) {
                    $cx = $self->{'Exif_offset'}->[$self->{'Exif_cnt'}];
                }
                elsif (( $self->{'MakerNote_size'} )
                &&     ( $self->{'MakerNote_offset'} )) {
                    # Decide whether to Process MakerNote Offset Normally
                    # or Differently
                    # Initial setup to process normally.

                    $cx = $self->{'MakerNote_offset'};
                    debug("Pushing MakerNote offset, $cx");

                    delete $self->{'MakerNote_offset'};

                    push @{$self->{'Exif_offset'}}, ( $cx );
                    push @{$self->{'Exif_titles'}}, ( "MakerNote" );

                    if ( $self->{'Make'} eq 'Canon' ) {
                        # CANON reads like another IFD.
                    }
                    else {
                        my $end = $cx + $self->{'MakerNote_size'};
                        debug("Undoing MakerNote offset");
                        pop @{$self->{'Exif_offset'}};
                        pop @{$self->{'Exif_titles'}};

                        $cx = $#{$buff};
                        next TP;
                    }
                }
                else {
                    $cx = $#{$buff};
                    next TP;
                }
            }
            else {
                critical( "$name: Offset does not match position, $cx.");
            }

            # Next Offset
            $cx--; # For incrementor
            next TP;
        }
    }
}


sub readIFD {
    my $self = shift;
    my $buff = shift;
    my $cx = shift;
    my $ifd = shift;
    my $endian = $self->{'Exif_endian'};

    my $name = ref($self) || $self || 'Exif';
    $name .= q{->readIFD()};

    if ( ! defined ( $buff ) ) {
        critical( "$name: Nothing in buffer.");
    }
    if ( 'ARRAY' ne ref($buff) ) {
        critical( "$name: buffer is not an array.");
    }

    if ( ! defined $ifd ) {
        $ifd = {};
    }
    elsif ( 'HASH' ne ref($ifd) ) {
        critical( "$name: ifd structure expected (3rd argument)");
    }
    if ( ! exists ( $ifd->{'count'} ) ) {
        $ifd->{'count'} = 0;
        $ifd->{'record'} = [];
    }

    # Record count first.
    my $ifd_cnt = _bytesToInt( $buff, $endian, $cx, 2 );
    $ifd->{'count'} += $ifd_cnt;
    
    $cx += 2;

    # Each record (needs a counter)
    foreach my $ifd_cx ( 0 .. $ifd_cnt-1 ) {
        my $tag = _bytesToInt( $buff, $endian, $cx, 2 );
        my $fmt = _bytesToInt( $buff, $endian, $cx+2, 2 );
        my $noc = _bytesToInt( $buff, $endian, $cx+4, 4 );
        my $val = _bytesToInt( $buff, $endian, $cx+8, 4 );
        $ifd->{'record'}->[$ifd_cx] = {
            'offset' => $cx,
            'tag' => $tag,
            'fmt' => $fmt,
            'noc' => $noc,
            'val' => $val,
            };
        $cx += 12;

        $self->readIFDTag($buff, $ifd, $ifd_cx);
    }
    my $off = _bytesToInt( $buff, $endian, $cx, 4 );
    if ( $off ) {
        return $off
    }
    return undef;

}


sub readIFDTag {
    my $self = shift;
    my $buff = shift;
    my $ifd = shift;
    my $ifd_cx = shift;
    my $endian = $self->{'Exif_endian'};

    my $type = 0;
    if ( exists $ifd->{'Type'} ) {
        $type = $ifd->{'Type'};
    }


    my $name = ref($self) || $self || 'Exif';
    $name .= q{->readIFDTag()};

    if ( q{HASH} ne ref($ifd) ) {
        critical( "$name: No IFD Capture Received.");
    }

    if ( ! defined ( $buff ) ) {
        critical( "$name: Nothing in buffer.");
    }
    if ( 'ARRAY' ne ref($buff) ) {
        critical( "$name: buffer is not an array.");
    }

    my $tag = $ifd->{'record'}->[$ifd_cx]->{'tag'};
    my $fmt = $ifd->{'record'}->[$ifd_cx]->{'fmt'};
    my $noc = $ifd->{'record'}->[$ifd_cx]->{'noc'};
    my $val = $ifd->{'record'}->[$ifd_cx]->{'val'};

    # Tag Name (DEFAULTs to the Hex of the Tag)
    if ( q{MakerCanon} eq $type ) {
        $ifd->{'record'}->[$ifd_cx]->{'tag_name'} = _canonMakerNoteTagName($tag);
    }
    elsif ( q{GPS} eq $type ) {
        $ifd->{'record'}->[$ifd_cx]->{'tag_name'} = _gpsInfoTagName($tag);
    }
    else {
        $ifd->{'record'}->[$ifd_cx]->{'tag_name'} = _exifTagName($tag);
    }

    # Format Name
    $ifd->{'record'}->[$ifd_cx]->{'fmt_name'} = _formatName($fmt);

    # Expanded Value (if supported)
    my $str = _expValueFromFormat($buff, $endian, $fmt, $noc, $val);
    $ifd->{'record'}->[$ifd_cx]->{'val_exp'} = $str;

    # Only customize the ones that we know how to customize

    if ( 0x010e == $tag ) {
        # Copyright
        if ( defined $str && length($str) ) {
            $self->{'Copyright'} = $str;
        }
    }
    elsif ( 0x010f == $tag ) {
        # Make
        if ( defined $str && length($str) ) {
            $self->{'Make'} = $str;
        }
    }
    elsif ( 0x0110 == $tag ) {
        # Model
        if ( defined $str && length($str) ) {
            $self->{'Model'} = $str;
        }
    }
    if ( 0x0112 == $tag && 3 == $fmt  ) {
        # q{Orientation};
        if ( $val == 1 ) {
            $str = q{normal (upper left)};
        }
        elsif ($val = 8 ) {
            $str = q{-90 counter-clockwise (lower left)};
        }
        elsif ($val = 3 ) {
            $str = q{upside-down (lower right)};
        }
        elsif ($val = 6 ) {
            $str = q{+90 clockwise (upper right)};
        }
        # Mirrored versions
        elsif ( $val == 2 ) {
            $str = q{normal (mirrored)};
        }
        elsif ($val = 7 ) {
            $str = q{-90 counter-clockwise (mirrored)};
        }
        elsif ($val = 4 ) {
            $str = q{upside-down (mirrored)};
        }
        elsif ($val = 5 ) {
            $str = q{+90 clockwise (mirrored)};
        }
        # Undefined versions
        elsif ($val = 9 ) {
            $str = q{undefined};
        }

        $ifd->{'record'}->[$ifd_cx]->{'val_exp'} = $str;

        # Top Level Tag
        $self->{'Orientation'} = $str;
        debug( "Orientation: $str\n" );
    }
    elsif ( 0x0128 == $tag && 3 == $fmt  ) {
        # q{ResolutionUnit};
        if ( $val == 1 ) {
            $str = q{none};
        }
        elsif ($val = 2 ) {
            $str = q{inch};
        }
        elsif ($val = 3 ) {
            $str = q{centimeter};
        }
        $ifd->{'record'}->[$ifd_cx]->{'val_exp'} = $str;
    }
    elsif ( 0x0132 == $tag ) {
        # DateTime
        if ( defined $str && length($str) ) {
            $self->{'DateTime'} = $str;
        }
    }
    elsif ( 0x014a == $tag && 4 == $fmt && 1 == $noc ) {
        # q{SubIFDs};
#        debug( "Exif SubIFD: $val\n" );
        debug("Pusing SubIFD.a offset, $val");
        push @{$self->{'Exif_offset'}}, ( $val );
        push @{$self->{'Exif_titles'}}, ( "SubIFD.a" );
    }
    elsif ( 0x8769 == $tag && 4 == $fmt && 1 == $noc ) {
        # q{Exif SubIFD};
#        debug( "Exif SubIFD: $val\n" );
        debug("Pusing SubIFD.b offset, $val");
        push @{$self->{'Exif_offset'}}, ( $val );
        push @{$self->{'Exif_titles'}}, ( "SubIFD.b" );
    }
    elsif ( 0x8825 == $tag && 4 == $fmt && 1 == $noc ) {
        # q{GPSInfo};
#        debug( "Exif SubIFD: $val\n" );
        debug("Pusing GPSInfo offset, $val");
        push @{$self->{'Exif_offset'}}, ( $val );
        push @{$self->{'Exif_titles'}}, ( "GPSInfo" );
    }
    elsif ( 0x9000 == $tag && 7 == $fmt ) {
        # q{Unknown};
        my $str = _strInBuff( $buff, $noc, $val );
        $ifd->{'record'}->[$ifd_cx]->{'val_exp'} = $str;
    }
    elsif ( 0x9003 == $tag ) {
        # DateTimeOriginal
        if ( defined $str && length($str) ) {
            $self->{'DateTimeOriginal'} = $str;
        }
    }
    elsif ( 0x9009 == $tag && 7 == $fmt ) {
        # q{Unknown};
        my $str = _strInBuff( $buff, $noc, $val );
        debug( sprintf( "0x9009: %s\n", $str) );
        $ifd->{'record'}->[$ifd_cx]->{'val_exp'} = $str;
    }
    elsif ( 0x927c == $tag && 7 == $fmt ) {
        # q{MakerNote};
        $self->{'MakerNote_size'} = $noc;
        $self->{'MakerNote_offset'} = $val;
    }
    elsif ( 0xa005 == $tag && 7 == $fmt ) {
        # q{ExifInteroperabilityOffset};
        debug( sprintf( "ExifInteroperabilityOffset: Read as IFD:\n") );
        debug("Pusing ExifInteroperabilityOffset offset, $val");
        push @{$self->{'Exif_offset'}}, ( $val );
        push @{$self->{'Exif_titles'}}, ( "ExifInteroperabilityOffset" );
    }
    elsif ( 0xa000 == $tag ) {
        # 'FlashPixVersion'
        my $str = _strInBuff( $buff, $noc, $val );
        $ifd->{'record'}->[$ifd_cx]->{'val_exp'} = $str;
    }
    elsif ( 0xa001 == $tag ) {
        # 'ColorSpace',
        my $str = $val;
        if ( 1 == $val ) {
            $str = q{sRGB};
        }
        elsif ( 2 == $val ) {
            $str = q{Adobe RGB};
        }
        elsif ( 0xFFFF == $val ) {
            $str = q{Uncalibrated (See InteroperabilityIndex)};
        }
        $ifd->{'record'}->[$ifd_cx]->{'val_exp'} = $str;
    }
    elsif ( 0xa210 == $tag && 3 == $fmt  ) {
        # q{FocalPlaneResolutionUnit};
        if ( $val == 1 ) {
            $str = q{none};
        }
        elsif ($val = 2 ) {
            $str = q{inch};
        }
        elsif ($val = 3 ) {
            $str = q{centimeter};
        }
        $ifd->{'record'}->[$ifd_cx]->{'val_exp'} = $str;
    }

}


sub make
{
    my $self = shift;

    my $name = ref($self) || $self || 'Exif';
    $name .= q{->make()};

    if ( ! exists( $self->{'Exif_read'} ) || 0 == $self->{'Exif_read'} ) {
        critical( "$name: called before anything was read.");
    }

    if ( exists( $self->{'Make'} ) ) {
        return $self->{'Make'};
    }
    return q{};
}

sub copyright
{
    my $self = shift;

    my $name = ref($self) || $self || 'Exif';
    $name .= q{->copyright()};

    if ( ! exists( $self->{'Exif_read'} ) || 0 == $self->{'Exif_read'} ) {
        critical( "$name: called before anything was read.");
    }

    if ( exists( $self->{'Copyright'} ) ) {
        return $self->{'Copyright'};
    }
    return q{};
}

sub model
{
    my $self = shift;

    my $name = ref($self) || $self || 'Exif';
    $name .= q{->model()};

    if ( ! exists( $self->{'Exif_read'} ) || 0 == $self->{'Exif_read'} ) {
        critical( "$name: called before anything was read.");
    }

    if ( exists( $self->{'Model'} ) ) {
        return $self->{'Model'};
    }
    return q{};
}

sub orientation
{
    my $self = shift;

    my $name = ref($self) || $self || 'Exif';
    $name .= q{->orientation()};

    if ( ! exists( $self->{'Exif_read'} ) || 0 == $self->{'Exif_read'} ) {
        critical( "$name: called before anything was read.");
    }

    if ( exists( $self->{'Orientation'} ) ) {
        return $self->{'Orientation'};
    }
    return q{};
}


sub datetime
{
    my $self = shift;

    my $name = ref($self) || $self || 'Exif';
    $name .= q{->datetime()};

    if ( ! exists( $self->{'Exif_read'} ) || 0 == $self->{'Exif_read'} ) {
        critical( "$name: called before anything was read.");
    }

    if ( exists( $self->{'DateTimeOriginal'} ) ) {
        return $self->{'DateTimeOriginal'};
    }
    elsif ( exists( $self->{'DateTime'} ) ) {
        return $self->{'DateTime'};
    }
    return q{};
}


sub dumpAll
{
    my $self = shift;
    $self->dump( { dumpUnknown => 1} );
}


sub dump
{
    my $self = shift;
    my $opt = shift;
    my $all = 0;

    my $name = ref($self) || $self || 'Exif';
    $name .= q{->dump()};

    my $ifd_cx = 0;

    if ( ! exists( $self->{'Exif_read'} ) || 0 == $self->{'Exif_read'} ) {
        critical( "$name: called before anything was read.");
    }
    else {

#                debug( qq{$name: Exif count is now: }
#                    . $self->{'Exif_cnt'}
#                    . qq{\n}
#                );
        $ifd_cx = $self->{'Exif_cnt'};
    }

    if ( ! defined( $ifd_cx ) || 0 == $ifd_cx ) {
        print "No IFD Sections Found.\n";
        return;
    }
    else {
        print "$ifd_cx IFD Sections Found:\n";
    }

    if ( defined $opt ) {
        if ( q{HASH} eq ref $opt ) {
            if ( exists $opt->{'dumpUnknown'} ) {
                $all = 1;
            }
#            else {
#                print qq{No dumpUnknown option\n};
#            }
        }
        else {
            critical( "$name: Option passed as " . ref($opt) || 'string' . ".");
        }
    }
#    else {
#        print qq{No option at all\n};
#    }

    for ( my $cx = 0; $cx < $ifd_cx; $cx++ ) {
        my $Exif = $self->{'Exif_IFD'}->{$cx};

        # Exif MUST be defined properly... die
        if ( ! defined ( $Exif ) ) {
            if ( ! defined( $self ) ) {
                print {*STDERR} "self not found.";
            }
            elsif ( ! defined( $self->{'Exif_IFD'} ) ) {
                print {*STDERR} "self->{'Exif_IFD'} not found.";
            }
            elsif ( ! defined( $self->{'Exif_IFD'}->{$cx} ) ) {
                print {*STDERR} "self->{'Exif_IFD'}->{\$cx} not found.";
            }
            critical( "$name: Exif $cx not found.");
        }

        my $count = $Exif->{'count'};
        my $records = $Exif->{'record'};

        # records MUST be defined properly... die
        if ( !defined $records ) {
            critical( "$name: Tags not found.");
        }
        elsif ( q{ARRAY} ne ref $records ) {
            critical( "$name: Tags not formatted correctly (expecting array).");
        }

        if ( $count != scalar( @$records ) ) {
            my $tmp = scalar( @$records );
            critical( "$name: Tag array count incorrect (got $tmp expecting $count).");
        }

        if ( defined $Exif->{'comment'} && $Exif->{'comment'} ) {
            print $Exif->{'comment'} . ", $count tags:\n";
        }
        else {
            print "IFD Section $cx, $count tags:\n";
        }

        my $known = 0;
        my $count_unknown = 0;
        foreach my $rec ( @{$records} ) {
            my $tag = q{};
            my $fmt = q{};
            my $noc = q{};
            my $val = q{};
            $known = 0;
            if ( exists $rec->{'tag_name'} && $rec->{'tag_name'} ) {
                $known = 1;
                $tag = $rec->{'tag_name'};
            }
            elsif ( exists $rec->{'tag'} ) {
                $count_unknown++;
                $tag = sprintf("0x%04X", $rec->{'tag'});
            }
            # else error?
            if ( exists $rec->{'fmt_name'} ) {
                $fmt = $rec->{'fmt_name'};
            }
            elsif ( exists $rec->{'fmt'} ) {
                $fmt = sprintf("0x%02X", $rec->{'fmt'});
            }
            # else error?
            if ( exists $rec->{'noc'} ) {
                $noc = $rec->{'noc'};
            }
            # else error?
            if ( exists $rec->{'val_exp'} && defined( $rec->{'val_exp'} ) ) {
                $val = $rec->{'val_exp'};
            }
            elsif ( exists $rec->{'val'} && defined( $rec->{'val'} ) ) {
                $val = sprintf("0x%08X", $rec->{'val'});
                $val .= qq{ $fmt};
                if ( 4 < $noc ) {
                    $val .= q{, address offset}
                }
            }
            # else error?
            if ( $known ) {
                if ( $all ) {
                    printf qq{%5d:% 30s: %-30s [%s]\n}, $noc, $tag, $val, $fmt;
                }
                else {
                    printf qq{%5d:% 30s: %s\n}, $noc, $tag, $val;
                }
            }
            elsif ( $all ) {
                print qq{$tag (size $noc): $val\n};
            }
        }
        if ( ! $all && $count_unknown ) {
            print qq{ ... and $count_unknown unknown.\n};
        }
    }
}


sub _strInBuff
{
    my ( $buff, $noc, $val ) = @_;
    my $str = q{};

    if ( 4 < $noc ) {
        for ( my $cx = $val; $cx<$val+$noc; $cx++ ) {
            my $ch = $buff->[$cx];
            if ( 0 == $ch ) {
                return $str;
            }
            my $cch = chr($ch);
            $str .= chr($ch);
        }
    }
    else {
        if ( 'I' eq _local_endian() ) {
            for ( my $cx = 0; $cx<$noc; $cx++ ) {
                my $mul = 0xFF;
                my $zro = ( 2 * $cx );
                my $shft = ( 8 * $cx );

                # $cx 0, mul is 0xFF
                # $cx 1, mul is 0xFF00
                # $cx 2, mul is 0xFF0000
                # $cx 3, mul is 0xFF000000

                if ( $zro ) {
                    my $hex = "FF";
                    $hex .= ( "0" x $zro );
                    # Assign new $mul
                    $mul = hex($hex);
                }

                my $mask = ( $val & $mul );
#                debug( sprintf( "VAL (%x)\n", $val ));
#                debug( sprintf( "MASK (%x)\n", $mask ));
                my $cch = ( $mask >>$shft );
                if ( 0 == $cch ) {
                    return $str;
                }
                $str .= chr( $cch );
            }
        }
        else {
            # 'M' style to string ... never been tested...
            for ( my $cx = 0; $cx<$noc; $cx++ ) {
                my $mul = 0xFF;
                my $reverse = ( $noc - $cx );
                my $zro = ( 2 * $reverse );
                my $shft = ( 8 * $reverse );

                # $reverse 3, mul is 0xFF000000
                # $reverse 2, mul is 0xFF0000
                # $reverse 1, mul is 0xFF00
                # $reverse 0, mul is 0xFF

                if ( $zro ) {
                    my $hex = "FF";
                    $hex .= ( "0" x $zro );
                    # Assign new $mul
                    $mul = hex($hex);
                }

                my $mask = ( $val & $mul );
                my $cch = ( $mask >>$shft );
                if ( 0 == $cch ) {
                    return $str;
                }
                $str .= chr( $cch );
            }
        }
    }

    return $str;
}


sub _hexDump
{
    my $buff = shift;
    my $offset = shift;
    my $noc = shift;

    my $max = scalar @{$buff};

    if ( $max < $offset ) {
        confess( "Request to _hexDump outside of loaded buffer ($max < $offset)." );
    }
    if ( $max < $offset+$noc ) {
        debug( "Request to _hexDump past loaded buffer ($max < $offset), showing what exists." );
        $noc = $max - $offset
    }

    my $border
 = q{+--------------------------------------------------+------------------+};
    my $formatter
 = q{| 00 01 02 03 04 05 06 07 08 09 0A 0B 0C 0D 0E 0F  | 0123456789ABCDEF |};
    my $str = q{};
    my $hex = q{};
    my $txt = q{};
    my $lines = 0;
    for ( my $cx = 0; $cx<$noc; $cx++ ) {
        if ( 0 == $cx ) {
            $str .= "$border\n";
            $str .= "$formatter\n";
            $str .= "$border\n";
        }
        elsif ( ( 0 != $cx ) && ( 0 == ( $cx % 16 ) ) ) {
            $lines++;
            $str .= sprintf( "|%48s  | %16s |\n", $hex, $txt );
            $hex = q{};
            $txt = q{};

            if ( 0 == ( $lines % 30 ) ) {
                $str .= "$border\n";
                $str .= "$formatter\n";
                $str .= "$border\n";
            }
        }
        my $newch = $buff->[$offset+$cx] || 0;
        $hex .= sprintf( " %02X", $newch );
        if ( 31 < $newch && 127 > $newch ) {
            $txt .= chr($newch);
        }
        else {
            $txt .= q{.};
        }
    }
    $str .= sprintf( "|%-48s  | %-16s |\n", $hex, $txt );
    $str .= "$border";
    return $str;
}


sub HexView {
    my $self = shift;
    my $data = shift;
    # If a filehandle  ref was an arg we convert
    # it to an array (in a rather ugly fashion)
     if (ref($data) eq 'GLOB') {
            @_ = <$data>;
            undef $data;    # clean the 'GLOB(0x123456)'
    }
    while (@_){$data .= shift}

    my ($hex, $char);
TT: foreach (split (//,$data)){
        $hex  .= sprintf('%02X ', ($_));
        if ( ($_) > 13 && ($_) < 126 ) {
             $char .= chr($_);
        }
        else {
             $char .= q{.};
        }
    }

    local $: = ''; # $FORMAT_LINE_BREAK_CHARACTERS (and we don't want that)
my $formathead =<<"HEAD";
format =
+--------------------------------------------------+------------------+
| 00 01 02 03 04 05 06 07 08 09 0A 0B 0C 0D 0E 0F  | 0123456789ABCDEF |
+--------------------------------------------------+------------------+
HEAD
my $formatline = <<'LINE';
| ^<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<< | ^<<<<<<<<<<<<<<< |
 $hex,                                             $char,
LINE
my $formatend = <<'END';
+--------------------------------------------------+------------------+
.
END
    eval($formathead . $formatline x (int(length($data)/16)+1) . $formatend);
    write;
    return 1;
}


sub elog
{
    my $level = shift;
    my @output = @_;
    my $logline = join(q{ }, @output);

    if ( $logline !~ m/\n$/ ) {
        $logline .= qq{\n};
    }

    if ( $VERBOSE ) {
        print {*STDERR} $logline;
    }
    elsif ( q{debug} eq $level ) {
        $DEBUG .= $logline;
    }
    elsif ( q{info} eq $level ) {
        $DEBUG .= $logline;
    }
    elsif ( q{warning} eq $level ) {
        $ERROR .= $logline;
    }
    elsif ( q{error} eq $level ) {
        $ERROR .= $logline;
    }
    if ( q{critical} eq $level ) {
        confess( $logline );
    }
}


sub debug
{
    elog('debug', @_);
}

sub info
{
    elog('info', @_);
}

sub warning
{
    elog('warning', @_);
}

sub error
{
    elog('error', @_);
}

sub critical
{
    my @output = @_;
    my $logline = join(q{ }, @output);

    if ( $logline !~ m/\n$/ ) {
        $logline .= qq{\n};
    }

    confess( $logline );
}



sub _local_endian
{
    my $is_big_endian = unpack("h*", pack("s", 1)) =~ /01/;
    if ( $is_big_endian ) {
        return 'M';
    }
    else {
        return 'I';
    }
}


sub _bytesToInt {
    my ( $buff, $endian, $offset, $length ) = @_;

    my $max = scalar @{$buff};

    if ( $offset > $max ) {
        critical(qq{_bytesToInt :: offset on buffer is too large ($offset).});
    }
    if ( $offset+$length > $max ) {
        critical(qq{_bytesToInt :: offset+length on buffer is too large ($offset+$length).});
    }

    my @bytes = @{$buff}[$offset .. $offset+$length-1];

    # Endian ... 'M' is Motorola.  Most significant bits first.
    # 'I' is Intel, least significant bits first.
    # This makes sure everything to 'I' style.
    if ( 'M' eq $endian ) {
        @bytes = reverse @bytes;
    }

    # Return variable (start with zero)
    my $ret = 0;

    # Going left to right, little endian significance.
    foreach my $cx ( 0 .. $length-1 ) {
        # $mul - multipy $bytes[$cx] by $mul
        my $mul = 0x1;
        # $zro - count of zeroes to add to 1 (to form new mul)
        my $zro = ( 2 * $cx );

        # $cx 0, mul is 0x1
        # $cx 1, mul is 0x100
        # $cx 2, mul is 0x10000
        # etc.

        if ( $zro ) {
            my $hex = "1";
            $hex .= ( "0" x $zro );
            # Assign new $mul
            $mul = hex($hex);
        }

        if ( $bytes[$cx] ) {
            $ret += ($bytes[$cx]) * $mul;
        }
    }

    return $ret;
}


sub _formatName {
    my $fmt = shift;

    if ( $fmt == 1 ) {
        return q{unsigned byte};
    }
    elsif ( $fmt == 2 ) {
        return q{ascii strings};
    }
    elsif ( $fmt == 3 ) {
        return q{unsigned short (2B)};
    }
    elsif ( $fmt == 4 ) {
        return q{unsigned long (4B)};
    }
    elsif ( $fmt == 5 ) {
        return q{unsigned rational (8B)};
    }
    elsif ( $fmt == 6 ) {
        return q{signed byte};
    }
    elsif ( $fmt == 7 ) {
        return q{undefined};
    }
    elsif ( $fmt == 8 ) {
        return q{signed short (2B)};
    }
    elsif ( $fmt == 9 ) {
        return q{signed long (4B)};
    }
    elsif ( $fmt == 10 ) {
        return q{signed rational (8B)};
    }
    elsif ( $fmt == 11 ) {
        return q{single float (4B unsupported)};
    }
    elsif ( $fmt == 12 ) {
        return q{double float (8B unsupported)};
    }
}


sub _expValueFromFormat {
    my ( $buff, $endian, $fmt, $noc, $val ) = @_;

    if ( $fmt == 1 ) {
        #return q{unsigned byte};
        return $val
    }
    elsif ( $fmt == 2 ) {
        #return q{ascii strings};
        return _strInBuff( $buff, $noc, $val );
    }
    elsif ( $fmt == 3 ) {
        #return q{unsigned short (2B)};
        return $val
    }
    elsif ( $fmt == 4 ) {
        #return q{unsigned long (4B)};
        return $val
    }
    elsif ( $fmt == 5 ) {
        #return q{unsigned rational (8B unsupported)};
        my $pri = _bytesToInt ( $buff, $endian, $val, 4 );
        my $den = _bytesToInt ( $buff, $endian, $val+4, 4 );
        my $ret = ( $pri / $den );
#        elog( 'debug', "Unsigned rational at ($val): $pri / $den = $ret" );
        return ($ret);
    }
    elsif ( $fmt == 6 ) {
        #return q{signed byte};
        if ( 0x7F > $val ) {
            return $val;
        }
        else {
            my $new = ( 0x7F & $val );
            return -1 * $new;
        }
    }
    elsif ( $fmt == 7 ) {
        # q{undefined};
        my $str = q{hex:};
        my $max = 30<$noc?30:$noc;
        if ( 4 >= $noc ) {
            return undef;
        }
        else {
            if ( $VERBOSE ) {
                $str .= qq{\n} . _hexDump($buff, $val, $noc );
            }
            else {
                for ( my $cx = 0; $cx<$max; $cx++ ) {
                    $str .= sprintf( " %02X", $buff->[$val+$cx] );
                }
                $str .= q{ ...};
            }
        }
        return $str;
    }
    elsif ( $fmt == 8 ) {
        #return q{signed short (2B)};
        if ( 0x7FFF > $val ) {
            return $val;
        }
        else {
            my $new = ( 0x7FFF & $val );
            return -1 * $new;
        }
    }
    elsif ( $fmt == 9 ) {
        #return q{signed long (4B)};
        if ( 0x7FFFFFFF > $val ) {
            return $val;
        }
        else {
            my $new = ( 0x7FFFFFFF & $val );
            return -1 * $new;
        }
    }
    elsif ( $fmt == 10 ) {
        #return q{signed rational (8B unsupported)};
        my $pri = _bytesToInt ( $buff, $endian, $val, 4 );
        my $den = _bytesToInt ( $buff, $endian, $val+4, 4 );
        if ( 0x7FFFFFFF > $pri ) {
            $pri = ( 0x7FFFFFFF & $pri );
            $pri = -1 * $pri;
        }
        my $ret = ( $pri / $den );
#        elog( 'debug', "Signed rational at ($val): $pri / $den = $ret" );
        return ($ret) || 0;
    }
    elsif ( $fmt == 11 ) {
        #return q{single float (4B unsupported)};
        # TODO figure this out
        return undef;
    }
    elsif ( $fmt == 12 ) {
        #return q{double float (8B unsupported)};
        # TODO figure this out
        return undef;
    }
}


sub _canonMakerNoteTagName
{
    my $ask = shift;

    my %tag = (
        # MakerNote (Canon)
        0x0001  =>  'CameraSettings',
        0x0002  =>  'FocalLength',
        0x0004  =>  'ShotInfo',
        0x0005  =>  'Panorama',
        0x0006  =>  'ImageType',
        0x0007  =>  'Firmware',
        0x0008  =>  'FileNumber',
        0x0009  =>  'OwnerName',
        0x000c  =>  'SerialNumber',
        0x000d  =>  'CameraInfo',
        0x000f  =>  'CustomFunctions',
        0x0010  =>  'ModelID',
        0x0012  =>  'PictureInfo',
        0x0013  =>  'ThumbnailImageValidArea',
        0x0015  =>  'SerialNumberFormat',
        0x001a  =>  'SuperMacro',
        0x0026  =>  'AFInfo',
        0x0083  =>  'OriginalDecisionDataOffset',
        0x00a4  =>  'WhiteBalanceTable',
        0x0095  =>  'LensModel',
        0x0096  =>  'InternalSerialNumber',
        0x0097  =>  'DustRemovalData',
        0x0099  =>  'CustomFunctions',
        0x00a0  =>  'ProcessingInfo',
        0x00aa  =>  'MeasuredColor',
        0x00b4  =>  'ColorSpace',
        0x00d0  =>  'VRDOffset',
        0x00e0  =>  'SensorInfo',
        0x4001  =>  'ColorData',
        # MakerNote (Olympus)
#        0x0200  =>  'MAKER_OLY_SpecialMode',
#        0x0201  =>  'MAKER_OLY_JpegQual',
#        0x0202  =>  'MAKER_OLY_Macro',
#        0x0204  =>  'MAKER_OLY_DigiZoom',
#        0x0207  =>  'MAKER_OLY_SoftwareRelease',
#        0x0208  =>  'MAKER_OLY_PictInfo',
#        0x0209  =>  'MAKER_OLY_CameraID',
#        0x0f00  =>  'MAKER_OLY_DataDump',
    );

    if ( defined $tag{$ask} ) {
        return $tag{$ask};
    }
    else {
        return undef;
    }
}


sub _gpsInfoTagName
{
    my $ask = shift;

    my %tag = (
        # GPS Tags
        0x0000  =>  'GPSVersionID',
        0x0001  =>  'GPSLatitudeRef',
        0x0002  =>  'GPSLatitude',
        0x0003  =>  'GPSLongitudeRef',
        0x0004  =>  'GPSLongitude',
        0x0005  =>  'GPSAltitudeRef',
        0x0006  =>  'GPSAltitude',
        0x0007  =>  'GPSTimeStamp',
        0x0008  =>  'GPSSatellites',
        0x0009  =>  'GPSStatus',
        0x000a  =>  'GPSMeasureMode',
        0x000b  =>  'GPSDegreeOfPrecision',
        0x000c  =>  'GPSSpeedRef',
        0x000d  =>  'GPSSpeed',
        0x000e  =>  'GPSTrackRef',
        0x000f  =>  'GPSTrack',
        0x0010  =>  'GPSImgDirectionRef',
        0x0011  =>  'GPSImgDirection',
        0x0012  =>  'GPSMapDatum',
        0x0013  =>  'GPSDestLatitudeRef',
        0x0014  =>  'GPSDestLatitude',
        0x0015  =>  'GPSDestLongitudeRef',
        0x0016  =>  'GPSDestLongitude',
        0x0017  =>  'GPSDestBearingRef',
        0x0018  =>  'GPSDestBearing',
        0x0019  =>  'GPSDestDistanceRef',
        0x001a  =>  'GPSDestDistance',
        0x001b  =>  'GPSProcessingMethod',
        0x001c  =>  'GPSAreaInformation',
        0x001d  =>  'GPSDateStamp',
        0x001e  =>  'GPSDifferential',
    );

    if ( defined $tag{$ask} ) {
        return $tag{$ask};
    }
    else {
        return undef;
    }
}


sub _exifTagName
{
    my $ask = shift;

    my %tag = (
        # Primary IFD0 Tags
        0x010e  =>  'Copyright',
        0x010f  =>  'Make',
        0x0110  =>  'Model',
        0x0112  =>  'Orientation',
        0x011a  =>  'X-Resolution',
        0x011b  =>  'Y-Resolution',
        0x0128  =>  'ResolutionUnit',
        0x0131  =>  'Software',
        0x0132  =>  'DateTime',
        0x013e  =>  'WhitePoint',
        0x013f  =>  'PrimaryChromaticities',
        0x0211  =>  'YCbCrCoefficients',
        0x0213  =>  'YCbCrPositioning',
        0x0214  =>  'ReferenceBlackWhite',
        0x8298  =>  'Copyright',
        0x8769  =>  'ExifOffset',
        # Exif SubIFD Tags
        0x829a  =>  'ExposureTime',
        0x829d  =>  'FNumber',
        0x8822  =>  'ExposureProgram',
        0x8827  =>  'ISOSpeedRatings',
        0x9000  =>  'ExifVersion',
        0x9003  =>  'DateTimeOriginal',
        0x9004  =>  'DateTimeDigitized',
        0x9101  =>  'ComponentConfiguration',
        0x9102  =>  'CompressedBitsPerPixel',
        0x9201  =>  'ShutterSpeedValue',
        0x9202  =>  'ApertureValue',
        0x9203  =>  'BrightnessValue',
        0x9204  =>  'ExposureBiasValue',
        0x9205  =>  'MaxApertureValue',
        0x9206  =>  'SubjectDistance',
        0x9207  =>  'MeteringMode',
        0x9208  =>  'LightSource',
        0x9209  =>  'Flash',
        0x920a  =>  'FocalLength',
        0x927c  =>  'MakerNote',
        0x9286  =>  'UserComment',
        0xa000  =>  'FlashPixVersion',
        0xa001  =>  'ColorSpace',
        0xa002  =>  'ExifImageWidth',
        0xa003  =>  'ExifImageHeight',
        0xa004  =>  'RelatedSoundFile',
        0xa005  =>  'ExifInteroperabilityOffset',
        0xa20e  =>  'FocalPlaneXResolution',
        0xa20f  =>  'FocalPlaneYResolution',
        0xa210  =>  'FocalPlaneResolutionUnit',
        0xa217  =>  'SensingMethod',
        0xa300  =>  'FileSource',
        0xa301  =>  'SceneType',
        0xa401  =>  'CustomRendered',
        0xa402  =>  'ExposureMode',
        0xa403  =>  'WhiteBalance',
        0xa404  =>  'DigitalZoomRatio',
        0xa405  =>  'FocalLenghtIn36mmFilm',
        0xa406  =>  'SceneCaptureType',
        0xa407  =>  'GainControl',
        0xa408  =>  'Contrast',
        0xa409  =>  'Saturation',
        0xa40a  =>  'Sharpness',
        0xa40b  =>  'DeviceSettingDescription',
        0xa40c  =>  'SubjectDistanceRange',
        0xa420  =>  'ImageUniqueID',
        # IFD1 (Thumbnail Image) Tags
        0x0100  =>  'IFD1_ImageWidth',
        0x0101  =>  'IFD1_ImageLength',
        0x0102  =>  'IFD1_BitsPerSample',
        0x0103  =>  'IFD1_Compression',
        0x0106  =>  'IFD1_PhotometricInterpretation',
        0x0111  =>  'IFD1_StripOffsets',
        0x0115  =>  'IFD1_SamplesPerPixel',
        0x0116  =>  'IFD1_RowsPerStrip',
        0x0117  =>  'IFD1_StripByteConunts',
#        0x011a  =>  'IFD1_XResolution',
#        0x011b  =>  'IFD1_YResolution',
#        0x0128  =>  'IFD1_ResolutionUnit',
        0x011c  =>  'IFD1_PlanarConfiguration',
        0x0201  =>  'IFD1_JpegIFOffset',
        0x0202  =>  'IFD1_JpegIFByteCount',
#        0x0211  =>  'IFD1_YCbCrCoefficients',
        0x0212  =>  'IFD1_YCbCrSubSampling',
#        0x0213  =>  'IFD1_YCbCrPositioning',
#        0x0214  =>  'IFD1_ReferenceBlackWhite',
        # Baseline TIFF Tags
        0x00fe  =>  'TIFF_NewSubfileType',
        0x00ff  =>  'TIFF_SubfileType',
#        0x0100  =>  'IFD1_ImageWidth',
#        0x0101  =>  'IFD1_ImageLength',
#        0x0102  =>  'IFD1_BitsPerSample',
#        0x0103  =>  'IFD1_Compression',
#        0x0106  =>  'IFD1_PhotometricInterpretation',
        0x0107  =>  'TIFF_Threshholding',
        0x0108  =>  'TIFF_CellWidth',
        0x0109  =>  'TIFF_CellLength',
        0x010a  =>  'TIFF_FillOrder',
#        0x010e  =>  'TIFF_ImageDescription', # Copyright
#        0x010f  =>  'Make',
#        0x0110  =>  'Model',
#        0x0111  =>  'IFD1_StripOffsets',
#        0x0112  =>  'Orientation',
#        0x0115  =>  'IFD1_SamplesPerPixel',
#        0x0116  =>  'IFD1_RowsPerStrip',
#        0x0117  =>  'IFD1_StripByteConunts',
        0x0118  =>  'TIFF_MinSampleValue',
        0x0119  =>  'TIFF_MaxSampleValue',
#        0x011a  =>  'X-Resolution',
#        0x011b  =>  'Y-Resolution',
#        0x011c  =>  'IFD1_PlanarConfiguration',
        0x0120  =>  'TIFF_FreeOffsets',
        0x0121  =>  'TIFF_FreeByteCounts',
        0x0122  =>  'TIFF_GrayResponseUnit',
        0x0123  =>  'TIFF_GrayResponseCurve',
#        0x0128  =>  'ResolutionUnit',
#        0x0131  =>  'Software',
#        0x0132  =>  'DateTime',
        0x013b  =>  'TIFF_Artist',
        0x013c  =>  'TIFF_HostComputer',
        0x0140  =>  'TIFF_ColorMap',
        0x0152  =>  'TIFF_ExtraSamples',
#        0x8298  =>  'Copyright',
        # Misc Tags
        0x012d  =>  'TransferFunction',
        0x013d  =>  'Predictor',
        0x0142  =>  'TileWidth',
        0x0143  =>  'TileLength',
        0x0144  =>  'TileOffsets',
        0x0145  =>  'TileByteCounts',
        0x014a  =>  'SubIFDs',
        0x015b  =>  'JPEGTables',
        0x828d  =>  'CFARepeatPatternDim',
        0x828e  =>  'CFAPattern',
        0x828f  =>  'BatteryLevel',
        0x83bb  =>  'IPTC/NAA',
        0x8773  =>  'InterColorProfile',
        0x8824  =>  'SpectralSensitivity',
        0x8825  =>  'GPSInfo',
        0x8828  =>  'OECF',
        0x8829  =>  'Interlace',
        0x882a  =>  'TimeZoneOffset',
        0x882b  =>  'SelfTimerMode',
        0x920b  =>  'FlashEnergy',
        0x920c  =>  'SpatialFrequencyResponse',
        0x920d  =>  'Noise',
        0x9211  =>  'ImageNumber',
        0x9212  =>  'SecurityClassification',
        0x9213  =>  'ImageHistory',
        0x9214  =>  'SubjectLocation',
        0x9215  =>  'ExposureIndex',
        0x9216  =>  'TIFF/EPStandardID',
        0x9290  =>  'SubSecTime',
        0x9291  =>  'SubSecTimeOriginal',
        0x9292  =>  'SubSecTimeDigitized',
        0xa20b  =>  'FlashEnergy.2',
        0xa20c  =>  'SpatialFrequencyResponse.2',
        0xa214  =>  'SubjectLocation.2',
        0xa215  =>  'ExposureIndex.2',
        0xa302  =>  'CFAPattern.2',
    );

    if ( defined $tag{$ask} ) {
        return $tag{$ask};
    }
    else {
        return undef;
    }
}

1;

