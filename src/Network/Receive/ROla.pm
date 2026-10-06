package Network::Receive::ROla;

use strict;
use base qw(Network::Receive::ServerType0);
use Globals qw($char $messageSender);
use I18N qw(bytesToString);
use Log qw(debug message);
use Translation qw(T TF);
use AI;
use Plugins;

sub new {
	my ( $class ) = @_;
	my $self = $class->SUPER::new( @_ );

	my %packets = (
		'0097' => [ 'private_message',      'v Z24 V Z*',                                                  [qw(len privMsgUser flag privMsg)] ],                                                                                                                                                                                                                               # -1
		'009D' => [ 'item_exists',          'a4 V C v3 C2',                                                [qw(ID nameID identified x y amount subx suby)] ],
		'009E' => [ 'item_appeared',        'a4 v2 C v2 C2 v',                                             [qw(ID nameID type identified x y subx suby amount)] ],
		'01C8' => [ 'item_used',            'a2 V a4 v C',                                                 [qw(ID itemID actorID remaining success)] ],
		'07FD' => [ 'special_item_obtain',  'v C V c/Z a*',                                                [qw(len type nameID holder etc)] ],                                                                                                                                                                                                                                 # record "c/Z" (holder) means: if the first byte ('c') = 24(dec), then Z24, if 'c' = 18(dec), then Z18, еtc.
		'09FD' => [ 'actor_moved',          'v C a4 a4 v3 V v2 V2 v V v6 a4 a2 v V C2 a6 C2 v2 V2 C v Z*', [qw(len object_type ID charID walk_speed opt1 opt2 option type hair_style weapon shield lowhead tick tophead midhead hair_color clothes_color head_dir costume guildID emblemID manner opt3 stance sex coords xSize ySize lv font maxHP HP isBoss opt4 name)] ],
		'09FE' => [ 'actor_connected',      'v C a4 a4 v3 V v2 V2 v7 a4 a2 v V C2 a3 C2 v2 V2 C v Z*',     [qw(len object_type ID charID walk_speed opt1 opt2 option type hair_style weapon shield lowhead tophead midhead hair_color clothes_color head_dir costume guildID emblemID manner opt3 stance sex coords xSize ySize lv font maxHP HP isBoss opt4 name)] ],
		'09FF' => [ 'actor_exists',         'v C a4 a4 v3 V v2 V2 v7 a4 a2 v V C2 a3 C3 v2 V2 C v Z*',     [qw(len object_type ID charID walk_speed opt1 opt2 option type hair_style weapon shield lowhead tophead midhead hair_color clothes_color head_dir costume guildID emblemID manner opt3 stance sex coords xSize ySize state lv font maxHP HP isBoss opt4 name)] ],
		'0A09' => [ 'deal_add_other',       'V C V C3 a16 a25',                                            [qw(nameID type amount identified broken upgrade cards options)] ],
		'0A0A' => [ 'storage_item_added',   'a2 V V C4 a16 a25',                                           [qw(ID amount nameID type identified broken upgrade cards options)] ],
		'0A0B' => [ 'cart_item_added',      'a2 V V C4 a16 a25',                                           [qw(ID amount nameID type identified broken upgrade cards options)] ],
		'0A37' => [ 'inventory_item_added', 'a2 v V C3 a16 V C2 a4 v a25 C v',                             [qw(ID amount nameID identified broken upgrade cards type_equip type fail expire unknown options favorite viewID)] ],
		'0ADD' => [ 'item_appeared',        'a4 V v C v2 C2 v C v',                                        [qw(ID nameID type identified x y subx suby amount show_effect effect_type)] ],
		'0B40' => [ 'vending_start',        'v a4 a*',                                                     [qw(len accountID itemList)] ],  # -1: lista da propria loja (itens de 58 bytes)
		'0B94' => [ 'rodex_accept_all_result', 'V3',                                                   [qw(unknown1 unknown2 accept)] ],                                                                                                                                                                                                                                  # 14
		'0B95' => [ 'rodex_settings',       'v a*',                                                        [qw(len settings)] ],  # -1: pares V2 (chave 1 = aceita correio de qualquer um); so o cliente usa
		'0BC9' => [ 'config_info_all',      'C4 V',                                                        [qw(open_equip call_deny pet_autofeed homun_autofeed costume)] ],  # 10: configuracoes ao entrar no mapa; so o cliente usa
		'0C32' => [ 'account_server_info',  'v a4 a4 a4 a4 a26 C x17 a*',                                  [qw(len sessionID accountID sessionID2 lastLoginIP lastLoginTime accountSex serverInfo)] ],
	);

	$self->{packet_list}{$_} = $packets{$_} for keys %packets;

	my %handlers = qw(
		received_characters 099D
		received_characters_info 082D
		sync_received_characters 09A0
		account_server_info 0C32
	);

	$self->{packet_lut}{$_} = $handlers{$_} for keys %handlers;

	$self->{buying_store_items_list_pack} = "V v C V";
	$self->{makable_item_list_pack}       = "V4";
	$self->{npc_market_info_pack}         = "V C V2 v";
	$self->{npc_store_info_pack}          = "V V C V";
	$self->{vender_items_list_item_pack}  = 'V v2 C V C3 a16 a25 V v C'; # trailing C = enchant grade
	$self->{vender_items_list_item_pack_self} = 'V v2 C V C2 @56 C @15 a16 a25 @57 C'; # 0B40 (sub_5C3EF0): refino em +56, depois das opcoes; os @ poem os campos na ordem do vending_start
	$self->{rodex_read_mail_item_pack}    = 'v V C3 a16 a4 C a4 a25';

	return $self;
}

