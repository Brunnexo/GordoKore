package TOTP;

use strict;

use lib $Plugins::current_plugin_folder;
use Digest::SHA qw(hmac_sha1);
use MIME::Base32;
use Math::BigInt;

BEGIN {
    eval {
        require FFI::Platypus;
        FFI::Platypus->import();
        1;
    } or do {
        print "[TOTP] FFI::Platypus não encontrado. Instalando...\n";
        system("cpanm FFI::Platypus") == 0 or
        system("cpan FFI::Platypus") == 0 or
        die "[TOTP] Falha ao instalar FFI::Platypus\n";

        require FFI::Platypus;
        FFI::Platypus->import();
        print "[TOTP] FFI::Platypus instalado!\n";
    };
}


use Cwd 'abs_path';

my $ffi = FFI::Platypus->new( api => 1 );
my $lib_path;
if ( $^O eq 'MSWin32' ) {
    $lib_path = abs_path("$Plugins::current_plugin_folder/lib.dll");
} else {
    $lib_path = abs_path("$Plugins::current_plugin_folder/lib.so");
}

die "[TOTP] Native library not found: $lib_path\n"
    unless defined $lib_path && -r $lib_path;

$ffi->lib($lib_path);
$ffi->attach(GenerateOtpHash => ['string'] => 'string');

sub new {
    my ($class, %opts) = @_;
    my $self = {
        digits   => $opts{digits}   || 6,
        timestep => $opts{timestep} || 30,
    };
    bless $self, $class;
    return $self;
}

sub _get_seed {
    my ($email) = @_;

    return undef unless defined $email;

    my $seed = GenerateOtpHash($email);

    die "[TOTP] GenerateOtpHash returned undef\n"
        unless defined $seed;

    return $seed;   # já é Base32 (16 chars)
}

sub _process {
    my ( $self, $secret, $bin_code ) = @_;

    my $hash   = hmac_sha1($bin_code, $secret);
    my $offset = ord(substr($hash, -1)) & 0xf;
    my $dt     = unpack "N", substr($hash, $offset, 4);
    $dt &= 0x7fffffff;
    $dt = Math::BigInt->new($dt);

    my $modulus = 10 ** $self->{digits};

    if ( $self->{digits} < 10 ) {
        return sprintf( "%0$self->{digits}d", $dt->bmod($modulus) );
    } else {
        return $dt->bmod($modulus);
    }
}

sub totp_seed {
    my ( $self, $seed, $manual_time ) = @_;

    $secret = decode_base32($seed);
    $secret = join( "", map { chr(hex($_)) } $secret =~ /(..)/g )
        if $secret =~ /^[a-fA-F0-9]{32,}$/;

    my $time = $manual_time || time();
    my $T = Math::BigInt->new( int( $time / $self->{timestep} ) );

    ( my $hex = $T->as_hex ) =~ s/^0x(.*)/"0"x(16 - length($1)) . $1/e;
    my $bin_code = join( "", map { chr( hex($_) ) } $hex =~ /(..)/g );

    return $self->_process( $secret, $bin_code );
}

sub totp_username {
    my ( $self, $username, $manual_time ) = @_;

    my $secret = _get_seed($username);

    $secret = decode_base32($secret);
    $secret = join( "", map { chr(hex($_)) } $secret =~ /(..)/g )
        if $secret =~ /^[a-fA-F0-9]{32,}$/;

    my $time = $manual_time || time();
    my $T = Math::BigInt->new( int( $time / $self->{timestep} ) );

    ( my $hex = $T->as_hex ) =~ s/^0x(.*)/"0"x(16 - length($1)) . $1/e;
    my $bin_code = join( "", map { chr( hex($_) ) } $hex =~ /(..)/g );

    return $self->_process( $secret, $bin_code );
}

1;