package Daemond::Lite::Log::Object;

use strict;
use Carp;
our %METHOD;
BEGIN {
	if (eval { require Log::Any; }) {
		%METHOD = map { $_ => 1 } Log::Any->logging_methods(),Log::Any->logging_aliases;
		*HAVE_LOG_ANY = sub () { 1 };
	} else {
		*HAVE_LOG_ANY = sub () { 0 };
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
		%METHOD = map { $_ => 1 } @logging_methods,@logging_aliases;
	}
}

sub new {
	my $self = bless {}, shift;
	$self->{log} = shift;
	$self;
}

sub is_null {
	my $self = shift;
	return 0 unless HAVE_LOG_ANY;
	my $logger = Log::Any->get_logger( category => scalar caller() );
	return ref $logger eq 'Log::Any::Adapter::Null' ? 1 : 0;
}


sub prefix {
	my $self = shift;
	$self->{prefix} = shift;
}

sub syslogname {
	my $self = shift;
}

BEGIN {
	no strict 'refs';
	for my $m (keys %METHOD) {
		*$m = sub {
			my $self = $_[0];
			my $can = $self->{log}->can($m);
			no warnings 'redefine';
			*$m = sub {
				my $self = $_[0];
				@_ = ($self->{log}, $self->{prefix}.$_[1], @_ > 2 ? (@_[2..$#_]) : ());
				goto &$can;
			};
			goto &$m;
		};
	}
}

our $AUTOLOAD;
sub  AUTOLOAD {
	my $self = $_[0];
	my ($name) = $AUTOLOAD =~ m{::([^:]+)$};
	no strict 'refs';
	if ( exists $METHOD{$name} ) {
		my $can = $self->{log}->can($name);
		*$AUTOLOAD = sub {
			my $self = $_[0];
			@_ = ($self->{log}, $self->{prefix}.$_[1], @_ > 2 ? (@_[2..$#_]) : ());
			goto &$can;
		};
		goto &$AUTOLOAD;
	} else {
		if( my $can = $self->{log}->can($name) ) {
			*$AUTOLOAD = sub { splice(@_,0,1,$_[0]->{log}); goto &$can; };
			goto &$AUTOLOAD;
		} else {
			croak "No such method $name on ".ref $self;
		}
	}
}

sub DESTROY {}

1;
