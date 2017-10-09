use Exif;

MAIN: {
    my $var = 0x3f828f5c;
    my $val = {};
    my $tt = {};

    printf( "_float4byte: 0x%08X\n\n", $var);

    $tt = Exif::_float4byte($var, $val);

    printf( "     Sign: %d\n", $val->{'sign'} );
    printf( " Exponent: %d\n", $val->{'exponent'} );
    printf( " Mantissa: %ld / %ld\n", $val->{'numerator'},
                                      $val->{'denominator'} );
    printf( "         ( %.30f )\n", $val->{'mantissa'} );
    printf( "   Number: %.30f\n", $val->{'num'} );
    printf( "   Normal: %s\n", $val->{'out'} );

    print( "\n\n");


    $var = 0x3FF051EB851EB852;
    printf( "_float8byte: 0x%016X\n\n", $var);

    $tt = Exif::_float8byte($var, $val);

    printf( "     Sign: %d\n", $val->{'sign'} );
    printf( " Exponent: %d\n", $val->{'exponent'} );
    printf( " Mantissa: %ld / %ld\n", $val->{'numerator'},
                                      $val->{'denominator'} );
    printf( "         ( %.30f )\n", $val->{'mantissa'} );
    printf( "   Number: %.30f\n", $val->{'num'} );
    printf( "   Normal: %s\n", $val->{'out'} );
    print( "\n");
}
