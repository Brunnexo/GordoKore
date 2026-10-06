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
# Mapa alvo: "GKLM" + "mapa" (DLL, janela de monstros) = lockMap do config.txt.
#
# Selecao de monstros (janela no cliente, monstros de qualquer mapa da tabela do cliente):
#   "GKMQ"                      (DLL) pede o mapa atual e as regras
#   "GKMC" + "ID estado nome"   (DLL) muda a regra de um monstro (nome em CP1252, como o cliente mostra)
#   "GKMS" + "mapa\nestado chave\n...\nM nameID nome\n..."  (resposta 'X', e de novo a cada troca de mapa e a cada
#                               monstro novo na tela) mapa atual, regras (chave = ID ou nome em minusculas, CP1252,
#                               da linha do mon_control) e os monstros ja vistos no mapa ("M": eventos, que nao
#                               estao na tabela de navegacao do cliente) e "L mapa" (lockMap atual)
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
#   "GKKC" + "ID tipo" e linhas "opcao valor"  (DLL) salva; valor vazio tira a linha, as outras linhas do bloco ficam. Tipo 2 (so a
#                                              primeira linha) = habilidade nova na barra: cria o bloco do tipo que combina com o
#                                              alvo (si mesmo/ator = suporte, o resto = ofensiva)
#   "GKKD" + "ID tipo"                         (DLL) tira o bloco do tipo da habilidade (tipo 2 = os dois)
#   "GKKS" + "ID tipo achada alcance alvo" e linhas "opcao valor"  (resposta 'X', tambem apos salvar/remover; alvo: 1 inimigo,
#                                              2 local, 4 si mesmo, 16 ator)
# Ofensiva = bloco attackSkillSlot do proprio OpenKore e suporte = useSelf_skill, com o nome da habilidade; as opcoes vao como
# o OpenKore escreve (texto em CP1252 na ida e na volta):
#   attackSkillSlot Tornado de Carrinho {
#       sp > 30
#       monstersCount >= 2
#       whenStatusInactive Blessing
#   }
# So entram as opcoes conhecidas de cada bloco (@SKILL_KINDS). Sem bloco, cria um depois do ultimo do tipo. Remover tira o
# bloco inteiro. Guarda um .bak antes e recarrega o config.txt.
package GordoKore;

use strict;
use File::Copy qw(copy);
use Plugins;
use Commands;
use Settings;
use Encode qw(decode encode);
use Globals qw(%items_lut %itemSlotCount_lut %pickupitems %config $net $field $char $npcsList $monstersList %npcs_lut %mon_control %monsters_lut %maps_lut %portals_lut);
use POSIX ();
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
use constant NAVI_ARROWS   => 'GKNF'; # + mapa: o OpenKore nao achou rota, a DLL passa a seguir as setas do navi do jogo
use constant NAVI_STEP     => 'GKNW'; # + linhas "tipo mapa x y [destino]": plano das setas (W portal, N NPC + mapa para onde leva, F destino final)
use constant NAVI_NPC_MENUS => 5;     # menus do NPC de teleporte respondidos (principal, cidades, confirmacao...)
use constant PORTALS_QUERY => 'GKPQ'; # pede a DLL as ligacoes entre mapas do navi do jogo
use constant PORTALS       => 'GKPL'; # + linhas "tipo origem x y destino x y" (varios frames)
use constant PORTALS_END   => 'GKPE'; # + ultimas linhas: fim da lista
use constant PORTAL_NEAR   => 5;      # portal do portals.txt a ate tantas celulas (mesma origem e destino) = o mesmo
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
use constant COMMAND       => 'GKCM'; # comando do console (janela Situacao do GordoKore e modulos do SDK)
use constant AI_QUERY      => 'GKAQ'; # a DLL pede o estado da IA
use constant AI_STATE      => 'GKAI'; # "modo acao": modo 0 desligada, 1 manual, 2 ligada; acao do topo da fila
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
	['mainLoop_post',                \&onMainLoop, undef],
	['fail_calc_map_route',          \&onRouteFail, undef],
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
	my @lock = $config{lockMap} ? ("L $config{lockMap}") : (); # mapa de trabalho atual
	my $payload = MONSTERS . join("\n", $map, (map { "$_->[0] $_->[1]" } monsterStates()), @lock, @seen);
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
	naviMapChanged();
}

# ---------------------------------------------------------------------------
# Navi: sem rota no OpenKore (portals.txt), segue as setas do navi do jogo
# ---------------------------------------------------------------------------

