#########################################################################
# infiniteSpace
#
# Automatiza Espaço Infinito una vez que el personaje ya está en 1@infi.
# No crea la instancia ni habla con la Arqueóloga exterior.
# Automatiza o Espaço Infinito quando o personagem já está em 1@infi.
# Não cria a instância nem fala com a Arqueóloga de fora.
#
# Los textos de consola y del registro salen en español | português.
# Os textos do console e do registro saem em espanhol | português.
#
# Configuración opcional / Configuração opcional:
#   infiniteSpace_enabled        1
#   infiniteSpace_difficulty     hard
#   infiniteSpace_exit           1
#   infiniteSpace_roomTimeout    900
#   infiniteSpace_actionTimeout  20
#   infiniteSpace_chestDelay     8
#   infiniteSpace_weight         90
#   infiniteSpace_dryRun         0
#
# Comandos / Comandos: infi on|off|status|reset
#########################################################################
package infiniteSpace;

BEGIN {
	require File::Basename;
	unshift @INC, File::Basename::dirname(__FILE__);
}

use strict;
use utf8;
use Route;
use Plugins;
use Commands;
use AI;
use Network;
use Settings;
use Time::HiRes qw(time);
use POSIX qw(strftime);
use File::Path qw(make_path);
use Globals qw($char $field $net $npcsList $portalsList $monstersList $itemsList %config %pickupitems);
use Utils::PathFinding;
use Misc qw(percent_weight mon_control);
use Log qw(message warning error);

Plugins::register(
	'infiniteSpace',
	'Automatiza las 50 salas de Espaco Infinito desde 1@infi | Automatiza as 50 salas do Espaco Infinito a partir de 1@infi',
	\&on_unload,
);

my $hooks = Plugins::addHooks(
	['in_game',                         \&on_in_game],
	['Network::Receive::map_changed',   \&on_map_changed],
	['portal_exist',                    \&on_actor_changed],
	['npc_exist',                       \&on_actor_changed],
	['packet/mvp_you',                  \&on_mvp],
	['packet/mvp_item',                 \&on_mvp_item],
	['self_died',                       \&on_death],
	['serverDisconnect/success',        \&on_disconnect],
	['mainLoop_post',                   \&on_loop],
	['configModify',                    \&on_config_modify],
	['post_configModify',               \&on_post_config_modify],
);

my $commands = Commands::register(
	['infi', 'Espaco Infinito | Espaço Infinito: infi on|off|status|reset', \&cmd_infi],
);

my $rooms = InfiniteSpace::Route::rooms();
my $enabled = config_bool('infiniteSpace_enabled', 1);
my $active = 0;
my $state = 'inactive';
my $room_index;
my $state_since = time;
my $room_since = time;
my $portal_seen_at;
my $mvp_seen = 0;
my $mvp_item_seen = 0;
my $chest_claimed = 0;
my $action_attempts = 0;
my $last_action = '';
my $last_status = '';
my $initial_talk_done = 0;
my $clear_since;
my $scan_step = 0;
my $last_scan = 0;
my $last_block_log = 0;
my %seen_in_room;
my %companions;
my %hunt_started;
my %ghosts;
my %near_since;
my $last_hunt = 0;
my $chest_idle_since;
my %sweep_cache;
my %instance_loot;
my %loot_tries;
my $last_loot = 0;
my $sweep_required = 0;
my $portal_idle_since;
%instance_loot = map { $_ => 1 } instance_loot_ids();
my %saved_config;
my $saved_pickup_full;
my $pickup_replaced = 0;
my $config_guard_active = 0;

sub on_unload {
	restore_instance_config();
	Plugins::delHooks($hooks);
	Commands::unregister($commands) if $commands;
	write_log(espt('plugin descargado', 'plugin descarregado'));
}

sub config_value {
	my ($key, $default) = @_;
	return (defined $config{$key} && $config{$key} ne '') ? $config{$key} : $default;
}

sub config_bool {
	my ($key, $default) = @_;
	my $value = config_value($key, $default);
	return $value ? 1 : 0;
}

sub is_instance {
	return $field && defined $field->baseName && $field->baseName eq '1@infi';
}

sub current_pos {
	return unless $char && $char->{pos_to};
	return ($char->{pos_to}{x}, $char->{pos_to}{y});
}

sub room {
	return unless defined $room_index;
	return $rooms->[$room_index];
}

sub room_label {
	return '-' unless defined $room_index;
	my $r = room();
	return sprintf('%d/50 (%s %d%s)', $r->{number}, espt('bloque', 'bloco'), $r->{block}, $r->{boss} ? ', MVP' : '');
}

sub set_state {
	my ($new_state, $reason) = @_;
	return if $state eq $new_state && (!defined $reason || $reason eq '');
	$state = $new_state;
	$state_since = time;
	$last_status = $reason || '';
	write_log("estado=$state sala=" . room_label() . ($reason ? " motivo=$reason" : ''));
}

sub write_log {
	my ($text) = @_;
	make_path('instancias') unless -d 'instancias';
	if (open(my $fh, '>>:utf8', 'instancias/infiniteSpace.log')) {
		print $fh '[' . strftime('%Y-%m-%d %H:%M:%S', localtime) . "] $text\n";
		close $fh;
	}
}

sub announce {
	my ($text, $domain) = @_;
	$domain ||= 'info';
	message "[InfiniteSpace] $text\n", $domain;
	write_log($text);
}

sub espt {
	my ($es, $pt) = @_;
	return "$es | $pt";
}

sub reset_room_state {
	$portal_seen_at = undef;
	$mvp_seen = 0;
	$mvp_item_seen = 0;
	$chest_claimed = 0;
	$action_attempts = 0;
	$last_action = '';
	$clear_since = undef;
	$scan_step = 0;
	$chest_idle_since = undef;
	$sweep_required = 0;
	$portal_idle_since = undef;
	%loot_tries = ();
	$room_since = time;
}

