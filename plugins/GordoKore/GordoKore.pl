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
# NPC de venda / do armazem = o NPC mais proximo do personagem no mapa atual (qualquer um: nem so
# Kafra guarda itens e os nomes dos vendedores variam):
#   "GKNP" / "GKAP"                (DLL) escolhe o NPC mais proximo como NPC de venda / do armazem
#   "GKNS" / "GKAS" + "mapa x y"   (resposta 'X') sellAuto_npc / storageAuto_npc atual, tambem enviado junto com a lista
# Candidatos: os NPCs na tela ($npcsList, posicao real) e os do %npcs_lut (tables/npcs.txt: "mapa x y" =>
# nome), menos os de nome so escondido ("#..."). Menor distancia em linha reta da posicao atual do
# personagem (calcPosition); <prefixo>_standpoint fica vazio (o AI anda ate o NPC). O jeito de falar
# com o NPC do armazem (storageAuto_npc_type / _steps) fica como esta no config.txt.
#
# Iniciar: "GKGO" + "sell" / "storage" (DLL) = comando autosell / autostorage.
#
# Relog: o comando "relog [segundos|a..b]" do OpenKore manda "GKRL" + segundos (resposta 'X') e a
# DLL volta o cliente pro login e loga depois desse tempo (no XKore o relog do OpenKore sozinho nao
# derruba o cliente). Sem argumento = 5, como o OpenKore; 0 = fica no login.
#
# Navegacao: "GKNV" + "mapa [x y]" (DLL) = /navi digitado no chat do cliente; o personagem
# anda ate la com o AI em manual (ai manual + move).

package GordoKore;

use strict;
use File::Copy qw(copy);
use Plugins;
use Commands;
use Settings;
use Globals qw(%items_lut %itemSlotCount_lut %pickupitems %config $net $field $char $npcsList %npcs_lut);
use Utils qw(calcPosition);
use Log qw(message error warning);
use Misc qw(configModify parseReload);

use constant QUERY      => 'GKSQ';
use constant ITEMS      => 'GKIC';
use constant PICK_NPC   => 'GKNP';
use constant NPC        => 'GKNS';
use constant PICK_STORAGE_NPC => 'GKAP';
use constant STORAGE_NPC      => 'GKAS';
use constant START      => 'GKGO';
use constant RELOG      => 'GKRL';
use constant NAVI       => 'GKNV';
use constant NO_PICKUP  => 127;   # sem linha no pickupitems.txt
use constant RECORD     => 'V l C c';
use constant RECORD_SIZE => 10;

Plugins::register('GordoKore', 'Kore-Bridge: toda a comunicacao da DLL com o OpenKore', \&Unload, \&Unload);

# Por tipo de NPC: prefixo no config.txt, tag da resposta e nome nas mensagens
my %NPC_KIND = (
	sell    => { config => 'sellAuto',    tag => NPC,         label => 'venda' },
	storage => { config => 'storageAuto', tag => STORAGE_NPC, label => 'armazem' },
);

my $hooks = Plugins::addHooks(
	['Network::clientSend/observed', \&onClientSendObserved, undef],
	['Commands::run/pre',            \&onCommand, undef],
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
# NPC de venda / do armazem
# ---------------------------------------------------------------------------

sub sendNpc {
	my ($kind) = @_;
	sendToClient($NPC_KIND{$kind}{tag} . ($config{"$NPC_KIND{$kind}{config}_npc"} // ''));
}

# Candidatos do mapa atual: os NPCs na tela (posicao real, vinda do servidor) e os do tables/npcs.txt
# (que pode estar desatualizado ou nao ter todos); [nome, x, y]
sub npcCandidates {
	my ($map) = @_;
	my @candidates;
	if ($npcsList) {
		foreach my $npc (@{$npcsList->getItems()}) {
			my $pos = $npc->{pos_to} || $npc->{pos} or next;
			push @candidates, [$npc->name, $pos->{x}, $pos->{y}];
		}
	}
	while (my ($key, $name) = each %npcs_lut) {
		my ($npc_map, $x, $y) = split ' ', $key;
		push @candidates, [$name, $x, $y] if defined $y && $npc_map eq $map;
	}
	return @candidates;
}

# NPC mais proximo do personagem (posicao de agora, mesmo andando)
sub setNearestNpc {
	my ($kind) = @_;
	my $info = $NPC_KIND{$kind};
	unless ($field && $char && ($char->{pos_to} || $char->{pos})) {
		warning "[GordoKore] Sem mapa/posicao do personagem pra procurar o NPC de $info->{label}\n";
		return sendNpc($kind);
	}
	my $map = $field->baseName;
	my $here = calcPosition($char);
	my ($best, $best_dist);
	foreach my $candidate (npcCandidates($map)) {
		my ($name, $x, $y) = @$candidate;
		(my $shown = $name) =~ s/#.*$//; # parte escondida do nome ("Kafra#prt1")
		next if $shown =~ /^\s*$/;        # so escondido ("#prtjm1"): NPC de efeito, nao se fala com ele
		my $dist = sqrt(($x - $here->{x}) ** 2 + ($y - $here->{y}) ** 2);
		($best, $best_dist) = ([$shown, $x, $y], $dist) if !defined $best_dist || $dist < $best_dist;
	}
	unless ($best) {
		warning "[GordoKore] Nenhum NPC de $info->{label} em $map (na tela ou no tables/npcs.txt)\n";
		return sendNpc($kind);
	}
	my ($name, $x, $y) = @$best;
	configModify("$info->{config}_npc", "$map $x $y");
	configModify("$info->{config}_standpoint", '');
	message sprintf("[GordoKore] NPC de %s: %s (%s %d %d), a %.0f celulas de %d %d\n",
		$info->{label}, $name, $map, $x, $y, $best_dist, $here->{x}, $here->{y}), 'success';
	sendNpc($kind);
}

# ---------------------------------------------------------------------------
# relog
# ---------------------------------------------------------------------------

# Mesmas regras do cmdRelog: vazio = 5, N, a..b = aleatorio entre a e b, 0 = fica offline
sub onCommand {
	my (undef, $args) = @_;
	return unless $args->{switch} eq 'relog';
	my $arg = $args->{args} // '';
	$arg =~ s/^\s+|\s+$//g;
	my $seconds;
	if ($arg eq '') {
		$seconds = 5;
	} elsif ($arg =~ /^\d+$/) {
		$seconds = $arg;
	} elsif ($arg =~ /^(\d+)\.\.(\d+)$/ && $1 <= $2) {
		$seconds = int(rand($2 - $1) + $1 + 0.5);
	} else {
		return; # o cmdRelog mostra o erro de sintaxe
	}
	return unless clientAlive();
	sendToClient(RELOG . $seconds);
	message "[GordoKore] Cliente voltando pro login" . ($seconds ? ", login em ${seconds}s" : '') . "\n", 'connection';
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
		sendNpc($_) for qw(sell storage);
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
	} elsif ($tag eq PICK_NPC || $tag eq PICK_STORAGE_NPC) {
		setNearestNpc($tag eq PICK_NPC ? 'sell' : 'storage');
	} elsif ($tag eq START) {
		# So os dois comandos (o frame vem da DLL, nada de comando livre)
		my %commands = (sell => 'autosell', storage => 'autostorage');
		my $command = $commands{substr($msg, 4)} or return;
		message "[GordoKore] $command\n", 'info';
		Commands::run($command);
	}
}

1;
