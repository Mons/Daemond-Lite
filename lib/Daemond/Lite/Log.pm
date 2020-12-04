package Daemond::Lite::Log;

use strict;
no warnings;

=for TODO
BEGIN {
	if (eval { require Log::Any; $Log::Any::VERSION >= 0.12; }) {
		#warn "have log::any";
		Log::Any->import('$log');
		*HAVE_LOG_ANY = sub () { 1 };
		require Daemond::Lite::Log::Object;
		
	} else {
		require Daemond::Lite::Log::Object;
		require Daemond::Lite::Log::Simple;
		*HAVE_LOG_ANY = sub () { 0 };
	}
}
=cut

our (%logging_methods, %logging_methods_numbers);

BEGIN {
	%logging_methods = (
		trace     => 8,
		debug     => 7,
		info      => 6,
		notice    => 5,
		warning   => 4,
		error     => 3,
		critical  => 2,
		alert     => 1,
		emergency => 0,
	);
	%logging_methods_numbers = reverse %logging_methods;
	require Daemond::Lite::Log::Object;
	require Daemond::Lite::Log::Simple;
	*HAVE_LOG_ANY = sub () { 0 };
}

our $LOG;

sub import {
	shift;
	@_ or return;
	my $caller = caller;
	no strict 'refs';
	if (HAVE_LOG_ANY) {
		my $logger = Log::Any->get_logger(category => 'Daemond');
		my $wrapper = Daemond::Lite::Log::Object->new( $logger );
		$LOG = $wrapper;
		#warn "export $wrapper";
		*{ $caller.'::log' } = \$LOG;
	}
	else {
		$LOG ||= Daemond::Lite::Log::Object->new(
			Daemond::Lite::Log::Simple->new()
		);
		*{ $caller.'::log' } = \$LOG;
	}
}

sub configure {
	my $self = shift;
	my $d = shift;
	if (HAVE_LOG_ANY) {
		# TBD
	} else {
		$LOG = Daemond::Lite::Log::Object->new(
			Daemond::Lite::Log::Simple->new( $d )
		);
	}
}

sub set {
	my $self = shift;
	my $logger = shift;
	$LOG = Daemond::Lite::Log::Object->new( $logger );
}

1;
