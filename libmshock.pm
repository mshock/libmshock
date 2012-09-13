#! perl -w

# my very own perl module
# containing many useful subroutines
# and possibly some less useful ones
# TODO: look into using Config::Param to replace Getopt::Std & Config::Simple
# TODO: add Pod::Usage documentation of module, usage() can be for callers
package libmshock;

# must support an elderly version of ActivePerl
#use 5.010_000;

use strict;

# export some useful stuff (or not)
require Exporter;
our @ISA = qw(Exporter);
our @EXPORT = qw(process_opts vprint usage REGEX_TRUE error warning sub_opt calling_self);
our @EXPORT_OK = qw(get_self id_ref create_file dot print_href);

use Carp;
use Getopt::Std qw(getopts);
use Config::Simple ('-lc');	# ignore case for config keys
use File::Basename qw(basename);


###########################################
#	globals
###########################################
# constants
use constant REGEX_TRUE => qr/true|t|y|yes|1/i;
# globals for use in calling script
our (%cli_args,%cfg_opts,$verbose,$log_handle, $die_msg);
# internal globals
my (%lib_opts);

# perform basic initialization tasks
# use caller to determine if called directly or included as module
init(caller);

# automatically process options from CLI and/or config file
#process_opts()
#	or warning('there was a problem loading your configs');

# be a good package and return true
1;


#########################################
#	begin subs	
#
#########################################

# always runs at module load/call
# TODO: load module configs from conf file (if any)
sub init {
	my ($caller_flag) = @_;
	
	# load config file for the module itself
	%lib_opts = %{load_conf('libmshock.conf')}
		or warn("could not load libmshock.conf config file - using all default configs\n");
	
	
	# initialize some additional behaviors for interrupts
	signal_hooks();
		
	# check if called from CLI or used as a module
	unless ($caller_flag) {
		# execute default behavior here when called from CLI
		run();
		# module usage message (not to be confused with extensible usage sub)
		pm_usage();
	}
	else {
		# report module load success if being used
		load_success();
	}
}

# run this code when script is called directly
sub run {
	print "this is the default run() code\n";
}

# processs generic command line options
# (verbose and help/usage)
# only argument is extra flags
# TODO: add simple mode which turns off complaints about CLI or configs if not in use
sub process_opts {
	my ($caller_opts) = @_;
	
	# get script filename minus extension
	my $self = get_self();
	
	# load CLI options, defaults and caller-specified
	getopts('vhl'.$caller_opts, \%cli_args);
	
	my $conf_file = $cli_args{c} || "$self.conf";
	
	%cfg_opts = %{load_conf($conf_file)}
		or warning('could not load config file, skipping (default mode)');
	
	usage() if $cli_args{h} || $ARGV[0];
	$verbose = $cli_args{v} || $cfg_opts{verbose} =~ REGEX_TRUE;
	my $logfile_path = $cli_args{l} || $cfg_opts{log_path} || "$self.log";
	
	# default mode will be to open logs in append mode
	load_log({
		MODE => '>>',
		PATH => $logfile_path,		
	})
		or warning('could not open log file, skipping');
	
	return 1;
}

# executes when module loads successfully when imported into another
# TODO: some way to disable this (verbosity?)
# TODO: actually check that all functionality is working
sub load_success {
	print "libmshock loaded successfully!\n";
}

# compares a variable reference against a Perl reftype (see docs for list)
# no type arg: return ref type (empty string if none)
# otherwise compare ref against type, return bool
sub id_ref {
	my ($ref, $type) = @_;
	my $ref_type = ref($ref);
	# no args, return type
	if (! defined $type) {
		return $ref_type;
	}
	# compare types
	return uc $ref_type eq uc $type; 
}

# load / create default log
# returns true on success
sub load_log {
	my ($opts) = @_;

	open($log_handle, $opts->{MODE}, $opts->{PATH})
		or error('could not handle log file'); 
		
	return tell($log_handle) != -1 ? 1 : 0;
}

# load configurations from conf file to hash
# args: conf file path, output conf file hash ref
sub load_conf {
	my ($conf_file, $cfg_href) = @_;
	
	# if no conf file, create one if create_config enabled in libmshock.conf
	if ((! -f $conf_file) && $lib_opts{create_conf}) {
		create_file($conf_file, ("# this is a template configuration file\n# hash (#) or semi-colon (;) denotes commented line"))
			or error("failed to create configuration file: $conf_file")
			and return 0;
	}
	
	my $cfg = new Config::Simple($conf_file)
		or error("could not load config file: $conf_file")
		and return 0;

	# simplified ini file, all variables under default block	
	$cfg_href = $cfg->vars()
		or warning('problem loading config file values into hash: '. $cfg->error());
	
	return $cfg_href;
}

