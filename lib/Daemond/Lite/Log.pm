package Daemond::Lite::Log;

use strict;
BEGIN {
	if (eval { require Log::Any; $Log::Any::VERSION >= 0.12 }) {
		warn "have log::any";
		Log::Any->import('$log');
		*HAVE_LOG_ANY = sub () { 1 };
		require Daemond::Lite::Log::Object;
		
	} else {
		require Daemond::Lite::Log::Simple;
		*HAVE_LOG_ANY = sub () { 0 };
	}
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
		warn "export $wrapper";
		*{ $caller.'::log' } = \$wrapper;
	}
	else {
		$LOG ||= Daemond::Lite::Log::Simple->new();
		*{ $caller.'::log' } = \$LOG;
	}
}

1;