sub recover_room {
	return unless is_instance() && $char;
	my ($x, $y) = current_pos();
	my $found = InfiniteSpace::Route::room_for_position($x, $y);
	return unless defined $found;

	my $changed = !defined($room_index) || $found != $room_index;
	if ($changed && defined $room_index) {
		# Un mob nuevo nunca conserva el ID de actor de la sala anterior:
		# si cruza el portal con nosotros es un acompañante, no un mob de la sala.
		$companions{$_} = 1 for keys %seen_in_room;
	}
	%seen_in_room = () if $changed;
	if ($changed) {
		%hunt_started = ();
		%ghosts = ();
		%near_since = ();
	}
	$room_index = $found;
	reset_room_state() if $changed;
	$initial_talk_done = 1 if $room_index > 0 || has_real_monsters() || expected_portal_present();
	set_state('combat', espt("recuperada desde $x,$y", "recuperada a partir de $x,$y")) if $state eq 'inactive' || $state eq 'entering' || $changed;
	announce(espt('Sala ' . room_label() . " detectada en $x,$y", 'Sala ' . room_label() . " detectada em $x,$y"), 'success') if $changed;
}

sub activate {
	return unless $enabled && is_instance();
	%companions = () unless $active;
	$active = 1;
	apply_instance_config();
	AI::state(AI::AUTO) if AI::state() != AI::AUTO;
	recover_room();
	if (defined $room_index && $room_index == 0 && !$initial_talk_done
		&& !has_real_monsters() && !expected_portal_present()) {
		set_state('initial_wait', espt('esperando NPC de dificultad', 'aguardando NPC de dificuldade'));
	}
}

sub stop_automation {
	my ($reason) = @_;
	$active = 0;
	set_state('stopped', $reason);
	AI::clear(qw/move route mapRoute NPC/);
	AI::state(AI::MANUAL) if AI::state() != AI::MANUAL;
	restore_instance_config();
	warning "[InfiniteSpace] " . espt('DETENIDO', 'PARADO') . ": $reason. " . espt('Control manual habilitado', 'Controle manual habilitado') . ".\n";
	write_log(espt('DETENIDO', 'PARADO') . ": $reason");
}

sub complete {
	$active = 0;
	set_state('completed', espt('salida confirmada', 'saída confirmada'));
	restore_instance_config();
	announce(espt(
		'Instancia terminada; salida a ' . ($field ? $field->baseName : '?'),
		'Instância terminada; saída para ' . ($field ? $field->baseName : '?'),
	), 'success');
}

sub at_least {
	my ($key, $min) = @_;
	my $value = $config{$key};
	return (defined $value && $value =~ /^\d+$/ && $value > $min) ? $value : $min;
}

sub instance_config {
	my %temporary = (
		lockMap                     => '1@infi',
		route_randomWalk            => 0,
		attackAuto                  => at_least('attackAuto', 2),
		attackMaxDistance           => at_least('attackMaxDistance', 2),
		attackRouteMaxPathDistance  => at_least('attackRouteMaxPathDistance', 20),
		attackMaxRouteTime          => at_least('attackMaxRouteTime', 6),
		attackAuto_inLockOnly       => 0,
		attackAuto_onlyWhenSafe     => 0,
		attackChangeTarget          => 0,
		attackNoGiveup              => 1,
		teleportAuto_hp             => 0,
		teleportAuto_sp             => 0,
		teleportAuto_portal         => 0,
		teleportAuto_idle           => 0,
		teleportAuto_search         => 0,
		teleportAuto_dropTarget     => 0,
		teleportAuto_dropTargetKS   => 0,
		teleportAuto_dropTargetHidden => 0,
		teleportAuto_lostTarget     => 0,
		teleportAuto_unstuck        => 0,
		teleportAuto_deadly         => 0,
		teleportAuto_maxDmg         => 0,
		teleportAuto_maxDmgInLock   => 0,
		teleportAuto_totalDmg       => 0,
		teleportAuto_totalDmgInLock => 0,
		teleportAuto_minAggressives => 0,
		teleportAuto_minAggressivesInLock => 0,
		teleportAuto_atkCount       => 0,
		teleportAuto_atkMiss        => 0,
		teleportAuto_useSkill       => 0,
		route_escape_reachedNoPortal => 0,
		route_escape_randomWalk     => 0,
		portalRecord                => 0,
		portalRecord_recompileAfter => 0,
		storageAuto                 => 0,
		sellAuto                    => 0,
		buyAuto_0                   => '',
	);
	# infiniteSpace_set_<clave> <valor> en config.txt añade o pisa claves.
	for my $key (keys %config) {
		next unless $key =~ /^infiniteSpace_set_(.+)$/;
		$temporary{$1} = $config{$key};
	}
	return %temporary;
}

sub snapshot_file {
	my $profile = 'default';
	my $file = eval { Settings::getConfigFilename() } || '';
	$profile = $1 if $file =~ /[\\\/]([^\\\/]+)[\\\/]config\.txt$/i;
	return "instancias/estado/$profile.config_previo.txt";
}

sub write_snapshot {
	make_path('instancias/estado') unless -d 'instancias/estado';
	my $file = snapshot_file();
	open(my $fh, '>:utf8', $file) or return;
	print $fh "# Valores originales antes de entrar a 1\@infi. Se restauran solos al salir.\n";
	print $fh "# Valores originais antes de entrar em 1\@infi. São restaurados sozinhos ao sair.\n";
	for my $key (sort keys %saved_config) {
		my $saved = $saved_config{$key};
		print $fh $key . ' ' . ($saved->{exists} ? (defined $saved->{value} ? $saved->{value} : '') : '<no existía>') . "\n";
	}
	close $fh;
}

sub apply_instance_config {
	return if $config_guard_active;
	my %temporary = instance_config();
	for my $key (keys %temporary) {
		$saved_config{$key} = {
			exists => exists $config{$key},
			value  => $config{$key},
		};
		$config{$key} = $temporary{$key};
	}
	$config_guard_active = 1;
	apply_instance_pickup();
	write_snapshot();
	my $dump = join(', ', map { "$_=$temporary{$_}" } sort keys %temporary);
	write_log(espt(
		"config temporal aplicado ($dump); copia en " . snapshot_file(),
		"config temporária aplicada ($dump); cópia em " . snapshot_file(),
	));
}

sub restore_instance_config {
	return unless $config_guard_active;
	for my $key (keys %saved_config) {
		if ($saved_config{$key}{exists}) {
			$config{$key} = $saved_config{$key}{value};
		} else {
			delete $config{$key};
		}
	}
	%saved_config = ();
	restore_instance_pickup();
	$config_guard_active = 0;
	unlink snapshot_file();
	write_log(espt('config original restaurado', 'config original restaurada'));
}

