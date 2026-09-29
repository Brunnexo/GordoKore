# GordoKore
#
# Ponto unico de comunicacao entre a DLL do Kore-Bridge e o OpenKore.
#
# Lista de venda: espelha a "Lista de venda" do Kore-Bridge (janela no cliente) com os itens a
# venda do items_control.txt (coluna auto-sell = 1).
#
# A DLL manda frames 'C' (hook 'Network::clientSend/observed'):
#   "GKSQ"                 pede a lista atual
#   "GKSL" + uint32 LE...  lista inteira desejada (botao "Salvar venda")
# e recebe de volta um frame 'X' "GKSL" + uint32 LE com os IDs a venda.
#
# Salvar marca os IDs da lista pra vender e desmarca os que sairam dela, via
# comando iconf (plugin xConf); as outras colunas da linha sao mantidas.
#
# NPC de venda:
#   "GKNP"                 (DLL) o proximo NPC clicado no cliente vira o NPC de venda
#   "GKNS" + "mapa x y"    (resposta 'X') sellAuto_npc atual, tambem enviado junto com a lista
# O NPC e' pego na resposta do servidor ao clique (loja: npc_store_begin; dialogo:
# npc_talk / npc_talk_responses). sellAuto_npc = posicao do NPC e sellAuto_standpoint =
# posicao do personagem nesse momento (ele ja andou ate o NPC pra falar).
# Depois fecha o que o clique abriu: dialogo com 0x0146 (a DLL fecha as janelas 16/17 e
# repassa ao servidor) e loja com 0x09D4 (a DLL fecha 25/50 e segura o pacote).
#
# Navegacao: "GKNV" + "mapa [x y]" (DLL) = /navi digitado no chat do cliente; o personagem
# anda ate la com o AI em manual (ai manual + move).

package GordoKore;

use strict;
use Plugins;
use Commands;
use Globals qw(%items_control %items_lut %config $net $npcsList $field $char $messageSender %talk %ai_v);
use Log qw(message error warning);
use Misc qw(configModify);

use constant QUERY      => 'GKSQ';
use constant LIST       => 'GKSL';
use constant PICK_NPC   => 'GKNP';
use constant NPC        => 'GKNS';
use constant NAVI       => 'GKNV';
use constant PICK_TIMEOUT => 120; # segundos esperando o clique

Plugins::register('GordoKore', 'Kore-Bridge: toda a comunicacao da DLL com o OpenKore', \&Unload, \&Unload);

my $picking_since; # time() do "Selecionar NPC"; undef = fora do modo

my $hooks = Plugins::addHooks(
	['Network::clientSend/observed', \&onClientSendObserved, undef],
	['packet/npc_store_begin',       \&onNpcContact, undef],
	['packet/npc_talk',              \&onNpcContact, undef],
	['packet/npc_talk_responses',    \&onNpcContact, undef],
);

message "[GordoKore] Plugin loaded!\n", 'success';

sub Unload {
	Plugins::delHooks($hooks);
}

# { id => chave no items_control } dos itens com auto-sell = 1
sub itemsForSale {
	my %id_of_name;
	while (my ($id, $name) = each %items_lut) {
		$id_of_name{lc $name} //= $id;
	}

	my %sale;
	while (my ($key, $control) = each %items_control) {
		next if $key eq 'all' || !$control->{sell};
		my $id = $key =~ /^\d+$/ ? $key : $id_of_name{$key};
		$sale{$id} //= $key if defined $id;
	}
	return \%sale;
}

sub sendList {
	return unless $net && $net->can('clientAlive') && $net->clientAlive;
	my @ids = sort { $a <=> $b } keys %{itemsForSale()};
	my $payload = LIST . pack('V*', @ids);
	$net->{client}->send('X' . pack('v', length $payload) . $payload);
}

