####
# Exif.pm
# Some comments are cut/paste from here:
#    https://www.media.mit.edu/pia/Research/deepview/exif.html
use warnings;
use strict;
package Exif;

use constant {
    JPEG0   => 0xFF,
    JPEG1   => 0xD8,
    JPEGZ   => 0xD9,
    APP1    => 0xE1,
};

our $ERROR = q{};
our $DEBUG = q{};


sub new
{
    my $class = shift;
    my $self = { };
    bless $self, ref($class) || $class || 'Exif';

    $self->{'m_endian'} = _local_endian();

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

    if ( 0 == scalar(@args) ) {
        return;
    }
    elsif ( 1 == scalar(@args) ) {
        # Deal with inbound hash
        if ( q{HASH} eq ref($args[0]) ) {
            $opts = $args[0];

            if ( exists $opts->{'buffer'} ) {
                $self->buffer($opts->{'buffer'});
            }
            elsif ( exists $opts->{'filename'} ) {
                $self->filename($opts->{'filename'});
            }
        }
        elsif ( q{ARRAY} eq ref($args[0]) ) {
            # De-reference inbound array ref
            return $self->init(@{$args[0]});
        }
        else {
            if ( -f $args[0] ) {
                $self->filename($args[0]);
            }
            elsif ( 30 < length($args[0]) ) {
                $self->buffer($args[0]);
            }
            else {
                return;
            }

            return;
        }

    }

    # Deal with inbound ARRAY
    for ( my $cx = 0; $cx < $#args; $cx++ ) {
        if ( q{buffer} eq $args[$cx] ) {
            $self->buffer($args[++$cx]);
        }
        elsif (q{filename} eq $args[$cx]) {
            $self->filename($args[++$cx]);
        }
        else {
            my $nm = ref($self) || $self || 'Exif';
            $nm .= '->init()';
            die "$nm: Invalid parameters.";
        }
    }

}


sub buffer
{
    my $self = shift;
    my $buffer = shift;
    my $name = ref($self) || $self || 'Exif';
    $name .= q{->buffer()};

    if ( ! defined($buffer) ) {
        die "$name: No buffer supplied.";
    }
    if ( 30 > length($buffer) ) {
        die "$name: Supplied buffer too small.";
    }

    $self->{'raw_buffer'} = $buffer;
    $self->read();
}


sub filename
{
    my $self = shift;
    my $fn = shift;
    my $name = ref($self) || $self || 'Exif';
    $name .= q{->filename()};

    if ( 0 == length($fn) ) {
        die "$name: called with no filename.\n";
        return;
    }
    if ( ! -f $fn ) {
        die "$name: file $fn not found.\n";
        return;
    }
    $self->{'opt'}->{'filename'} = $fn;

    my $fh = undef;
    open( $fh, '<', $fn ) || die "$name: Unable to open: $!";
    binmode $fh;

    my $tenK = q{};
    read( $fh, $tenK, 11000, 0 ) || die "$name: Unable to read: $!";
    close ( $fh );

    if ( length($tenK) ) {
        $self->buffer($tenK);
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
        die "$name: Nothing in buffer.";
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
        die "$name: No JPEG header in buffer.";
    }
}


