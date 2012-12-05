package Daemond::Lite::Log::AdapterScreen;

use strict;
use parent qw(Log::Any::Adapter::Core);

our %COLOR = (
	trace     => "36",
	debug     => "37",
	info      => "1;37",
	notice    => "33",
	warning   => "1;33",
	error     => "31",
	critical  => "4;31",
	alert     => "1;31",
	emergency => "1;37;41",
);

sub new { my $pk = shift; bless {@_},$pk; }
sub is_null {0}
{
	no strict 'refs';
	for my $method ( Log::Any->logging_methods() ) {
		*$method = sub {
			shift;
			my $msg = shift;
			if (@_ and index($msg,'%') > -1) {
				$msg = sprintf $msg, @_;
			}
			$msg =~ s{\n*$}{};
			{
				no warnings 'utf8';
				if (-t STDOUT) {
					print STDOUT "\e[".( $COLOR{$method} || 0 )."m";
				}
				print STDOUT "[".uc( substr($method,0,4) )."] ".$msg;
				if (-t STDOUT) {
					print STDOUT "\e[0m";
				}
				print STDOUT "\n";
			}
		};
	}
	my %aliases  = Log::Any->log_level_aliases;
	for my $method ( keys %aliases ) {
		#warn "Create alias $method for $aliases{$method}";
		*$method = \&{ $aliases{ $method } };
	}
	for my $method ( Log::Any->detection_methods() ) {
		no strict 'refs';
		*$method = sub () { 1 };
	}
}


1;
