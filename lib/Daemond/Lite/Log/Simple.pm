package Daemond::Lite::Log::Simple;

use strict;

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

sub is_null { 0 }

sub new {
	my $self = bless {}, shift;
	$self->{log} = shift;
	$self->{caller} = 1;
	$self;
}

our %METHOD = map { $_ => 1 } @logging_methods,@logging_aliases;

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
		*$AUTOLOAD = sub {
			my $self = $_[0];
			my ($file,$line) = (caller)[1,2];
			printf STDERR 
				$self->{prefix}.$_[1].($self->{caller} ? " [$file:$line]\n" : "\n"),
				@_ > 2 ? (@_[2..$#_]) : ();
		};
		goto &$AUTOLOAD;
	} else {
		croak "No such method $name on ".ref $self;
	}
}

sub DESTROY {}

1;
