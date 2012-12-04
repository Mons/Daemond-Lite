package Daemond::Lite;

=head1 NAME

Daemond::Lite - Lightweight version of daemonization toolkit

=head1 SYNOPSIS

    package main;
    use Daemond::Lite;
    
    name 'sample';
    config 'daemon.conf';
    children 1;
    pid '/tmp/%n.%u.pid';
    nocli;
    syslog 'local0';

    sub start { # before fork
        warn "$$ starting";
    }

    sub run { # inside forked child
        warn "$$ run";
        my $self = shift;
        $self->{run} = 1;
        while($self->{run}) {
            sleep 1;
        }
    }

    sub stop {
        warn "$$ stop";
        my $self = shift;
        $self->{run} = 0;
    }

    runit()

=head1 DESCRIPTION

    Easy tool for creating daemons

=cut

our $VERSION = '0.05';

use strict;

use Cwd;
use FindBin;

use Daemond::Lite::Conf;
use Getopt::Long qw(:config gnu_compat bundling);

use Data::Dumper;

#use Daemond::Lite::Log '$log';
use Log::Any '$log';
BEGIN {
		require Log::Any::Adapter;
		Log::Any::Adapter->set('+Daemond::Lite::Log::AdapterScreen');
}

use Daemond::Lite::Daemonization;

use Time::HiRes qw(time sleep);
use POSIX qw(WNOHANG);
# TODO: sigtrap

our $D;
sub log : method { $log }

sub import {
	my $pk = shift;
	$D ||= bless {
		env => {},
		src => {},
	}, $pk;
	my $caller = caller;
	$D->{caller} and $D->die("Duplicate call of $pk from $caller. Previous was from $D->{caller}");
	$D->{caller} = $caller;
	for my $m (keys %Daemond::Lite::) {
		next unless $m =~ s{^export_}{};
		no strict 'refs';
		my $proto = prototype \&{ 'export_'.$m };
		$proto = '@' unless defined $proto;
		*{ $caller.'::'. $m } = eval qq{
			sub ($proto) { &export_$m( \$D,\@_ ) };
		};
	}
}

use Daemond::Lite::Say;
*say  = \&Daemond::Lite::Say::say;
*sayn = \&Daemond::Lite::Say::sayn;
*warn = \&Daemond::Lite::Say::warn;
*die  = \&Daemond::Lite::Say::die;

=for rem
sub die {
	my $self = shift;
	my $msg = "@_";
	substr($msg,length $msg) = "\n"
		if substr($msg,-1,1) ne "\x0a";
	die ($msg);
}

sub warn {
	my $self = shift;
	my $msg = "@_";
	substr($msg,length $msg) = "\n"
		if substr($msg,-1,1) ne "\x0a";
	warn ($msg);
}

sub say {
	my $self = shift;
	my $msg = "@_";
	substr($msg,length $msg) = "\n"
		if substr($msg,-1,1) ne "\x0a";
	print $self->{cf}{name}.': '.$msg;
}

=cut

sub verbose { $_[0]{cf}{verbose} }
sub name    { $_[0]{src}{name} || $_[0]{cfg}{name} || $0 }
sub is_parent { $_[0]{is_parent} }

#### Export functions

sub export_name($) {
	my $self = shift;
	$self->{src}{name} = shift;
}

sub export_nocli () {
	shift->{src}{cli} = 0;
}

sub export_syslog($) {
	warn "TODO: syslog";
}

sub export_config($) {
	my $self = shift;
	-e $_[0] or $self->die("No config file found: $_[0]\n");
	$self->{config_file} = shift;
}

sub export_children ($) {
	my $self = shift;
	$self->{src}{children} = shift;
}

sub export_pid ($) {
	my $self = shift;
	$self->{src}{pid} = shift;
}

