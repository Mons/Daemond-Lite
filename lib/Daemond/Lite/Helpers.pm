package Daemond::Lite::Helpers;

use Carp;

sub import {
	my $caller = caller;
	*{$caller.'::guard'} = \&Daemond::Lite::Guard::guard;
	*{$caller.'::UID'} = {};
	*{$caller.'::GID'} = {};
	tie %{$caller.'::UID'}, 'Daemond::Lite::UID::HASH';
	tie %{$caller.'::GID'}, 'Daemond::Lite::GID::HASH';
}

package Daemond::Lite::Guard;

use strict;

sub guard(&) {
	my $code = shift;
	my $self = bless [$code], __PACKAGE__;
}
sub DESTROY {
	my $self = shift;
	@_ = ();
	goto &{ $self->[0] };
}

package Daemond::Lite::UID::HASH;

sub TIEHASH { bless do{ \(my $o) },shift;}
sub FETCH   { (getpwuid($_[1]))[0] }

package Daemond::Lite::GID::HASH;

sub TIEHASH { bless do{ \(my $o) },shift;}
sub FETCH   { (getgrgid($_[1]))[0] }

package Daemond::Lite::Tie::Handle;

use strict;
no warnings;
use base 'Tie::Handle';

our $Interceptor;

our $INSIDE;

sub TIEHANDLE {
	my $pkg = shift;
	my $sub = shift;
	bless [ $sub ],$pkg;
}
sub FILENO { undef }
sub BINMODE {}
sub READ {}
sub READLINE {}
sub GETC {}
sub CLOSE {}
sub OPEN { shift }
sub EOF {}
sub TELL {0}
sub SEEK {}
sub DESTROY {}

sub PRINT {
	my $self = shift;
	my $sub = $self->[0];
	#local $self->[0] = sub { die "Nested call at @{[ (caller)[1,2] ]}\n" };
	local $self->[0] = sub {};
	local $Interceptor = 1;
	$sub->( join($,,@_) );
}
sub PRINTF {
	my $self = shift;
	my $format = shift;
	my $sub = $self->[0];
	#local $self->[0] = sub { die "Nested call at @{[ (caller)[1,2] ]}\n" };
	local $self->[0] = sub {};
	local $Interceptor = 1;
	$sub->( sprintf($format,@_) );
}
sub WRITE {
	my $self = shift;
	my ($scalar,$length,$offset)=@_;
	my $sub = $self->[0];
	#local $self->[0] = sub { die "Nested call at @{[ (caller)[1,2] ]}\n" };
	local $self->[0] = sub {};
	local $Interceptor = 1;
	$sub->( substr($scalar,$offset,$length) );
	
}

1;
