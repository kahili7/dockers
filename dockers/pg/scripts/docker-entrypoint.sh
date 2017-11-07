#!/bin/sh

gosu postgres /usr/pgsql-$PGVER/bin/initdb

gosu postgres cp /tmp/pg_hba.conf $PGDATA
gosu postgres cp /tmp/postgresql.conf $PGDATA

gosu postgres /usr/pgsql-$PGVER/bin/postgres
