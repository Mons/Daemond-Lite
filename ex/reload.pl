#!/usr/bin/perl
use 5.010;
use utf8;
use strict;
use warnings;

use EV;
use AnyEvent;
use Daemond::Lite;
use AnyEvent::HTTP::Server;

use Socket;
use Fcntl;
use Data::Dumper;
use Digest::MD5 qw(md5 md5_hex md5_base64);

name 'reload';
config 'reload.conf';
children 2;
pid '/tmp/%n.%u.pid';

# nocli; # start without commands (start/stop)

my $sockets;

sub set_nocloexec {
	my $fh = shift;
	my $flags = fcntl $fh, F_GETFD, 0 or return;
	fcntl $fh, F_SETFD, $flags & ~FD_CLOEXEC;
}

sub set_nonblock {
	my $fh = shift;
	my $flags = fcntl $fh, F_GETFL, 0 or return;
	fcntl $fh, F_SETFL, $flags | O_NONBLOCK;
}

sub check { # before detach, but after all configuration
	my $self = shift;
	warn "$$ checking";
	# die "port is undefined" unless ($self->{cfg}->{port});
	1;
}

my $PAGE = do { local $/ = undef; <DATA> };
$PAGE //= "%%%GEN%%%";

sub start { # before fork
	my $self = shift;
	warn "$$ starting";
	warn $self->{rising};
	$self->{this}{http} = AnyEvent::HTTP::Server->new(
		host   => $self->{cfg}{host},
		port   => $self->{cfg}{port},
		listen => $self->{cfg}{listen},
		(sockets => $sockets) x !! $sockets,
		favicon => undef,
		cb   => sub {
			my $r = shift;
			my $rid = md5_base64(rand(0xffffffff) . time());
			$self->log->info("[%s] Request %s %s%s from [%s]. UA=\"%s\" RF=\"%s\"", $rid,
				$r->method, $r->uri, ($r->headers->{'content-length'} ? '+'.$r->headers->{'content-length'}.'b' : ''),
				$r->headers->{'x-real-ip'},
				$r->headers->{'user-agent'},
				$r->headers->{'referer'});
			if ($r->method eq 'CALL') {
				# warn $r->body;
				my $body = '';
				return sub {
					my ($is_last, $bodypart) = @_;
					$body .= $$bodypart;
					return unless $is_last;
					my $ret = eval $body;
					$r->reply(201, $ret, headers => {
						'content-type' => 'text/plain',
					});
				};
			}
			return 405 unless ($r->method eq 'GET');
			
			(my $res = $PAGE) =~ s/%%%GEN%%%/$self->{rising}/me;
			return 200, $res;
		}
	);
	$self->{this}{http}->listen;
}

sub perish {
	my $self = shift;
	warn "$$ perish";
	my %ret;
	for (keys %{$self->{this}{http}{fhs_named}}) {
		$ret{$_} = fileno($self->{this}{http}{fhs_named}{$_});
		set_nocloexec($self->{this}{http}{fhs_named}{$_});
	}
	return \%ret;
}

sub rise {
	my $self = shift;
	warn "$$ rise ", $self->{rising};
	my $data = shift;
	for (keys %$data) {
		open my $f, "+<&=$data->{$_}" or die "open: $!";
		$data->{$_} = $f;
		set_nonblock($f);
	}
	$sockets = $data;
}

sub run { # inside forked child
	warn "$$ run";
	my $self = shift;
	$self->{this}{run} = 1;
	$self->{this}{http}->accept;
	EV::loop;
}

sub stop {
	warn "$$ stop";
	my $self = shift;
	$self->{this}->{run} = 0;
	$self->{this}{http}->noaccept;
	my $w; $w = EV::timer 1, 0, sub {
		undef $w;
		EV::unloop;
	};
}

runit();

__DATA__
<!DOCTYPE html>
<html lang="en">
	<head>
		<title>reloas.pl</title>
	</head>
	<body>
		<h1>Reload generation %%%GEN%%%</h1>
	</body>
</html>