# simple hash dump utility/debug function
# basic sorting functionality (as sub ref)
# TODO: how is performance on large hashes? possible improvements?
sub print_href {
	my ($href, $sort, $sort_func) = @_;
	
	# get hash keys
	my @keys = keys %{$href};
	$sort_func = sub {$a cmp $b} if !$sort_func;
	@keys = sort $sort_func @keys if $sort;
	
	for my $key (@keys) {
		print "$key: ", $href->{$key}, "\n";
	}	
}

# creates an empty file
# optional list argument for initial contents
# returns false or filehandle to new file
sub create_file {
	my ($file, @opt_lines) = @_;
	
	# verify not overwriting a file
	if (-f $file) {
		warning("create_file() cannot create a file that already exists (aborting): $file");
		return 0;
	}
	# create file and write optional initial lines
	open (my $fh ,'+>', $file)
		or error("could not create file for read/write: $file")
		and return 0;
	# TODO: is this the most efficient way to do this? just curious...
	print $fh join "\n", @opt_lines;
	
	return $fh;
}

# standard warning message
# notification that feature failed to load, not fatal
sub warning {
	my ($msg) = @_;
	vprint("[warning]\t$msg\n",1);
}

# standard error (not STDERR) message
# usually the root cause of why the feature failed to load
# prints $! error var for debug
sub error {
	my ($msg) = @_;
	carp $msg;
	vprint("[ error ]\t$msg: $!\n",2);
}

# standard croak (die), but also writes to log first
# useful for debugging, but may come in handy elsewhere
sub fatal {
	my ($msg) = @_;
	vprint("[ fatal ]\t$msg: $!\n",3);
}

# improved print sub for logging and verbosity
# optional level for debugging
sub vprint {
	my ($msg, $level) = @_;
	
	# only print to the log if the handle is legit
	print $log_handle $msg if defined $log_handle && tell($log_handle) >= 0;
	# only print to STDOUT if verbose mode enabled
	
	# handle level of message (not to be confused with verbosity)
	# fake switch statement
	if (!$level) {print "\n$msg\n" if $verbose;}
	elsif ($level == 1) {carp "\n$msg\n" if $verbose}
	elsif ($level == 2) {carp "\n$msg\n"}
	elsif ($level == 3) {croak "\n$msg\n"}
	else {warn "\n\nhold on to your butts!\n\n" and croak "\n$msg\n"};
	
}


# get the basename of the calling script
# options hash:
#	STRIP_EXT => remove .pl or .pm (default is true)
# TODO: add more options (various path components)
sub get_self {
	my ($opts) = @_;
	my $strip_ext = $opts->{STRIP_EXT} !~ REGEX_TRUE;
	my $name = basename($0);
	($name =~ s/\.p[lm]//i) if $strip_ext;
	return $name;
}

# processes arguments passed to subroutine in hashref
# either returns hash value for key or 0
# TODO: rewrite this whole module to use this sub
sub sub_opt {
	my ($href, $opt) = @_;
	
	error("bad options hashref $href") if ref($href) ne 'HASH';
	warning("no option passed to sub_opt()") if !$opt; 
	
	return exists $href->{$opt} ? $href->{$opt} : 0;
}



# returns true if arg is a . or .. file
# useful for filetree traversal loops (and more legible)
sub dot {
	return shift =~ /^\.+$/;
}

# release log filehandle
# and all fhs in arrayref of handles
sub cleanup {
	my ($filehandles_aref) = @_;

	for my $filehandle (@{$filehandles_aref}) {
	 	 close $filehandle if $filehandle; 
	}

	close $log_handle if $log_handle;	
}

# print usage/help statement
# intelligently handle exit code
# TODO: add caller configs to usage
sub usage {
	my $self = get_self();
	print "
usage:	$self.pl [hvl$
	-h	prints this message
	-v 	verbose mode enabled
	-l 	logfile path";
	exit($cli_args{h}?0:1);
}

# usage statement for the module itself
# TODO: integrate with generic usage sub
sub pm_usage {
	print "
libmshock.pm called directly rather than imported
you should be using this as a Perl module, silly
stay tuned for direct call functionality
";
}

# overwrite signals to execute custom functionality
# usually carp before (likely) releasing to original handler
sub signal_hooks {	
	# interrupt signal (control-C)
	$SIG{INT} = \&INT_CONFESS if $lib_opts{'default.confess_int'};
}

# custom handler for SIG{INT}
sub INT_CONFESS {
	# portable && paranoid
	$SIG{INT} = \&INT_CONFESS;
	confess "libmshock.pm caught interrupt, stack backtracing...\n";	
}