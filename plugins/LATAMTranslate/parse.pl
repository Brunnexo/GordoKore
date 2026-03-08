use strict;
use warnings;

use Cpanel::JSON::XS;
use Storable qw(store);

open my $fh, '<', 'strings.json' or die $!;
local $/;
my $json = <$fh>;
close $fh;

my $data = Cpanel::JSON::XS->new->decode($json);

store $data, 'strings.store';

print "Convertido para Storable\n";