sub export_runit () {
	my $self = shift;
	$self->configure;
	
	if ($self->{cf}{cli}) {
		warn "Running cli";
	}
	elsif ($self->{pid}) {
		warn "Running only pid";
		if( $self->{pid}->lock ) {
			# OK
		} else {
			$self->die("Pid lock failed");
		}
	}
	else {
		$self->warn("No CLI, no PID. Beware!");
	}
	$self->say("<g>starting up</>... (pidfile = ".$self->abs_path( $self->{cf}{pid} ).", pid = <y>$$</>, detach = ".$self->{cf}{detach}.", log is null: ".$self->log->is_null.")");
	
	if( $self->log->is_null ) {
		#$self->d->warn("You are using null Log::Any. You will see no logs. Maybe you need to set up is with Log::Any::Adapter");
		$self->warn("You are using null Log::Any. We just setup a simple screen adapter. Maybe you need to set it up with Log::Any::Adapter?");
		require Log::Any::Adapter;
		Log::Any::Adapter->set('+Daemond::Lite::Log::AdapterScreen');
	}
	#$self->log->prefix("$$ PARENT: ");
	$self->log->notice("starting...");
	
	warn "runit @_";
	
	$self->{cf}{children} > 0 or $self->die("Need at least 1 child");
	
	Daemond::Lite::Daemonization->process( $self );
	
	$self->setup_signals;
	$self->setup_scoreboard;
	$self->{startup} = 1;
	$self->{is_parent} = 1;
	
	
	if (my $start = $self->{caller}->can('start')) {
		$start->($self);
	}
	
	while () {
		#$self->d->proc->action('idle');
		if ($self->{shutdown}) {
			$self->log->notice("Received shutdown notice, gracefuly terminating...");
			#$self->d->proc->action('shutdown');
			last;
		}
		$self->check_scoreboard;
		$self->idle or sleep 0.1;
	}
	$self->shutdown();
	return;
}

#### Export functions

sub configure {
	my $self = shift;
	$self->{conf} = {};
	$self->env_config;
	$self->load_config;
	$self->getopt_config;
	$self->merge_config();
	if ($self->{cf}{pid}) {
		require Daemond::Lite::Pid;
		warn $self->{cf}{pid};
		$self->{cf}{pid} =~ s{%([nu])}{do{
			if ($1 eq 'n') {
				$self->{cf}{name} or $self->die("Can't assign '%n' into pid: Don't know daemon name");
			}
			elsif($1 eq 'u') {
				scalar getpwuid($<);
			}
			else {
				$self->die( "Pid name contain non-translateable entity $1" );
				'%'.$1;
			}
		}}sge;
		warn $self->{cf}{pid};
		$self->{pid} = Daemond::Lite::Pid->new( file => $self->abs_path($self->{cf}{pid}) );
		
	}
	
}

sub env_config {
	my $self = shift;
	$self->{env}{cwd} = $FindBin::Bin;
	$self->{env}{bin} = $FindBin::Script;
}

sub abs_path {
	my ($self,$file) = @_;
	$file = $self->{env}{cwd}.'/'.$file
		if substr($file,0,1) ne '/';
	return Cwd::abs_path( $file );
}

sub load_config {
	my $self = shift;
	my $file = $self->{config_file};
	$file = $self->{env}{cwd}.'/'.$file
		if substr($file,0,1) ne '/';
	$self->{cfg} = Daemond::Lite::Conf::load($self->abs_path( $file ));
}

sub getopt_config {
	my $self = shift;
	my %opts = (
		#detach   => 1,
		#children => 1,
		#verbose  => 0,
		#max_die  => 10,
	);
	my %getopt = (
		"nodetach|f!"       => sub { $opts{detach} = 0 },
		"children|c=i"      => sub { shift;$opts{children} = shift },
		"verbose|v+"        => sub { $opts{verbose}++ },
		'exit-on-error|x=i' => sub { shift; $opts{max_die} = shift },
		'pidfile|p=s'       => sub { shift; $opts{pidfile} = shift; },
	);
	if (my $getopt = $self->{caller}->can('getopt')) {
		my %add = $getopt->($self, \%opts);
		for (keys %add) {
			if (defined $add{$_}) {
				$getopt{$_} = $add{$_};
			} else {
				delete $getopt{$_};
			}
		}
	}
	my %defs = %opts;
	GetOptions(%getopt) or $self->usage(\%getopt, \%defs); # TODO: defs
	$self->{opt} = \%opts;
}

