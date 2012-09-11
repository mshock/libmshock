#! perl -w

# my very own perl module
# containing many useful subroutines
# and possibly some less useful ones
# TODO: research converting messages to Carp module
package libmshock;

use strict;

# export some useful stuff (or not)
require Exporter;
our @ISA = qw(Exporter);
our @EXPORT = qw(process_opts vprint usage REGEX_TRUE error warning sub_opt);
our @EXPORT_OK = qw(get_self id_ref);

use Carp;
use Switch;
use Getopt::Std;
use Config::Simple ('-lc');	# ignore case for config keys
use File::Basename;


# globals
use constant REGEX_TRUE => qr/true|t|y|yes|1/i;
our (%cli_args,%cfg_opts,$verbose,$log_handle);
# additional usage message customization hash
# TODO: implement adding hash values to usage message
our %usage_mod;

# catch if module is run directly from CLI
run_harness();

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
sub run_harness {
	load_conf('libmshock.conf')
		or warn("could not load libmshock config file, using all default configs\n");
	if (calling_self()) {
		# execute default behavior here when called from CLI
		pm_usage();
	}
	else {
		# report module load success if being used
		load_success();
	}
}

# processs generic command line options
# (verbose and help/usage)
# only argument is extra flags
# TODO: add simple mode which turns off complaints about CLI or configs if not in use
sub process_opts {
	my ($opts) = @_;
	
	# get script filename minus extension
	my $self = get_self();
	
	# load CLI options, defaults and caller-specified
	getopts('vhl'.$opts, \%cli_args);
	
	my $conf_file = $cli_args{c} || "$self.conf";
	
	load_conf($conf_file)
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

# check if called directly from CLI or imported
# (intended for use in utility Perl modules)
sub calling_self {
	return (caller)[0] !~ m/main/;
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
	
	my $cfg = new Config::Simple($conf_file)
		or error('could not load config file: ' . $conf_file);
	
	%{$cfg_href} = $cfg->vars()
		or warning('problem loading config file values into hash');	
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


# improved print sub for logging and verbosity
# optional level for debugging
sub vprint {
	my ($msg, $level) = @_;
	
	# only print to the log if the handle is legit
	print $log_handle $msg if tell($log_handle) >= 0;
	# only print to STDOUT if verbose mode enabled
	
	# handle level of message (not to be confused with verbosity)
	switch($level) {
		case 1 {
			carp $msg if $verbose;			
		}
		case 2 {
			carp $msg;
		}
		case 3 {
			croak $msg;
		}
		case {$level > 3} {
			print "Hold on to your butts!\n";
			croak $msg;
		}
		else {
			print $msg if $verbose;
		}
	}
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
# TODO: add user options and docs
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