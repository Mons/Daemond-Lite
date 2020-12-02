package Daemond::Lite::Log::Simple;

use strict;
use Carp;
use Daemond::Lite::Log ();

our %MAP;

BEGIN {
	if( eval{ require Unix::Syslog } ) {
		Unix::Syslog->import( ':macros', ':subs' );
		*SYSLOG = sub () { 1 };
	}
	elsif( eval{ require Sys::Syslog; } ) {
		Sys::Syslog->import( ':standard', ':macros' );
		*SYSLOG = sub () { 1 };
		warn "Usage of Sys::Syslog may be dangerous in long-running processes. Better install Unix::Syslog\n";
	}
	else {
		*SYSLOG = sub () { 0 };
	}
}
BEGIN {
	if (SYSLOG) {
		%MAP = (
			trace     => LOG_DEBUG,
			debug     => LOG_DEBUG,
			info      => LOG_INFO,
			notice    => LOG_NOTICE,
			warning   => LOG_WARNING,
			error     => LOG_ERR,
			critical  => LOG_CRIT,
			alert     => LOG_ALERT,
			emergency => LOG_EMERG,
		);
	}
}

our ( %log_level_aliases, %logging_methods, @logging_aliases );

BEGIN {
	%log_level_aliases = (
		inform => 'info',
		warn   => 'warning',
		err    => 'error',
		crit   => 'critical',
		fatal  => 'critical'
	);
	*logging_methods = \%Daemond::Lite::Log::logging_methods;
	@logging_aliases = keys(%log_level_aliases);
}

our %COLOR = (
	trace     => "36",
	debug     => "37",
	info      => "1;37",
	notice    => "33",
	warning   => "1;33",
	error     => "31",
	critical  => "4;31",
	alert     => "1;31",
	emergency => "1;37;41",
);

sub is_null { 0 }

sub new {
	my $pkg = shift;
	my $d = shift;
	my $self = bless {
		screen => 1,
		syslog => SYSLOG,
		d      => $d,
	}, $pkg;
	$self;
}

BEGIN {
	no strict 'refs';
	for my $method ( keys %logging_methods, ) {
		*$method = sub {
			my $self = shift;
			my $msg = shift;
			return if $logging_methods{$method} > $self->{d}->log_level;
			if (@_ and index($msg,'%') > -1) {
				$msg = sprintf $msg, @_;
			}
			$msg =~ s{\n*$}{};
			if ($self->{screen}) {
				#unless ($self->{outfh}) {
				#	open $self->{outfh}, '>&',STDOUT;
				#	binmode $self->{outfh},':raw';
				#}
				binmode STDOUT,':raw';
				{
					no warnings 'utf8';
					if (-t STDOUT) {
						print STDOUT "\e[".( $COLOR{$method} || 0 )."m";
					}
					print STDOUT "[".uc( substr($method,0,4) )."] ".$msg;
					if (-t STDOUT) {
						print STDOUT "\e[0m";
					}
					print STDOUT "\n";
				}
			}
			if (SYSLOG and $self->{syslog}) {
				if ( !$self->{syslogopened} and $self->{d} and $self->{d}->name ) {
					$self->{syslogopened} = 1;
					openlog( $self->{d}->name, 0, LOG_DAEMON() );
				}
				my $message = (exists $MAP{lc $method} ? '': "[$method] ").$msg;
				utf8::encode $message if utf8::is_utf8 $message;
				local $@;
				eval {
					syslog( $MAP{ lc($method) } || $MAP{warning}, "%s", $message );
				};
			}
		};
		for( @logging_aliases ) {
			if ($log_level_aliases{ $_ } eq $method) {
				*$_ = \&$method;
			}
		}
	}
}

sub DESTROY {
	my $self = shift;
	if (SYSLOG and $self->{syslog} and $self->{syslogopened}) {
		closelog();
	}
}

1;
