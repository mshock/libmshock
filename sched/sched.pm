#! perl -w

package libmshock::sched;

# this is a library with utility functions for scheduling tasks
# also OO task creation and management

use libmshock;
use strict;

require Exporter;
our @ISA = qw(Exporter);
our @EXPORT_OK = qw(sched_task);

our $AUTOLOAD;

use Params::Check qw(check);
use Date::Manip qw(UnixDate);
use Time::Duration qw(from_now);

# construct a new task
sub new {
	my $class = shift;
	my $params = shift;
	
	my $tmpl = {
		cmd => {
			defined => 1,
			default => sub {},
			strict_type => 1,
		},
		sched => {
			defined => 1,
			default => 'never',
			strict_type => 1,
		},
	};
	
	my $parsed = check($tmpl,$params)
		or warning("failed to create task object: scheduled task arguments must be defined if provided")
		and return undef;
	
	my $self = {
		cmd => $parsed->{cmd},
		sched => $parsed->{sched},
		active => 0,
	};
	
	bless $self, $class;
	
	return $self;
}

# OO schedule self
sub schedule {
	my $self = shift;
	
	# check if task is already active
	if( $self->{active} && $self->{active} =~ m/^-?\d+$/ ) {
		warning(sprintf('task is already scheduled w/ PID: %s', $self->{active}));
		return;
	}
	
	# schedule the task
	# set active equal to pid
	$self->{active} = sched_task($self->{sched}, $self->{cmd});
	return $self->{active};
}

# functionally schedule a forked command
# parses a string for scheduled time
# returns child process ID
sub sched_task {
	my ($sched_string,$cmd_coderef) = shift;
	my $sched_epoch = UnixDate($sched_string,'%s')
		or fatal("could not parse schedule string: $sched_string\n");
	my $sleep_duration = $sched_epoch - time;
	
	# fork a sleeping child (phrasing)
	my $pid = fork;
	unless ($pid) {
		sleep $sleep_duration;
		&$cmd_coderef;
		exit;
	}
	vprint(sprintf("task scheduled for %s\nPID: $pid\n", from_now($sleep_duration)));
	return $pid;
}

# handle accessors w/ AUTOLOAD
sub AUTOLOAD {
	
}



sub DESTROY {};