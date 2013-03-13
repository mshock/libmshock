#! perl -w

# TODO this is becoming a mess, turns out package namespace is out of whack, OO + functional collisions are becoming a hassle
# TODO refactor useful subs from other projects into this module

# my very own perl (currently, monstrous) module
# containing many useful subroutines
# and possibly some less useful ones
# TODO stuck halfway between functional and OO, convert everything entirely to OO, thinking major paradigm shift
# TODO switch to AppConfig standard with external default definitions file
# TODO switch to Log4Perl for log handling
# TODO (INV) Smart::Comments for debug messages and commenting
# TODO add Pod::Usage documentation of module, usage() can be for callers
# TODO move pod external or make inline
# TODO (INV) Moose, Mouse, Moo, Mo - so many OO modules. I am overhead averse and find 'rolling-my-own' to be highly educational - probably stick with that

package libmshock;

# TODO (INV) not everything will work if we use this version... 5.10 is standard
# must support an elderly version of ActivePerl
use 5.010_000;

use strict;

# export some useful stuff (or not)
require Exporter;
our @ISA       = qw(Exporter);
our @EXPORT    = qw(REGEX_TRUE);
our @EXPORT_OK = qw(id_ref create_file dot print_href CONF_PATH MOD_PATH);

# add the :all tag to Exporter
our %EXPORT_TAGS = ( all => [ ( @EXPORT, @EXPORT_OK ) ],
					 min => [qw()] );

use Carp;
use feature qw(say switch);
use AppConfig qw(:argcount);
# TODO (INV) Params::Validate a better alternative? or use prototypes
use Params::Check qw(check);
use File::Basename qw(basename);
use Pod::Usage qw(pod2usage);

###########################################
#	globals
###########################################
# TODO (INV) move constant declaration to external code file?
# handy constants
use constant {
	REGEX_TRUE => qr/true|(^t$)|(^y$)|yes|(^1$)/i,
	MOD_PATH   => __FILE__,

	# sorta clever initialization of config file path constant ^_^
	# newer (5.13.4+) Perl versions can avoid a do{...} block:
	# 	CONF_PATH => (__FILE__ =~ s/pm$/conf/ir),
	CONF_PATH => do { $_ = __FILE__; s/pm$/conf/i; $_ },
};

# perform basic initialization tasks
# use caller to determine if called directly or included as module
if (caller) {

	# be a good package and return true
	return 1;
}

our ( $cfg, @CLI );

# backup CLI prior to consumption
@CLI = @ARGV;

init();

#########################################
#	begin subs
#
#########################################

# always runs at module load/call
# TODO load module configs from conf file (if any)
sub init {

	# the ever-powerful and needlessly vigilant config variable - seriously
	$cfg = load_conf();

	# initialize some additional behaviors for interrupts
	signal_hooks();

	# execute default behavior here when called from CLI
	run();

}

# run this code when module is called directly from CLI
sub run {
	print "this is the default run() code\n";
}

# (re)loads configs from an optional relative path for sub-script callers
sub load_conf {
	my ($relative_path) = (@_);

	$cfg = AppConfig->new( { CREATE => 1,
							 ERROR  => \&appconfig_error,
							 GLOBAL => { ARGCOUNT => ARGCOUNT_ONE,
										 DEFAULT  => "<undef>",
							 },
						   }
	);

# bring in configuration code from external file
# separate AppConfig hash and possible future configs for ease of use
# INV: look into best practices for calling sub-packages (another module is preventing me from using Config.pm)
	require 'Config/config.pl';
	TQASched::Config::define_defaults( \$cfg );

# first pass at CLI args, mostly checking for config file setting (note - consumes @ARGV)
	$cfg->getopt();

# parse config file for those vivacious variables and their rock steady, dependable values
	$cfg->file( ( defined $relative_path ? "$relative_path/" : '' )
				. $cfg->config_file() );

	# second pass at CLI args, they take precedence over config file
	$cfg->getopt( \@CLI );

	return $cfg;
}

