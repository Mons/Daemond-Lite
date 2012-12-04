package Daemond::Lite::Log::AdapterScreen;

use strict;
use parent qw(Log::Any::Adapter::Core);

sub new { my $pk = shift; bless {@_},$pk; }
sub is_null {0}
{
	no strict 'refs';
	for my $method ( Log::Any->logging_methods() ) {
		#warn "Create method $method";
		*$method = sub {
			shift;
			#warn "call $method from @{[  ( caller )[1,2] ]}";
			my $msg = shift;
			my $fileline = join ':', ( caller )[1,2];
			if (@_ and index($msg,'%') > -1) {
				$msg = sprintf $msg, @_;
			}
			$msg =~ s{\n*$}{};
			{
				no warnings 'utf8';
				print STDOUT "[\U$method\E] ".$msg." [$fileline]\n";
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
