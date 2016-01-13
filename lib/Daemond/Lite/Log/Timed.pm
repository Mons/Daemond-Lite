package Daemond::Lite::Log::Timed;

use strict;
use Carp;
use POSIX qw(strftime );
use Time::HiRes ();
use Time::Local qw( timelocal_nocheck timegm_nocheck );
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

{
	my $tzgen = int(time()/600)*600;
	my $tzoff = timegm_nocheck( localtime($tzgen) ) - $tzgen;
	#warn "gen at ".localtime()." as for ".localtime($tzgen);
	sub localtime_c {
		my $time = shift // time();
		if ($time > $tzgen + 600) {
			$tzgen = int($time/600)*600;
			$tzoff = timegm_nocheck( localtime($tzgen) ) - $tzgen;
		}
		gmtime($time+$tzoff);
	}
	
	sub date {
		my ($time,$ms) = Time::HiRes::gettimeofday();
		if ($time > $tzgen + 600) {
			$tzgen = int($time/600)*600;
			$tzoff = timegm_nocheck( localtime($tzgen) ) - $tzgen;
		}
		if ($INC{'EV.pm'}) {
			*date = \&date_ev;
			goto &date_ev;
		}
		sprintf("%s.%03d",strftime("%Y-%m-%dT%H:%M:%S",gmtime($time+$tzoff)),int($ms/1000));
	}
	
	sub date_ev {
		my ($time,$ms) = Time::HiRes::gettimeofday();
		if ($time > $tzgen + 600) {
			$tzgen = int($time/600)*600;
			$tzoff = timegm_nocheck( localtime($tzgen) ) - $tzgen;
		}
		sprintf( "%s.%03d/%+0.3f",strftime("%Y-%m-%dT%H:%M:%S",gmtime($time+$tzoff)),int($ms/1000), EV::now() - $time - $ms/1e6 );
	}
}

our ( %log_level_aliases, @logging_methods, @logging_aliases );

BEGIN {
	%log_level_aliases = (
		inform => 'info',
		warn   => 'warning',
		err    => 'error',
		crit   => 'critical',
		fatal  => 'critical'
	);
	@logging_methods = qw(trace debug info notice warning error critical alert emergency);
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
		tzoff  => 0,
		write_time_to_syslog => 1,
		@_,
	}, $pkg;
	$self;
}

BEGIN {
	no strict 'refs';
	for my $method ( @logging_methods, ) {
		*$method = sub {
			my $self = shift;
			my $msg = shift;
			if (@_ and index($msg,'%') > -1) {
				$msg = sprintf $msg, @_;
			}
			$msg =~ s{\n*$}{};
			my $fullmsg = date().' '.$msg;
			if ($self->{screen}) {
				binmode STDOUT,':raw';
				{
					no warnings 'utf8';
					if (-t STDOUT) {
						print STDOUT "\e[".( $COLOR{$method} || 0 )."m";
					}
					print STDOUT "[".uc( substr($method,0,4) )."] ".$fullmsg;
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
				my $message = (exists $MAP{lc $method} ? '': "[$method] ").( $self->{write_time_to_syslog} ? $fullmsg : $msg );
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
