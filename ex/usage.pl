#!/usr/bin/env perl

use lib::abs '../lib';
use Daemond::Lite;

name 'sample';
config 'daemon.conf';
children 1;
pid '%n.%u.pid';
nocli;
syslog 'local0';

sub start {
	warn "$$ starting";
}

sub run {
	warn "$$ run";
	my $self = shift;
	$self->{run} = 1;
	while($self->{run}) {
		sleep 1;
	}
	#die "$$ gone $!";
}

sub stop {
	warn "$$ stop";
	my $self = shift;
	$self->{run} = 0;
}

runit();