my $naviTarget; # mapa do ultimo /navi (o OpenKore ainda calcula a rota)
my $naviFollow; # mapa do /navi sendo seguido pelas setas
my $naviPlan;   # pontos das setas mandados pela DLL: [{ kind, map, x, y, dest }], o destino (F) por ultimo
my $naviApplied; # ponto ja seguido neste mapa ("tipo mapa x y"): a DLL reenvia o plano quando a rota muda
my $naviUsed;    # portal/NPC das setas em uso ({ map, x, y, dest, kind }): ao chegar no destino dele vira portals.txt
my $naviTalking; # conversando com o NPC das setas (a sobra da sequencia sai na troca de mapa)

sub endNaviTalk {
	return unless $naviTalking;
	undef $naviTalking;
	AI::clear('NPC');
}

# Resposta de menu do NPC de teleporte: o destino (codigo do mapa ou nome de exibicao), a opcao de
# teletransporte do menu principal ou a confirmacao. Sem espacos: o talknpc separa os passos por espaco
sub naviNpcRegex {
	my ($dest) = @_;
	my @words = ($dest);
	my $display = $maps_lut{"$dest.rsw"};
	push @words, (split /\s+/, $display)[0] if defined $display && length $display;
	push @words, qw(Teletransporte Teleporte Teleport Transporte Viajar Warp);
	my $words = join '|', map { quotemeta } grep { length } @words;
	$words =~ s/\\? /\\s/g;
	# Confirmacao: palavra inteira (sem \b no "Si" com acento: fora do utf8 o i acentuado nao e' letra para o \b)
	return "r~/(?:$words|\\b(?:Sim|Yes)\\b|(?<![a-z])S\x{ED}(?![a-z]))/i";
}

# Conversa com NPC de teleporte: "c" antes de cada menu (o TalkNPC ignora "c" sobrando quando o NPC pede uma
# escolha), entao vale com ou sem autoTalkCont. A mesma sequencia vai para o portals.txt
sub naviNpcSequence {
	my ($dest) = @_;
	my $regex = naviNpcRegex($dest);
	return join ' ', (map { ('c', $regex) } 1 .. NAVI_NPC_MENUS), 'c';
}

sub onRouteFail {
	my (undef, $args) = @_;
	return unless defined $naviTarget && defined $args->{map_to} && $args->{map_to} eq $naviTarget;
	$naviFollow = $naviTarget;
	undef $naviTarget;
	undef $naviPlan;
	undef $naviApplied;
	undef $naviUsed;
	message "[GordoKore] OpenKore sem rota para $naviFollow: seguindo as setas do navi do jogo\n", 'info';
	sendToClient(NAVI_ARROWS . $naviFollow);
}

# Mapa novo: o portal/NPC usado vira portals.txt (com a posicao real de chegada), a sobra da conversa com o NPC
# sai (ele ja teleportou) e vale o ponto das setas daqui
sub naviMapChanged {
	undef $naviTarget if defined $naviTarget && $field && $field->baseName eq $naviTarget; # chegou pelo OpenKore
	if ($naviUsed && $field && $char && $char->{pos} && $naviUsed->{dest} && $field->baseName eq $naviUsed->{dest}) {
		my ($x, $y) = @{$char->{pos}}{qw(x y)};
		my $line = "$naviUsed->{map} $naviUsed->{x} $naviUsed->{y} $naviUsed->{dest} $x $y";
		$line .= ' 0 ' . naviNpcSequence($naviUsed->{dest}) if $naviUsed->{kind} eq 'N';
		addPortals([$line], 'aprendido pelas setas do navi') unless portalKnown($naviUsed->{map}, $naviUsed->{x}, $naviUsed->{y}, $naviUsed->{dest});
	}
	undef $naviUsed;
	endNaviTalk();
	undef $naviApplied;
	applyNaviPlan();
	requestPortals();
}

