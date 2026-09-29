# GordoKore
#
# Ponto unico de comunicacao entre a DLL do Kore-Bridge e o OpenKore.
#
# Lista de venda (janela no cliente) = editor do items_control.txt e da coleta do pickupitems.txt.
#
# A DLL manda frames 'C' (hook 'Network::clientSend/observed'):
#   "GKSQ"                 pede os itens
#   "GKIC" + registros     lista inteira desejada (botao "Salvar")
# e recebe de volta um frame 'X' "GKIC" + registros com os itens do items_control.txt.
# Registro (10 bytes, LE): uint32 ID, int32 minimo, uint8 flags (bit 0 guardar, 1 vender,
# 2 por no carrinho, 3 pegar do carrinho), int8 coleta (-1..2 ou 127 = sem linha no pickupitems).
#
# Salvar reescreve os dois arquivos de uma vez (guarda um .bak antes):
#   items_control.txt: atualiza as linhas dos itens da lista (mantendo o nome/ID e o comentario
#   da linha), tira as dos itens que sairam dela e acrescenta os novos ("ID ... #Nome").
#   A linha "all", comentarios e linhas cujo item nao se acha na tabela ficam como estao.
#   pickupitems.txt: so mexe nos itens da lista (127 tira a linha); o resto fica.
# Linhas por nome, por ID ou "Nome#ID#" valem igual (o items_control.txt aceita os tres).
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
use File::Copy qw(copy);
use Plugins;
use Commands;
use Settings;
use Globals qw(%items_lut %itemSlotCount_lut %pickupitems %config $net $npcsList $field $char $messageSender %talk %ai_v);
use Log qw(message error warning);
use Misc qw(configModify parseReload);

use constant QUERY      => 'GKSQ';
use constant ITEMS      => 'GKIC';
use constant PICK_NPC   => 'GKNP';
use constant NPC        => 'GKNS';
use constant NAVI       => 'GKNV';
use constant PICK_TIMEOUT => 120; # segundos esperando o clique
use constant NO_PICKUP  => 127;   # sem linha no pickupitems.txt
use constant RECORD     => 'V l C c';
use constant RECORD_SIZE => 10;

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

sub clientAlive {
	return $net && $net->can('clientAlive') && $net->clientAlive;
}

sub sendToClient {
	my ($payload) = @_;
	$net->{client}->send('X' . pack('v', length $payload) . $payload) if clientAlive();
}

# ---------------------------------------------------------------------------
# items_control.txt / pickupitems.txt
# ---------------------------------------------------------------------------

# { nome em minusculas (com e sem "[slots]") => ID }
sub idsByName {
	my %ids;
	while (my ($id, $name) = each %items_lut) {
		$ids{lc $name} //= $id;
		$ids{lc "$name [$itemSlotCount_lut{$id}]"} //= $id if $itemSlotCount_lut{$id};
	}
	return \%ids;
}