=for rem

source:
	name, pid, conffile, ...
config:
	name, pid, ...
getopt:
	conffile, pid, ...

=cut

sub is_defined(@) {
	if (defined $_[1]) {
		($_[0], $_[1])
	} else {
		();
	}
}

sub _opt {
	my $self = shift;
	my $opt = shift;
	my $src = [ qw(opt cfg src) ];
	if (@_ and ref $_[0]) {
		$src = shift;
	}
	my $def = shift;
	for (@$src) {
		if ( defined $self->{$_}{$opt} ) {
			return ( $opt => $self->{$_}{$opt} );
		}
	}
	if( defined $def ) {
		return ( $opt => $def );
	}
	else {
		()
	}
}

sub merge_config {
	my $self = shift;
	#warn Dumper $self;
	my %cf = (
		$self->_opt( 'name', [qw(src cfg env)], $0 ), # TODO
		
		$self->_opt('children', 1),
		$self->_opt('verbose',  0),
		$self->_opt('detach',   1),
		$self->_opt('max_die',  10),
		
		$self->_opt('cli', [qw(src cfg opt)], 1),
		$self->_opt('pid'),
		
		start_timeout => 10,
		signals => [qw(TERM INT QUIT HUP USR1 USR2)],
	);
	$self->{cf} = \%cf;
	warn Dumper $self->{cf};
}

sub usage {
	my $self = shift;
	my $opts = shift;
	my $defs = shift;
	
	$self->merge_config;
	
	print "Usage:\n\t$self->{env}{bin} [options]";
	if ( $self->{cf}{cli} ) {
		print " command";
	}
	print "\n\nOptions are:\n";
	for ( sort keys %$opts ) {
		my %opctl;
		my ($names) = / ((?: \w+[-\w]* )(?: \| (?: \? | \w[-\w]* ) )*) /sx;
		my %names; @names{ split /\|/, $names } = ();
		my ($name, $orig) = Getopt::Long::ParseOptionSpec ($_, \%opctl);
		#warn Dumper [$name, \%opctl];
		print "\t";
		my $op = $opctl{$name}[0];
		my $oplast;
		my $first;
		for ( $name, grep $_ ne $name, keys %opctl ) {
			next if !exists $names{$_};;
			print " | " if $first++;
			if (length () > 1 ) {
				print "--";
			} else {
				print "-";
			}
			print "$_";
			if ($op eq 's') {
				print + (length()>1 ? '=value' : 'S' );
			}
			elsif ($op eq 'i') {
				print + (length()>1 ? '=number' : 'X' );
			}
			elsif ($op eq '') {
				#print "($op)";
			}
			else {
				#print STDERR " ($opctl{$name}[0])";
			}
			
			#print STDERR "$_";
		}
		if ($op eq 's' or $op eq 'i' or $op eq '') {
		}
		else {
			print " ($op)";
		}
		if (exists $defs->{$name}) {
			print " (default = $defs->{$name})";
		}
		print "\n\n";
		#my ($name, $short, $type) = 
		#print STDERR ""
	}
	
	exit(255);
}

sub setup_signals {
	my $self = shift;
	# Setup SIG listeners
	# ???: keys %SIG ?
	my $for = $$;
	my $mysig = 'Daemond::Lite::SIGNAL';
	#for my $sig ( qw(TERM INT HUP USR1 USR2 CHLD) ) {
	$SIG{PIPE} = 'IGNORE';
	for my $sig ( @{ $self->{cf}{signals} } ) {
		my $old = $SIG{$sig};
		if (defined $old and UNIVERSAL::isa($old, $mysig) or !ref $old) {
			undef $old;
		}
		$SIG{$sig} = sub {
			eval {
				if ($self) {
					$self->sig(@_);
				}
			};
			warn "Got error in SIG$sig: $@" if $@;
			goto &$old if defined $old;
		};
		bless $SIG{$sig}, $mysig;
	}
	$SIG{CHLD} = sub { $self->SIGCHLD(@_) };
	$SIG{PIPE} = 'IGNORE' unless exists $SIG{PIPE};
}

