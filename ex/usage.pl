#!/usr/bin/env perl

# for nodetach mode run me with -f
# -x1 denotes only one exception in child before complete exit
# 	perl usage.pl -f start -x1

use lib::abs '../lib';
use Daemond::Lite;

name 'sample';
config 'daemon.conf';
children 1;
pid '%n.%u.pid';
#nocli; # to disable start/stop/restart commands

sub check { # runned before fork and detach
	my $self = shift;
	$self->{this} = bless{},'main';
	warn "checking for $self->{cfg}{additional}{section}";
	die "Need configuration" unless $self->{cfg}{additional}{section};
}

sub start { # runned after detach but before child fork
	warn "$$ starting";
}

sub run { # runned after fork in every child process
	warn "$$ run";
	my $self = shift;
	$self->{this}{run} = 1;
	while($self->{this}{run}) {
		warn "working...";
		sleep 1;
	}
	#die "$$ gone $!";
}

sub stop { # caloled in every child when signaled
	warn "$$ stop";
	my $self = shift;
	$self->{this}{run} = 0;
}

runit();

