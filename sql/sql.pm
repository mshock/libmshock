#! perl -w

package libmshock::sql;

use strict;

require Exporter;
our @ISA = qw(Exporter);
our @EXPORT_OK = qw(verify_db_href init_handles);

use libmshock;
use Params::Check qw(check);
use DBI;

# create a new a new sql db object
sub new {
	my $class = shift;
	my $params = shift;

	my $parsed = verify_db_href($params)
		or return undef;
	
	my $self = {
		name => $parsed->{name},
		server => $parsed->{server},
		user => $parsed->{user},
		pwd => $parsed->{pwd},
	};
	
	bless $self, $class;
	return $self;
}

# use OO attr to create and return handle
sub get_handle {
	return (init_handles(shift))[0]; 
}

# verify that a hashref contains all expected database info
sub verify_db_href {
	my $db = shift;
	
	my $tmpl = {
		name => {
			required => 1,
			defined => 1,
			default => '',
			strict_type => 1,
		},
		server => {
			default => 'localhost',
			strict_type => 1,		
		},
		user => {
			required => 1,
			defined => 1,
			default => '',
			strict_type => 1,
		},
		pwd => {
			default => '',
			strict_type => 1,
		},
	};
	return check($tmpl,$db);
}

# create database handles
sub init_handles {
	my @db_info = @_;
	
	my @dbhs;
	for my $db (@db_info) {
		my $parsed = verify_db_href($db)
			or warning(Params::Check::last_error())
			and next;
		my $dbh = DBI->connect(
			sprintf("dbi:ODBC:Driver={SQL Server};Database=%s;Server=%s;UID=%s;PWD=%s",
				$parsed->{name},
				$parsed->{server},
				$parsed->{user},
				$parsed->{pwd}
			)	
		) 
			or warning(DBI->errstr)
			and next;
		push @dbhs, $dbh;
	}
	return @dbhs;
}

# BCP interface subs - see BCPlib for a BCP-only module

# OO bcp import interface
sub bcp_in {
	my $self = shift;
	my $params = shift;
	
	$params->{db} = $self;
	$params->{op} = 'in';
	
	# handle bcp command
	return bcp($params);
}

# OO bcp export interface
sub bcp_out {
	my $self = shift;
	my $params = shift;
	
	$params->{db} = $self;
	$params->{op} = 'out';
	
	return bcp($params);
}

# OO bcp query export interface
sub bcp_queryout {
	my $self = shift;
	my $params = shift;
	
	$params->{db} = $self;
	$params->{op} = 'queryout';
	
	return bcp($params);
}

# BCP functional interface
sub bcp {
	my $params = shift;
	
	my ($op,$db,$bcp_path,$table,$error_log,$encoding,$query_out);
	
	my $tmpl = {
		op => {
			required => 1,
			allow => qr/^(in|out|queryout)$/i,
			store => \$op,
		},
		query => {
			defined => 1,
			store => \$query_out,
		},
		db => {
			required => 1,
			defined => 1,
			allow => sub {return $_->isa('sql')},
			store => \$db,
		},
		bcp_path => {
			required => 1,
			defined => 1,
			store => \$bcp_path,
		},
		table => {
			defined => 1,
			store => \$table,
		},
		error_log => {
			default => 'bcp.errors',
			strict_type => 1,
			store => \$error_log,
		},
		encoding => {
			default => 'c',
			strict_type => 1,
			allow => qr/^[cnNw]$/,
			store => \$encoding,
		},
	};
	check($tmpl, $params)
		or warning("unable to parse bcp args\n")
		and return;
	
	verify_db_href($db)
		or warning("unable to parse db href in bcp\n")
		and return;
	
	# check that there is a query for queryout
	if ($op eq 'queryout' && !$query_out) {
		warning("no query passed for queryout in bcp");
		return;
	}
	# else a table needs to be supplied
	elsif ($op ne 'queryout' && !$table) {
		warning("no table passed for operation: $op in bcp");
		return;
	}
	
	# change bcp's first argument based on operation
	my $bcp_arg = $op eq 'queryout' ? $query_out : "[$db->{name}].dbo.[$table]";
	
	# run bcp command
	return `bcp $bcp_arg $op $bcp_path -S$db->{server} -U$db->{user} -P$db->{pwd} -e$error_log -$encoding`;
}