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
#
# Mapa alvo: "GKLM" + "mapa" (DLL, botao direito no mapa-mundi) = lockMap do config.txt.
#
# Selecao de monstros (janela no cliente, so os monstros do mapa atual):
#   "GKMQ"                      (DLL) pede o mapa atual e as regras
#   "GKMC" + "ID estado nome"   (DLL) muda a regra de um monstro (nome em CP1252, como o cliente mostra)
#   "GKMS" + "mapa\nestado chave\n...\nM nameID nome\n..."  (resposta 'X', e de novo a cada troca de mapa e a cada
#                               monstro novo na tela) mapa atual, regras (chave = ID ou nome em minusculas, CP1252,
#                               da linha do mon_control) e os monstros ja vistos no mapa ("M": eventos, que nao
#                               estao na tabela de navegacao do cliente)
# Estados: 0 padrao, 1 atacar, 2 so se agredido, 3 ignorar, 4 fugir (ignora e teleporta).
# As regras ficam no mon_control.txt do OpenKore, que o plugin reescreve (guarda um .bak antes e recarrega):
# muda so <attack> e <teleport> da linha do monstro. A chave e' o nome (o que o OpenKore ve e consulta antes do
# ID; o ID da tabela de navegacao do cliente nem sempre e' o nameID do servidor); sem nome, o ID.
# Linha nova herda os campos do "all" (<search> inclusive: com 0 o OpenKore deixa de contar o monstro no
# teleportAuto_search e teleporta atras de outro). Padrao tira as linhas por nome e por ID do monstro (vale o
# "all"; o .bak guarda o arquivo de antes).
# O estado mostrado vem do que esta carregado: linhas com outros valores (atacar 2/3, teleporte 2..) ficam em padrao.
#
# Cura automatica (janela no cliente: itens de cura de HP e de SP e a porcentagem de cada um):
#   "GKHQ"                           (DLL) pede as regras
#   "GKHC" + "H|S porcentagem ID..." (uma linha por tipo)  (DLL) salva as regras de HP (H) e/ou de SP (S); IDs na ordem de prioridade
#   "GKHS" + "H porcentagem ID...\nS porcentagem ID..."  (resposta 'X', tambem apos salvar) regras atuais
# Ficam no config.txt como um bloco useSelf_item do proprio OpenKore por tipo (nada de opcoes extras), com os itens em
# ordem de prioridade (o OpenKore usa o primeiro da lista que houver no inventario):
#   useSelf_item Red Potion, Orange Potion, Yellow Potion {
#       hp < 40%          (ou sp < 40%)
#   }
# Item entra pelo nome; se o nome nao e' unico na tabela de itens, pelo ID. Um bloco e' da janela quando so tem essa
# condicao (timeout e disabled tambem valem); blocos com outras condicoes ficam como estao. Salvar reescreve so o bloco do
# tipo (HP ou SP): troca a lista e a porcentagem mantendo as outras opcoes dele, junta blocos da janela que ja existiam
# e tira o bloco se a lista ficar vazia (guarda um .bak antes e recarrega o config.txt). Porcentagem 0 deixa o bloco
# com "disabled 1" (a lista continua la).
#
# Habilidades automaticas (janela unica: barra vertical de habilidades + abas Ofensiva/Suporte; tipo 0 = ofensiva, 1 = suporte):
#   "GKKL"                                    (DLL) pede as habilidades da barra
#   "GKKA" + "ID:tipos ..."                    (resposta 'X', tambem apos salvar/remover) tipos: 1 ofensiva, 2 suporte, 3 as duas;
#                                              na ordem do config.txt (attackSkillSlot primeiro, depois useSelf_skill)
#   "GKKQ" + "ID tipo"                         (DLL) pede o bloco do tipo da habilidade
#   "GKKC" + "ID tipo achada v1 v2 v3 v4"      (DLL) salva (0 = sem a condicao); tipo 2 = habilidade nova na barra: cria o bloco do
#                                              tipo que combina com o alvo (si mesmo/ator = suporte, o resto = ofensiva)
#   "GKKD" + "ID tipo"                         (DLL) tira o bloco do tipo da habilidade (tipo 2 = os dois)
#   "GKKS" + "ID tipo achada v1 v2 v3 v4 alcance alvo x y"  (resposta 'X', tambem apos salvar/remover; alvo: 1 inimigo, 2 local,
#                                              4 si mesmo, 16 ator; x y = celula do personagem)
# Ofensiva = bloco attackSkillSlot do proprio OpenKore, com o nome da habilidade (v1..v4 = SP, monstros, tentativas, usos):
#   attackSkillSlot Tornado de Carrinho {
#       sp >= 30                (SP minimo)
#       monstersCount >= 2      (quantidade minima de monstros)
#       maxAttempts 4           (tentativas, com ou sem sucesso)
#       maxUses 3               (usos com sucesso)
#   }
# Suporte = bloco useSelf_skill (v1..v4 = HP, SP, monstros agressivos, intervalo):
#   useSelf_skill Bencao {
#       hp <= 50%               (HP no maximo)
#       sp >= 30                (SP minimo)
#       aggressives >= 2        (monstros agressivos no minimo)
#       timeout 30              (segundos entre usos)
#   }
# Salvar so mexe nessas quatro linhas (as outras opcoes do bloco ficam; "sp > 30" vale 31); sem bloco, cria um depois do
# ultimo do tipo. Remover tira o bloco inteiro. Guarda um .bak antes e recarrega o config.txt.
package GordoKore;

