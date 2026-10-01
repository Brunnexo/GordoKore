#!/usr/bin/perl
# Extract maps (.gat + .rsw) from a GRF using GRF Editor's GrfCL.exe,
# convert them to .fld2 and gzip them to .fld2.gz.
#
# Usage:
#   perl grf_to_fld2gz.pl "C:\Program Files (x86)\GRF Editor" "C:\RO\data.grf" "C:\out"
#
# arg 1: GRF Editor folder (or the path of GrfCL.exe itself)
# arg 2: .grf file
# arg 3: output folder (created if missing; existing .fld2.gz files are replaced)
use strict;
use warnings;
use File::Path qw(make_path remove_tree);
use File::Find;
use File::Basename;
use File::Spec;
use Cwd;
use IO::Compress::Gzip qw(gzip $GzipError);

use constant {
	TILE_NOWALK => 0,
	TILE_WALK => 1,
	TILE_SNIPE => 2,
	TILE_WATER => 4,
	TILE_CLIFF => 8,
};
use constant CHUNK => 150; # maps per GrfCL call, keeps the command line < 32k chars

my @TILE_TYPE = (
	TILE_WALK,
	TILE_NOWALK,
	TILE_WATER,
	TILE_WALK|TILE_WATER,
	TILE_WATER|TILE_SNIPE,
	TILE_CLIFF|TILE_SNIPE,
	TILE_CLIFF
);

die "Usage: $0 <GRF Editor folder|GrfCL.exe> <file.grf> <output folder>\n" if @ARGV != 3;
my ($editor, $grf, $outDir) = @ARGV;

my $grfCL = -d $editor ? "$editor/GrfCL.exe" : $editor;
($grfCL, $grf, $outDir) = map { File::Spec->rel2abs($_) } ($grfCL, $grf, $outDir);
die "GrfCL.exe not found: $grfCL\n" unless -f $grfCL;
die "GRF not found: $grf\n" unless -f $grf;
make_path($outDir);

my $tmp = "$outDir/_grf_tmp";
remove_tree($tmp);
make_path($tmp);

my @maps = listMaps();
die "No maps found in $grf\n" unless @maps;
print "[grf_to_fld2gz] ".scalar(@maps)." maps found\n";

my ($ok, $fail) = (0, 0);
while (my @chunk = splice(@maps, 0, CHUNK)) {
	extract(map { ("data\\$_.gat", "data\\$_.rsw") } @chunk);
	# GrfCL aborts the whole call if one path is missing: retry the missing maps one by one
	extract("data\\$_.gat", "data\\$_.rsw") for grep { !findFile($tmp, "$_.gat") } @chunk;

	foreach my $name (@chunk) {
		my ($gat, $rsw) = map { findFile($tmp, "$name.$_") } qw(gat rsw);
		my $fld2 = "$tmp/$name.fld2";
		eval {
			die "not in GRF\n" unless $gat && $rsw;
			gat_to_fld2($gat, $fld2, readWaterLevel($rsw));
			gzip($fld2 => "$outDir/$name.fld2.gz", Name => "$name.fld2") or die "gzip failed: $GzipError\n";
		};
		if ($@) { chomp $@; print "[grf_to_fld2gz] Skipped '$name': $@\n"; $fail++ }
		else    { print "[grf_to_fld2gz] OK '$name'\n"; $ok++ }
		unlink grep { defined } $gat, $rsw, $fld2;
	}
}
remove_tree($tmp);
print "[grf_to_fld2gz] Done: $ok converted, $fail skipped -> $outDir\n";
exit($fail ? 1 : 0);

# Find extracted file regardless of how GrfCL lays out subfolders.
sub findFile {
	my ($dir, $file) = @_;
	my $found;
	find({ no_chdir => 1, wanted => sub { $found = $File::Find::name if !$found && lc(basename($_)) eq lc($file) } }, $dir);
	return $found;
}

# Run GrfCL from inside $tmp (it drops a tmp/ folder in its cwd). With stdout redirected it
# prints a console "invalid handle" error after extracting: ignore output and exit code.
sub extract {
	my $cwd = getcwd();
	chdir $tmp;
	system($grfCL, "-open", $grf, "-extractFolder", $tmp, @_, "-exit");
	chdir $cwd;
}

# GrfCL cannot list a GRF without a console, so map names come from the
# resnametable.txt / mapnametable.txt stored in the GRF.
# ponytail: maps missing from both tables are not found, add a name list option if needed
sub listMaps {
	my %maps;
	extract("data\\resnametable.txt", "data\\mapnametable.txt");
	foreach my $t (qw(resnametable mapnametable)) {
		my $file = findFile($tmp, "$t.txt") or next;
		open(my $f, "<:raw", $file) or next;
		while (<$f>) { $maps{$1} = 1 if /^([\w@.\-]+)\.(?:gat|rsw)#/i }
		close $f;
		unlink $file;
	}
	return sort keys %maps;
}

sub readWaterLevel {
	my ($rswFile) = @_;
	open(my $f, "<:raw", $rswFile) or die "Cannot open $rswFile for reading.\n";
	seek $f, 166, 0;
	read $f, my $buf, 4;
	close $f;
	return unpack("f", $buf);
}

sub gat_to_fld2 {
	my ($gat, $fld2, $waterLevel) = @_;
	open(my $in, "<:raw", $gat) or die "Cannot open $gat for reading.\n";
	open(my $out, ">:raw", $fld2) or die "Cannot open $fld2 for writing.\n";

	read($in, my $data, 14);
	my ($width, $height) = unpack("V2", substr($data, 6, 8));
	print $out pack("v2", $width, $height);

	while (read($in, $data, 20)) {
		my ($a, $b, $c, $d) = unpack("f4", $data);
		my $type = unpack("C", substr($data, 16, 1));
		my $averageDepth = ($a + $b + $c + $d) / 4;

		if ($type > $#TILE_TYPE) {
			print "[grf_to_fld2gz] Unknown blocktype ($type) in $gat, treated as unwalkable\n";
			print $out pack("C", $TILE_TYPE[1]);
		} elsif ($averageDepth > $waterLevel) {
			print $out pack("C", (($TILE_TYPE[$type] & TILE_WATER) == TILE_WATER) ? $TILE_TYPE[$type] : $TILE_TYPE[$type]|TILE_WATER);
		} else {
			print $out pack("C", $TILE_TYPE[$type]);
		}
	}
	close $in;
	close $out;
}
