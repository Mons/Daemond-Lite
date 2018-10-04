package Daemond::Lite::Pid;

use strict;
use warnings;
use Carp;
use Cwd ();
use POSIX qw(O_EXCL O_CREAT O_RDWR); 
use Fcntl qw(LOCK_SH LOCK_EX LOCK_NB LOCK_UN);
use Scalar::Util qw(weaken);

use Daemond::Lite::Helpers;
#use Daemond::Log '$log';
#use Daemond::D;

#sub log { $log }

sub d   { $Daemond::Lite::D }
sub log { $Daemond::Lite::log }

our %REGISTRY;
END {
	# Explicitly call DESTROY
	# In some sutuations DESTROY not called, while END works better
	for (values %REGISTRY) {
		#warn "Left in registry $_";
		$_->DESTROY;
	}
}

sub DESTROY {
	my $self = shift;
	delete $REGISTRY{int $self};
	if ($self->{locked} and $self->{owner} == $$) {
		#warn "Destroying and erasing pid $self by $$";
		$self->unlink;
	} else {
		#warn "Destroying anothers ($self->{owner}) pid $self by $$";
	}
	%$self = ();
	bless $self, 'Daemond::Pid::destroyed';
}
sub Daemond::Lite::Pid::destroyed::AUTOLOAD {}

sub old { shift->{old} }
sub file { shift->{pidfile} }
sub new {
	my $pkg = shift;
	my $self = bless {@_},$pkg;
	weaken( $REGISTRY{int $self} = $self );
	$self->{file} or croak "Need args `file' and action";
	my $do = delete $self->{action};
	$self->{pidfile} = Cwd::abs_path(delete $self->{file});
	#warn "locking $self->{pidfile}";
	$self->{locked} = 0;
	$self->{owner} = 0;
	return $self;
}

sub translate {
	my $self = shift;
	$self->{pidfile} =~ s{%([nu])}{do{
		if ($1 eq 'n') {
			$self->d->name or croak "Can't assign '%n' into pid: Don't know daemon name yet";
		}
		elsif($1 eq 'u') {
			scalar getpwuid($<);
		}
		else {
			'%'.$1;
		}
	}}sge;
}

sub lock {
	my $self = shift;
	my $appname = $self->d->name;
	my $pidfile = $self->{pidfile};
	$pidfile =~ '%' and die "Pidfile contain non-translated entity\n";
	
	$self->d->say("Lock $pidfile") unless $self->{opt}{silent};
	
	if (-e $pidfile) {
		if ($self->{locked} = $self->do_lock) {
			#warn "Locked existing file";
			chomp( my $pid = do { open my $p,'<',$pidfile; local $/; <$p> }  );
			if ($pid and $pid != $$) {
				#warn "$appname - have stalled (not locked) pidfile with pid $pid\n";
				die "Have running process with pid $pid. Won't do anything. Fix this yourself\n" if kill 0 => $pid;
				truncate $self->{pidhandle},0;
			} else {
				# old process is dead
			}
		} else {
			$self->{locked} = $self->check_existing;
		}
	}
	else {
		#warn "No pidfile, let's lock\n";
		undef $!;
		$self->{locked} = $self->do_lock or do {
			if (-e $pidfile) {
				warn "File was absent but now is locked";
				$self->{locked} = $self->check_existing;
			} else {
				die "$$: Could not lock pid file $pidfile";
			}
		}
	}
	if ($self->{locked}) {
		$self->log->notice("$$: Pidfile `$pidfile' was locked") if $self->d->verbose;
		flock $self->{pidhandle},LOCK_EX | LOCK_NB or croak "Relock failed: $!";
		$self->{owner} = $$;
		$self->write();
	}
	return $self->{locked};
}

sub relock {
	my $self = shift;
	if ($self->{locked}) {
		flock $self->{pidhandle},LOCK_EX | LOCK_NB or croak "Relock failed: $!";
		$self->{owner} = $$;
		$self->write();
	} else {
		croak "Couldn't relock since not locked";
	}
}