# configModify guarda TODO %config en config.txt. Si algo lo llama durante la
# instancia, se reescribe el archivo con los valores originales.
sub instance_loot_ids {
	return (
		6905, 968, 18128, 28703, 603, 607, 730, 1000, 1029,
		4642, 4643, 4644, 4645, 4647, 4648, 4649, 4650, 4651,
		4121, 4123, 4131, 4132, 4134, 4135, 4137, 4140, 4142, 4143,
		4144, 4146, 4147, 4168, 4189, 4263, 4276, 4302, 4305, 4318, 4324,
	);
}

sub apply_instance_pickup {
	return if $pickup_replaced;
	$saved_pickup_full = { %pickupitems };
	%pickupitems = (all => 0);
	$pickupitems{$_} = 2 for instance_loot_ids();
	%instance_loot = map { $_ => 1 } instance_loot_ids();
	$pickup_replaced = 1;
	write_log(espt(
		'pickup de la instancia en memoria: solo loot listado, all 0',
		'pickup da instância em memória: só o loot listado, all 0',
	));
}

sub restore_instance_pickup {
	return unless $pickup_replaced;
	%pickupitems = %{ $saved_pickup_full || {} };
	$saved_pickup_full = undef;
	$pickup_replaced = 0;
	write_log(espt('pickup original restaurado', 'pickup original restaurado'));
}

sub on_config_modify {
	my (undef, $args) = @_;
	return unless $config_guard_active && $args && defined $args->{key};
	my $key = $args->{key};
	return unless exists $saved_config{$key};
	$saved_config{$key} = { exists => 1, value => $args->{val} };
	write_log(espt(
		"el usuario cambió $key durante la instancia; se conserva al restaurar",
		"o usuário alterou $key durante a instância; será mantido ao restaurar",
	));
}

sub on_post_config_modify {
	return unless $config_guard_active;
	my %temporary;
	for my $key (keys %saved_config) {
		$temporary{$key} = { exists => exists $config{$key}, value => $config{$key} };
		if ($saved_config{$key}{exists}) {
			$config{$key} = $saved_config{$key}{value};
		} else {
			delete $config{$key};
		}
	}
	Misc::saveConfigFile();
	for my $key (keys %temporary) {
		if ($temporary{$key}{exists}) {
			$config{$key} = $temporary{$key}{value};
		} else {
			delete $config{$key};
		}
	}
}

sub on_in_game {
	activate() if $enabled && is_instance();
}

sub on_map_changed {
	if (is_instance()) {
		if (!$active && $enabled) {
			$state = 'entering';
			activate();
		} elsif ($active) {
			recover_room();
		}
		return;
	}

	if ($active) {
		if ($state eq 'final_exit' || $state eq 'exiting') {
			complete();
		} else {
			stop_automation(espt('salió inesperadamente de 1@infi', 'saiu inesperadamente de 1@infi'));
		}
	}
}

sub on_actor_changed {
	return unless $active && is_instance() && defined $room_index;
	if (expected_portal_present() && !defined $portal_seen_at) {
		$portal_seen_at = time;
		write_log(espt(
			'portal esperado visible en ' . join(',', @{room()->{exit}}),
			'portal esperado visível em ' . join(',', @{room()->{exit}}),
		));
	}
}

sub on_mvp {
	return unless $active && is_instance() && room() && room()->{boss};
	$mvp_seen = 1;
	# El servidor borra a los esclavos junto con el MVP sin avisar al cliente.
	my $count = 0;
	if ($monstersList) {
		for my $monster (@{$monstersList->getItems()}) {
			next unless $monster && $monster->{ID} && is_slave_leftover($monster);
			mark_ghost($monster, 'MVP');
			$count++;
		}
	}
	write_log(espt("MVP muerto: $count actores eliminados de la lista", "MVP morto: $count atores removidos da lista")) if $count;
	set_state('wait_chest', espt('MVP derrotado', 'MVP derrotado'));
	announce(espt(
		'MVP del bloque ' . room()->{block} . ' derrotado; esperando el cofre',
		'MVP do bloco ' . room()->{block} . ' derrotado; aguardando o baú',
	), 'success');
}

sub on_mvp_item {
	return unless $active && is_instance() && room() && room()->{boss};
	$mvp_item_seen = 1;
	write_log(espt('paquete MVP item recibido', 'pacote de item de MVP recebido'));
}

sub on_death {
	stop_automation(espt('el personaje murió', 'o personagem morreu')) if $active;
}

sub on_disconnect {
	if ($active) {
		write_log(espt(
			'desconexión; se intentará recuperar la sala al volver',
			'desconexão; a sala será recuperada ao voltar',
		));
		$active = 0;
		$state = 'inactive';
		restore_instance_config();
	}
}

sub expected_portal_present {
	my $r = room() or return 0;
	my ($x, $y) = @{$r->{exit}};
	return actor_at($portalsList, $x, $y) ? 1 : 0;
}

sub chest_present {
	my $r = room() or return 0;
	return 0 unless $r->{boss};
	my ($x, $y) = @{$r->{chest}};
	return actor_at($npcsList, $x, $y) ? 1 : 0;
}

sub exit_npc_present {
	return actor_at($npcsList, 366, 392) ? 1 : 0;
}

sub actor_at {
	my ($list, $x, $y) = @_;
	return unless $list;
	for my $actor (@{$list->getItems()}) {
		next unless $actor && $actor->{pos};
		return $actor if $actor->{pos}{x} == $x && $actor->{pos}{y} == $y;
	}
	return;
}

sub real_monsters {
	return () unless $monstersList;
	my @out;
	for my $monster (@{$monstersList->getItems()}) {
		next unless $monster && $monster->{pos};
		next if $monster->{dead};
		next if $companions{$monster->{ID}};
		next if is_ghost($monster);
		# attack_auto 0 son plantas u objetos que no bloquean el portal.
		# -1 del perfil apunta a IDs clásicos; los mobs de la instancia caen en "all".
		my $control = mon_control($monster->{name}, $monster->{nameID});
		next if $control && defined $control->{attack_auto} && $control->{attack_auto} == 0;
		push @out, $monster;
	}
	return @out;
}

sub has_real_monsters {
	return real_monsters() ? 1 : 0;
}