# 0B94
sub rodex_accept_all_result {
	my ($self, $args) = @_;
	message $args->{accept} ? T("All rodex mails accepted.\n") : T("All rodex mails rejected.\n"), "info";
}

# 0B95: configuracoes do RODEX ao entrar no mapa (o cliente marca a janela do correio); so mostra
sub rodex_settings {
	my ($self, $args) = @_;
	my @pairs = unpack '(V2)*', $args->{settings};
	while (my ($key, $value) = splice @pairs, 0, 2) {
		if ($key == 1) {
			message $value ? T("Rodex: mail from any player is allowed.\n") : T("Rodex: mail from unknown players is blocked.\n"), "info";
		} else {
			message TF("Rodex: unknown setting %d = %d\n", $key, $value), "info";
		}
	}
}

# 0BC9: equipamento publico, chamada por habilidade, alimentacao de mascote/homunculo, trajes (sub_5B94C0); so mostra
sub config_info_all {
	my ($self, $args) = @_;
	message TF("Settings: %s, %s, %s, %s, costume option %d.\n",
		$args->{open_equip} ? T("equipment shown to others") : T("equipment hidden from others"),
		$args->{call_deny} ? T("skill summons blocked") : T("skill summons allowed"),
		$args->{pet_autofeed} == 1 ? T("pet autofeed on") : T("pet autofeed off"),
		$args->{homun_autofeed} == 1 ? T("homunculus autofeed on") : T("homunculus autofeed off"),
		$args->{costume}), "info";
}

sub guild_name {
	my ($self, $args) = @_;

	my $guildID = $args->{guildID};
	my $emblemID = $args->{emblemID};
	my $mode = $args->{mode};
	my $guildName = bytesToString($args->{guildName});
	$char->{guild}{name} = $guildName;
	$char->{guildID} = $guildID;
	$char->{guild}{emblem} = $emblemID;

	debug "guild name: $guildName\n";

	# Skip in XKore mode 1 / 3
	return if $self->{net}->version == 1;

	# emulate client behavior
	$messageSender->sendGuildRequestInfo(3);
	$messageSender->sendGuildRequestInfo(1);		# Requests for Members list, list job title

}

# ROla's private server repurposes 'fail' code 12 on the classic buy_result (00CA)
# to report a successful Barter Market exchange (items/currency were confirmed to
# actually transfer when this code was observed). Everything else falls back to the
# stock behavior.
sub buy_result {
	my ($self, $args) = @_;

	if ($args->{fail} == 12) {
		message T("Barter Market exchange completed.\n"), "success";
		if (AI::is("buyAuto")) {
			AI::args()->{recv_buy_packet} = 1;
		}
		Plugins::callHook('buy_result', {fail => $args->{fail}});
		return;
	}

	return $self->SUPER::buy_result($args);
}

1;
