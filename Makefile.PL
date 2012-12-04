use 5.016001;
use ExtUtils::MakeMaker;
# See lib/ExtUtils/MakeMaker.pm for details of how to influence
# the contents of the Makefile that is written.
WriteMakefile(
	NAME              => 'Daemond::Lite',
	VERSION_FROM      => 'lib/Daemond/Lite.pm', # finds $VERSION
	ABSTRACT_FROM     => 'lib/Daemond/Lite.pm', # retrieve abstract from module
	PREREQ_PM         => {
		'Cwd' => 0,
		'Getopt::Long' => 0,
		'Time::HiRes' => 0,
		'Scalar::Util' => 0,
	},
	AUTHOR            => 'Mons Anderson <mons@cpan.org>',
);
