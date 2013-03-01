package Daemond::Lite::Conf::Clone;

use strict;

use Exporter;
our @EXPORT = qw{ clone };
our @EXPORT_OK = qw{ clone };

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
