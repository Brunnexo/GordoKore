package InfiniteSpace::Route;

use strict;
use warnings;
use Exporter 'import';

our @EXPORT_OK = qw(rooms room_count room_for_position);

my @ROOMS;

sub add_block {
	my ($entries, $exits, $chest) = @_;
	for my $i (0 .. $#$entries) {
		push @ROOMS, {
			entry => [@{$entries->[$i]}],
			exit  => [@{$exits->[$i]}],
			boss  => ($i == $#$entries ? 1 : 0),
			($i == $#$entries ? (chest => [@$chest]) : ()),
		};
	}
}

add_block(
	[
		[30, 10], [30, 41], [30, 73], [30, 105], [30, 137],
		[30, 220], [30, 253], [30, 285], [30, 317], [30, 349],
	],
	[
		[30, 31], [30, 63], [30, 95], [30, 127], [30, 168],
		[30, 243], [30, 275], [30, 307], [30, 339], [30, 380],
	],
	[30, 369],
);

add_block(
	[
		[112, 10], [112, 41], [112, 73], [112, 105], [112, 137],
		[112, 220], [112, 253], [112, 285], [112, 317], [112, 349],
	],
	[
		[112, 31], [112, 63], [112, 95], [112, 127], [112, 168],
		[112, 243], [112, 275], [112, 307], [112, 339], [112, 380],
	],
	[112, 369],
);

add_block(
	[
		[198, 10], [198, 41], [198, 73], [198, 105], [198, 137],
		[198, 220], [194, 245], [194, 277], [194, 309], [194, 341],
	],
	[
		[198, 31], [198, 63], [198, 95], [198, 127], [198, 168],
		[194, 235], [194, 267], [194, 299], [194, 331], [194, 392],
	],
	[194, 380],
);

add_block(
	[
		[280, 10], [280, 41], [280, 73], [280, 105], [280, 137],
		[280, 220], [280, 245], [280, 277], [280, 309], [280, 341],
	],
	[
		[280, 31], [280, 63], [280, 95], [280, 127], [280, 168],
		[280, 235], [280, 267], [280, 299], [280, 331], [280, 392],
	],
	[280, 380],
);

add_block(
	[
		[362, 10], [362, 41], [362, 73], [362, 105], [362, 137],
		[362, 220], [366, 245], [366, 277], [366, 309], [366, 341],
	],
	[
		[362, 31], [362, 63], [362, 95], [362, 127], [362, 168],
		[366, 235], [366, 267], [366, 299], [366, 331], [366, 392],
	],
	[366, 380],
);

# Salas grandes confirmadas en juego. No siguen un múltiplo fijo.
my %LARGE = map { $_ => 1 } (4, 10, 15, 20, 25, 29, 35, 40, 45, 50);

for my $i (0 .. $#ROOMS) {
	$ROOMS[$i]{number} = $i + 1;
	$ROOMS[$i]{block} = int($i / 10) + 1;
	$ROOMS[$i]{large} = $LARGE{$i + 1} ? 1 : 0;
}

sub rooms {
	return \@ROOMS;
}

sub room_count {
	return scalar @ROOMS;
}

sub room_for_position {
	my ($x, $y) = @_;
	return unless defined $x && defined $y;

	# La sala es el tramo entre su entrada y su portal. La entrada de la
	# sala siguiente puede quedar más cerca en coordenadas y, sin embargo,
	# del otro lado del muro.
	my ($best, $best_dx);
	for my $i (0 .. $#ROOMS) {
		my ($ex, $ey) = @{$ROOMS[$i]{entry}};
		my ($px, $py) = @{$ROOMS[$i]{exit}};
		my $y0 = $ey < $py ? $ey : $py;
		my $y1 = $ey > $py ? $ey : $py;
		next if $y < $y0 || $y > $y1;
		my $dx = abs($x - $ex);
		my $dx_exit = abs($x - $px);
		$dx = $dx_exit if $dx_exit < $dx;
		next if $dx > 40;
		if (!defined $best_dx || $dx < $best_dx) {
			$best = $i;
			$best_dx = $dx;
		}
	}
	return $best if defined $best;

	# Entre el portal y la entrada siguiente todavía no se puede cruzar.
	my ($behind, $behind_dist);
	for my $i (0 .. $#ROOMS) {
		my ($ex, $ey) = @{$ROOMS[$i]{entry}};
		my ($px, $py) = @{$ROOMS[$i]{exit}};
		next if abs($x - $px) > 40 && abs($x - $ex) > 40;
		my $passed = $py >= $ey ? $y > $py : $y < $py;
		next unless $passed;
		my $dist = abs($y - $py);
		if (!defined $behind_dist || $dist < $behind_dist) {
			$behind = $i;
			$behind_dist = $dist;
		}
	}
	return $behind if defined $behind;

	my ($fallback, $fallback_distance);
	for my $i (0 .. $#ROOMS) {
		my ($rx, $ry) = @{$ROOMS[$i]{entry}};
		my $distance = abs($x - $rx) + abs($y - $ry);
		if (!defined $fallback_distance || $distance < $fallback_distance) {
			$fallback = $i;
			$fallback_distance = $distance;
		}
	}
	return $fallback;
}

1;
