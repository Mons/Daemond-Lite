package Daemond::Lite::Conf::YAML;

use strict;
use parent 'YAML::Loader';

my $LIMIT_LOAD = 5;
our $LOAD = 0;

sub new {
	my $class = shift;
	my $self = $class->SUPER::new();
	$self->{pathinclude} = $_[0];
	return $self; 
}

sub load {
	my $self = shift;
	local $LOAD = $LOAD+1;
	die "Limit load (no more $LIMIT_LOAD recursive inclusion)!"
		if $LOAD > $LIMIT_LOAD;
	$self->stream($_[0] || '');
	my $ret = $self->_parse();
	return $ret; 
}

sub _parse_explicit {
	my $self = shift;
	my ($node, $explicit) = @_;
	if (!ref $node and $explicit eq 'include') {
		open ( my $rin, '<:raw', $self->{pathinclude}.$node) or warn("$!"),return "$node/error $!";
		local $/;
		my $tmp = <$rin>;
		close $rin;
		return  ref($self)->new($self->{pathinclude})->load($tmp); 
	}
	else {
		return $self->SUPER::_parse_explicit(@_);
	}
}



1;