# return FileDate format for current day GMT
sub now_date {
	my ( $sec, $min, $hour, $mday, $mon, $year, $wday, $yday, $isdst )
		= gmtime(time);
	return sprintf( '%u%02u%02u', $year + 1900, $mon + 1, $mday );
}

# return UPD date based on current date
sub upd_date {
	my ($now_date) = @_;
	unless ( defined $now_date ) {
		$now_date = now_date();
	}
	my ( $year, $month, $mday ) = parse_filedate($now_date);
	my $time_arg = timegm( 0, 0, 0, $mday, $month - 1, $year - 1900 )
		or die "[1]\tupd_date() failed for: $now_date\n";

	# get DOW
	my ($wday) = ( gmtime($time_arg) )[6];

	# weekends use Friday's UPD
	# fastest way to get
	#	sat
	if ( $wday == 6 ) {
		$time_arg -= 86400;
	}

	#	sun
	elsif ( $wday == 0 ) {
		$time_arg -= 172800;
	}

	#	mon
	elsif ( $wday == 1 ) {
		$time_arg -= 259200;
	}

	# all other days use previous date
	else {
		$time_arg -= 86400;
	}

	# convert back to YYYYMMDD format
	( $year, $month, $mday ) = gmtime($time_arg)
		or die "[2]\tupd_date() failed for: $time_arg\n";

	# zero pad month and day
	return sprintf( '%u%02u%02u', $year, $month, $mday );
}

# compares a variable reference against a Perl reftype (see docs for list)
# no type arg: return ref type (empty string if none)
# otherwise compare ref against type, return bool
sub id_ref {
	my ( $ref, $type ) = @_;
	my $ref_type = ref($ref);

	# no args, return type
	if ( !defined $type ) {
		return $ref_type;
	}

	# compare types
	return uc $ref_type eq uc $type;
}

# parse YYYYMMDD into (y,m,d)
sub parse_filedate {
	my ($filedate) = @_;
	if ( my ( $year, $month, $mday )
		 = ( $filedate =~ m/(\d{4})(\d{2})(\d{2})/ ) )
	{
		return ( $year, $month, $mday );
	}
	return;
}

# handle any errors in AppConfig parsing - namely log them
sub appconfig_error {

	# hacky way to force always writing this log to top-level dir
	# despite the calling script's location
	my $top_log = ( __PACKAGE__ ne 'TQASched'
					? $INC{'TQASched.pm'} =~ s!\w+\.pm!!gr
					: ''
	) . $cfg->log();

	write_log( { logfile => $top_log,
				 type    => 'WARN',
				 msg     => join( "\t", @_ ),
			   }
	);
}

# read an entire file into memory
sub slurp_file {
	my ($file) = @_;
	local $/;
	my $fh;
	open( $fh, '<', $file )
		or error("could not open file for slurping: $file")
		and return;
	my $suction = <$fh>;
	close $fh;
	return $suction;
}

# calculate JDN from YMD
sub julianify {
	my ( $year, $month, $day ) = @_;
	my $a = int( ( 14 - $month ) / 12 );
	my $y = $year + 4800 - $a;
	my $m = $month + 12 * $a - 3;

	return
		  $day 
		+ int( ( 153 * $m + 2 ) / 5 ) 
		+ 365 * $y 
		+ int( $y / 4 )
		- int( $y / 100 ) 
		+ int( $y / 400 )
		- 32045;
}

# init handles method, a little different from standard
# only imports DBI if called
sub init_handle {
	my @db_hrefs = @_;

	require DBI;
	DBI->import();	

	my @dbhs = ();
	for my $db (@db_hrefs) {
		# connecting to master since database may need to be created
		push @dbhs,
			DBI->connect(
			sprintf(
				"dbi:ODBC:Database=%s;Driver={SQL Server};Server=%s;UID=%s;PWD=%s",
				$db->{name} || 'master', $db->{server},
				$db->{user}, $db->{pwd}
			)
			) or die "failed to initialize database handle\n";
	}
	return \@dbhs;
}


