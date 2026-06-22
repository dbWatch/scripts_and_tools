CREATE SCHEMA IF NOT EXISTS dbwatch_cc;

CREATE TABLE IF NOT EXISTS dbwatch_cc.pgbackrest_backup_log (
  id SERIAL PRIMARY KEY,
  stanza TEXT NOT NULL,
  backup_type TEXT NOT NULL,
  backup_label TEXT NOT NULL,
  timestamp_start TIMESTAMPTZ NOT NULL,
  timestamp_stop TIMESTAMPTZ NOT NULL,
  wal_start TEXT NOT NULL,
  wal_stop TEXT NOT NULL,
  db_size TEXT NOT NULL,
  db_backup_size TEXT NOT NULL,
  repo_backup_set_size TEXT NOT NULL,
  repo_backup_size TEXT NOT NULL,
  insert_time TIMESTAMPTZ DEFAULT now(),
  CONSTRAINT pgbackrest_unique_backup UNIQUE (stanza, backup_label)
);
