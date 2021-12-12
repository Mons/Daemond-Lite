package Daemond::Lite::Log::Simple;

use strict;
use Carp;
use Daemond::Lite::Log ();

our %MAP;
sub LOG_EMERG    () { 0 }
sub LOG_ALERT    () { 1 }
sub LOG_CRIT     () { 2 }
sub LOG_ERR      () { 3 }
sub LOG_WARNING  () { 4 }
sub LOG_NOTICE   () { 5 }
sub LOG_INFO     () { 6 }
sub LOG_DEBUG    () { 7 }

sub LOG_KERN     () { 0 }
sub LOG_USER     () { 8 }
sub LOG_MAIL     () { 16 }
sub LOG_DAEMON   () { 24 }
sub LOG_AUTH     () { 32 }
sub LOG_SYSLOG   () { 40 }
sub LOG_LPR      () { 48 }
sub LOG_NEWS     () { 56 }
sub LOG_UUCP     () { 64 }
sub LOG_CRON     () { 72 }
sub LOG_AUTHPRIV () { 80 }
sub LOG_FTP      () { 88 }
sub LOG_LOCAL0   () { 128 }
sub LOG_LOCAL1   () { 136 }
sub LOG_LOCAL2   () { 144 }
sub LOG_LOCAL3   () { 152 }
sub LOG_LOCAL4   () { 160 }
sub LOG_LOCAL5   () { 168 }
sub LOG_LOCAL6   () { 176 }
sub LOG_LOCAL7   () { 184 }

my %FACILITY;
BEGIN {
	%FACILITY = (
		kern     => LOG_KERN,
		user     => LOG_USER,
		mail     => LOG_MAIL,
		daemon   => LOG_DAEMON,
		auth     => LOG_AUTH,
		syslog   => LOG_SYSLOG,
		lpr      => LOG_LPR,
		news     => LOG_NEWS,
		uucp     => LOG_UUCP,
		cron     => LOG_CRON,
		authpriv => LOG_AUTHPRIV,
		ftp      => LOG_FTP,
		local0   => LOG_LOCAL0,
		local1   => LOG_LOCAL1,
		local2   => LOG_LOCAL2,
		local3   => LOG_LOCAL3,
		local4   => LOG_LOCAL4,
		local5   => LOG_LOCAL5,
		local6   => LOG_LOCAL6,
		local7   => LOG_LOCAL7,
	);
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

sub syslog ($$@);

sub new {
	my $pkg = shift;
	my $d = shift;
	my $syslog = 0;
	my $facility;
	if (my $cf = $d->{cfg}{log} && $d->{cfg}{log}{syslog} ) {
		$cf->{module} //= "Unix::Syslog";
		eval qq{require $cf->{module};} or die $@;
		$syslog = $cf->{module};
		if ($cf->{setlogsock}) {
			$syslog->can('setlogsock')->( $cf->{setlogsock} );
		}
		if ($cf->{facility}) {
			$facility = $FACILITY{ $cf->{facility} } or die "Unsupported facility: $cf->{facility}\n";
		}
	} else {
		if( eval{ require Unix::Syslog } ) {
			$syslog = "Unix::Syslog";
		}
		elsif( eval{ require Sys::Syslog; } ) {
			$syslog = "Sys::Syslog";
			warn "Usage of Sys::Syslog may be dangerous in long-running processes. Better install Unix::Syslog\n";
		}
	}
	if ($syslog) {
		*syslog = $syslog->can('syslog');
	}
	my $self = bless {
		screen => 1,
		syslog => $syslog,
		facility => $facility,
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
			if ($self->{syslog}) {
				if ( !$self->{syslogopened} and $self->{d} and $self->{d}->name ) {
					$self->{syslogopened} = 1;
					$self->{syslog}->can('openlog')->( $self->{d}->name, 0, $self->{facility} // LOG_DAEMON() );
				}
				my $message = (exists $MAP{lc $method} ? '': "[$method] ").$msg;
				utf8::encode $message if utf8::is_utf8 $message;
				eval {
					syslog( $MAP{ lc($method) } || $MAP{warning}, "%s", $message );
					1;
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
	if ($self->{syslog} and $self->{syslogopened}) {
		$self->{syslog}->can('closelog')->();
	}
}

1;
