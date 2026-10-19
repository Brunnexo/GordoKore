#########################################################################
#  Auto-update do GordoKore via GitHub Releases.
#
#  Chamado do BEGIN do openkore.pl, ANTES de carregar o XSTools.dll (depois
#  disso o Windows trava as DLLs). So usa modulos core/Strawberry; nada do Kore.
#
#  Erros (sem rede, release invalida...) dao die: o openkore.pl captura e
#  sobe o bot na versao atual.
#########################################################################
package Utils::Updater;

use strict;
use warnings;
use Archive::Zip qw(AZ_OK);
use Digest::SHA;
use Fcntl qw(:flock);
use File::Basename qw(dirname);
use File::Path qw(make_path);
use File::Spec;
use File::Temp;
use HTTP::Tiny;
use JSON::PP qw(decode_json);

use constant {
	REPO => 'Brunnexo/GordoKore',
	ASSET => 'GordoKore.zip',
};

# DLLs que o bot em execucao mantem travadas.
my @DLLS = qw(XSTools.dll NetRedirect.dll src/auto/XSTools/XSTools.dll src/auto/XSTools/NetRedirect.dll);

# Arquivos do usuario: a release so cria se ainda nao existirem, nunca sobrescreve.
sub _keep {
	my ($name) = @_;
	return $name =~ m{^(?:control|profiles|logs)/}
		|| $name eq 'tables/item_weights.txt'   # aprendido pelo plugin item_weight_recorder
		|| $name =~ m{^[^/]+\.bat$};
}

sub _version {
	open(my $fh, '<', "$_[0]/VERSION") or return '';
	my $v = <$fh> // '';
	$v =~ s/\s+$//;
	return $v;
}

# Se atualizou, relanca o openkore.pl (com os mesmos argumentos) e termina este processo.
sub run {
	my ($root, $script, @args) = @_;
	return if $ENV{GORDOKORE_UPDATED} || $ENV{GORDOKORE_NO_UPDATE};
	return if -d "$root/.git";   # checkout de desenvolvimento: nao sobrescrever

	# Dois perfis abrindo juntos: um atualiza, o outro espera. O lock cai sozinho se o processo morrer.
	open(my $lock, '>', File::Spec->catfile(File::Spec->tmpdir, 'gordokore-update.lock')) or die "lock: $!\n";
	flock($lock, LOCK_EX);
	# VERSION gravado depois que este processo iniciou ($^T): outro perfil atualizou enquanto esperavamos,
	# entao o openkore.pl que lemos e velho. Relanca (pior caso: um relancamento a toa).
	my $updated = ((stat "$root/VERSION")[9] // 0) >= $^T || _update($root);
	close $lock;
	return unless $updated;

	$ENV{GORDOKORE_UPDATED} = 1;   # evita loop se a release nova der problema
	my $rc = system($^X, $script, @args);
	exit($rc == -1 ? 1 : $rc >> 8);
}

# Retorna 1 se instalou uma versao nova, 0 se nao havia nada a fazer.
sub _update {
	my ($root) = @_;
	my $local = _version($root);
	my $api = $ENV{GORDOKORE_API} || 'https://api.github.com';
	my $http = HTTP::Tiny->new(agent => 'GordoKore-updater', timeout => 15, verify_SSL => 1);

	my $res = $http->get("$api/repos/" . REPO . '/releases/latest');
	die "GitHub respondeu $res->{status} $res->{reason}\n" unless $res->{success};
	my $rel = decode_json($res->{content});
	return 0 if $rel->{tag_name} eq $local;
	my ($asset) = grep { $_->{name} eq ASSET } @{ $rel->{assets} || [] };
	die "release sem " . ASSET . "\n" unless $asset;

	# Outro perfil com o bot aberto trava as DLLs: nao da pra atualizar agora.
	foreach my $f (@DLLS) {
		next unless -e "$root/$f";
		if (!open(my $fh, '+<', "$root/$f")) {
			print "[update] bot aberto em outro perfil, pulando.\n";
			return 0;
		}
	}

	print "[update] nova versao $rel->{tag_name} (atual: '$local'). Baixando...\n";
	my $tmp = File::Temp->new(SUFFIX => '.zip');   # apagado sozinho ao sair do escopo
	binmode $tmp;
	$res = $http->get($asset->{browser_download_url}, { data_callback => sub { print $tmp $_[0] } });
	die "download falhou: $res->{status} $res->{reason}\n" unless $res->{success};
	close $tmp;

	# ponytail: sem digest na API (GHES antigo) nao verifica; so HTTPS.
	if (($asset->{digest} // '') =~ /^sha256:(\w+)$/) {
		my $want = lc $1;
		my $got = Digest::SHA->new(256)->addfile($tmp->filename, 'b')->hexdigest;
		die "sha256 do zip nao confere\n" if $got ne $want;
	}

	print "[update] Instalando...\n";
	my $zip = Archive::Zip->new;
	$zip->read($tmp->filename) == AZ_OK or die "zip invalido\n";
	# openkore.pl por ultimo: o processo atual ainda o esta lendo.
	my @members = sort { ($a->fileName eq 'openkore.pl') <=> ($b->fileName eq 'openkore.pl') } $zip->members;
	foreach my $m (@members) {
		my $name = $m->fileName;
		die "caminho suspeito no zip: $name\n" if $name =~ m{(?:^|/)\.\.(?:/|$)} || $name =~ m{^(?:/|\w:)};
		my $dest = "$root/$name";
		if ($m->isDirectory) {
			make_path($dest);
			next;
		}
		next if _keep($name) && -e $dest;
		make_path(dirname($dest));
		$m->extractToFileNamed($dest) == AZ_OK or die "falha ao extrair $name\n";
	}

	# So grava a versao no fim: se algo falhou antes, a proxima abertura tenta de novo.
	open(my $fh, '>', "$root/VERSION") or die "VERSION: $!\n";
	print $fh $rel->{tag_name};
	close $fh;
	print "[update] atualizado para $rel->{tag_name}.\n";
	return 1;
}

1;