# translate weekday string to localtime int code
sub code_weekday {
	my $weekday = shift;
	my $rv;
	given ($weekday) {
		when (/monday|mon/i)    { $rv = 1 }
		when (/tuesday|tues?/i)   { $rv = 2 }
		when (/wednesday|wed/i) { $rv = 3 }
		when (/thursday|thurs?/i)  { $rv = 4 }
		when (/friday|fri/i)    { $rv = 5 }
		when (/saturday|sat/i)  { $rv = 6 }
		when (/sunday|sun/i)    { $rv = 0 }
		default             { $rv = -1 };
	}
	return $rv;
}

# add ordinal component to numeric values (-st,-nd,-rd,-th)
sub ordinate {
	my ($number) = (@_);
	my $ord = '';
	given ($number) {
		when (/1[123]$/) { $ord = 'th' }
		when (/1$/)      { $ord = 'st' }
		when (/2$/)      { $ord = 'nd' }
		when (/3$/)      { $ord = 'rd' }
		default          { $ord = 'th' };
	}
	return $number . $ord;
}

# current timestamp SQL DateTime format for GMT or machine time (local)
sub timestamp {
	my @now
		= $cfg->tz() =~ m/(?:GM[T]?|UT[C]?)/i
		? gmtime(time)
		: localtime(time);
	return
		sprintf "%4d-%02d-%02d %02d:%02d:%02d",
		$now[5] + 1900,
		$now[4] + 1,
		@now[ 3, 2, 1, 0 ];
}

# total seconds after midnight calculation
sub offset_midnight_seconds {
	my ( $hour, $min, $sec ) = @_;
	return $hour * 3600 + $min * 60 + $sec;
}

# human readable clock time string from seconds offset
sub offset_clock_minutes {
	my $offset = shift;

	my $hours   = int( $offset / 60 );
	my $minutes = $offset - $hours * 60;
	return sprintf '%02u:%02u', $hours, $minutes;
}

# returns true if arg is a . or .. file
# useful for filetree traversal loops (and more legible)
sub dot {
	return shift =~ /^\.+$/;
}

# print usage/help statement
# intelligently handle exit code
# TODO use Pod::Usage
sub usage {
	my ($exit_val) = @_;
	pod2usage( { -verbose => $cfg->verbosity,
				 -exit    => $exit_val || 0
			   }
	);
}

# TODO (INV) is there a better way to get stack backtrace out of confess?
# overwrite signals to execute custom functionality
# usually carp before (likely) releasing to original handler
sub signal_hooks {

	# interrupt signal (control-C)
	$SIG{INT} = \&INT_CONFESS if $cfg->{confess_int};
}

# custom handler for SIG{INT}
sub INT_CONFESS {

	# portable && paranoid
	$SIG{INT} = \&INT_CONFESS;
	confess "libmshock.pm caught interrupt, stack backtracing...\n";
}

# end script, begin POD
__END__

=head1 NAME

libmshock - mshock's library of more-or-less handy Perl functions

=head1 SYNOPSIS

	# import into script:
	use libmshock;
	my $libmshock = libmshock->new(\%opts);
	
	# or call from CLI
	libmshock.pm [vh] [-l logfile] [function] [args...]
		-v 	verbose mode
		-h 	print usage/help
		-l 	logfile for module
	
=head1 LICENSE AND COPYRIGHT

Copyright (c) 2012 Matt Shockley

This library is free software; you can redistribute it and/or
modify it under the same terms as Perl itself.

=head1 BUGS AND LIMITATIONS

See TODO or INV comment tags for more info on current bugs and limitations.

=head1 INCOMPATIBILITIES

This module is/was mostly tested and debugged under ActivePerl v5.10 due to production limitations.
It is possible that there will be incompatibilities using this module under Perl versions older than v5.10.

=head1 AVAILABILITY

git clone https://github.com/mshock/libmshock.git

=head1 AUTHOR

Matt Shockley <shockleyme |AT| gmail.com>

=head1 VERSION

1.00

=head2 Methods

=over

=item load()

Returns a new libmshock object.
Possible ways to call B<new()>
	$lib = new 
	$lib = new libmshock(\%cfg);
	
=back


=cut
