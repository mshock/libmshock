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

	my $parsed = verify_db_href($tmpl,$params)
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

# OO connect and return handle
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
			default = '',
			strict_type => 1,
		},
		pwd => {
			default => '',
			strict_type => 1,
		},
	}
	return check($tmpl,$db);
}

# create database handles
sub init_handles {
	my @db_info = @_;
	
	my @dbhs;
	for my $db (@db_info) {
		my $parsed = verify_db_href($db)
			or warn Params::Check::last_error();
			and next;
		my $dbh = DBI->connect(
			sprintf("dbi:ODBC:Driver={SQL Server};Database=%s;Server=%s;UID=%s;PWD=%s",
				$parsed->{name},
				$parsed->{server},
				$parsed->{user},
				$parsed->{pwd}
			)	
		) 
			or warn DBI->errstr
			and next;
		push @dbhs, $dbh;
	}
	return @dbhs;
}