sub sig {
	my $self = shift;
	my $sig = shift;
	if ($self->is_parent) {
		if( my $sigh = $self->can('SIG'.$sig)) {
			@_ = ($self);
			goto &$sigh;
		}
		$self->log->debug("Got sig $sig, terminating");
		exit(255);
	} else {
		return if $sig eq 'INT';
		return if $sig eq 'CHLD';
		if( my $cb = $self->{caller}->can( 'SIG'.$sig ) ) {
			@_ = ($self,$sig);
			goto &$cb;
		} else {
			$self->log->debug("Got sig $sig, terminating");
			exit(255);
		}
	}
}

sub childs {
	my $self = shift;
	keys %{ $self->{chld} };
}

sub SIGTERM {
	my $self = shift;
	unless ($self->is_parent) {
		if($self->{shutdown}) {
			$self->log->warn("Received TERM during shutdown, force exit");
			exit(1);
		} else {
			$self->log->warn("Received TERM...");
		}
		$self->call_stop();
		return;
	}
	if($self->{shutdown}) {
		$self->log->warn("Received TERM during shutdown, force exit");
		kill KILL => -$_,$_ for $self->childs;
		exit 1;
	}
	$self->log->warn("Received TERM, shutting down");
	$self->{shutdown} = 1;
	my $timeout = ( $self->{cf}{exit_timeout} || 10 ) + 1;
	$self->log->warn("Received TERM, shutting down with timeout $timeout");
	$SIG{ALRM} = sub {
		$self->log->critical("Not exited till alarm, killall myself");
		kill KILL => -$_,$_ for $self->childs;
		no warnings 'internal'; # Aviod 'Attempt to free unreferenced scalar' for nester sighandlers
		exit( 255 );
	};
	alarm $timeout;
}

sub SIGINT {
	my $self = shift;
	$self->{shutdown} = 1;
}

