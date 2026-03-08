package LatamChecksum;

use strict;
use Plugins;
use Globals;
use Misc;
use AI;
use utf8;
use Network::Send ();
use Log           qw(message warning error debug);
use IO::Socket::INET;
use Time::HiRes qw(usleep);

my $counter = 0;
my $enabled = 0;
my $current_seed = 0;  # Para armazenar a seed atual

# TCP checksum server configuration
my $TIMEOUT = 1000;

Plugins::register( "LatamChecksum", "Latam checksum for xKore 3", \&unload );

my $hooks = Plugins::addHooks(
	['start3',                \&checkServer, undef],
);
my $base_hooks;

sub checkServer {
	my $master = $masterServers{ $config{master} };
	if ( grep { $master->{serverType} eq $_ } qw(ROla) ) {
		$base_hooks = Plugins::addHooks(
			[ 'serverDisconnect/fail',    \&serverDisconnect, undef ],
			[ 'serverDisconnect/success', \&serverDisconnect, undef ],
			[ 'Network::serverSend/pre',  \&serverSendPre,    undef ],
			[ 'Network::clientSend',      \&clientSend,       undef ]  # Hook para xKore 3
		);
	}
}

sub unload {
	Plugins::delHooks( $base_hooks );
	Plugins::delHooks( $hooks ) if ( $hooks );
}

sub calc_checksum {
	my ( $data ) = @_;
	
	my $addr = $config{checksum_ip} || 'localhost';
	my $port = $config{checksum_port} || 2349;

	# Create socket connection
	my $socket = IO::Socket::INET->new(
		PeerHost => $addr,
		PeerPort => $port,
		Proto    => 'tcp',
		Timeout  => $TIMEOUT
	);
	
	unless ($socket) {
		error "LatamChecksum: Failed to connect to checksum server at $addr:$port!\n";
		return 0; # Return 0 as fallback checksum
	}

	# Send data to server with current counter value
	my $packet = $data . pack("N", $counter); # Send data + counter in network byte order
	
	unless (print $socket $packet) {
		error "LatamChecksum: Failed to send data to checksum server at $addr:$port - $!\n";
		$socket->close();
		return 0;
	}
	
	# Read checksum response - agora estrutura completa
	my $response;
	my $bytes_read = sysread($socket, $response, 17); # 1 + 8 + 4 + 4 = 17 bytes
	$socket->close();
	
	unless (defined $bytes_read && $bytes_read == 17) {
		error "LatamChecksum: Failed to read complete response from server at $addr:$port\n";
		return 0;
	}
	
	# Desempacota: 1 byte checksum + 8 bytes seed + 4 bytes counter
	my ($checksum, $seed_low, $seed_high, $server_counter) = unpack("C Q L", $response);
	
	# Atualiza seed atual
	$current_seed = ($seed_high << 32) | $seed_low;
	
	debug "LatamChecksum: Counter=$counter, Checksum=$checksum, Seed=$current_seed\n" if $config{debug_checksum};
	
	return $checksum;
}

sub serverDisconnect {
	warning "Checksum disabled on server disconnect.\n";
	$enabled = 0;
	$counter = 0;
	$current_seed = 0;  # Reset da seed
}

# Hook para pacotes enviados ao servidor (xKore normal)
sub serverSendPre {
	my ( $self, $args ) = @_;
	my $msg       = $args->{msg};
	my $messageID = uc( unpack( "H2", substr( $$msg, 1, 1 ) ) ) . uc( unpack( "H2", substr( $$msg, 0, 1 ) ) );

	# Skip se estiver usando xKore 3
	if ( ref($::net) eq 'Network::XKore2' || ref($::net) eq 'Network::XKore3' ) {
		return;
	}

	processPacket($msg, $messageID);
}

# Hook para pacotes enviados pelo cliente (xKore 3)
sub clientSend {
	my ( $self, $args ) = @_;
	my $msg = $args->{msg};
	my $messageID = uc( unpack( "H2", substr( $$msg, 1, 1 ) ) ) . uc( unpack( "H2", substr( $$msg, 0, 1 ) ) );

	# Apenas processa se estiver usando xKore 3
	if ( ref($::net) eq 'Network::XKore3' ) {
		processPacket($msg, $messageID);
	}
}

sub processPacket {
	my ($msg, $messageID) = @_;

	if ( $counter == 0 ) {
		# Primeiro pacote após login no mapa ou primeiro pacote específico
		if ( $messageID eq '0B1C' ) {
			warning "Checksum enabled on first packet (0B1C).\n";
			$enabled = 1;
		}

		if ( $messageID eq $messageSender->{packet_lut}{map_login} ) {
			warning "Checksum enabled on map login.\n";
			$enabled = 1;
			$messageSender->sendPing() if $messageSender;
		}
	}

	# Adiciona checksum apenas se estiver conectado e enabled
	if ( $::net && $::net->getState() >= 4 && $enabled ) {
		my $checksum = calc_checksum( $$msg );
		$$msg .= pack( "C", $checksum );
		debug "LatamChecksum: Added checksum $checksum to packet $messageID\n" if $config{debug_checksum};
	}

    $counter = ($counter + 1) & 0xFFF;
}




1;