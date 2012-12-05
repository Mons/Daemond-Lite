package Daemond::Lite::Conf;

use strict;
use Carp;

BEGIN {
	my $HAVE_YAML = 0;
	if ( eval{ require YAML::XS; 0 } ) {
		# TODO: unicode?
		YAML::XS->import(qw(Load));
		$HAVE_YAML = 1;
	}
	elsif( eval{ require YAML::Syck; 1 } ) {
		$YAML::Syck::ImplicitUnicode = 1;
		#$YAML::Syck::ImplicitBinary = 1;
		YAML::Syck->import(qw(Load));
		$HAVE_YAML = 1;
	}
	elsif ( eval{ require YAML; 1 } ) {
		YAML->import(qw(Load));
		$HAVE_YAML = 1;
	}
	else {
		$HAVE_YAML = 0;
	}
	*HAVE_YAML = sub () { $HAVE_YAML };
}

sub load {
	my $file = shift;
	#warn "loading YAML $file";
	open my $f,'<:raw', $file or die "Can't open file `$file': $!\n";
	local $/;
	my $data = <$f>;
	close $f;
	if ($data =~ /^\s*?---/s) {
		parse_yaml($file, \$data);
	}
	else {
		parse_ini($file, \$data);
	}
	#warn "Data: $data";
}

# Derived from Adam Kennedy's Config::Tiny
sub parse_ini {
	my $file = shift;
	warn "loading INI $file";
	# Parse the file
	my %cf;
	my $ns;
	my $counter = 0;
	utf8::decode(${ $_[0] });
	foreach ( split /(?:\015{1,2}\012|\015|\012)/, ${$_[0]} ) {
		$counter++;

		# Skip comments and empty lines
		next if /^\s*(?:\#|\;|$)/;

		# Remove inline comments
		s/\s\;\s.+$//g;

		# Handle section headers
		if ( /^\s*\[\s*(.+?)\s*\]\s*$/ ) {
			# Create the sub-hash if it doesn't exist.
			# Without this sections without keys will not
			# appear at all in the completed struct.
			$cf{$ns = $1} ||= {};
			next;
		}
		# Handle properties
		if ( /^\s*([^=]+?)\s*=\s*(.*?)\s*$/ ) {
			if( defined $ns ) {
				$cf{$ns}{$1} = $2;
			} else {
				$cf{$1} = $2;
			}
			next;
		}
		
		return die( "INI Syntax error in `$file' at line $counter: '$_'\n" );
	}
	return \%cf;
}

sub parse_yaml {
	HAVE_YAML or die "Neither YAML::Syck, nor YAML::XS nor YAML found. Use INI config file or install some YAML module\n";
	my $file = shift;
	return Load(${$_[0]});
}

1;