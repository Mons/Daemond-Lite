package Daemond::Lite::Daemonization;

use strict;
use Carp;
use Daemond::Lite::Helpers;
use Time::HiRes qw(sleep time);
use POSIX qw(WNOHANG);
use Errno;

our @SIG;
BEGIN {
	use Config;
	@SIG = split ' ',$Config{sig_name};
	$SIG[0] = '';
}
BEGIN {
	*CORE::GLOBAL::exit = sub (;$) { defined &CORE::exit ? goto &CORE::exit : CORE::exit($_[0]); };
}
our $on_end;
END {
	$on_end and $on_end->();
}

# ->process( $daemon )

sub process {
	# To avoid some bullshit, add alarm
	my $pkg = shift;
	my $self = shift; # << Really a daemon object
	return unless $self->{cf}{detach};
	return if $self->{detached}++;
	my $name = $self->{cf}{name};
	
	my $proc = sub {
		$0 = "<> $name: @_ (perl)";
	};
	my $slog;
	
	if (0) {}
	elsif ( eval { require Sys::Syslog; Sys::Syslog::openlog($name, "ndelay,pid", "local0") } ) {
		#warn "Create syslog";
		my $g = guard {
			#warn "closing log";
			closelog();
		};
		$slog = sub {
			my $msg;
			if (@_ > 1 and index($_[0], '%') > -1) {
				$msg = sprintf $_[0], @_[1..$#_];
			} else {
				$msg = "@_";
			}
			$msg =~ s{\n+$}{}s;
			Sys::Syslog::syslog( Sys::Syslog::LOG_WARNING(), "%s", $msg );
			return if $Daemond::Lite::Tie::Handle::Interceptor;
			eval { printf STDERR $msg; };
			$g = $g;
		}
	}
	elsif ( open my $cmd,'|-',"logger -t '${name}[$$]'" ) {
		close $cmd;
		pipe my $r,my $w;
		select( (select($r),$|++,select($w),$|++)[0] );
		
		defined( my $pid = fork ) or die "Could not fork for logger: $!";
		unless($pid) {
			close $w;
			$proc->("temporary syslog");
			for (@SIG) {
				length() and $SIG{$_} = 'IGNORE';
			}
			#$SIG{INT} = $SIG{TERM} = $SIG{QUIT} = 'IGNORE';
			open my $cmd,'|-',"logger -t '${name}[$$]'";
			while ( sysread( $r, my $buf, 4096 ) ) {
				next if $! == Errno::EINTR or $! == Errno::EAGAIN;
				{ syswrite($cmd, $buf) > 0 or ( ($! == Errno::EINTR or $! == Errno::EAGAIN) and redo ) or last }
			}
			#warn "logger gone: $!";
			exit;
		}
		close $r;
		$slog = sub {
			my $msg;
			if (@_ > 1 and index($_[0], '%') > -1) {
				$msg = sprintf $_[0], @_[1..$#_];
			} else {
				$msg = "@_";
			}
			$msg .= "\n" unless substr($msg,-1,1) eq "\x0a";
			eval { syswrite( $w, $msg ); };
			return if $Daemond::Lite::Tie::Handle::Interceptor;
			eval { printf STDERR $msg; };
		};
		
	}
	else {
		 warn "Could not open temporary syslog command (logger): $!\n";
		 # TODO: Sys::Syslog?
		 $slog = sub {
			return if $Daemond::Lite::Tie::Handle::Interceptor;
			my $msg;
			if (@_ > 1 and index( $_[0], '%')> -1) {
				$msg = sprintf $_[0], @_[1..$#_];
			} else {
				$msg = "@_";
			}
			$msg .= "\n" unless substr($msg,-1,1) eq "\x0a";
			printf STDERR $msg;
		 };
	}
	
	local $SIG{__WARN__} = sub {
		$slog->("WARN @_");
	};
	local $SIG{__DIE__} = sub {
		$slog->("DIED @_");
	};
	local $SIG{INT} = local $SIG{TERM} = local $SIG{QUIT} = sub {
		$slog->("SIG @_");
	};
	local *CORE::GLOBAL::exit = sub (;$) {
		$slog->("exit @_ called from @{[ (caller)[1,2] ]}");
		defined &CORE::exit ? goto &CORE::exit : CORE::exit($_[0]);
	};
	$proc->("instantiator");
	
	my $parent = $$;
	defined( my $pid = fork ) or die "Could not fork: $!";
	if ($pid) { # controlling terminal
		*CORE::GLOBAL::exit = sub (;$) { defined &CORE::exit ? goto &CORE::exit : CORE::exit($_[0]); };
		$proc->("control");
		select( (select(STDOUT),$|=1,select(STDERR),$|=1)[0] );
		if ($self->{pid}) {
			$self->{pid}->forget;
			
			my $timeout = $self->{cf}{start_timeout};
			
			local $_ = $self->{pid}->file;
			$SIG{ALRM} = sub {
				$self->die("Daemon not started in $timeout seconds. Possible something wrong. Look at syslog");
			};
			alarm $timeout;
			$self->say("<y>waiting for $pid to gone</>..\0");
			while(1) {
				if( my $kid = waitpid $pid,WNOHANG ) {
					my ($exitcode, $signal, $core) = ($? >> 8, $SIG[$? & 127] || ($? & 127), $? & 128);
					if ($exitcode != 0 or $signal or $core) {
						# Shit happens with our child
						local $! = $exitcode;
						$self->sayn(
							"<r>exited with code=$exitcode".($exitcode > 0 ? " ($!)" : '')." ".
							($signal ? "(sig: $signal)":'').
							($core && $signal ? ' ' : '').
							( $core ? '(core dumped)' : '')."\n");
						exit 255;
					} else {
						# it's ok
						$self->sayn(" <g>done</>\n");
					}
					sleep 0.1;
					last;
				} else {
					$self->sayn(".");
					sleep 0.1;
				}
			}
			$self->say("<y>Reading new pid</>...\0");
			while (1) {
				my $newpid = $self->{pid}->read;
				if ($newpid == $pid) {
					-e or $self->die("Pidfile disappeared. Possible daemon died. Look at syslog");
					$self->sayn(".");
					sleep 0.1;
				} else {
					$pid = $newpid;
					$self->sayn(" <g>$pid</>\n");
					last;
				}
			}
			alarm 0;
			$self->say("<y>checking it's live</>...\0");
			sleep 0.3;
			unless (kill 0 => $pid) {
				$self->sayn(" <r>no process with pid $pid. Look at syslog\n");
				exit 255;
			}
			$self->sayn(" <g>looks ok</>\n");
			sleep 1;
			#kill 9 => $pid;
=for rem
		alarm 0;
		# unless $child;
		sleep 1 if kill 0 => $child; # give daemon time to die, if it have some errors
		kill 0 => $child or die "Daemon lost. PID $child is absent. Look at syslog\n";
=cut
		}
		exit;
	} # 1st fork
	$proc->("intermediate");
	
	# Exitcode tests
	#die "Test";
	#kill KILL => $$;
	#kill SEGV => $$;
	#exit 255;
	
	# Make fork once again to fully detach from controller
	defined( $pid = fork ) or die "Could not fork: $!";
	if ($pid) {
		*CORE::GLOBAL::exit = sub (;$) { defined &CORE::exit ? goto &CORE::exit : CORE::exit($_[0]); };
		#warn "forked 2 $pid";
		$self->{pid}->forget if $self->{pid};
		exit;
	}
	$proc->("main [waiting]");
	waitpid(getppid, 0);
	$proc->("main");
	$self->{pid}->relock() if $self->{pid}; # Relock after forks
	
	# Exit test
	
	POSIX::setsid() or die "Can't detach from controlling terminal";
	
	$self->{pid}->relock() if $self->{pid}; # Relock after forks
	
	$pkg->redirect_output($self, $slog);
	
	#close $cmd;
=for TODO
	$pkg->chroot($self);
	$pkg->change_user($self);
=cut
	#$self->log->notice("Daemonized! $$");
	#$slog->("daemonized: $$");
	#$on_end = sub {
	#	warn( "Process $$ gone" );
	#};
	return;
}

sub redirect_output {
	my $pkg = shift;
	my $self = shift;
	my $logcmd = shift;
	return unless $self->{cf}{detach};
	# Keep fileno of std* correct.
	#$self->log->notice("std* fileno = %d, %d, %d", (fileno STDIN, fileno STDOUT, fileno STDERR));
	#$logcmd->("Logging ok");
	close STDIN;  open STDIN,  '<', '/dev/null' or die "open STDIN  < /dev/null failed: $!";
	close STDOUT; open STDOUT, '>', '/dev/null' or die "open STDOUT > /dev/null failed: $!";
	close STDERR; open STDERR, '>', '/dev/null' or die "open STDERR > /dev/null failed: $!";
	#$logcmd->( "STD closed %d, %d, %d", fileno STDIN, fileno STDOUT, fileno STDERR );
	if ($self->{cf}{verbose} > 0) {
		tie *STDERR, 'Daemond::Lite::Tie::Handle', sub { $self->log->warning("STDERR: ".$_[0]) };
	}
	#$logcmd->("Logging ok\n");
	if ($self->{cf}{verbose} > 1) {
		tie *STDOUT, 'Daemond::Lite::Tie::Handle', sub { $self->log->debug("STDOUT: ".$_[0]) };
	}
	#$self->log->notice("std* fileno = %d, %d, %d", fileno STDIN, fileno STDOUT, fileno STDERR);
	#$self->log->warn( "Logging initialized" );
	#$logcmd->("Logging ok");
	return;
}

=for TODO
sub change_user {
	my $pkg = shift;
	my $self = shift;
	$self->d->user or $self->d->group or return;
	my @chown;
	my ($uid,$gid);
	warn "before change user we have UID=$UID{$<}($<), GID=$GID{$(}($(); EUID=$UID{$>}($>), EGID=$GID{$)}($))\n";
	if(defined( local $_ = $self->{user} )) {
		defined( $uid = (getpwnam $_)[2] || (getpwuid $_)[2] )
			or croak "Can't switch to user $_: No such user";
	}
	if(defined( local $_ = $self->{group} )) {
		defined( $uid = (getgrnam $_)[2] || (getgrgid $_)[2] )
			or croak "Can't switch to group $_: No such group";
	}
	if ($> == 0) {
		#warn "I'm root, I can do anything";
		# First, chown files. Later we'll couldn't do this
		for (qw( pid log )) {
			my $handle = $self->{$_.'handle'};
			local $_ = $self->{$_.'file'};
			next unless -e $_;
			my ($u,$g) = (stat)[4,5];
			#warn "my file $_ have uid=$UID{$u}($u), gid=$GID{$g}($g)";
			#local $!;
			chown $uid || -1,$gid || -1, $handle || $_ or croak "chown $_ to uid=$UID{$uid}($uid), gid=$GID{$gid}($gid) failed: $!";
			#($u,$g) = (stat)[4,5];
			#warn "now my file $_ have uid=$UID{$u}($u), gid=$GID{$g}($g)";
		}

		local $!;
		$> = $uid if defined $uid;
		croak "Change uid failed: $!" if $!;
		$) = $gid if defined $gid;
		croak "Change gid failed: $!" if $!;
	}
	else {
		croak "Can't change uid or gid by user $UID{$>}($>). Need root";
	}
	warn "after change user we have UID=$UID{$<}($<), GID=$GID{$(}($(); EUID=$UID{$>}($>), EGID=$GID{$)}($))\n";
	return
}

sub chroot {
	#TODO
}

=cut

1;
