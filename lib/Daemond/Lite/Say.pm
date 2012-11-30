package Daemond::Lite::Say;

use strict;

our %COLOR = (
	'/'        => 0,
    clear      => 0,
    reset      => 0,
    b          => 1,
    bold       => 1,
    dark       => 2,
    faint      => 2,
    underline  => 4,
    underscore => 4,
    blink      => 5,
    reverse    => 7,
    concealed  => 8,

    black      => 30,   on_black   => 40,
    red        => 31,   on_red     => 41, r => 31,
    green      => 32,   on_green   => 42, g => 32,
    yellow     => 33,   on_yellow  => 43, y => 33,
    blue       => 34,   on_blue    => 44, n => 34, # navy
    magenta    => 35,   on_magenta => 45,
    cyan       => 36,   on_cyan    => 46,
    white      => 37,   on_white   => 47, w => 37,
);

our $COLOR = join '|',keys %COLOR;
our $LASTSAY = 1;
sub say:method {
	my $self = shift;
	my $color = -t STDOUT;
	my $msg = ($LASTSAY ? '' : "\n")."<green>".$self->name."</> - ".shift;
	$LASTSAY = 1;
	for ($msg) {
		if ($color) {
			s{<($COLOR)>}{ "\033[$COLOR{$1}m" }sge;
		} else {
			s{<(?:$COLOR)>}{}sgo;
		}
		unless (s{\0$}{\033[0m}) {
			s{(?:\n|)$}{\033[0m\n};
		} else {
			$LASTSAY = 0;
		}
	}
	if (@_ and index($msg,'%') > -1) {
		$msg = sprintf $msg, @_;
	}
	print STDOUT $msg;
}

sub sayn {
	my $self = shift;
	my $color = -t STDOUT;
	my $msg = shift;
	$LASTSAY = 0;
	for ($msg) {
		if ($color) {
			s{<($COLOR)>}{ "\033[$COLOR{$1}m" }sge;
		} else {
			s{<(?:$COLOR)>}{}sgo;
		}
		if(s{\n$}{}) {
			$LASTSAY = 1;
		}
	}
	$msg .= "\033[0m\n" if $LASTSAY;
	if (@_ and index($msg,'%') > -1) {
		$msg = sprintf $msg, @_;
	}
	print STDOUT $msg;
}

sub warn:method {
	my $self = shift;
	my $msg = shift;
	$self->say('<r>'.$msg,@_);
}

sub die:method {
	my $self = shift;
	my $msg = shift;
	$self->say('<r>'.$msg,@_);
	no warnings 'internal'; # Aviod 'Attempt to free unreferenced scalar' for nester sighandlers
	exit 255;
}

1;