use strict;
use File::Copy qw(copy);
use Plugins;
use Commands;
use Settings;
use Encode qw(decode encode);
use Globals qw(%items_lut %itemSlotCount_lut %pickupitems %config $net $field $char $npcsList $monstersList %npcs_lut %mon_control %monsters_lut);
use Utils qw(calcPosition);
use Log qw(message error warning);
use Misc qw(configModify parseReload);
use Skill;

use constant QUERY      => 'GKSQ';
use constant ITEMS      => 'GKIC';
use constant PICK_NPC   => 'GKNP';
use constant NPC        => 'GKNS';
use constant PICK_STORAGE_NPC => 'GKAP';
use constant STORAGE_NPC      => 'GKAS';
use constant START      => 'GKGO';
use constant RELOG      => 'GKRL';
use constant NAVI       => 'GKNV';
use constant LOCK_MAP   => 'GKLM';
use constant MONSTER_QUERY => 'GKMQ';
use constant MONSTER_SET   => 'GKMC';
use constant MONSTERS      => 'GKMS';
use constant HEAL_QUERY    => 'GKHQ';
use constant HEAL_SET      => 'GKHC';
use constant HEAL          => 'GKHS';
use constant HEAL_MAX_ITEMS => 16;
use constant SKILL_QUERY   => 'GKKQ';
use constant SKILL_SET     => 'GKKC';
use constant SKILL_REMOVE  => 'GKKD';
use constant SKILL         => 'GKKS';
use constant SKILL_LIST    => 'GKKL';
use constant SKILLS        => 'GKKA';
use constant SKILL_MAX     => 9;
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
	['Network::Receive::map_changed', \&onMapChanged, undef],
	['objectAdded',                  \&onObjectAdded, undef],
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
# Selecao de monstros
# ---------------------------------------------------------------------------

my %MONSTER_RULES = (
	1 => [1,  0],  # atacar
	2 => [0,  0],  # so se agredido
	3 => [-1, 0],  # ignorar
	4 => [-1, 1],  # fugir (ignora e teleporta)
);