# Ponto das setas no mapa atual: no mapa do destino, o destino; senao o ultimo passo da rota neste mapa.
# Portal: anda ate ele (troca de mapa). NPC de teleporte: conversa escolhendo o destino. Destino: anda e encerra
sub applyNaviPlan {
	return unless $naviPlan && $naviFollow && $field;
	my $here = $field->baseName;
	my ($final) = grep { $_->{kind} eq 'F' } @$naviPlan;
	my $step = $final && $final->{map} eq $here ? $final : (grep { $_->{kind} ne 'F' && $_->{map} eq $here } @$naviPlan)[-1];
	unless ($step) {
		my $maps = join ' ', map { $_->{map} } @$naviPlan;
		warning "[GordoKore] Setas do navi: nenhum ponto da rota em $here (rota: $maps)\n";
		return;
	}
	my ($kind, $x, $y, $dest) = @{$step}{qw(kind x y dest)};
	my $key = "$kind $here $x $y";
	return if defined $naviApplied && $naviApplied eq $key;
	$naviApplied = $key;
	endNaviTalk();

	if ($kind eq 'F') {
		Commands::run("move $x $y") if $x > 0 && $y > 0;
		message "[GordoKore] Setas do navi: chegando ao destino em $naviFollow\n", 'success';
		undef $naviFollow;
		undef $naviPlan;
		return;
	}
	return unless $x > 0 && $y > 0;
	$naviUsed = { kind => $kind, map => $here, x => $x, y => $y, dest => $dest };
	if ($kind eq 'N' && defined $dest) {
		$naviTalking = 1;
		message "[GordoKore] Setas do navi: falando com o NPC em ($x, $y) para ir a $dest\n", 'info';
		Commands::run("talknpc $x $y " . naviNpcSequence($dest));
	} elsif ($kind eq 'N') {
		Commands::run("move $x $y");
		message "[GordoKore] Setas do navi: o proximo passo e' um NPC em ($x, $y). Fale com ele para continuar.\n", 'info';
	} else {
		message "[GordoKore] Setas do navi: indo ao portal em ($x, $y)\n", 'info';
		Commands::run("move $x $y");
	}
}

# ---------------------------------------------------------------------------
# portals.txt: ligacoes do navi do jogo que o OpenKore nao tem
# ---------------------------------------------------------------------------

my $portalsDone;   # importacao feita nesta sessao
my $portalsAsked;  # momento do ultimo pedido a DLL (o navi pode ainda nao ter carregado)
my @portalsLines;  # linhas recebidas ate o GKPE
my @portalsQueue;  # [linhas, origem] esperando o OpenKore parar: o "portals recompile" recarrega a tabela de
                   # portais e derruba a rota em andamento

# Ja existe no portals.txt: mesma origem e destino, saida a ate PORTAL_NEAR celulas
sub portalKnown {
	my ($map, $x, $y, $dest) = @_;
	foreach my $portal (values %portals_lut) {
		next unless $portal->{source}{map} eq $map;
		next unless grep { $_->{map} eq $dest } values %{$portal->{dest}};
		my $pos = $portal->{source}{pos} || $portal->{source};
		return 1 if abs($pos->{x} - $x) <= PORTAL_NEAR && abs($pos->{y} - $y) <= PORTAL_NEAR;
	}
	return 0;
}

# Rotas novas: entram na fila e vao para o portals.txt quando o OpenKore nao estiver andando nem seguindo as setas
sub addPortals {
	my ($lines, $origin) = @_;
	push @portalsQueue, [[@$lines], $origin] if @$lines;
}

# A cada volta do laco principal: grava a fila com o OpenKore parado
sub flushPortals {
	return unless @portalsQueue;
	return if AI::inQueue('route', 'mapRoute', 'NPC'); # andando (rota do OpenKore ou setas) ou falando com NPC
	my @queue = @portalsQueue;
	@portalsQueue = ();
	my (@lines, %origins);
	foreach (@queue) {
		push @lines, @{$_->[0]};
		$origins{$_->[1]} = 1;
	}
	writePortals(\@lines, join(', ', sort keys %origins));
}

# Acrescenta no fim do portals.txt (copia .bak antes da primeira vez) e recompila as rotas
sub writePortals {
	my ($lines, $origin) = @_;
	return unless @$lines;
	my $file = Settings::getTableFilename('portals.txt');
	return unless $file && -f $file;
	copy($file, "$file.bak") unless -f "$file.bak";
	open my $out, '>>:utf8', $file or do {
		error "[GordoKore] Nao deu para gravar em $file: $!\n";
		return;
	};
	my $stamp = POSIX::strftime('%Y-%m-%d %H:%M', localtime);
	print $out "\n# GordoKore: $origin ($stamp)\n";
	print $out "$_\n" for @$lines;
	close $out;
	message "[GordoKore] portals.txt: " . scalar(@$lines) . " rota(s) nova(s) ($origin)\n", 'success';
	Commands::run('portals recompile');
}

# Uma vez por sessao, no primeiro mapa com o cliente ligado (de novo a cada 30 s se o navi ainda nao carregou)
sub requestPortals {
	return if $portalsDone || !clientAlive();
	return if $portalsAsked && time - $portalsAsked < 30;
	$portalsAsked = time;
	@portalsLines = ();
	sendToClient(PORTALS_QUERY);
}

