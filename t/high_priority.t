use strict;
use Exif;

use Data::Dumper;

MAIN: {
    my $res = Exif->new({ filename => 't/Kawehi.JPG' });
    #my $res = Exif->new({ filename => 't/CaryElwes.JPG' });
    $res->read();

    print "Orientation: " . $res->orientation() . qq{\n};
    print "Copyright: " . $res->copyright() . qq{\n};
    print "Make: " . $res->make() . qq{\n};
    print "Model: " . $res->model() . qq{\n};
    print "Date Taken: " . $res->datetime() . qq{\n};
}