sub SIGCHLD {
	my $self = shift;
		while ((my $child = waitpid(-1,WNOHANG)) > 0) {
			my ($exitcode, $signal, $core) = ($? >> 8, $SIG[$? & 127] // $? & 127, $? & 128);
			my $died;
			if ($exitcode != 0) {
				# Shit happens with our child
				$died = 1;
				{
					local $! = $exitcode;
					$self->log->alert("CHLD: child $child died with $exitcode ($!) (".($signal ? "sig: $signal, ":'')." core: $core)");
				}
			} else {
				if ($signal || $core) {
					{
						local $! = $exitcode;
						$self->log->alert("CHLD: child $child died with $signal (exit: $exitcode/$!, core: $core)");
					}
				}
				else {
					# it's ok
					$self->log->debug("CHLD: child $child normally gone");
				}
			}
			my $pid = $child;
			if($self->{chld}) {
				if (defined( my $data=delete $self->{chld}{$pid} )) { # if it was one of ours
					my $slot = $data->[0];
					$self->score_drop($slot);
					if ($died) {
						$self->{dies}++;
						if ( $self->{cf}{max_die} > 0 and $self->{dies} + 1 > ( $self->{cf}{max_die} ) * $self->{cf}{children} ) {
							$self->log->critical("Children repeatedly died %d times, stopping",$self->{_}{dies});
							$self->shutdown(); # TODO: stop
						}
					} else {
						$self->{dies} = 0;
					}
				} 
				else {
					$self->log->warn("CHLD for $pid child of someone else.");
				}
			}
		}
	
}

sub setup_scoreboard {
	my $self = shift;
	$self->{score} = ':'.('.'x$self->{cf}{children});
}

sub score_take {
	my ($self, $status) = @_;
	if( ( my $idx = index($self->{score}, '.') ) > -1 ) {
		length $status or $status = "?";
		$status = substr($status,0,1);
		substr($self->{score},$idx,1) = $status;
		return $idx;
	} else {
		return undef;
	}
}

sub score_drop {
	my ($self, $slot) = @_;
	if ( $slot > length $self->{score} ) {
		warn "Slot $slot over bound";
		return 0;
	}
	if ( substr($self->{score},$slot, 1) ne '.' ) {
		substr($self->{score},$slot, 1) = '.';
		return 1;
	}
	else {
		warn "slot $$ not taken";
		return 0;
	}
}

sub check_scoreboard {
	my $self = shift;
	
	return if $self->{forks} > 0; # have pending forks

	#DEBUG_SC and $self->diag($self->score->view." CHLD[@{[ map { qq{$_=$self->{chld}{$_}[0]} } $self->childs ]}]; forks=$self->{_}{forks}");
	
	my $count = $self->{cf}{children};
	my $check = 0;
	my $update;
	while( my ($pid, $data) = each %{ $self->{chld} } ) {
		my ($slot) = @$data;
		if (kill 0 => $pid) {
			# child alive
			$check++;
		} else {
			$self->log->critical("child $pid, slot $slot exited without notification? ($!)");
			delete $self->{chld}{$pid};
			$self->score_drop($slot);
		}
	}
	#warn "check: $check/$count is alive";
	#$self->log->debug( "Current childs: %s",$self->dumper(\%check) );
	
	if ( $check != $count ) {
		$update = $count - $check;
		$self->log->debug("actual childs ($check) != required count ($count). change by $update")
			if $self->verbose > 1;
	}
	
	#$self->log->debug( "Update: %s",join ', ',map { "$_+$update{$_}" } keys %update ) if %update and $self->d->verbose > 1;
	if ( $update > 0 ) {
		$self->start_workers($update);
	} else {
		#DEBUG_SC and $self->diag("Killing %d",-$count);
		while ($update < 0) {
			my ($pid,$data) = each %{ $self->{chld} };
			kill TERM => $pid or $self->log->debug("killing $pid: $!");
			$update++;
		}
	}
}

sub start_workers {
	my $self = shift;
	my ($n) = @_;
	$n > 0 or return;
	#$self->d->proc->action('forking '.$n);
	warn "start_workers +$n";
	for(1..$n) {
		$self->{forks}++;
		$self->fork() or return;
	}
}

sub DEBUG_SLOW() { 0 }
sub DO_FORK() { 1 }
sub fork : method {
	my ($self) = @_;

	# children should not honor this event
	# Note that the forked POE kernel might have these events in it already
	# This is unavoidable :-(
	$self->log->alert("!!! Child should not be here!"),return if !$self->is_parent;
	$self->log->notice("ignore fork due to shutdown"),return if $self->{shutdown};
	#warn "$$: fork";

	####
	if ( $self->{forks} ) {
		$self->{forks}--;
		#$self->d->proc->action($self->{_}{forks} ? 'forking '.$self->{_}{forks} : 'idle' );
	};

	DEBUG_SLOW and sleep(0.2);

	my $slot = $self->score_take( 'F' ); # grab a slot in scoreboard

	# Failure!  We have too many children!  AAAGH!
	unless( defined $slot ) {
		$self->log->critical( "NO FREE SLOT! Something wrong ($self->{score})" );
		return;
	}
	
	# TODO!!!
	#pipe my $rh, my $wh or die "Watch pipe failed: $!";
	
	my $pid;
	if (DO_FORK) {
		$pid = fork();
	} else {
		$pid = 0;
	}
	unless ( defined $pid ) {            # did the fork fail?
		$self->log->critical( "Fork failed: $!" );
		$self->score->drop($slot);   # give slot back
		return;
	}
	DEBUG_SLOW and sleep(0.2);
	
	if ($pid) {                         # successful fork; parent keeps track
		$self->{chld}{$pid} = [ $slot ];
		$self->log->debug( "Parent server forked a new child [slot=$slot]. children: (".join(' ', $self->childs).")" )
			if $self->verbose > 0;
		
		if( $self->{forks} == 0 and $self->{startup} ) {
			# End if pre-forking startup time.
			delete $self->{startup};
		}
		return 1;
	}
	else {
		$self->{is_parent} = 0;
		#DEBUG and $self->diag( "I'm forked child with slot $slot." );
		#$self->log->prefix('CHILD F.'.$alias.':');
		#$self->d->proc->info( state => FORKING, type => "child.$alias" );
		$self->exec_child();
		# must not reach here
		exit 255;
		
	}
	return;
}

sub shutdown {
	my $self = shift;
	
	#$self->d->proc->action('shutting down');
	
	my $finishing = time;
	
	my %chld = %{$self->{chld}};
	#$SIG{CHLD} = 'IGNORE';
	if ( $self->{chld} and %chld  ) {
		# tell children to go away
		$self->log->debug("TERM'ing children [@{[ keys %chld ]}]") if $self->verbose > 1;
		kill TERM => $_ or delete($chld{$_}),$self->warn("Killing $_ failed: $!") for keys %chld;
	}
	
	DEBUG_SLOW and sleep(2);
	
	$self->{shutdown} = 1 ;
	
	$self->log->debug("Reaping kids") if $self->verbose > 1;
	my $timeout = ( $self->{cf}{exit_timeout} || 10 ) + 1;
	while (1) {
		my $kid = waitpid ( -1,WNOHANG );
		#( DEBUG or DEBUG_SIG ) and
			$kid > 0 and $self->log->notice("reaping $kid");
		delete $chld{$kid} if $kid > 0;
		if ( time - $finishing > $timeout ) {
			$self->log->alert( "Timeout $timeout exceeded, killing rest of processes @{[ keys %chld ]}" );
			kill KILL => $_ or delete($chld{$_}) for keys %chld;
			last;
		} else {
			last if $kid < 0;
			sleep(0.01);
		}
	}
	$self->log->debug("Finished") if $self->verbose;
	exit;
}


sub idle {}

sub setup_child_sig {
	my $self = shift;
	$SIG{PIPE} = 'IGNORE';
	$SIG{CHLD} = 'IGNORE';
	my %sig = (
		TERM => bless(sub {
			warn "$$: term received"; 
			$self->{shutdown}++ and exit(1);
			if( my $cb = $self->{caller}->can( 'stop' ) ) {
				$cb->($self);
			} else {
				exit(0);
			}
		}, 'Daemond::Lite::SIGNAL'),
		INT => bless(sub { warn "$$: sigint to child"; }, 'Daemond::Lite::SIGNAL'),
	);
	if( my $cb = $self->{caller}->can( 'on_sig' ) ) {
		for my $sig (keys %sig) {
			$cb->($self, $sig, $sig{$sig});
		}
	} else {
		for my $sig (keys %sig) {
			$SIG{$sig} = $sig{$sig};
		}
	}
}

sub exec_child {
	my $self = shift;
	$self->setup_child_sig;
	
	eval {
		if( my $cb = $self->{caller}->can( 'run' ) ) {
			$cb->($self);
			$self->log->notice("Child $$ correctly finished");
		} else {
			die "Whoa! no run at start!";
		}
	1} or do {
		my $e = $@;
		$self->log->error("Child error: $e");
		die $e;
	};
	exit;
}

sub call_stop {
	my $self = shift;
	
}

1;
__END__
=back

=head1 AUTHOR

Mons Anderson, C<< <mons@cpan.org> >>

=head1 COPYRIGHT & LICENSE

Copyright 2012 Mons Anderson, all rights reserved.

This program is free software; you can redistribute it and/or modify it
under the terms of either: the GNU General Public License as published
by the Free Software Foundation; or the Artistic License.

=cut
