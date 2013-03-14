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
	my $data = ${$_[0]};
	if ( $data =~ /\n[^"'\n]*: !include\s[^"'\n]+\n/s ) {
		require File::Basename;
		require Daemond::Lite::Conf::YAML;
		my ($name, $path) = File::Basename::fileparse($file);
		return clone( Daemond::Lite::Conf::YAML->new($path)->load($data) );
	}
	return Load($data);
}

my %SEEN;
sub clone($);
sub clone($) {
	my $ref = shift;
	exists $SEEN{0+$ref} and warn("return seen $ref: $SEEN{0+$ref}"),return $SEEN{0+$ref};
	local $SEEN{0+$ref};
	if ( UNIVERSAL::isa( $ref, 'HASH' ) ) {
		$SEEN{0+$ref} = my $new = {};
		%$new = map { ref() ? clone($_) : $_ } %$ref;
		bless $new, ref $ref if ref $ref ne 'HASH';
		return $new;
	}
	elsif ( UNIVERSAL::isa( $ref, 'ARRAY' ) ) {
		$SEEN{0+$ref} = my $new = [];
		@$new = map { ref() ? clone($_) : $_ } @$ref;
		bless $new, ref $ref if ref $ref ne 'ARRAY';
		return $new;
	}
	elsif ( UNIVERSAL::isa( $ref, 'SCALAR' ) ) {
		my $copy = $$ref;
		$SEEN{0+$ref} = my $new = \$copy;
		bless $new, ref $ref if ref $ref ne 'SCALAR';
		return $new;
	}
	elsif ( UNIVERSAL::isa( $ref, 'REF' ) ) {
		my $copy;
		$SEEN{0+$ref} = my $new = \$copy;
		$copy = clone( $$ref );
		bless $new, ref $ref if ref $ref ne 'REF';
		return $new;
	}
	elsif ( UNIVERSAL::isa( $ref, 'LVALUE' ) ) {
		my $copy = $$ref;
		my $new = \$copy;
		bless $new, ref $ref if ref $ref ne 'LVALUE';
		return $new;
	}
	else {
		die "Cloning of ".ref( $ref )." not supported";
	}
}

1;
