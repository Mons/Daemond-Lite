package Daemond::Lite::Log::Object;

use strict;
use Carp;
use Log::Any ();

sub new {
	my $self = bless {}, shift;
	$self->{log} = shift;
	$self->{caller} = 1;
	$self;
}

sub is_null {
	my $self = shift;
	my $logger = Log::Any->get_logger( category => scalar caller() );
	return ref $logger eq 'Log::Any::Adapter::Null' ? 1 : 0;
}

our %METHOD = map { $_ => 1 } Log::Any->logging_methods(),Log::Any->logging_aliases;
sub prefix {
	my $self = shift;
	$self->{prefix} = shift;
}

our $AUTOLOAD;
sub  AUTOLOAD {
	my $self = $_[0];
	my ($name) = $AUTOLOAD =~ m{::([^:]+)$};
	no strict 'refs';
	if ( exists $METHOD{$name} ) {
		my $can = $self->{log}->can($name);
		*$AUTOLOAD = sub {
			warn "call $AUTOLOAD";
			my $self = $_[0];
			my ($file,$line) = (caller)[1,2];
			@_ = ($self->{log}, $self->{prefix}.$_[1].($self->{caller} ? " [$file:$line]" : ''), @_ > 2 ? (@_[2..$#_]) : ());
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
