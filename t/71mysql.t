use strict;
use warnings;  

use Test::More;
use Test::Exception;
use lib qw(t/lib);
use DBICTest;
use DBI::Const::GetInfoType;

my ($dsn, $user, $pass) = @ENV{map { "DBICTEST_MYSQL_${_}" } qw/DSN USER PASS/};

#warn "$dsn $user $pass";

plan skip_all => 'Set $ENV{DBICTEST_MYSQL_DSN}, _USER and _PASS to run this test'
  unless ($dsn && $user);

plan tests => 11;

my $schema = DBICTest::Schema->connect($dsn, $user, $pass);

my $dbh = $schema->storage->dbh;

$dbh->do("DROP TABLE IF EXISTS artist;");

$dbh->do("CREATE TABLE artist (artistid INTEGER NOT NULL AUTO_INCREMENT PRIMARY KEY, name VARCHAR(100), rank INTEGER NOT NULL DEFAULT '13', charfield CHAR(10));");

$dbh->do("DROP TABLE IF EXISTS cd;");

$dbh->do("CREATE TABLE cd (cdid INTEGER NOT NULL AUTO_INCREMENT PRIMARY KEY, artist INTEGER, title TEXT, year INTEGER, genreid INTEGER, single_track INTEGER);");

$dbh->do("DROP TABLE IF EXISTS producer;");

$dbh->do("CREATE TABLE producer (producerid INTEGER NOT NULL AUTO_INCREMENT PRIMARY KEY, name TEXT);");

$dbh->do("DROP TABLE IF EXISTS cd_to_producer;");

$dbh->do("CREATE TABLE cd_to_producer (cd INTEGER,producer INTEGER);");

#'dbi:mysql:host=localhost;database=dbic_test', 'dbic_test', '');

# This is in Core now, but it's here just to test that it doesn't break
$schema->class('Artist')->load_components('PK::Auto');

# test primary key handling
my $new = $schema->resultset('Artist')->create({ name => 'foo' });
ok($new->artistid, "Auto-PK worked");

# test LIMIT support
for (1..6) {
    $schema->resultset('Artist')->create({ name => 'Artist ' . $_ });
}
my $it = $schema->resultset('Artist')->search( {},
    { rows => 3,
      offset => 2,
      order_by => 'artistid' }
);
is( $it->count, 3, "LIMIT count ok" );
is( $it->next->name, "Artist 2", "iterator->next ok" );
$it->next;
$it->next;
is( $it->next, undef, "next past end of resultset ok" );

my $test_type_info = {
    'artistid' => {
        'data_type' => 'INT',
        'is_nullable' => 0,
        'size' => 11,
        'default_value' => undef,
    },
    'name' => {
        'data_type' => 'VARCHAR',
        'is_nullable' => 1,
        'size' => 100,
        'default_value' => undef,
    },
    'rank' => {
        'data_type' => 'INT',
        'is_nullable' => 0,
        'size' => 11,
        'default_value' => 13,
    },
    'charfield' => {
        'data_type' => 'CHAR',
        'is_nullable' => 1,
        'size' => 10,
        'default_value' => undef,
    },
};

SKIP: {
    my $mysql_version = $dbh->get_info( $GetInfoType{SQL_DBMS_VER} );
    skip "Cannot determine MySQL server version", 1 if !$mysql_version;

    my ($v1, $v2, $v3) = $mysql_version =~ /^(\d+)\.(\d+)(?:\.(\d+))?/;
    skip "Cannot determine MySQL server version", 1 if !$v1 || !defined($v2);

    $v3 ||= 0;

    if( ($v1 < 5) || ($v1 == 5 && $v2 == 0 && $v3 <= 3) ) {
        $test_type_info->{charfield}->{data_type} = 'VARCHAR';
    }

    my $type_info = $schema->storage->columns_info_for('artist');
    is_deeply($type_info, $test_type_info, 'columns_info_for - column data types');
}

## Can we properly deal with the null search problem?
##
## Only way is to do a SET SQL_AUTO_IS_NULL = 0; on connect
## But I'm not sure if we should do this or not (Ash, 2008/06/03)

NULLINSEARCH: {
    
    ok my $artist1_rs = $schema->resultset('Artist')->search({artistid=>6666})
    => 'Created an artist resultset of 6666';
    
    is $artist1_rs->count, 0
    => 'Got no returned rows';
    
    ok my $artist2_rs = $schema->resultset('Artist')->search({artistid=>undef})
    => 'Created an artist resultset of undef';
    
    TODO: {
    	local $TODO = "need to fix the row count =1 when select * from table where pk IS NULL problem";
	    is $artist2_rs->count, 0
	    => 'got no rows';    	
    }

    my $artist = $artist2_rs->single;
    
    is $artist => undef
    => 'Nothing Found!';
}
    
my $cd = $schema->resultset ('CD')->create ({});

my $producer = $schema->resultset ('Producer')->create ({});

lives_ok { $cd->set_producers ([ $producer ]) } 'set_relationship doesnt die';

# clean up our mess
END {
    #$dbh->do("DROP TABLE artist") if $dbh;
}
