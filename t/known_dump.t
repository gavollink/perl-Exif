use strict;
use Exif;

use Data::Dumper;

MAIN: {
    my $res = Exif->new({ filename => 't/Kawehi.JPG' });
    $res->read();
    $res->dump();
}