sub applyList {
	my @ids = @_;
	unless (Plugins::registered('xConf')) {
		error "[GordoKore] plugin xConf nao carregado (loadPlugins_list); lista de venda ignorada\n";
		return;
	}

	my %wanted = map { $_ => 1 } @ids;
	my $sale = itemsForSale();

	# Sairam da lista: desmarca a venda, mantendo as outras colunas
	foreach my $id (grep { !$wanted{$_} } keys %$sale) {
		my $control = $items_control{$sale->{$id}};
		Commands::run(join ' ', 'iconf', $id, map { $_ // 0 } @{$control}{qw(keep storage)}, 0, @{$control}{qw(cart_add cart_get)});
	}

	# Entraram: marca pra vender (mantem o resto se ja existia linha)
	foreach my $id (grep { !$sale->{$_} } @ids) {
		my $control = $items_control{$id} || {};
		Commands::run(join ' ', 'iconf', $id, map { $_ // 0 } @{$control}{qw(keep storage)}, 1, map { $_ // 0 } @{$control}{qw(cart_add cart_get)});
	}

	message "[GordoKore] " . scalar(@ids) . " item(s) a venda\n", 'success';
}

sub sendNpc {
	return unless $net && $net->can('clientAlive') && $net->clientAlive;
	my $payload = NPC . ($config{sellAuto_npc} // '');
	$net->{client}->send('X' . pack('v', length $payload) . $payload);
}

sub onNpcContact {
	my ($hook, $args) = @_;
	return unless defined $picking_since;
	if (time - $picking_since > PICK_TIMEOUT) {
		undef $picking_since;
		return;
	}

	undef $picking_since;
	my $ID = $args->{ID} // substr($args->{RAW_MSG} // '', 4, 4);
	setSellNpc($ID);

	# Fecha o que o clique abriu (a DLL fecha as janelas ao ver o pacote)
	if ($hook eq 'packet/npc_store_begin') {
		$messageSender->sendSellBuyComplete;
		# O npc_store_begin preencheu o %talk; sem limpar, o proximo TalkNPC (autosell) acha
		# que ainda esta conversando com outro NPC ("Talking to wrong npc.")
		undef %talk;
		delete $ai_v{'npc_talk'};
	} else {
		$messageSender->sendTalkCancel($ID);
	}
}

sub setSellNpc {
	my ($ID) = @_;
	my $npc = $npcsList ? $npcsList->getByID($ID) : undef;
	unless ($npc && $field && $char) {
		warning "[GordoKore] NPC clicado nao encontrado na lista de NPCs do OpenKore\n";
		sendNpc(); # a janela volta a mostrar o NPC atual
		return;
	}

	my $map = $field->baseName;
	my $pos = $npc->{pos_to} || $npc->{pos};
	my $stand = $char->{pos_to} || $char->{pos};
	configModify('sellAuto_npc', "$map $pos->{x} $pos->{y}");
	configModify('sellAuto_standpoint', "$map $stand->{x} $stand->{y}");
	message "[GordoKore] NPC de venda: " . $npc->name . " ($map $pos->{x} $pos->{y})\n", 'success';
	sendNpc();
}

sub onClientSendObserved {
	my (undef, $args) = @_;
	my $msg = $args->{msg};
	return unless defined $msg && length($msg) >= 4;

	my $tag = substr($msg, 0, 4);
	if ($tag eq QUERY) {
		sendList();
		sendNpc();
	} elsif ($tag eq LIST) {
		applyList(unpack('V*', substr($msg, 4)));
		sendList();
	} elsif ($tag eq NAVI) {
		my ($map, $x, $y) = split ' ', substr($msg, 4);
		return unless defined $map && $map =~ /^[\w@.-]+$/; # vira comando do console: so nome de mapa
		my $target = (defined $y && $x =~ /^\d+$/ && $y =~ /^\d+$/) ? "$map $x $y" : $map;
		message "[GordoKore] /navi: $target\n", 'info';
		Commands::run('ai manual');
		Commands::run("move $target");
	} elsif ($tag eq PICK_NPC) {
		$picking_since = time;
		message "[GordoKore] Clique no NPC de venda no cliente\n", 'info';
	}
}

1;
