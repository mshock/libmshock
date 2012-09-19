#! perl -w

# my very own perl module
# containing many useful subroutines
# and possibly some less useful ones
# TODO: stuck halfway between functional and OO, convert everything entirely to OO, thinking major paradigm shift
# INV: Moose, Mouse, Moo, Mo - so many OO modules. I am overhead averse and find 'rolling-my-own' to be highly educational - probably stick with that
# TODO: look into using Config::Param to replace Getopt::Std & Config::Simple
# TODO: add Pod::Usage documentation of module, usage() can be for callers
package libmshock;

# must support an elderly version of ActivePerl
use 5.010_000;

use strict;

# export some useful stuff (or not)
require Exporter;
our @ISA = qw(Exporter);
our @EXPORT = qw(process_opts vprint REGEX_TRUE error warning);
our @EXPORT_OK = qw(get_self id_ref create_file dot print_href CONF_PATH MOD_PATH);

use Carp;
use Params::Check qw(check);
use Getopt::Std qw(getopts);
use Config::General;
use File::Basename qw(basename);


###########################################
#	globals
###########################################
# handy constants
use constant {
	REGEX_TRUE => qr/true|t|y|yes|1/i,
	MOD_PATH => __FILE__,
	# sorta clever initialization of config file path constant ^_^
	# newer (5.13.4+) Perl versions can avoid a do{...} block:
	# 	CONF_PATH => (__FILE__ =~ s/pm$/conf/ir),
	CONF_PATH => do {$_ = __FILE__; s/pm$/conf/i; $_ },
};

# globals for use in calling script
our (%cli_args,%cfg_opts,$verbose,$log_handle, $die_msg);
# implement AUTOLOAD
our $AUTOLOAD;
# internal globals
my (%lib_opts);

# perform basic initialization tasks
# use caller to determine if called directly or included as module
init(caller);

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
	%lib_opts = %{load_conf(CONF_PATH)}
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
		# report module load success if being imported
		load_success() if $verbose;
	}
}

# run this code when module is called directly from CLI
sub run {
	print "this is the default run() code\n";
}

# object constructor for calling script
sub load {
	# create new libmshock object
	my ($this, $params_href) = @_;
	$params_href = {} if !$params_href;
	my $class = ref($this) || $this;
		
	# load options from config file
	# = load_conf(CONF_PATH);
	# load/override options from CLI
	
	# load/override options from constructor arguments	
	
	# template for checking all constructor parameters
	my $tmpl = {
		auto_add => {
			default => 'false',
			defined => 1,
			
		}
	};
	my $opts = check($tmpl, $params_href, $verbose)  
		or fatal("problem with constructor parameters: " . Params::Check::last_error());
	
	
	# default attributes/opts for object
	my $self = {
		auto_add => $opts->{auto_add},
	};
	
	# create the class instance
	bless $self, $class;
	
	return $self;
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
	
	# load caller script's config file options
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
	print "libmshock.pm loaded successfully!\n";
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
	if ((! -f $conf_file) && exists $lib_opts{create_conf} && $lib_opts{create_conf} =~ REGEX_TRUE) {
		create_file($conf_file, ("# this is a template configuration file\n# hash (#) or semi-colon (;) denotes commented line"))
			or error("failed to create config file: $conf_file")
			and return;
	}
	elsif (! -f $conf_file) {
		error("failed to find config file: $conf_file and auto_create not enabled") and return;
	}
	
	my $cfg = new Config::General( (
		-ConfigFile => $conf_file,
		-IncludeRelative => 1,
		-LowerCaseNames => 1,
		
	))
		or error("could not load config file: $conf_file")
		and return;

	# get all configs from loaded file into hash
	%{$cfg_href} = $cfg->getall
		or warning("problem loading config file values into hash: $!");
	
	# dump conf key pairs (testing)
	#print_href({hashref => $cfg_href});
	
	return $cfg_href;
}

# simple hash dump utility/debug function
# basic sorting functionality (as sub ref)
# TODO: how is performance on large hashes? possible improvements?
sub print_href {
	my ($href, $sort, $sort_func);
	
	my $tmpl = {
		hashref	=> { required => 1, default => {}, defined => 1, strict_type => 1, store => \$href },
		enable_sort => {default => 0, defined => 1, strict_type => 1, store => \$sort},
		sort_func => {default => sub {$a cmp $b}, defined => 1 , strict_type => 1, store => \$sort_func} 
	};
	check($tmpl,shift,$verbose)
		or warning('print_href() arg check failed: ' . Params::Check::last_error());
	
	# get hash keys
	my @keys = keys %{$href};
	@keys = sort $sort_func @keys if $sort;
	
	for my $key (@keys) {
		print "$key => ", $href->{$key}, "\n";
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
	# fake switch statement (Switch is deprecated)
	if (!$level) {print "\n$msg\n" if $verbose}
	elsif ($level == 1) {carp "\n$msg\n" if $verbose}
	elsif ($level == 2) {carp "\n$msg\n"}
	elsif ($level == 3) {croak "\n$msg\n"}
	else {warn "\n\nhold on to your butts!\n\n" and croak "\n$msg\n"};
	
}


# get the basename of the calling script
# TODO: add more options (various path components)
sub get_self {
	my ($strip_extension) = @_;
	my $name = basename($0);
	($name =~ s/\.p[lm]//i) if $strip_extension !~ REGEX_TRUE;
	return $name;
}

# returns true if arg is a . or .. file
# useful for filetree traversal loops (and more legible)
sub dot {
	return shift =~ /^\.+$/;
}

# release log filehandle
# and all fhs in arrayref of handles
sub cleanup {
	my ($fhs_aref);

	my $tmpl = {
		filehandles => {default => [], defined => 1, strict_type => 1, store => \$fhs_aref}
	};
	check($tmpl, shift, $verbose)
		or warning('cleanup() arg check failed: ' . Params::Check::last_error());

	for my $filehandle (@{$fhs_aref}) {
	 	 close $filehandle; 
	}

	close $log_handle if $log_handle;	
}

# print usage/help statement
# intelligently handle exit code
# TODO: use Pod::Usage
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

# use AUTOLOAD to handle all get/set OO operations
sub AUTOLOAD {
	my ($self, @args) = @_;
	# get/set: get_attribute/set_attribute
	my ($operation, $attribute) = ($AUTOLOAD =~ /(get|set)_(\w+)/i);
	# not a get/set operation
	error("Method name $AUTOLOAD is not in the recognized form (get|set)_attribute\n") and return 
		unless ($operation && $attribute);
	# no such attribute to get or add+set not enabled
		error("No such attribute '$attribute' exists in the class " . ref($self)) and return
			unless (exists $self->{$attribute} || $self->{auto_add} =~ REGEX_TRUE);
	
	
	# handle operation & define sub for future use
	if (lc $operation eq 'get') {
		# temporarily disable strict refs to alter symbol table
		{	
			no strict 'refs';
			*{$AUTOLOAD} = sub {return shift->{$attribute}};
		}
		return $self->{$attribute};
	}
	elsif (lc $operation eq 'set') {
		{
			no strict 'refs';
			*{$AUTOLOAD} = sub {return shift->{$attribute} = shift};
		}
		return $self->{$attribute} = $args[0];
	}
	
}

# empty DESTROY to avoid AUTOLOAD call
sub DESTROY {}

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

=item new()

Returns a new libmshock object.
Possible ways to call B<new()>
	$lib = new 
	$lib = new libmshock(\%cfg);
	

=item C<>


=back


=cut