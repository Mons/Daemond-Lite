package Daemond::Lite::Cli;

use strict;
use warnings;
use Carp;
use Cwd ();
use Daemond::Lite::Log '$log';

sub log { $_[0]{d}->log }

sub d { $_[0]{d} }
sub new {
	my $pkg = shift;
	my $self = bless { @_ }, $pkg;
	return $self;
}

sub force_quit { shift->d->exit_timeout }

sub commands {
	[ 'start',    "Start the process", ],
	[ 'stop',     "Stop the process", ],
	[ 'restart',  "Restart the process", ],
}

sub usage {
	my $self = shift;
	$self->d->usage;
};

sub process {
	my $self = shift;
	my $pid = $self->{pid} or croak "Pid object required for Cli to operate";
	my $do = $ARGV[0] or $self->usage;
	$self->help if $do eq 'help';
	
	my $appname = $self->d->name; # TODO
	
	my $killed = 0;
	$self->{locked} = 0;
	my $info = "<b><green>$appname</>";
	
	if ($pid->lock) {
		# OK
	}
	elsif (my $oldpid = $pid->old) {
		if ($do eq 'stop' or $do eq 'restart') {
			$killed = $self->kill($oldpid);
			exit if $do eq 'stop';
			$self->{locked} = $pid->lock;
		}
		elsif ($do eq 'check') {
			if (kill(0,$oldpid)) {
				$self->d->say( "<g>running</> - pid <r>$oldpid</>");
				#$self->pidcheck($pidfile, $oldpid);
				exit;
			} 
		}
		elsif ($do eq 'start') {
			$self->d->say( "is <b><red>already running</> (pid <red>$oldpid</>)" );
			exit(3);
		}
		else {
			$self->action(\$do,$oldpid);
		}
	}
	else {
		$self->d->say( "<red>pid neither locked nor have old value</>");
		exit 255;
	}
	
	$self->d->say( "<y><b>no instance running</>" )
		if $do =~ /^(?:stop|check)$/ or ($do eq 'restart' and !$killed);
		#if $do =~ /^(reload|stop|check)$/ or ($do eq 'restart' and !$killed);
	
	exit if $do =~ /^(?:stop|check)$/;
	#$self->pidcheck($pidfile),exit if $do eq 'check';
	
	$self->d->say("<b><y>unknown command: <r>$do</>"),$self->usage if $do !~ /^(restart|start)$/;;
	#$self->log->debug("$appname - $do");
}

sub action {
	my ($self,$doref,$oldpid) = @_;
	$self->d->say( "<b><y>unknown command: <r>$$doref</>");
	$self->usage;
}

sub kill {
	my ($self, $pid) = @_;
	
	my $appname = $self->d->name; # TODO
	
	my $talkmore = 1;
	my $killed = 0;
	if (kill(0, $pid)) {
		$killed = 1;
		kill(INT => $pid);
		$self->d->say("<y>killing $pid with <b><w>INT</>");
		my $t = time;
		sleep(1) if kill(0, $pid);
		if ($self->force_quit and kill(0, $pid)) {
			$self->d->say("<y>waiting for $pid to die...</>");
			$talkmore = 1;
			while(kill(0, $pid) && time - $t < $self->force_quit + 2) {
				sleep(1);
			}
		}
		if (kill(TERM => $pid)) {
			$self->d->say("<y>killing $pid group with <b>TERM</><y>...</>");
			if ($self->force_quit) {
				while(kill(0, $pid) && time - $t < $self->force_quit * 2) {
					sleep(1);
				}
			} else {
				sleep(1) if kill(0, $pid);
			}
		}
		if (kill(KILL =>  $pid)) {
			$self->d->say("<y>killing $pid group with <r><b>KILL</><y>...</>");
			my $k9 = time;
			my $max = $self->force_quit * 4;
			$max = 60 if $max < 60;
			while(kill(0, $pid)) {
				if (time - $k9 > $max) {
					print "Giving up on $pid ever dying.\n";
					exit(1);
				}
				print "Waiting for $pid to die...\n";
				sleep(1);
			}
		}
		$self->d->say("<g>process $pid is gone</>") if $talkmore;
	} else {
		$self->d->say("<y>process $pid no longer running</>") if $talkmore;
	}
	return $killed;
}

1;