sub importPortals {
	my @lines = @portalsLines;
	@portalsLines = ();
	return unless @lines; # navi ainda nao carregou: o proximo mapa pede de novo
	$portalsDone = 1;
	my (@new, %seen);
	foreach (@lines) {
		my ($type, $map, $x, $y, $dest, $dx, $dy) = /^(\d+) ([\w@.-]+) (\d+) (\d+) ([\w@.-]+) (\d+) (\d+)$/ or next;
		next if portalKnown($map, $x, $y, $dest) || $seen{"$map $x $y $dest"}++;
		# 200 = portal; o resto e' NPC de teleporte (conversa escolhendo o destino; o navi nao traz o preco)
		push @new, $type == 200 ? "$map $x $y $dest $dx $dy" : "$map $x $y $dest $dx $dy 0 " . naviNpcSequence($dest);
	}
	message "[GordoKore] Navi do jogo: " . scalar(@lines) . " ligacoes, " . scalar(@new) . " fora do portals.txt\n", 'info';
	addPortals(\@new, 'ligacoes do navi do jogo');
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

# Tipos na ordem do protocolo (0 = ofensiva, 1 = suporte; 2 = "o plugin decide" ao adicionar) e as opcoes que a janela pode
# gravar em cada bloco (as do proprio OpenKore)
my @SKILL_KINDS = (
	{
		block   => 'attackSkillSlot',
		options => [qw(lvl dist maxDist maxCastTime minCastTime hp sp ap onAction inQueue notInQueue whenStatusActive
			whenStatusInactive whenFollowing spirit amuletType aggressives previousDamage stopWhenHit inLockOnly notInTown timeout
			disabled monsters notMonsters monstersCount monstersCountDist maxAttempts maxUses target_hp target_whenStatusActive
			target_whenStatusInactive target_deltaHp whenPartyMembersNear whenPartyMembersNearDist inInventory isSelfSkill
			isStartSkill manualAI)],
	},
	{
		block   => 'useSelf_skill',
		options => [qw(lvl maxCastTime minCastTime hp sp ap onAction inQueue notInQueue whenStatusActive whenStatusInactive
			whenFollowing spirit amuletType aggressives monsters notMonsters monstersCount monstersCountDist stopWhenHit inLockOnly
			notWhileSitting notInTown timeout disabled whenPartyMembersNear whenPartyMembersNearDist inInventory manualAI)],
	},
);
use constant SKILL_KIND_AUTO => 2;
use constant SKILL_VALUE_MAX => 60;

sub skillOptionAllowed {
	my ($kind, $key) = @_;
	return scalar grep { $_ eq $key } @{$SKILL_KINDS[$kind]{options}};
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

# "ID tipo achada alcance alvo" e as opcoes conhecidas do bloco; alcance e alvo a janela usa no teste
sub sendSkill {
	my ($idn, $kind) = @_;
	my (undef, @lines) = readConfig();
	my $block = findSkillBlock(\@lines, $idn, $kind);
	my $skill = eval { Skill->new(idn => $idn) };
	my $range = $skill ? int(($skill->getRange // 0) + 0.5) : 0;
	my $target = $skill ? ($skill->getTargetType // 0) : 0;
	my @text = (join(' ', $idn, $kind, $block ? 1 : 0, $range, $target));
	if ($block) {
		foreach my $key (@{$SKILL_KINDS[$kind]{options}}) {
			my $value = $block->{conditions}{$key};
			push @text, "$key " . encode('cp1252', $value) if defined $value && $value ne '';
		}
	}
	sendToClient(SKILL . join("\n", @text));
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

# "ID tipo" e linhas "opcao valor" da DLL -> bloco do tipo no config.txt; devolve (ID, tipo) pra responder.
# Tipo 2 (habilidade nova na barra): cria o bloco do tipo que combina com o alvo da habilidade, se ela ainda nao tem nenhum
sub applySkill {
	my ($body) = @_;
	my ($header, @option_lines) = split /\r?\n/, $body;
	my ($idn, $kind) = ($header // '') =~ /^(\d+) ([012])\s*$/ or return;

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
		@option_lines = ();
	}

	my $block_name = $SKILL_KINDS[$kind]{block};
	my $block = findSkillBlock(\@lines, $idn, $kind);
	my @text = $block ? @lines[$block->{first} .. $block->{last}] : ("$block_name $name {", '}');
	my $changed = !$block;
	my @changes;
	foreach my $line (@option_lines) {
		my ($key, $value) = $line =~ /^([A-Za-z_]+)(?: (.*))?$/ or next;
		next unless skillOptionAllowed($kind, $key);
		$value = decode('cp1252', $value // '');
		$value =~ s/[{}#\t]//g;
		$value =~ s/^\s+|\s+$//g;
		$value = substr($value, 0, SKILL_VALUE_MAX);
		my $current = $block ? $block->{conditions}{$key} : undef;
		$current = '' unless defined $current;
		$current =~ s/^\s+|\s+$//g;
		next if $current eq $value;
		$changed = 1;
		push @changes, $value eq '' ? "-$key" : "$key $value";
		if ($value ne '') {
			setBlockOption(\@text, $key, $value);
		} else {
			removeBlockOption(\@text, $key);
		}
	}
	return ($idn, $kind) unless $changed;

	# Bloco existente: no mesmo lugar (e com a linha em branco que vinha depois); novo: depois do ultimo do tipo
	my @slots = configBlocks(\@lines, $block_name);
	my $blank_after = $block && defined $lines[$block->{last} + 1] && $lines[$block->{last} + 1] =~ /^\s*$/;
	my @insert = $block ? ($blank_after ? (@text, '') : @text) : ('', @text);
	my $at = $block ? $block->{first} : @slots ? $slots[-1]{last} + 1 : scalar @lines;
	writeConfigLines($path, replaceBlocks(\@lines, $block ? [$block] : [], $at, @insert)) or return ($idn, $kind);

	message sprintf("[GordoKore] %s %s: %s\n", $block_name, $name, @changes ? join(', ', @changes) : 'criado'), 'success';
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
# Estado da IA (janela Situacao do GordoKore)
# ---------------------------------------------------------------------------

my $lastAiState = '';

# Manda so quando muda (o laco principal roda o tempo todo); $force responde ao pedido da DLL
sub sendAiState {
	my ($force) = @_;
	my $state = AI::state() . ' ' . (AI::action() // '');
	return if !$force && $state eq $lastAiState;
	return unless clientAlive();
	$lastAiState = $state;
	sendToClient(AI_STATE . $state);
}

sub onMainLoop {
	sendAiState(0);
	flushPortals();
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
	} elsif ($tag eq NAVI_STEP) {
		return unless defined $naviFollow;
		my @plan;
		for (split /\n/, substr($msg, 4)) {
			my ($kind, $map, $x, $y, $dest) = /^([WNF]) ([\w@.-]+) (-?\d+) (-?\d+)(?: ([\w@.-]+))?$/ or next;
			push @plan, { kind => $kind, map => $map, x => $x, y => $y, dest => $dest };
		}
		unless (@plan) {
			warning "[GordoKore] Setas do navi: plano da DLL sem pontos validos\n";
			return;
		}
		$naviPlan = \@plan;
		message "[GordoKore] Setas do navi: rota com " . scalar(@plan) . " ponto(s), " . join(', ', map { "$_->{kind} $_->{map}" } @plan) . "\n", 'info';
		applyNaviPlan();
	} elsif ($tag eq PORTALS) {
		push @portalsLines, split /\n/, substr($msg, 4);
	} elsif ($tag eq PORTALS_END) {
		push @portalsLines, split /\n/, substr($msg, 4);
		importPortals();
	} elsif ($tag eq AI_QUERY) {
		sendAiState(1);
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
		sendMonsters(); # a janela de monstros mostra o mapa de trabalho
	} elsif ($tag eq ITEMS) {
		applyItems(substr($msg, 4));
		sendItems();
	} elsif ($tag eq NAVI) {
		my ($map, $x, $y) = split ' ', substr($msg, 4);
		return unless defined $map && $map =~ /^[\w@-]+$/; # vira comando do console: so nome de mapa
		my $target = (defined $y && $x =~ /^\d+$/ && $y =~ /^\d+$/) ? "$map $x $y" : $map;
		message "[GordoKore] /navi: $target\n", 'info';
		$naviTarget = $map; # sem rota no OpenKore: onRouteFail passa para as setas do jogo
		undef $naviFollow;
		undef $naviPlan;
		undef $naviApplied;
		endNaviTalk();
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
	} elsif ($tag eq COMMAND) {
		# Campo "Enviar comando" da janela de IA e modulos do SDK (DLLs do proprio usuario): comando livre, uma linha
		my $command = substr($msg, 4);
		return unless length $command && $command !~ /[\r\n]/;
		message "[GordoKore] $command\n", 'info';
		Commands::run($command);
	}
}

1;
