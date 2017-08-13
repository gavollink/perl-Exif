use strict;
use Exif;

use Data::Dumper;

MAIN: {
    my $res = Exif->new({ filename => 't/CaryElwes.JPG' });
    $res->read();
    $res->dumpAll();
}