# Linha de controle -> (chave como esta no arquivo, valores, comentario do fim, ID)
# Chave "Nome#ID#", ID ou nome (como o xConf: a chave vai ate o primeiro numero)
sub parseLine {
	my ($line, $ids) = @_;
	return if $line =~ /^\s*(#|$)/;
	my ($key, $rest) = $line =~ /^\s*(.+?)\s+(-?\d.*)$/ or return;
	my ($values, $comment) = $rest =~ /^(.*?)(\s*#.*)?$/;
	my $id;
	if ($key =~ /#(\d+)#\s*$/) {
		$id = $1;
	} elsif ($key =~ /^\d+$/) {
		$id = $key;
	} else {
		$id = $ids->{lc $key};
	}
	return ($key, [split ' ', $values], $comment // '', $id);
}

sub controlFile {
	return Settings::getControlFilename($_[0]);
}

sub readLines {
	my ($file) = @_;
	open(my $in, '<:encoding(UTF-8)', controlFile($file)) or return;
	my @lines = <$in>;
	close $in;
	s/[\r\n]+$// for @lines;
	return @lines;
}

sub writeLines {
	my ($file, @lines) = @_;
	my $path = controlFile($file);
	copy($path, "$path.bak");
	open(my $out, '>:utf8', $path) or do {
		error "[GordoKore] nao consegui gravar $path: $!\n";
		return;
	};
	print $out join("\n", @lines), "\n";
	close $out;
	parseReload($file);
}

sub pickupOf {
	my ($id) = @_;
	my $name = lc($items_lut{$id} // '');
	return $pickupitems{$name} if $name ne '' && exists $pickupitems{$name};
	return $pickupitems{$id} if exists $pickupitems{$id};
	return NO_PICKUP;
}

# Itens do items_control.txt na ordem do arquivo (um por ID)
sub readItems {
	my $ids = idsByName();
	my (@items, %seen);
	foreach my $line (readLines('items_control.txt')) {
		my ($key, $values, undef, $id) = parseLine($line, $ids);
		next if !defined $key || lc $key eq 'all' || !defined $id || $seen{$id}++;
		my ($keep, $storage, $sell, $cart_add, $cart_get) = map { $_ // 0 } @{$values}[0 .. 4];
		push @items, {
			id => $id, keep => $keep, storage => $storage, sell => $sell,
			cart_add => $cart_add, cart_get => $cart_get, pickup => pickupOf($id),
		};
	}
	return @items;
}

sub sendItems {
	my $payload = ITEMS;
	foreach my $item (readItems()) {
		my $flags = ($item->{storage} ? 1 : 0) | ($item->{sell} ? 2 : 0) | ($item->{cart_add} ? 4 : 0) | ($item->{cart_get} ? 8 : 0);
		$payload .= pack(RECORD, $item->{id}, $item->{keep}, $flags, $item->{pickup});
	}
	sendToClient($payload);
}

sub applyItems {
	my ($data) = @_;
	my (@wanted, %wanted);
	for (my $at = 0; $at + RECORD_SIZE <= length $data; $at += RECORD_SIZE) {
		my ($id, $keep, $flags, $pickup) = unpack(RECORD, substr($data, $at, RECORD_SIZE));
		next if $wanted{$id};
		$wanted{$id} = {
			values => join(' ', $keep, map { ($flags >> $_) & 1 } 0 .. 3), # minimo guardar vender carrinho+ carrinho-
			pickup => $pickup,
		};
		push @wanted, $id;
	}
	my $ids = idsByName();

	# items_control.txt: troca os valores, tira quem saiu, acrescenta os novos
	my (@lines, %written);
	foreach my $line (readLines('items_control.txt')) {
		my ($key, undef, $comment, $id) = parseLine($line, $ids);
		if (!defined $key || lc $key eq 'all' || !defined $id) {
			push @lines, $line;
		} elsif ($wanted{$id} && !$written{$id}++) {
			push @lines, "$key $wanted{$id}{values}$comment";
		}
	}
	push @lines, "$_ $wanted{$_}{values} #" . ($items_lut{$_} // '') for grep { !$written{$_} } @wanted;
	writeLines('items_control.txt', @lines);

	# pickupitems.txt: so os itens da lista (127 = sem linha); o resto fica
	my (@pickup, %done);
	foreach my $line (readLines('pickupitems.txt')) {
		my ($key, undef, $comment, $id) = parseLine($line, $ids);
		if (!defined $key || lc $key eq 'all' || !defined $id || !$wanted{$id}) {
			push @pickup, $line;
		} elsif ($wanted{$id}{pickup} != NO_PICKUP && !$done{$id}++) {
			push @pickup, "$key $wanted{$id}{pickup}$comment";
		}
	}
	push @pickup, "$_ $wanted{$_}{pickup} #" . ($items_lut{$_} // '')
		for grep { !$done{$_} && $wanted{$_}{pickup} != NO_PICKUP } @wanted;
	writeLines('pickupitems.txt', @pickup);

	message "[GordoKore] items_control.txt: " . scalar(@wanted) . " item(s) salvos\n", 'success';
}

# ---------------------------------------------------------------------------
# NPC de venda
# ---------------------------------------------------------------------------

sub sendNpc {
	sendToClient(NPC . ($config{sellAuto_npc} // ''));
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

# ---------------------------------------------------------------------------
# Frames da DLL
# ---------------------------------------------------------------------------

sub onClientSendObserved {
	my (undef, $args) = @_;
	my $msg = $args->{msg};
	return unless defined $msg && length($msg) >= 4;

	my $tag = substr($msg, 0, 4);
	if ($tag eq QUERY) {
		sendItems();
		sendNpc();
	} elsif ($tag eq ITEMS) {
		applyItems(substr($msg, 4));
		sendItems();
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
