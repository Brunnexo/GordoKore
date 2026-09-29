# stepMacro - grava ações do jogador num arquivo texto portável e reproduz depois.
#
# Comandos:
#   stepmacro rec <nome>    inicia a gravação
#   stepmacro stoprec       para a gravação e salva control/actions/<nome>.txt
#   stepmacro start <nome>  reproduz um arquivo gravado
#   stepmacro stop          aborta a reprodução
#
# No XKore 1 padrão, pacotes que o *cliente* manda pro servidor nunca passam
# pelo processo do próprio OpenKore - só os pacotes que o OpenKore mesmo manda
# passam. Por isso a maior parte da gravação funciona observando as RESPOSTAS
# DO SERVIDOR (que sempre passam pelo OpenKore) e inferindo o que o jogador
# deve ter feito:
#   - Commands::run/pre : comandos digitados no console/macro (buy, sell, store, a)
#   - configModify      : mudanças de configuração via console ou GUI
#   - packet_useitem, packet_charStats, packet/skill_update : confirmação do
#     servidor de que um item foi usado / um ponto de atributo ou skill foi gasto
#   - Network::clientSend/observed com 'actor_action' (ataque real de clique,
#     via DLL como o Kore-Bridge - ver mais abaixo): grava "atkid <nameID>",
#     usando o ID da espécie do monstro (estável), não o ID de instância (que
#     muda a cada spawn). O comando 'atkid' (registrado por este plugin) acha
#     o monstro certo na tela pelo nameID e ataca na reprodução.
#   - npc_talk, packet/npc_talk_continue, packet/npc_talk_responses,
#     packet/npc_talk_number, packet/npc_talk_text, npc_talk_done : o próprio
#     fluxo do diálogo do NPC. Isso mostra quando um "continuar" foi necessário,
#     quando um menu/número/texto foi pedido etc, mas NÃO qual item de menu,
#     número ou texto o jogador realmente mandou - essa parte é gravada como um
#     placeholder pra preencher manualmente.
#
# Se a DLL injetada encaminhar os pacotes de saída do próprio cliente
# (Kore-Bridge com seu frame 'C', ligado ao hook 'Network::clientSend/observed'
# aqui), a opção de menu/número/texto exata é decodificada dali e o placeholder
# é preenchido automaticamente - ver onClientSendObserved(). Isso é best-effort:
# se o cliente embaralhar os bytes de saída antes de chegarem no socket (ver o
# README do Kore-Bridge), a decodificação falha silenciosamente e o placeholder
# fica pra edição manual, igual sem a mudança na DLL.
#
# Formato do arquivo: um comando do OpenKore por linha, '#' inicia comentário.
# O arquivo pode ser copiado pra qualquer outra instância do OpenKore e editado à mão.

package stepMacro;

use strict;
use Plugins;
use Settings;
use Globals;
use Utils;
use Misc;
use Network;
use Network::PacketParser qw(STATUS_STR STATUS_AGI STATUS_VIT STATUS_INT STATUS_DEX STATUS_LUK ACTION_ATTACK);
use I18N qw(bytesToString);
use Log qw(message error warning);
use Translation qw/T TF/;

use constant STEP_DELAY => 0.7; # segundos mínimos entre linhas reproduzidas

# Comandos de console que valem a pena gravar como estão (só quando digitados
# no console/macro - clicar na janela correspondente do jogo NÃO é capturado aqui).
my %recordable = (
	buy   => sub { $_[0] =~ /\d/ },
	sell  => sub { $_[0] =~ /^(?:\d|done)/ },
	store => sub { $_[0] =~ /\S/ },
);

my %statusName = (
	STATUS_STR() => 'str', STATUS_AGI() => 'agi', STATUS_VIT() => 'vit',
	STATUS_INT() => 'int', STATUS_DEX() => 'dex', STATUS_LUK() => 'luk',
);

my ($recName, @recLines, %pendingTalk);
my ($playName, @playLines, $nextTime);

