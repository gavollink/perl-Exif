use strict;
use Exif;

use Data::Dumper;

MAIN: {
    my $res = Exif->new({ filename => 't/Kawehi.JPG' });
    $res->read();
    print {*STDERR} qq{DEBUG:\n};
    print {*STDERR} $Exif::DEBUG . qq{\n};
    print {*STDERR} qq{ERRORS:\n};
    print {*STDERR} $Exif::ERROR . qq{\n};

    print {*STDERR} qq{Exif_IFD:\n};
    print {*STDERR} Dumper($res->{'Exif_IFD'});
}