sub forget {
	my $self = shift;
	$self->{owner} = 0;
}

sub check_existing {
	my $self = shift;
	my $appname = $self->d->name;
	my $pidfile = $self->{pidfile};
			sleep(2) if -M $pidfile < 2/86400;
			if (-e $pidfile) {
				my $oldpid = do { open my $p,'<',$pidfile or die "$!"; local $/; <$p> };
				chomp($oldpid);
				if ($oldpid) {
					$self->{old} = $oldpid;
				}
				else {
					die "$appname - Pid file $pidfile is invalid (empty) but locked.\nPossible parent exited without childs. Exiting\n";
				}
			} else {
				return $self->lock();
			}
	return;
}

sub do_lock {
	local $!;
	my $self = shift;
	my $recurse = shift || 0;
	my $file = $self->{pidfile};
	my $f;
	my $created;
	my $failures = 0;
	OPEN: {
		if (-e $file) {
			unless (sysopen($f, $file, O_RDWR)) {
				redo OPEN if $!{ENOENT} and ++$failures < 5;
				croak "open $file: $!";
			}
		} else {
			unless (sysopen($f, $file, O_CREAT|O_EXCL|O_RDWR)) {
				redo OPEN if $!{EEXIST} and ++$failures < 5;
				croak "open >$file: $!";
			}
			$created = 1;
		}
		last;
	}
	my $r = flock($f, LOCK_EX | LOCK_NB);
	{
		if ($r) {
			my @stath = stat $f or die "Can't get stat on locked handle: $!\n";
			my @statf = stat $file or do {
				die "Can't stat on file `$file': $!\n" unless $!{ENOENT};
				die "Fall into recursion during lock tries\n" if $recurse > 5;
				return $self->do_lock($recurse + 1);
			};
			if ($stath[1] != $statf[1]) {
				# there is new file entry, our locked handle is invalid now
				die "Fall into recursion during lock tries\n" if $recurse > 5;
				return $self->do_lock($recurse + 1);
			}
			$self->{owner} = $$;
			$self->{pidhandle} = $f;
			select( (select($f),$|=1)[0] );
		}else{
			$self->log->debug("$$: Lock failed: $!") if $self->d->verbose;
			close $f unless $r;
		}
	}
	return $r;
}

sub do_unlock {
	my $self = shift;
	# FIXME: check handler
	flock($self->{pidhandle}, LOCK_UN);
	return;
}

sub write : method {
	my $self = shift;
	$self->{pidhandle} or croak "Can't write to unopened pidfile";
	$self->{locked}  or croak "Mustn't write to not locked pidfile";
	$self->{owner} == $$ or croak "Mustn't write to anothers pidfile (not owner)";
	seek $self->{pidhandle},0,0;
	print {$self->{pidhandle}} "$$\n";
	seek $self->{pidhandle},0,0;
	undef $!;
	return;
}

sub read : method {
	my $self = shift;
	return eval {
		local $\;
		my $h = $self->{pidhandle} or warn ("No pidhandle"), return;
		seek $h,0,0;
		my $data = <$h>;
		seek $h,0,0;
		chomp $data if $data;
		undef $!;
		$data;
	};
}

sub unlink : method {
	my $self = shift;
	if (-e $self->{pidfile}) {{
		$self->log->notice("$$: Unlinking pidfile `$self->{pidfile}'")
			if $self->d->verbose;
		my ($u,$g) = (stat $self->{pidfile})[4,5];
		unlink $self->{pidfile} and last or $self->log->warn( "$$: Can't unlink $self->{pidfile}(uid=$UID{$u}, gid=$GID{$g}): $!" );
		open my $f, '>', $self->{pidfile} or $self->log->warn( "$$: Can't open $self->{pidfile} for writing"),last;
		truncate $f,0;
		close $f;
		$self->log->warn( "$$: Erasing pidfile content" );
	}}
}

1;