Plugins::register('stepMacro', 'records and replays player actions', \&Unload);
my $hooks = Plugins::addHooks(
	['Commands::run/pre',        \&onCommand,      undef],
	['configModify',             \&onConfigModify, undef],
	['packet_useitem',           \&onItemUsed,     undef],
	['packet_charStats',         \&onStatAdded,    undef],
	['packet/skill_update',      \&onSkillAdded,   undef],
	['npc_talk',                 \&onTalkStart,    undef],
	['packet/npc_talk_continue', \&onTalkStep,     'c'],
	['npc_talk_responses',       \&onTalkChoice,   undef],
	['packet/npc_talk_number',   \&onTalkStep,     'd?'],
	['packet/npc_talk_text',     \&onTalkStep,     't="?"'],
	['npc_store_begin',          \&onTalkStep,     'b'],
	['npc_talk_done',            \&onTalkDone,     undef],
	['Network::clientSend/observed', \&onClientSendObserved, undef],
	['mainLoop_pre',             \&onLoop,         undef],
);
my $chooks = Commands::register(
	['stepmacro', 'record/replay player actions', \&cmdStepMacro],
	['atkid', 'attack the nearest monster with the given nameID', \&cmdAttackByNameID],
);

sub Unload {
	Plugins::delHooks($hooks);
	Commands::unregister($chooks);
}

sub addLine {
	my $line = shift;
	push @recLines, $line;
	message TF("[stepMacro] recorded: %s\n", $line), 'success';
}

# nameID é o ID da espécie do monstro (ex.: Poring = 1002) - estável entre
# sessões, ao contrário do ID de instância (GID), que muda a cada spawn.
sub findMonsterByNameID {
	my $nameID = shift;
	for my $m (@$monstersList) {
		return $m if defined $m->{nameID} && $m->{nameID} == $nameID;
	}
	return;
}

# Grava um ataque como "atkid <nameID>", com um comentário legível acima.
sub addAttackLine {
	my $monster = shift;
	addLine("# ataca: $monster->{name} ($monster->{nameID})");
	addLine("atkid $monster->{nameID}");
}

sub cmdAttackByNameID {
	my (undef, $args) = @_;
	my ($nameID) = defined($args) ? $args =~ /^(\d+)/ : ();
	if (!defined $nameID) {
		error T("Usage: atkid <nameID>\n");
		return;
	}
	my $monster = findMonsterByNameID($nameID);
	if (!$monster) {
		error TF("[stepMacro] nenhum monstro com nameID %s por perto\n", $nameID);
		return;
	}
	main::attack($monster->{ID});
}

sub flushTalk {
	return unless %pendingTalk;
	my $steps = join(' ', @{$pendingTalk{steps}});
	addLine("move $pendingTalk{map} $pendingTalk{x} $pendingTalk{y}") if $pendingTalk{map};
	addLine("# $_") for @{$pendingTalk{notes}};
	addLine("talknpc $pendingTalk{x} $pendingTalk{y}" . ($steps ne '' ? " $steps" : ''));
	%pendingTalk = ();
}

# Servidor abriu/continuou um diálogo. O primeiro inicia a gravação; os
# seguintes são só novas páginas de texto e não precisam de passo próprio
# (o passo já foi gravado por quem disparou *_continue/_responses/etc).
sub onTalkStart {
	my (undef, $args) = @_;
	return unless defined $recName && !defined $playName;
	return if %pendingTalk;
	my $npc = $npcsList->getByID($args->{ID});
	%pendingTalk = (
		map   => ($field ? $field->baseName : ''),
		x     => $npc ? $npc->{pos}{x} : 0,
		y     => $npc ? $npc->{pos}{y} : 0,
		steps => [],
		notes => [],
	);
}

# Genérico: "o servidor pediu algo, aqui está o passo do talknpc pra isso".
# $step é texto fixo (vindo do registro do hook acima), exceto no caso do menu,
# tratado à parte em onTalkChoice porque precisa da lista de opções.
sub onTalkStep {
	my (undef, $args, $step) = @_;
	return unless defined $recName && !defined $playName && %pendingTalk;
	push @{$pendingTalk{notes}}, "FIXME: fill in the value the NPC asked for ($step)" if $step =~ /\?/;
	push @{$pendingTalk{steps}}, $step;
}