sub activity_mark {
	my ($monster) = @_;
	return join(':', $monster->{time_move} || 0,
		$monster->{dmgToYou} || 0, $monster->{missedYou} || 0,
		$monster->{dmgFromYou} || 0, $monster->{missedFromYou} || 0);
}

sub mark_ghost {
	my ($monster, $reason) = @_;
	return unless $monster && $monster->{ID};
	return if $ghosts{$monster->{ID}};
	$ghosts{$monster->{ID}} = 1;
	$monster->{ignore} = 1;
	$clear_since = undef;
	my $pos = $monster->{pos_to} || $monster->{pos} || {};
	my $label = ($monster->{name} || 'mob') . ':' . ($monster->{nameID} || 0)
		. '@' . ($pos->{x} // '?') . ',' . ($pos->{y} // '?');
	# El núcleo solo borra actores que se alejan más de clientSight. Uno que
	# el servidor elimina en el lugar queda en la lista para siempre, y
	# ai_getAggressives lo vuelve a elegir aunque tenga ignore.
	$monstersList->remove($monster) if $monstersList;
	cancel_attack($monster->{ID});
	write_log(espt(
		"actor eliminado de la lista ($reason): $label",
		"ator removido da lista ($reason): $label",
	));
}

sub cancel_attack {
	my ($id) = @_;
	return unless $id && AI::action() eq 'attack';
	my $args = AI::args();
	return unless $args && $args->{ID} && $args->{ID} eq $id;
	AI::clear(qw/attack route move/);
	$char->sendAttackStop if $char;
}

sub is_ghost {
	my ($monster) = @_;
	return $monster && $monster->{ID} && $ghosts{$monster->{ID}} ? 1 : 0;
}

sub remember_room_monsters {
	return unless $monstersList;
	my ($x, $y) = current_pos();
	for my $monster (@{$monstersList->getItems()}) {
		next unless $monster && $monster->{ID} && $monster->{pos};
		$seen_in_room{$monster->{ID}} = 1;
		next if is_golden_poring($monster);
		next if !defined $x || $ghosts{$monster->{ID}} || $companions{$monster->{ID}};
		# Los Megalith no caminan ni pegan de lejos. Solo los esclavos del MVP
		# ("Escravo") quedan en la lista después de morir.
		next unless is_slave_leftover($monster);

		my $id = $monster->{ID};
		my $pos = $monster->{pos_to} || $monster->{pos};
		my $d = abs($pos->{x} - $x);
		my $dy = abs($pos->{y} - $y);
		$d = $dy if $dy > $d;
		my $sight = config_value('infiniteSpace_ghostDistance', 14);
		my $mark = activity_mark($monster);
		if ($d > $sight || !$near_since{$id} || $near_since{$id}{mark} ne $mark) {
			$near_since{$id} = $d <= $sight ? { time => time, mark => $mark } : undef;
			next;
		}
		next if time - $near_since{$id}{time} < config_value('infiniteSpace_ghostTime', 4);
		mark_ghost($monster, espt("sin actividad a $d celdas", "sem atividade a $d células"));
	}
}

# Acompañante en la primera sala: lo perseguimos 25 s, siempre a 3 celdas o
# menos, y nunca recibió daño nuestro.
sub check_unhittable {
	my ($monster) = @_;
	my $id = $monster->{ID};
	$hunt_started{$id} ||= time;
	return 0 if time - $hunt_started{$id} < 25;
	return 0 if $monster->{dmgFromYou} || $monster->{missedFromYou}
		|| $monster->{dmgToYou} || $monster->{missedYou};
	my ($x, $y) = current_pos();
	return 0 unless defined $x;
	my $d = abs($monster->{pos}{x} - $x) + abs($monster->{pos}{y} - $y);
	return 0 if $d > 3;
	$companions{$id} = 1;
	write_log(espt(
		'ignorado como acompañante: ' . ($monster->{name} || 'mob') . ':' . ($monster->{nameID} || 0),
		'ignorado como acompanhante: ' . ($monster->{name} || 'mob') . ':' . ($monster->{nameID} || 0),
	));
	return 1;
}

sub is_slave_leftover {
	my ($monster) = @_;
	my $name = $monster && $monster->{name} ? $monster->{name} : '';
	return $name =~ /escrav/i ? 1 : 0;
}

sub is_golden_poring {
	my ($monster) = @_;
	my $name = $monster && $monster->{name} ? $monster->{name} : '';
	return $name =~ /poring\s+de\s+ouro|golden\s+poring|gold\s+poring|poring\s+dourado/i ? 1 : 0;
}

sub golden_poring {
	my ($x, $y) = current_pos();
	my ($best, $best_d);
	for my $monster (real_monsters()) {
		next unless is_golden_poring($monster);
		my $d = 0;
		if (defined $x) {
			$d = abs($monster->{pos}{x} - $x) + abs($monster->{pos}{y} - $y);
		}
		if (!defined $best_d || $d < $best_d) {
			$best = $monster;
			$best_d = $d;
		}
	}
	return $best;
}

sub nearest_real_monster {
	my $golden = golden_poring();
	return $golden if $golden;
	my ($x, $y) = current_pos();
	return unless defined $x;
	my ($best, $best_d);
	for my $monster (real_monsters()) {
		my $d = abs($monster->{pos}{x} - $x) + abs($monster->{pos}{y} - $y);
		if (!defined $best_d || $d < $best_d) {
			$best = $monster;
			$best_d = $d;
		}
	}
	return $best;
}

# El Poring de Ouro huye. Mientras esté en pantalla se suelta el objetivo
# actual, el portal y el cofre, y se lo persigue hasta matarlo.
sub engage_golden {
	my $monster = golden_poring() or return 0;
	my $id = $monster->{ID};
	if (AI::action() eq 'attack') {
		my $args = AI::args();
		return 1 if $args && $args->{ID} && $args->{ID} eq $id;
	}
	return 1 if AI::action() eq 'route' && ($last_action || '') =~ /^prioridad /;
	return 1 if time - $last_hunt < 0.5 && ($last_action || '') =~ /Poring de Ouro|Golden Poring|Poring Dourado/i;
	$last_hunt = time;
	my $pos = $monster->{pos_to} || $monster->{pos};
	my ($x, $y) = ($pos->{x}, $pos->{y});
	my $label = ($monster->{name} || 'Poring de Ouro') . ':' . ($monster->{nameID} || 0) . " en $x,$y";
	if (dry_run()) {
		announce(espt("SIMULACIÓN: prioridad $label", "SIMULAÇÃO: prioridade $label"));
		return 1;
	}
	my $failed = $monster->{attack_failedLOS} || $monster->{attack_failed};
	AI::clear(qw/attack route move mapRoute NPC/);
	$char->sendAttackStop if $char;
	delete $monster->{attack_failedLOS};
	delete $monster->{attack_failed};
	delete $monster->{ignore};
	if ($failed) {
		walk_to($x, $y, espt('prioridad ' . $label, 'prioridade ' . $label));
	} else {
		main::attack($id);
		write_log(espt('prioridad ' . $label, 'prioridade ' . $label));
		$last_action = 'prioridad ' . $label;
	}
	return 1;
}

sub remaining_monsters_text {
	my @bits;
	for my $monster (real_monsters()) {
		push @bits, ($monster->{name} || 'mob') . ':' . ($monster->{nameID} || 0)
			. '@' . $monster->{pos}{x} . ',' . $monster->{pos}{y};
	}
	return join(' ', @bits);
}

sub note_monsters {
	if (has_real_monsters()) {
		$clear_since = undef;
		$sweep_required = 0;
		return 1;
	}
	$clear_since ||= time;
	return 0;
}

sub clear_for {
	my ($seconds) = @_;
	return 0 if has_real_monsters();
	return 0 unless defined $clear_since;
	return time - $clear_since >= $seconds;
}

sub log_blocked_portal {
	return unless expected_portal_present() && has_real_monsters();
	return if time - $last_block_log < 8;
	$last_block_log = time;
	write_log(espt(
		'portal cerrado, quedan ' . remaining_monsters_text(),
		'portal fechado, restam ' . remaining_monsters_text(),
	));
}

sub hunt_visible {
	return 0 unless has_real_monsters() && safe_for_action();
	return 1 if time - $last_hunt < 1;
	$last_hunt = time;
	my $monster = nearest_real_monster() or return 0;
	return 1 if check_unhittable($monster);
	my $pos = $monster->{pos_to} || $monster->{pos};
	my ($x, $y) = ($pos->{x}, $pos->{y});
	my $label = ($monster->{name} || 'mob') . ':' . ($monster->{nameID} || 0) . " en $x,$y";
	if (dry_run()) {
		announce(espt("SIMULACIÓN: atacar $label", "SIMULAÇÃO: atacar $label"));
		return 1;
	}
	# El núcleo lo descartó (sin LOS o sin ruta): caminar hasta él y reintentar.
	if ($monster->{attack_failedLOS} || $monster->{attack_failed}) {
		delete $monster->{attack_failedLOS};
		delete $monster->{attack_failed};
		delete $monster->{ignore};
		walk_to($x, $y, espt('acercarse a ' . $label, 'aproximar-se de ' . $label));
		return 1;
	}
	delete $monster->{ignore};
	main::attack($monster->{ID});
	write_log(espt('cazando ' . $label, 'caçando ' . $label));
	return 1;
}

sub max0 { $_[0] < 0 ? 0 : $_[0] }
sub min_max { $_[0] > $_[1] ? $_[1] : $_[0] }

sub reachable {
	my ($from, $x, $y, $box) = @_;
	return 0 if $x < 0 || $y < 0 || $x >= $field->width || $y >= $field->height;
	return 0 unless $field->isWalkable($x, $y);
	my $count = eval {
		PathFinding->new(
			field => $field,
			start => $from,
			dest  => { x => $x, y => $y },
			avoidWalls => 0,
			%$box,
		)->runcount;
	};
	return defined $count && $count >= 0 && $count <= 150;
}

# Recorrido completo: grilla de la sala, solo celdas alcanzables desde el
# personaje (las de otras salas quedan detrás del muro y se descartan).
sub sweep_points {
	my $r = room() or return;
	my $key = $r->{number};
	return @{$sweep_cache{$key}} if $sweep_cache{$key};
	my ($x0, $y0) = current_pos();
	return unless defined $x0;
	my $from = { x => $x0, y => $y0 };
	my ($ex, $ey) = @{$r->{entry}};
	my ($px, $py) = @{$r->{exit}};
	my ($ylo, $yhi) = $ey < $py ? ($ey, $py) : ($py, $ey);
	$ylo -= 4;
	$yhi += 4;
	my $cx = int(($ex + $px) / 2);
	# Sala grande: más ancha y un punto cada 5 celdas. El pasillo usa menos.
	my $half = $r->{large} ? 40 : 18;
	my $step = $r->{large} ? 5 : 8;
	my %box = (
		min_x => max0($cx - $half - 2), max_x => min_max($cx + $half + 2, $field->width - 1),
		min_y => max0($ylo - 2),        max_y => min_max($yhi + 2, $field->height - 1),
	);
	return unless $x0 >= $box{min_x} && $x0 <= $box{max_x} && $y0 >= $box{min_y} && $y0 <= $box{max_y};
	my @rows;
	my $flip = 0;
	for (my $y = $ylo; $y <= $yhi; $y += $step) {
		my @row;
		for (my $x = $cx - $half; $x <= $cx + $half; $x += $step) {
			push @row, [$x, $y] if reachable($from, $x, $y, \%box);
		}
		@row = reverse @row if $flip;
		$flip = !$flip;
		push @rows, @row;
	}
	$sweep_cache{$key} = \@rows if @rows;
	write_log(espt(
		'recorrido de sala ' . $r->{number} . ($r->{large} ? ' (grande)' : '') . ': ' . scalar(@rows) . ' puntos, paso ' . $step,
		'varredura da sala ' . $r->{number} . ($r->{large} ? ' (grande)' : '') . ': ' . scalar(@rows) . ' pontos, passo ' . $step,
	));
	return @rows;
}

sub scan_points {
	my $r = room() or return;
	# La grilla completa solo arranca después de esperar en el portal.
	# Hasta entonces basta el pasillo, también en las salas grandes.
	if ($sweep_required) {
		my @points = sweep_points();
		return @points if @points;
	}
	my ($px, $py) = @{$r->{exit}};
	my ($ex, $ey) = @{$r->{entry}};
	my $mid_y = int(($ey + $py) / 2);
	my $approach_y = $py > $ey ? $py - 4 : $py + 4;
	return (
		[$px, $mid_y],
		[$px, $approach_y],
	);
}

sub walk_to {
	my ($x, $y, $label) = @_;
	$last_action = $label;
	if (dry_run()) {
		announce(espt("SIMULACIÓN: mover a $label $x,$y", "SIMULAÇÃO: mover para $label $x,$y"));
		return 1;
	}
	AI::clear(qw/move route mapRoute/);
	main::ai_route(
		$field->baseName, $x, $y,
		attackOnRoute => 2,
		noSitAuto => 1,
		notifyUponArrival => 1,
	);
	write_log(espt("acción mover=$label coordenada=$x,$y", "ação mover=$label coordenada=$x,$y"));
	return 1;
}

sub scan_room {
	return unless safe_for_action();
	return if time - $last_scan < 1;
	$last_scan = time;
	my @points = scan_points();
	return unless @points;
	if ($scan_step >= @points) {
		$scan_step = 0;
		$sweep_required = 0;
		write_log(espt(
			'recorrido completo sin mobs; se vuelve a probar el portal',
			'varredura completa sem mobs; o portal será tentado de novo',
		));
		return;
	}
	my $point = $points[$scan_step++];
	walk_to($point->[0], $point->[1], espt(
		'recorrido ' . $scan_step . '/' . scalar(@points),
		'varredura ' . $scan_step . '/' . scalar(@points),
	));
}

sub is_instance_loot {
	my ($item) = @_;
	return 0 unless $item;
	my $id = $item->{nameID} || 0;
	return $instance_loot{$id} ? 1 : 0;
}

# Loot de la instancia en el suelo: se recoge antes que cualquier otra cosa,
# salvo el Poring de Ouro y la conversación con el cofre.
sub take_instance_loot {
	return 0 unless $itemsList && $char;
	return 0 if $state eq 'chest_clicking' || $state eq 'exiting' || $state eq 'initial_talking';
	my ($x, $y) = current_pos();
	return 0 unless defined $x;
	my ($best, $best_d);
	for my $item (@{$itemsList->getItems()}) {
		next unless $item && $item->{ID} && $item->{pos} && is_instance_loot($item);
		next if ($loot_tries{$item->{ID}} || 0) >= 4;
		my $d = abs($item->{pos}{x} - $x) + abs($item->{pos}{y} - $y);
		next if $d > 30;
		if (!defined $best_d || $d < $best_d) {
			$best = $item;
			$best_d = $d;
		}
	}
	return 0 unless $best;
	if ((AI::action() || '') eq 'take') {
		my $args = AI::args();
		return 1 if $args && $args->{ID} && $args->{ID} eq $best->{ID};
	}
	return 1 if time - $last_loot < 1;
	$last_loot = time;
	$loot_tries{$best->{ID}}++;
	my $label = ($best->{name} || 'item') . ':' . ($best->{nameID} || 0)
		. ' en ' . $best->{pos}{x} . ',' . $best->{pos}{y};
	if (dry_run()) {
		announce(espt("SIMULACIÓN: recoger $label", "SIMULAÇÃO: recolher $label"));
		return 1;
	}
	AI::clear(qw/attack route move mapRoute items_take items_gather/);
	$char->sendAttackStop;
	AI::take($best->{ID});
	write_log(espt(
		'recoger loot ' . $label . ' intento ' . $loot_tries{$best->{ID}},
		'recolher loot ' . $label . ' tentativa ' . $loot_tries{$best->{ID}},
	));
	return 1;
}

sub ai_busy {
	my $action = AI::action() || '';
	return 1 if $action =~ /^(?:attack|skill_use|items_take|items_gather|take|NPC|route|mapRoute|move)$/;
	return 1 if AI::inQueue(qw/attack skill_use items_take items_gather take NPC route mapRoute move/);
	return 0;
}

sub safe_for_action {
	return 0 if ai_busy();
	return 0 if defined $char && $char->{sitting};
	return 1;
}

sub dry_run {
	return config_bool('infiniteSpace_dryRun', 0);
}

sub do_talk {
	my ($x, $y, $sequence, $label) = @_;
	$last_action = $label;
	$action_attempts++;
	if (dry_run()) {
		announce(espt(
			"SIMULACIÓN: hablar $label en $x,$y" . ($sequence ? " [$sequence]" : ''),
			"SIMULAÇÃO: falar $label em $x,$y" . ($sequence ? " [$sequence]" : ''),
		));
		return 1;
	}
	AI::clear(qw/move route mapRoute NPC/);
	main::ai_talkNPC($x, $y, $sequence || '');
	write_log(espt(
		"acción hablar=$label coordenada=$x,$y intento=$action_attempts",
		"ação falar=$label coordenada=$x,$y tentativa=$action_attempts",
	));
	return 1;
}

sub do_route {
	my ($x, $y, $label) = @_;
	$last_action = $label;
	$action_attempts++;
	if (dry_run()) {
		announce(espt("SIMULACIÓN: mover a $label $x,$y", "SIMULAÇÃO: mover para $label $x,$y"));
		return 1;
	}
	walk_to($x, $y, $label);
	write_log(espt("intento=$action_attempts", "tentativa=$action_attempts"));
	return 1;
}

sub click_initial_npc {
	return unless safe_for_action();
	my $difficulty = lc(config_value('infiniteSpace_difficulty', 'hard'));
	# El acento de "Difícil" no siempre llega igual. Un carácter cualquiera
	# entre la f y "cil" cubre Difícil y Dificil, y no coincide con Fácil.
	# O acento de "Difícil" nem sempre chega igual. Um caractere qualquer
	# entre o f e "cil" cobre Difícil e Dificil, e não coincide com Fácil.
	my $pattern = $difficulty eq 'easy' ? 'F.cil' : 'Dif.cil';
	my $label = $difficulty eq 'easy' ? 'Modo Fácil' : 'Modo Difícil';
	do_talk(42, 8, 'r~/' . $pattern . '/i', espt("dificultad $label", "dificuldade $label"));
	$initial_talk_done = 1;
	set_state('initial_talking', espt("seleccionando $label", "selecionando $label"));
}

sub near_chest {
	my $r = room() or return 0;
	return 0 unless $r->{chest};
	my ($x, $y) = current_pos();
	return 0 unless defined $x;
	my ($cx, $cy) = @{$r->{chest}};
	my $dx = abs($x - $cx);
	my $dy = abs($y - $cy);
	$dx = $dy if $dy > $dx;
	return $dx <= 2;
}

sub click_chest {
	my $r = room() or return;
	return unless $r->{boss} && chest_present() && near_chest() && safe_for_action();
	my ($x, $y) = @{$r->{chest}};
	$chest_idle_since = undef;
	do_talk($x, $y, '', espt('cofre del bloque ' . $r->{block}, 'baú do bloco ' . $r->{block}));
	set_state('chest_clicking', espt('hablando con el cofre', 'falando com o baú'));
}

sub at_expected_portal {
	my $r = room() or return 0;
	my ($x, $y) = current_pos();
	return 0 unless defined $x;
	my ($px, $py) = @{$r->{exit}};
	my $dx = abs($x - $px);
	my $dy = abs($y - $py);
	$dx = $dy if $dy > $dx;
	return $dx <= 2;
}

sub begin_room_sweep {
	my ($reason) = @_;
	my $r = room() or return;
	$portal_idle_since = undef;
	$clear_since = time;
	$portal_seen_at = undef;
	$sweep_required = 1;
	$scan_step = 0;
	my $next = ($r->{boss} && $chest_claimed) ? 'post_chest' : 'combat';
	set_state($next, $reason);
}

sub move_to_expected_portal {
	my $r = room() or return;
	return unless expected_portal_present() && safe_for_action();
	my ($x, $y) = @{$r->{exit}};
	do_route($x, $y, espt('portal de salida de sala ' . $r->{number}, 'portal de saída da sala ' . $r->{number}));
	set_state('moving_portal', espt('avanzando al portal', 'avançando até o portal'));
}

sub click_final_exit {
	return unless exit_npc_present() && safe_for_action();
	do_talk(366, 392, '', espt('Arqueóloga de salida', 'Arqueóloga de saída'));
	set_state('exiting', espt('saliendo de la instancia', 'saindo da instância'));
}

sub timed_out {
	my ($seconds) = @_;
	return time - $state_since >= $seconds;
}

sub on_loop {
	return unless $active && $enabled && is_instance() && defined $room_index;

	my $weight_limit = config_value('infiniteSpace_weight', 90);
	if ($char && percent_weight($char) >= $weight_limit) {
		stop_automation(espt("peso igual o superior a ${weight_limit}%", "peso igual ou superior a ${weight_limit}%"));
		return;
	}

	my $room_timeout = config_value('infiniteSpace_roomTimeout', 900);
	if (time - $room_since >= $room_timeout) {
		stop_automation(espt('timeout en sala ' . room_label(), 'timeout na sala ' . room_label()));
		return;
	}

	my $action_timeout = config_value('infiniteSpace_actionTimeout', 20);
	my $r = room();
	remember_room_monsters();
	return if engage_golden();
	return if take_instance_loot();

	if ($state eq 'initial_wait') {
		click_initial_npc() if timed_out(3) && chest_or_npc_ready(42, 8);
		return;
	}

	if ($state eq 'initial_talking') {
		if (has_real_monsters() || expected_portal_present()) {
			$action_attempts = 0;
			set_state('combat', espt('Modo Difícil iniciado', 'Modo Difícil iniciado'));
		} elsif (timed_out($action_timeout)) {
			if ($action_attempts >= 3) {
				stop_automation(espt('el NPC inicial no inició el combate', 'o NPC inicial não iniciou o combate'));
			} else {
				set_state('initial_wait', espt('reintentando dificultad', 'tentando a dificuldade de novo'));
			}
		}
		return;
	}

	if ($state eq 'combat') {
		if (note_monsters()) {
			log_blocked_portal();
			hunt_visible();
			return;
		}

		if ($r->{boss} && !$mvp_seen) {
			# Recuperación: la sala ya está vacía y el portal abierto.
			if (expected_portal_present() && clear_for(5)) {
				$mvp_seen = 1;
				set_state('wait_chest', espt('MVP inferido tras recuperación', 'MVP inferido após recuperação'));
			}
			scan_room() if clear_for(2) && !expected_portal_present();
			return;
		}

		if ($r->{boss} && $mvp_seen) {
			set_state('wait_chest', espt('MVP derrotado', 'MVP derrotado'));
			return;
		}

		if (!$sweep_required && expected_portal_present() && clear_for(3)) {
			move_to_expected_portal();
		} elsif (clear_for(2)) {
			scan_room();
		}
		return;
	}

	if ($state eq 'wait_chest') {
		if (note_monsters()) {
			log_blocked_portal();
			hunt_visible();
			return;
		}
		if (!chest_present()) {
			stop_automation(espt(
				'no apareció el cofre en ' . join(',', @{$r->{chest}}),
				'o baú não apareceu em ' . join(',', @{$r->{chest}}),
			))
				if timed_out($action_timeout) && clear_for(2);
			return;
		}
		if (!near_chest()) {
			if (safe_for_action()) {
				my ($x, $y) = @{$r->{chest}};
				walk_to($x, $y, espt(
					'acercarse al cofre del bloque ' . $r->{block},
					'aproximar-se do baú do bloco ' . $r->{block},
				));
			}
			return;
		}
		my $delay = config_value('infiniteSpace_chestDelay', 8);
		click_chest() if time - $state_since >= $delay;
		return;
	}

	if ($state eq 'chest_clicking') {
		# El portal no puede cancelar la conversación: se espera a que termine.
		if (ai_busy()) {
			$chest_idle_since = undef;
			if (timed_out($action_timeout)) {
				AI::clear(qw/NPC route move mapRoute/);
				if ($action_attempts >= 3) {
					stop_automation(espt(
						'no se pudo abrir el cofre en ' . join(',', @{$r->{chest}}),
						'não foi possível abrir o baú em ' . join(',', @{$r->{chest}}),
					));
				} else {
					set_state('wait_chest', espt('reintentando el cofre', 'tentando o baú de novo'));
				}
			}
			return;
		}
		$chest_idle_since ||= time;
		return if time - $chest_idle_since < 2;
		$chest_claimed = 1;
		announce(espt(
			'Cofre del bloque ' . $r->{block} . ' abierto',
			'Baú do bloco ' . $r->{block} . ' aberto',
		), 'success');
		if ($r->{number} == InfiniteSpace::Route::room_count()) {
			if (config_bool('infiniteSpace_exit', 1)) {
				set_state('final_exit', espt('esperando Arqueóloga de salida', 'aguardando a Arqueóloga de saída'));
			} else {
				$active = 0;
				set_state('completed', espt('quedarse dentro configurado', 'permanecer dentro, conforme configurado'));
				announce(espt(
					'Quinto cofre reclamado; permanencia dentro configurada',
					'Quinto baú coletado; permanência dentro configurada',
				), 'success');
			}
		} else {
			$action_attempts = 0;
			set_state('post_chest', espt('esperando portal después del cofre', 'aguardando o portal depois do baú'));
		}
		return;
	}

	if ($state eq 'post_chest') {
		if (note_monsters()) {
			log_blocked_portal();
			hunt_visible();
			return;
		}
		if (!$sweep_required && expected_portal_present() && clear_for(3)) {
			move_to_expected_portal();
		} elsif (clear_for(2)) {
			scan_room();
		}
		return;
	}

	if ($state eq 'moving_portal') {
		if (has_real_monsters()) {
			$clear_since = undef;
			$portal_idle_since = undef;
			if ($r->{boss} && $chest_claimed) {
				set_state('post_chest', espt('quedan mobs; el portal no abre', 'ainda há mobs; o portal não abre'));
			} else {
				set_state('combat', espt('quedan mobs; el portal no abre', 'ainda há mobs; o portal não abre'));
			}
			return;
		}
		if (at_expected_portal()) {
			$portal_idle_since ||= time;
			my $wait = config_value('infiniteSpace_portalSweepDelay', 12);
			if (time - $portal_idle_since >= $wait) {
				if ($action_attempts >= 6) {
					stop_automation(espt('no pudo atravesar el portal esperado', 'não conseguiu atravessar o portal esperado'));
				} else {
					begin_room_sweep(espt(
						'en el portal ' . $wait . ' s sin abrir; recorriendo la sala',
						'no portal há ' . $wait . ' s sem abrir; varrendo a sala',
					));
				}
			}
			return;
		}
		$portal_idle_since = undef;
		if (timed_out($action_timeout) && safe_for_action()) {
			if ($action_attempts >= 6) {
				stop_automation(espt('no pudo llegar al portal esperado', 'não conseguiu chegar ao portal esperado'));
			} else {
				move_to_expected_portal();
			}
		}
		return;
	}

	if ($state eq 'final_exit') {
		click_final_exit();
		if (timed_out($action_timeout) && !exit_npc_present()) {
			stop_automation(espt('no apareció la Arqueóloga de salida en 366,392', 'a Arqueóloga de saída não apareceu em 366,392'));
		}
		return;
	}

	if ($state eq 'exiting' && timed_out($action_timeout)) {
		if ($action_attempts >= 3) {
			stop_automation(espt('la Arqueóloga no completó la salida', 'a Arqueóloga não completou a saída'));
		} else {
			set_state('final_exit', espt('reintentando salida', 'tentando a saída de novo'));
		}
	}
}

sub chest_or_npc_ready {
	my ($x, $y) = @_;
	return actor_at($npcsList, $x, $y) ? 1 : 0;
}

sub cmd_infi {
	my (undef, $args) = @_;
	my ($sub) = lc($args || 'status') =~ /^(\S+)/;
	$sub ||= 'status';

	if ($sub eq 'on') {
		$enabled = 1;
		announce(espt('automatización habilitada', 'automação habilitada'), 'success');
		activate() if is_instance();
	} elsif ($sub eq 'off') {
		$enabled = 0;
		stop_automation(espt('deshabilitada por el usuario', 'desabilitada pelo usuário')) if $active;
		announce(espt('automatización deshabilitada', 'automação desabilitada'));
	} elsif ($sub eq 'reset') {
		$state = 'inactive';
		$active = 0;
		$room_index = undef;
		$initial_talk_done = 0;
		activate() if $enabled && is_instance();
		announce(espt('estado reconstruido desde la posición actual', 'estado reconstruído a partir da posição atual'), 'success');
	} elsif ($sub eq 'status') {
		my ($x, $y) = current_pos();
		$x = defined $x ? $x : '?';
		$y = defined $y ? $y : '?';
		my $yes = espt('sí', 'sim');
		my $no = espt('no', 'não');
		message "[InfiniteSpace]\n"
			. "  " . espt('habilitado', 'habilitado') . ": " . ($enabled ? $yes : $no) . "\n"
			. "  " . espt('activo', 'ativo') . ": " . ($active ? $yes : $no) . "\n"
			. "  " . espt('estado', 'estado') . ": $state\n"
			. "  " . espt('sala', 'sala') . ": " . room_label() . "\n"
			. "  " . espt('posición', 'posição') . ": $x,$y\n"
			. "  MVP: " . ($mvp_seen ? $yes : $no) . "\n"
			. "  " . espt('cofre', 'baú') . ": " . ($chest_claimed ? espt('reclamado', 'coletado') : espt('pendiente', 'pendente')) . "\n"
			. "  " . espt('mobs en sala', 'mobs na sala') . ": " . scalar(real_monsters())
			. (has_real_monsters() ? ' (' . remaining_monsters_text() . ')' : '') . "\n"
			. "  " . espt('acompañantes ignorados', 'acompanhantes ignorados') . ": " . scalar(keys %companions) . "\n"
			. "  " . espt('fantasmas ignorados', 'fantasmas ignorados') . ": " . scalar(keys %ghosts) . "\n"
			. "  " . espt('config temporal', 'config temporária') . ": " . ($config_guard_active ? espt('activa, copia en ', 'ativa, cópia em ') . snapshot_file() : $no) . "\n"
			. ($last_status ? "  " . espt('detalle', 'detalhe') . ": $last_status\n" : '');
	} else {
		error "[InfiniteSpace] " . espt('Uso', 'Uso') . ": infi on|off|status|reset\n";
	}
}

announce(espt(
	'Plugin cargado; se activará automáticamente dentro de 1@infi',
	'Plugin carregado; será ativado automaticamente dentro de 1@infi',
), 'success');
activate() if $enabled && is_instance();

1;