# Linha do mon_control.txt -> (chave em minusculas, campos), como o parseMonControl; nada se for comentario ou vazia
sub monLine {
	my ($line) = @_;
	return if $line =~ /^#/;
	(my $body = $line) =~ s/\s*#.*//;
	$body =~ s/\s+$//;
	return unless length $body;
	my ($key, $args);
	if ($body =~ /\t/) {
		($key, $args) = split /\t+/, lc($body);
	} else {
		($key, $args) = lc($body) =~ /([\s\S]+?) ([\-\d\.]+[\s\S]*)/;
	}
	return unless defined $key && length $key;
	return ($key, [split / /, $args // '']);
}

# Campos <search> ... <weight> de uma linha nova: os do "all" (o <search> = 1 do "all" faz o monstro contar pro
# teleportAuto_search; com 0 o OpenKore ignora o monstro e teleporta atras de outro)
sub inheritedFields {
	my $all = $mon_control{all} || {};
	return (map { $all->{$_} // 0 } qw(teleport_search skillcancel_auto attack_lvl attack_jlvl attack_hp attack_sp)), $all->{weight} // 1;
}

# Mesma linha com <attack> e <teleport> trocados (chave, separador, demais campos e comentario ficam). Linha de
# antes do plugin herdar do "all" (6 zeros e peso 1) ganha o <search> do "all"
sub rewriteMonLine {
	my ($line, $attack, $teleport) = @_;
	my ($body, $comment) = $line =~ /^(.*?)(\s*#.*)?$/;
	my ($key, $sep, $args) = $body =~ /\t/ ? $body =~ /^(.*?)(\t+)(.*)$/ : $body =~ /^(.+?)( )(-?[\d.].*)$/;
	my @fields = split ' ', $args // '';
	@fields[0, 1] = ($attack, $teleport);
	if (@fields == 9 && !grep({ $_ ne '0' } @fields[2 .. 7]) && $fields[8] eq '1') {
		$fields[2] = (inheritedFields())[0];
	}
	return "$key$sep" . join(' ', @fields) . ($comment // '');
}

# Estado (1..4) de uma regra carregada; nada se nao e' nenhum dos quatro
sub ruleState {
	my ($rule) = @_;
	my ($attack, $teleport) = ($rule->{attack_auto}, $rule->{teleport_auto} // 0);
	return unless defined $attack && $attack =~ /^-?\d+$/ && $teleport =~ /^-?\d+$/;
	return 1 if $attack == 1  && $teleport == 0;
	return 2 if $attack == 0  && $teleport == 0;
	return 3 if $attack == -1 && $teleport == 0;
	return 4 if $attack == -1 && $teleport == 1;
	return;
}

# Chave do %mon_control (texto, em minusculas Unicode) -> CP1252 pra DLL (o cliente usa Windows-1252)
sub keyForClient {
	my ($key) = @_;
	return encode('cp1252', $key);
}

# [estado, chave] de tudo que esta carregado no %mon_control e cabe nos quatro estados ("all" nao conta)
sub monsterStates {
	my @states;
	foreach my $key (sort keys %mon_control) {
		next if $key eq 'all';
		my $state = ruleState($mon_control{$key});
		push @states, [$state, keyForClient($key)] if defined $state;
	}
	return @states;
}

# Monstros que ja apareceram na tela neste mapa (mapa => { nome minusculo => [nameID, nome] }): os de evento nao
# estao na tabela de navegacao do cliente, entao a janela soma estes a lista dela
my %seen_monsters;

sub rememberMonster {
	my ($monster) = @_;
	return 0 unless $field && $monster && $monster->{nameID};
	my $name = $monster->name;
	return 0 unless defined $name && length $name && $name !~ /^Unknown/i && $name !~ /[\t\n]/;
	my $seen = $seen_monsters{$field->baseName} //= {};
	return 0 if exists $seen->{lc $name} || keys %$seen >= 300;
	$seen->{lc $name} = [$monster->{nameID}, $name];
	return 1;
}

sub onObjectAdded {
	my (undef, $args) = @_;
	return unless $args->{type} eq 'monster';
	sendMonsters() if rememberMonster($args->{obj}) && clientAlive();
}

sub sendMonsters {
	my $map = $field ? $field->baseName : '';
	rememberMonster($_) for $monstersList ? @{$monstersList->getItems} : ();
	my @seen = map { "M $_->[0] " . encode('cp1252', $_->[1]) } sort { $a->[0] <=> $b->[0] } values %{$seen_monsters{$map} // {}};
	my $payload = MONSTERS . join("\n", $map, (map { "$_->[0] $_->[1]" } monsterStates()), @seen);
	sendToClient(length $payload < 60000 ? $payload : MONSTERS . $map); # o frame leva ate 64 KB
}

sub setMonsterState {
	my ($id, $state, $client_name) = @_;
	return unless $id =~ /^\d+$/ && $state =~ /^[0-4]$/;
	my $name = decode('cp1252', $client_name // '');
	$name = $monsters_lut{$id} // '' if $name eq '';
	$name =~ s/^\s+|\s+$//g;
	$name = '' if $name =~ /[#\t]/; # quebraria a linha do arquivo
	my $key = lc $name;

	my @lines = readLines('mon_control.txt');
	my ($by_id, $by_name);
	for my $i (0 .. $#lines) {
		my ($line_key) = monLine($lines[$i]) or next;
		$by_id = $i if $line_key eq $id;
		$by_name = $i if length $key && $line_key eq $key;
	}

	my ($attack, $teleport) = @{$MONSTER_RULES{$state} // [1, 0]};
	if (defined $by_name) {
		$lines[$by_name] = $state ? rewriteMonLine($lines[$by_name], $attack, $teleport) : undef;
		$lines[$by_id] = $state ? rewriteMonLine($lines[$by_id], $attack, $teleport) : undef if defined $by_id;
	} elsif (defined $by_id) {
		$lines[$by_id] = $state ? rewriteMonLine($lines[$by_id], $attack, $teleport) : undef;
	}
	if ($state && !defined $by_name && length $name) {
		# Linha por nome (o OpenKore consulta antes do ID); a por ID, se havia, segue igual
		push @lines, join(' ', $name, $attack, $teleport, inheritedFields());
	} elsif ($state && !defined $by_name && !defined $by_id) {
		push @lines, join(' ', $id, $attack, $teleport, inheritedFields());
	}
	writeLines('mon_control.txt', grep { defined } @lines);

	my @labels = ('padrao', 'atacar', 'so se agredido', 'ignorar', 'fugir');
	message "[GordoKore] Monstro " . (length $name ? $name : "#$id") . " ($id): $labels[$state]\n", 'info'; # o log ja converte texto
	sendMonsters();
}

sub onMapChanged {
	sendMonsters() if clientAlive();
}

# ---------------------------------------------------------------------------
# Cura automatica
# ---------------------------------------------------------------------------

# Tipos: letra no protocolo, condicao do useSelf_item e rotulo
my @HEAL_KINDS = (
	{ letter => 'H', key => 'hp', label => 'HP' },
	{ letter => 'S', key => 'sp', label => 'SP' },
);

# Nome do bloco + condicoes (condicao => valor) -> (tipo, [IDs na ordem], porcentagem; 0 se desligado) quando e' um bloco
# da janela: lista de itens conhecidos (nome ou ID) e so "hp < N%" ou "sp < N%" (timeout e disabled tambem valem)
sub healBlock {
	my ($name, $conditions, $ids) = @_;
	return if !defined $name || $name eq '';
	my @items;
	foreach my $token (split / *, */, $name) {
		my $id = $token =~ /^\d+$/ ? $token + 0 : $ids->{lc $token};
		return unless $id;
		push @items, $id;
	}
	return unless @items;
	my %set = map { $_ => $conditions->{$_} } grep { defined $conditions->{$_} && $conditions->{$_} ne '' } keys %$conditions;
	my $disabled = delete $set{disabled};
	delete $set{timeout};
	delete $set{$_} for grep { $_ ne 'hp' && $_ ne 'sp' && $set{$_} eq '0' } keys %set;
	my @kinds = grep { exists $set{$_->{key}} } @HEAL_KINDS;
	return unless @kinds == 1 && keys %set == 1;
	my ($percent) = $set{$kinds[0]{key}} =~ /^<=?\s*(\d+)%$/ or return;
	return ($kinds[0], \@items, $disabled ? 0 : $percent + 0);
}

# Blocos "<nome do bloco> <nome> {" do config.txt: { first, last (indices das linhas), name, conditions }
sub configBlocks {
	my ($lines, $block_name) = @_;
	my (@blocks, $current);
	for my $i (0 .. $#$lines) {
		my $line = $lines->[$i];
		if (!$current && $line =~ /^\s*\Q$block_name\E(?:\s+(.*?))?\s*\{\s*$/) {
			$current = { first => $i, name => $1 // '', conditions => {} };
		} elsif ($current && $line =~ /^\s*\}\s*$/) {
			$current->{last} = $i;
			push @blocks, $current;
			undef $current;
		} elsif ($current && $line =~ /^\s*([^#\s]\S*)(?:\s+(.*?))?\s*$/) {
			$current->{conditions}{$1} = $2 // '';
		}
	}
	return @blocks;
}

sub itemBlocks {
	return configBlocks($_[0], 'useSelf_item');
}

sub readConfigLines {
	my ($path) = @_;
	open(my $in, '<:encoding(UTF-8)', $path) or return;
	my @lines = <$in>;
	close $in;
	s/[\r\n]+$// for @lines;
	return @lines;
}

# Linhas do config.txt sem os blocos dados (e sem a linha em branco depois de cada um), com @insert no indice $at
sub replaceBlocks {
	my ($lines, $drop_blocks, $at, @insert) = @_;
	my %drop;
	foreach my $block (@$drop_blocks) {
		$drop{$_} = 1 for $block->{first} .. $block->{last};
		$drop{$block->{last} + 1} = 1 if defined $lines->[$block->{last} + 1] && $lines->[$block->{last} + 1] =~ /^\s*$/;
	}
	my @result;
	for my $i (0 .. scalar @$lines) {
		push @result, @insert if $i == $at;
		push @result, $lines->[$i] if $i < @$lines && !$drop{$i};
	}
	return @result;
}

# Grava o config.txt (com .bak) e recarrega
sub writeConfigLines {
	my ($path, @lines) = @_;
	copy($path, "$path.bak");
	open(my $out, '>:utf8', $path) or do {
		error "[GordoKore] nao consegui gravar $path: $!\n";
		return 0;
	};
	print $out join("\n", @lines), "\n";
	close $out;
	parseReload(quotemeta $path);
	return 1;
}

# Regras de cada tipo no config.txt: porcentagem (a do primeiro bloco ligado) e IDs na ordem dos blocos e das listas
sub currentHeal {
	my %rules = map { ($_->{key}, { percent => 0, items => [] }) } @HEAL_KINDS;
	my $path = Settings::getConfigFilename();
	my @lines = defined $path ? readConfigLines($path) : ();
	my $ids = idsByName();
	foreach my $block (itemBlocks(\@lines)) {
		my ($kind, $block_ids, $percent) = healBlock($block->{name}, $block->{conditions}, $ids) or next;
		my $rule = $rules{$kind->{key}};
		foreach my $id (@$block_ids) {
			push @{$rule->{items}}, $id unless @{$rule->{items}} >= HEAL_MAX_ITEMS || grep { $_ == $id } @{$rule->{items}};
		}
		$rule->{percent} ||= $percent;
	}
	return \%rules;
}

sub sendHeal {
	my $rules = currentHeal();
	sendToClient(HEAL . join("\n", map { my $rule = $rules->{$_->{key}}; "$_->{letter} " . join(' ', $rule->{percent}, @{$rule->{items}}) } @HEAL_KINDS));
}

# Troca (ou acrescenta antes do "}") a opcao de um bloco dado como lista de linhas
sub setBlockOption {
	my ($text, $key, $value) = @_;
	for my $i (1 .. $#$text - 1) {
		if ($text->[$i] =~ /^\s*\Q$key\E(?:\s|$)/) {
			$text->[$i] = "\t$key $value";
			return;
		}
	}
	splice(@$text, $#$text, 0, "\t$key $value");
}

# Bloco da lista de cura: o que ja existe (mantem as outras opcoes) ou um novo, com o nome/lista dos itens
sub healBlockText {
	my ($old, $lines, $kind, $names, $percent) = @_;
	my @text = $old ? @{$lines}[$old->{first} .. $old->{last}] : ('', "\t$kind->{key} < 0%", '}');
	$text[0] = "useSelf_item $names {";
	if ($percent > 0) {
		setBlockOption(\@text, $kind->{key}, "< ${percent}%");
		setBlockOption(\@text, 'disabled', 0) if grep { /^\s*disabled(?:\s|$)/ } @text;
	} else {
		setBlockOption(\@text, 'disabled', 1);
	}
	return @text;
}

# Como o item entra na lista do bloco: o nome (se levar de volta ao mesmo ID) ou o ID
sub healItemName {
	my ($id, $ids) = @_;
	my $name = $items_lut{$id};
	return $id unless defined $name && $name !~ /[,#{}\r\n]/ && $name =~ /\S/ && ($ids->{lc $name} // 0) == $id;
	return $name;
}

# "H 50 501 502" da DLL -> bloco useSelf_item do config.txt
sub applyHeal {
	my ($body) = @_;
	my ($letter, $percent, $list) = $body =~ /^([HS]) (\d{1,3})((?: \d+)*)\s*$/ or return;
	my ($kind) = grep { $_->{letter} eq $letter } @HEAL_KINDS;
	$percent = 100 if $percent > 100;
	$percent += 0;
	my %seen;
	my @wanted = grep { $_ > 0 && !$seen{$_}++ } split ' ', $list;
	splice(@wanted, HEAL_MAX_ITEMS) if @wanted > HEAL_MAX_ITEMS;

	my $path = Settings::getConfigFilename();
	my @lines = defined $path ? readConfigLines($path) : ();
	unless (@lines) {
		error "[GordoKore] nao consegui ler o config.txt\n";
		return;
	}
	my $ids = idsByName();
	my @blocks = itemBlocks(\@lines);

	# Blocos da janela deste tipo, na ordem do arquivo
	my @old = grep {
		my ($block_kind) = healBlock($_->{name}, $_->{conditions}, $ids);
		$block_kind && $block_kind->{key} eq $kind->{key};
	} @blocks;

	my @insert = @wanted ? (healBlockText($old[0], \@lines, $kind, join(', ', map { healItemName($_, $ids) } @wanted), $percent), '') : ();

	# Os blocos antigos saem; o novo entra onde estava o primeiro, ou depois do ultimo useSelf_item
	my $at = @old ? $old[0]{first} : @blocks ? $blocks[-1]{last} + 1 : scalar @lines;
	unshift @insert, '' if @insert && !@old && $at > 0;

	writeConfigLines($path, replaceBlocks(\@lines, \@old, $at, @insert)) or return;

	message sprintf("[GordoKore] useSelf_item de %s: %s, %d item(s)\n", $kind->{label}, $percent ? "abaixo de $percent%" : 'desligado', scalar @wanted), 'success';
}

# ---------------------------------------------------------------------------
# Habilidades automaticas: ofensivas (attackSkillSlot) e de suporte (useSelf_skill)
# ---------------------------------------------------------------------------

# Tipos na ordem do protocolo (0 = ofensiva, 1 = suporte; 2 = "o plugin decide" ao adicionar). Opcoes: as da janela, na ordem do
# protocolo; min = ">= N", max_percent = "<= N%", plain = N
my @SKILL_KINDS = (
	{
		block   => 'attackSkillSlot',
		options => [
			{ key => 'sp',            type => 'min',   label => 'SP' },
			{ key => 'monstersCount', type => 'min',   label => 'monstros' },
			{ key => 'maxAttempts',   type => 'plain', label => 'tentativas' },
			{ key => 'maxUses',       type => 'plain', label => 'usos' },
		],
	},
	{
		block   => 'useSelf_skill',
		options => [
			{ key => 'hp',          type => 'max_percent', label => 'HP' },
			{ key => 'sp',          type => 'min',         label => 'SP' },
			{ key => 'aggressives', type => 'min',         label => 'agressivos' },
			{ key => 'timeout',     type => 'plain',       label => 'intervalo' },
		],
	},
);
use constant SKILL_KIND_AUTO => 2;

# Valor de uma opcao como a janela mostra (sem a linha = 0); undef se o texto tem outra forma (intervalo, status...)
sub skillOptionValue {
	my ($option, $text) = @_;
	return 0 if !defined $text || $text eq '';
	if ($option->{type} eq 'min') {
		return $1 + 0 if $text =~ /^>=\s*(\d+)$/;
		return $1 + 1 if $text =~ /^>\s*(\d+)$/;
	} elsif ($option->{type} eq 'max_percent') {
		return $1 + 0 if $text =~ /^<=\s*(\d+)\s*%$/;
		return $1 - 1 if $text =~ /^<\s*([1-9]\d*)\s*%$/;
	} elsif ($text =~ /^\d+$/) {
		return $text + 0;
	}
	return undef;
}

sub skillOptionText {
	my ($option, $value) = @_;
	return ">= $value" if $option->{type} eq 'min';
	return "<= ${value}%" if $option->{type} eq 'max_percent';
	return "$value";
}

# ID da habilidade pelo nome (ou handle/ID) que esta no config.txt
sub skillIdn {
	my ($name) = @_;
	return unless defined $name && $name ne '';
	my $skill = eval { Skill->new(auto => $name) } or return;
	return $skill->getIDN;
}

# Primeiro bloco do tipo (attackSkillSlot ou useSelf_skill) da habilidade
sub findSkillBlock {
	my ($lines, $idn, $kind) = @_;
	foreach my $block (configBlocks($lines, $SKILL_KINDS[$kind]{block})) {
		my $block_idn = skillIdn($block->{name});
		return $block if defined $block_idn && $block_idn == $idn;
	}
	return;
}

sub removeBlockOption {
	my ($text, $key) = @_;
	@$text = ($text->[0], (grep { $_ !~ /^\s*\Q$key\E(?:\s|$)/ } @{$text}[1 .. $#$text - 1]), $text->[-1]);
}

sub readConfig {
	my $path = Settings::getConfigFilename();
	return ($path, defined $path ? readConfigLines($path) : ());
}

# "ID tipo achada v1 v2 v3 v4 alcance alvo x y": o bloco do tipo e o que o servidor mandou da habilidade (a janela usa no teste)
sub sendSkill {
	my ($idn, $kind) = @_;
	my (undef, @lines) = readConfig();
	my $block = findSkillBlock(\@lines, $idn, $kind);
	my @values;
	foreach my $option (@{$SKILL_KINDS[$kind]{options}}) {
		push @values, $block ? (skillOptionValue($option, $block->{conditions}{$option->{key}}) // 0) : 0;
	}
	my $skill = eval { Skill->new(idn => $idn) };
	my $range = $skill ? int(($skill->getRange // 0) + 0.5) : 0;
	my $target = $skill ? ($skill->getTargetType // 0) : 0;
	my $pos = $char && $char->{pos_to} ? $char->{pos_to} : {};
	sendToClient(SKILL . join(' ', $idn, $kind, $block ? 1 : 0, @values, $range, $target, $pos->{x} // 0, $pos->{y} // 0));
}

# Habilidades da barra: as dos blocos attackSkillSlot e useSelf_skill do config.txt, "ID:tipos" (1 = ofensiva, 2 = suporte,
# 3 = as duas), na ordem em que aparecem
sub sendSkillList {
	my (undef, @lines) = readConfig();
	my (@ids, %kinds);
	foreach my $kind (0 .. $#SKILL_KINDS) {
		foreach my $block (configBlocks(\@lines, $SKILL_KINDS[$kind]{block})) {
			my $idn = skillIdn($block->{name});
			next unless defined $idn;
			push @ids, $idn unless exists $kinds{$idn};
			$kinds{$idn} |= 1 << $kind;
		}
	}
	splice(@ids, SKILL_MAX) if @ids > SKILL_MAX;
	sendToClient(SKILLS . join(' ', map { "$_:$kinds{$_}" } @ids));
}

# "ID tipo achada v1 v2 v3 v4" da DLL -> bloco do tipo no config.txt; devolve (ID, tipo) pra responder.
# Tipo 2 (habilidade nova na barra): cria o bloco do tipo que combina com o alvo da habilidade, se ela ainda nao tem nenhum
sub applySkill {
	my ($body) = @_;
	my ($idn, $kind, @desired) = $body =~ /^(\d+) ([012]) [01] (\d{1,4}) (\d{1,4}) (\d{1,4}) (\d{1,4})\s*$/ or return;

	my $name = eval { Skill->new(idn => $idn)->getName };
	if (!defined $name || $name =~ /^Unknown / || $name =~ /[#{}\r\n]/) {
		warning "[GordoKore] Habilidade $idn sem nome valido na tabela de habilidades: nao da pra criar o bloco no config.txt\n";
		return ($idn, $kind == SKILL_KIND_AUTO ? 0 : $kind);
	}
	my ($path, @lines) = readConfig();
	unless (@lines) {
		error "[GordoKore] nao consegui ler o config.txt\n";
		return ($idn, $kind == SKILL_KIND_AUTO ? 0 : $kind);
	}

	if ($kind == SKILL_KIND_AUTO) {
		foreach my $existing (0 .. $#SKILL_KINDS) {
			return ($idn, $existing) if findSkillBlock(\@lines, $idn, $existing);
		}
		my $target = eval { Skill->new(idn => $idn)->getTargetType } // 0;
		$kind = $target == Skill::TARGET_SELF || $target == Skill::TARGET_ACTORS ? 1 : 0;
	}

	my @options = @{$SKILL_KINDS[$kind]{options}};
	my $block_name = $SKILL_KINDS[$kind]{block};
	my $block = findSkillBlock(\@lines, $idn, $kind);
	my @text = $block ? @lines[$block->{first} .. $block->{last}] : ("$block_name $name {", '}');
	my $changed = !$block;
	for my $i (0 .. $#options) {
		my ($option, $value) = ($options[$i], $desired[$i] + 0);
		$value = 100 if $option->{type} eq 'max_percent' && $value > 100;
		$desired[$i] = $value;
		my $current = $block ? skillOptionValue($option, $block->{conditions}{$option->{key}}) : 0;
		next if defined $current ? $current == $value : $value == 0; # ja esta assim (ou forma que a janela nao mostra e ficou 0)
		$changed = 1;
		if ($value > 0) {
			setBlockOption(\@text, $option->{key}, skillOptionText($option, $value));
		} else {
			removeBlockOption(\@text, $option->{key});
		}
	}
	return ($idn, $kind) unless $changed;

	# Bloco existente: no mesmo lugar (e com a linha em branco que vinha depois); novo: depois do ultimo do tipo
	my @slots = configBlocks(\@lines, $block_name);
	my $blank_after = $block && defined $lines[$block->{last} + 1] && $lines[$block->{last} + 1] =~ /^\s*$/;
	my @insert = $block ? ($blank_after ? (@text, '') : @text) : ('', @text);
	my $at = $block ? $block->{first} : @slots ? $slots[-1]{last} + 1 : scalar @lines;
	writeConfigLines($path, replaceBlocks(\@lines, $block ? [$block] : [], $at, @insert)) or return ($idn, $kind);

	message sprintf("[GordoKore] %s %s: %s\n", $block_name, $name, join(', ', map { "$options[$_]{label} $desired[$_]" } 0 .. $#options)), 'success';
	return ($idn, $kind);
}

# Tira o bloco do tipo da habilidade (tipo 2 = os dois)
sub removeSkill {
	my ($idn, $kind) = @_;
	foreach my $each ($kind == SKILL_KIND_AUTO ? (0 .. $#SKILL_KINDS) : $kind) {
		my ($path, @lines) = readConfig();
		my $block = @lines ? findSkillBlock(\@lines, $idn, $each) : undef;
		next unless $block;
		writeConfigLines($path, replaceBlocks(\@lines, [$block], $block->{first})) or return;
		message "[GordoKore] $SKILL_KINDS[$each]{block} de $block->{name} removido\n", 'success';
	}
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
	} elsif ($tag eq MONSTER_QUERY) {
		sendMonsters();
	} elsif ($tag eq HEAL_QUERY) {
		sendHeal();
	} elsif ($tag eq HEAL_SET) {
		applyHeal($_) for split /\n/, substr($msg, 4);
		sendHeal();
	} elsif ($tag eq SKILL_QUERY) {
		my ($idn, $kind) = substr($msg, 4) =~ /^(\d+) ([01])\s*$/ or return;
		sendSkill($idn, $kind);
	} elsif ($tag eq SKILL_SET) {
		my ($idn, $kind) = applySkill(substr($msg, 4));
		sendSkill($idn, $kind) if defined $idn;
		sendSkillList();
	} elsif ($tag eq SKILL_REMOVE) {
		my ($idn, $kind) = substr($msg, 4) =~ /^(\d+) ([012])\s*$/ or return;
		removeSkill($idn, $kind);
		sendSkill($idn, $kind == SKILL_KIND_AUTO ? 0 : $kind);
		sendSkillList();
	} elsif ($tag eq SKILL_LIST) {
		sendSkillList();
	} elsif ($tag eq MONSTER_SET) {
		my ($id, $state, $name) = substr($msg, 4) =~ /^(\d+) (\d)(?: (.*))?$/s;
		setMonsterState($id, $state, $name) if defined $state;
	} elsif ($tag eq LOCK_MAP) {
		my $map = substr($msg, 4);
		return unless $map =~ /^[\w@.-]+$/; # vai pro config.txt: so nome de mapa
		configModify('lockMap', $map);
		message "[GordoKore] Mapa alvo (lockMap): $map\n", 'success';
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