sub jpegRead
{
    my $self = shift;
    my $buff = shift;

    my $name = ref($self) || $self || 'Exif';
    $name .= q{->jpegRead()};

    if ( ! defined ( $buff ) ) {
        die "$name: Nothing in buffer.";
    }
    if ( 'ARRAY' ne ref($buff) ) {
        die "$name: buffer is not an array.";
    }

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
            if ( JPEG1 == $byte ) {
                # better be cx 1
                if ( $cx != 1 ) {
                    die "ERROR JPEG start marker found at byte $cx.";
                }
            }
            elsif ( APP1 == $byte ) {
                # Start of Exif ... probably (or JFIF)
                $app1 = 1;

                # Remove everything before the start of the EXIF
                splice(@$buff, 0, $cx-1);

                $self->readExifEnvelope($buff);
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
        die "$name: Nothing in buffer.";
    }
    if ( 'ARRAY' ne ref($buff) ) {
        die "$name: buffer is not an array.";
    }

    my $endian = undef;

    $self->{'Exif_offset'} = [];
    $self->{'Exif_read'} = 0;

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
                die $err;
            }
            push @{$self->{'Exif_offset'}}, ( $offset );
            $cx += $offset;

            $self->{'Exif_endian'} = $endian;

            $cx--; # For incrementor
            next TP;
        } # If header does exist (starting at this else)
        else {
            # header does exist IFD comes after
            if ( ! exists( $self->{'Exif_IFD'} ) ) {
                $self->{'Exif_IFD'} = {};
                $self->{'Exif_IFD'}->{$self->{'Exif_read'}} = {
                        'comment' =>    'IFD0',
                    };
            }
            else {
                my $tmp = "IFD" . $self->{'Exif_read'};
                $self->{'Exif_IFD'}->{$self->{'Exif_read'}} = {
                        'comment' =>    $tmp,
                    };
            }

            if ( $cx == $self->{'Exif_offset'}->[$self->{'Exif_read'}] ) {

                $DEBUG .= sprintf(
                    qq{%s: IFD offset (%d) identified, reading\n},
                    $name,
                    $cx
                );

                $cx = $self->readIFD(
                    $buff,
                    $cx,
                    $self->{'Exif_IFD'}->{$self->{'Exif_read'}}
                );

                $self->{'Exif_read'}++;

                if ( defined( $cx ) ) {
                    push @{$self->{'Exif_offset'}}, ( $cx );
                }
                if ( defined( $self->{'Exif_offset'}->[$self->{'Exif_read'}] ) ) {
                    $cx = $self->{'Exif_offset'}->[$self->{'Exif_read'}];
                }
                else {
                    $cx = $#{$buff};
                    next TP;
                }
            }
            else {
                die "$name: Offset does not match position, $cx.";
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
        die "$name: Nothing in buffer.";
    }
    if ( 'ARRAY' ne ref($buff) ) {
        die "$name: buffer is not an array.";
    }

    if ( ! defined $ifd ) {
        $ifd = {};
    }
    elsif ( 'HASH' ne ref($ifd) ) {
        die "$name: ifd structure expected (3rd argument)";
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

    my $name = ref($self) || $self || 'Exif';
    $name .= q{->readIFDTag()};

    if ( q{HASH} ne ref($ifd) ) {
        die "$name: No IFD Capture Received.";
    }

    if ( ! defined ( $buff ) ) {
        die "$name: Nothing in buffer.";
    }
    if ( 'ARRAY' ne ref($buff) ) {
        die "$name: buffer is not an array.";
    }

    my $tag = $ifd->{'record'}->[$ifd_cx]->{'tag'};
    my $fmt = $ifd->{'record'}->[$ifd_cx]->{'fmt'};
    my $noc = $ifd->{'record'}->[$ifd_cx]->{'noc'};
    my $val = $ifd->{'record'}->[$ifd_cx]->{'val'};

    # Tag Name (DEFAULTs to the Hex of the Tag)
    $ifd->{'record'}->[$ifd_cx]->{'tag_name'} = _exifTagName($tag);

    # Format Name
    $ifd->{'record'}->[$ifd_cx]->{'fmt_name'} = _formatName($fmt);

    # Expanded Value (if supported)
    my $str = _expValueFromFormat($buff, $fmt, $noc, $val);
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
            $str = q{normal (upper left};
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
            $str = q{normal (mirrored};
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
        $DEBUG .= "Orientation: $str\n";
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
#        $DEBUG .= "Exif SubIFD: $val\n";
        push @{$self->{'Exif_offset'}}, ( $val );
    }
    elsif ( 0x8769 == $tag && 4 == $fmt && 1 == $noc ) {
        # q{Exif SubIFD};
#        $DEBUG .= "Exif SubIFD: $val\n";
        push @{$self->{'Exif_offset'}}, ( $val );
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
        $DEBUG .= sprintf( "0x9009: %s\n", $str);
        $ifd->{'record'}->[$ifd_cx]->{'val_exp'} = $str;
    }
    elsif ( 0x927c == $tag && 7 == $fmt ) {
        # q{MakerNote};
        $DEBUG .= sprintf( "MakerNote: Try to read as IFD:\n");
        push @{$self->{'Exif_offset'}}, ( $val );
    }
    elsif ( 0xa005 == $tag && 7 == $fmt ) {
        # q{ExifInteroperabilityOffset};
        $DEBUG .= sprintf( "ExifInteroperabilityOffset: Read as IFD:\n");
        push @{$self->{'Exif_offset'}}, ( $val );
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
    $name .= q{->dump()};

    if ( ! exists( $self->{'Exif_read'} ) || 0 == $self->{'Exif_read'} ) {
        die "$name: called before anything was read.";
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
    $name .= q{->dump()};

    if ( ! exists( $self->{'Exif_read'} ) || 0 == $self->{'Exif_read'} ) {
        die "$name: called before anything was read.";
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
    $name .= q{->dump()};

    if ( ! exists( $self->{'Exif_read'} ) || 0 == $self->{'Exif_read'} ) {
        die "$name: called before anything was read.";
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
    $name .= q{->dump()};

    if ( ! exists( $self->{'Exif_read'} ) || 0 == $self->{'Exif_read'} ) {
        die "$name: called before anything was read.";
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
    $name .= q{->dump()};

    if ( ! exists( $self->{'Exif_read'} ) || 0 == $self->{'Exif_read'} ) {
        die "$name: called before anything was read.";
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
        die "$name: called before anything was read.";
    }
    else {
        $ifd_cx = $self->{'Exif_read'};
    }

    if ( ! defined( $ifd_cx ) || 0 == $ifd_cx ) {
        print "No IFD Sections Found.\n";
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
            die "$name: Option passed as " . ref($opt) || 'string' . ".";
        }
    }
    else {
        print qq{No option at all\n};
    }

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
            die "$name: Exif $cx not found.";
        }

        my $count = $Exif->{'count'};
        my $records = $Exif->{'record'};

        # records MUST be defined properly... die
        if ( !defined $records ) {
            die "$name: Tags not found.";
        }
        elsif ( q{ARRAY} ne ref $records ) {
            die "$name: Tags not formatted correctly (expecting array).";
        }

        if ( $count != scalar( @$records ) ) {
            my $tmp = scalar( @$records );
            die "$name: Tag array count incorrect (got $tmp expecting $count).";
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
            if ( exists $rec->{'val_exp'} && $rec->{'val_exp'} ) {
                $val = $rec->{'val_exp'};
            }
            elsif ( exists $rec->{'val'} && $rec->{'val'} ) {
                $val = sprintf("0x%08X", $rec->{'val'});
                if ( 4 < $noc ) {
                    $val .= q{ address offset}
                }
            }
            # else error?
            if ( $known ) {
                printf qq{% 30s: %s\n}, $tag, $val;
            }
            elsif ( $all ) {
                print qq{$tag ($fmt, count $noc): $val\n};
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
#                $DEBUG .= sprintf "VAL (%x)\n", $val;
#                $DEBUG .= sprintf "MASK (%x)\n", $mask;
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

        $ret += ($bytes[$cx]) * $mul;
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
        return q{unsigned rational (8B unsupported)};
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
        return q{signed rational (8B unsupported)};
    }
    elsif ( $fmt == 11 ) {
        return q{single float (4B unsupported)};
    }
    elsif ( $fmt == 12 ) {
        return q{double float (8B unsupported)};
    }
}


sub _expValueFromFormat {
    my ( $buff, $fmt, $noc, $val ) = @_;


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
        # TODO figure this out
        return undef;
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
        #return q{undefined};
        # TODO DECIDE HOW TO SHOW THIS
        return undef;
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
        # TODO figure this out
        return undef;
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
        0x011c  =>  'IFD1_PlanarConfiguration',
#        0x0128  =>  'IFD1_ResolutionUnit',
        0x011c  =>  'IFD1_PlanarConfiguration',
        0x0201  =>  'IFD1_JpegIFOffset',
        0x0202  =>  'IFD1_JpegIFByteCount',
#        0x0211  =>  'IFD1_YCbCrCoefficients',
        0x0212  =>  'IFD1_YCbCrSubSampling',
#        0x0213  =>  'IFD1_YCbCrPositioning',
#        0x0214  =>  'IFD1_ReferenceBlackWhite',
        # Misc Tags
        0x00fe  =>  'NewSubfileType',
        0x00ff  =>  'SubfileType',
        0x012d  =>  'TransferFunction',
        0x013b  =>  'Artist',
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
        # MakerNote (Canon)
        0x0006  =>  'MAKER_CNN_ImageType',
        0x0007  =>  'MAKER_CNN_Firmware',
        # MakerNote (Olympus)
        0x0200  =>  'MAKER_OLY_SpecialMode',
        0x0201  =>  'MAKER_OLY_JpegQual',
        0x0202  =>  'MAKER_OLY_Macro',
        0x0204  =>  'MAKER_OLY_DigiZoom',
        0x0207  =>  'MAKER_OLY_SoftwareRelease',
        0x0208  =>  'MAKER_OLY_PictInfo',
        0x0209  =>  'MAKER_OLY_CameraID',
        0x0f00  =>  'MAKER_OLY_DataDump',
    );

    if ( defined $tag{$ask} ) {
        return $tag{$ask};
    }
    else {
        return undef;
    }
}

1;