# Servidor mostrou um menu. Não dá pra ver qual opção o jogador escolheu (isso
# é um pacote que o cliente manda, invisível pro OpenKore aqui), então grava as
# opções como comentário e deixa um passo placeholder pra preencher à mão.
sub onTalkChoice {
	my (undef, $args) = @_;
	return unless defined $recName && !defined $playName && %pendingTalk;
	my @options = @{$args->{responses} || []};
	$pendingTalk{lastMenuCount} = @options - 1; # opções reais, sem contar o "Cancelar Conversa" auto-adicionado
	push @{$pendingTalk{notes}},
		"FIXME: replace the r? below with the option actually picked (r0.." . (@options - 2) . "): "
		. join(' | ', map { "r$_=$options[$_]" } 0 .. $#options - 1) . " | r" . (@options - 1) . "=Cancel Chat";
	push @{$pendingTalk{steps}}, 'r?';
}

sub onTalkDone {
	flushTalk() if defined $recName;
}

# Substitui o último passo do talknpc ainda não resolvido (r?/d?/t="?") pelo
# valor real, e remove a nota FIXME que pedia por ele - chamada só quando a
# gente realmente decodifica o pacote do próprio cliente (ver onClientSendObserved).
sub resolveLastStep {
	my $value = shift;
	return unless %pendingTalk && @{$pendingTalk{steps}} && $pendingTalk{steps}[-1] =~ /\?/;
	$pendingTalk{steps}[-1] = $value;
	pop @{$pendingTalk{notes}} if @{$pendingTalk{notes}} && $pendingTalk{notes}[-1] =~ /^FIXME/;
	message TF("[stepMacro] resolved from the real client packet: %s\n", $value), 'success';
}

# Dispara pra pacotes que o próprio cliente do jogo mandou, encaminhados por
# uma DLL como o Kore-Bridge via seu frame 'C' (src/Network/XKore.pm transforma
# isso nesse hook). Usado só pra preencher a resposta/número/texto exatos do
# npc talk que os hooks do lado do servidor acima não conseguem ver. Se o
# opcode não bater com nada na tabela do $messageSender, o cliente
# provavelmente embaralha os bytes de saída antes de chegarem no socket (ver o
# README do Kore-Bridge) - a gente só ignora silenciosamente e deixa o
# placeholder pra edição manual.
sub onClientSendObserved {
	my (undef, $args) = @_;
	return unless defined $recName && !defined $playName;
	my $msg = $args->{msg};
	return unless $messageSender && defined $msg && length($msg) >= 2;

	my $hex = uc(unpack("H2", substr($msg, 1, 1))) . uc(unpack("H2", substr($msg, 0, 1)));
	my $entry = $messageSender->{packet_list}{$hex} or return;
	my ($name, $packString, $varNames) = @$entry;
	my %f;
	@f{@$varNames} = unpack("x2 $packString", $msg) if $packString;

	if ($name eq 'actor_action' && defined $f{type} && $f{type} == ACTION_ATTACK) {
		my $monster = $monstersList && $monstersList->getByID($f{targetID});
		addAttackLine($monster) if $monster && defined $monster->{nameID};
		return;
	}

	return unless %pendingTalk;
	if ($name eq 'npc_talk_response' && defined $pendingTalk{lastMenuCount}) {
		my $choice = $f{response} - 1;
		if ($choice >= 0 && $choice < $pendingTalk{lastMenuCount}) {
			resolveLastStep("r$choice");
		} else {
			warning TF("[stepMacro] npc_talk_response out of range (raw=%s, max=%s) - left as placeholder\n",
				$f{response}, $pendingTalk{lastMenuCount});
		}
	} elsif ($name eq 'npc_talk_number') {
		resolveLastStep("d$f{value}");
	} elsif ($name eq 'npc_talk_text') {
		(my $text = bytesToString($f{text})) =~ s/"/'/g;
		resolveLastStep(qq{t="$text"});
	}
}

sub onItemUsed {
	my (undef, $args) = @_;
	return unless defined $recName && !defined $playName;
	return unless $args->{success} && $args->{userID} eq $accountID && $args->{item};
	addLine("is " . $args->{item}{name});
}

sub onStatAdded {
	my (undef, $args) = @_;
	return unless defined $recName && !defined $playName;
	my $stat = $statusName{$args->{type}} or return;
	addLine("stat_add $stat");
}

sub onSkillAdded {
	my (undef, $args) = @_;
	return unless defined $recName && !defined $playName;
	addLine("skills add $args->{ID}");
}

sub onConfigModify {
	my (undef, $args) = @_;
	return unless defined $recName;
	my $val = defined $args->{val} ? $args->{val} : '';
	addLine("conf $args->{key} $val");
}

sub onCommand {
	my (undef, $args) = @_;
	return unless defined $recName && !defined $playName;

	# 'a <binID>' (ataque digitado) - o binID é só um índice temporário na
	# lista de monstros na tela, então traduz pro nameID (estável) antes de gravar.
	if ($args->{switch} eq 'a') {
		my ($binID) = defined($args->{args}) ? $args->{args} =~ /^(\d+)$/ : ();
		return unless defined $binID;
		my $ID = $monstersID[$binID];
		return unless defined $ID && $ID ne '';
		my $monster = $monstersList && $monstersList->getByID($ID);
		addAttackLine($monster) if $monster && defined $monster->{nameID};
		return;
	}

	my $filter = $recordable{$args->{switch}} or return;
	my $line = $args->{args};
	$line = '' unless defined $line;
	$line =~ s/^\s+|\s+$//g;
	$filter->($line) or return;
	addLine("$args->{switch} $line" =~ s/\s+$//r);
}

sub filePath {
	my $name = shift;
	return unless defined $name && $name =~ /^[\w\-.]+$/ && $name !~ /^\.+$/;
	$name .= '.txt' unless $name =~ /\.txt$/i;
	my $dir = ((Settings::getControlFolders())[0] || 'control') . '/actions';
	return ($dir, "$dir/$name");
}

sub cmdStepMacro {
	my (undef, $args) = @_;
	$args = '' unless defined $args;
	my ($sub, $rest) = split(/\s+/, $args, 2);
	$sub = '' unless defined $sub;

	if ($sub eq 'rec') {
		cmdRec($rest);
	} elsif ($sub eq 'stoprec') {
		cmdStopRec();
	} elsif ($sub eq 'start') {
		cmdStart($rest);
	} elsif ($sub eq 'stop') {
		cmdStopAction();
	} else {
		error T("Usage: stepmacro rec <name> | stoprec | start <name> | stop\n");
	}
}

sub cmdRec {
	my ($name) = @_;
	if (defined $recName) {
		error T("[stepMacro] already recording, use 'stepmacro stoprec'\n");
	} elsif (defined $playName) {
		error T("[stepMacro] replay in progress, use 'stepmacro stop'\n");
	} elsif (!filePath($name)) {
		error T("Usage: stepmacro rec <name>\n");
	} else {
		($recName, @recLines) = ($name);
		%pendingTalk = ();
		message TF("[stepMacro] recording '%s'. Use 'stepmacro stoprec' to finish.\n", $name), 'success';
	}
}

sub cmdStopRec {
	if (!defined $recName) {
		error T("[stepMacro] not recording\n");
		return;
	}
	flushTalk();
	my ($dir, $path) = filePath($recName);
	mkdir $dir unless -d $dir;
	if (open my $fh, '>', $path) {
		print $fh "# stepMacro v1, recorded ", scalar(localtime), "\n", map { "$_\n" } @recLines;
		close $fh;
		message TF("[stepMacro] saved %d line(s) to %s\n", scalar(@recLines), $path), 'success';
	} else {
		error TF("[stepMacro] cannot write %s: %s\n", $path, $!);
	}
	undef $recName;
	@recLines = ();
}

sub cmdStart {
	my ($name) = @_;
	if (defined $recName) {
		error T("[stepMacro] recording in progress, use 'stepmacro stoprec'\n");
		return;
	}
	my (undef, $path) = filePath($name);
	if (!$path) {
		error T("Usage: stepmacro start <name>\n");
	} elsif (!open my $fh, '<', $path) {
		error TF("[stepMacro] cannot read %s: %s\n", $path, $!);
	} else {
		@playLines = grep { /\S/ && !/^\s*#/ } map { s/[\r\n]+$//r } <$fh>;
		close $fh;
		$playName = $name;
		$nextTime = 0;
		message TF("[stepMacro] replaying '%s' (%d step(s))\n", $name, scalar(@playLines)), 'success';
	}
}

sub cmdStopAction {
	if (defined $playName) {
		message T("[stepMacro] replay aborted\n"), 'success';
		undef $playName;
		@playLines = ();
	} else {
		error T("[stepMacro] nothing is being replayed\n");
	}
}

# Um passo de cada vez, só quando estiver no jogo, passado o delay e com a AI
# ociosa (tarefas de move/route/talknpc ficam na fila da AI até terminarem).
sub onLoop {
	return unless defined $playName;
	return unless $net && $net->getState() == Network::IN_GAME && $char;
	return if time < $nextTime || !AI::isIdle();
	my $line = shift @playLines;
	if (!defined $line) {
		message TF("[stepMacro] replay '%s' finished\n", $playName), 'success';
		undef $playName;
		return;
	}
	message TF("[stepMacro] step: %s\n", $line), 'success';
	Commands::run($line);
	$nextTime = time + STEP_DELAY;
}

1;
