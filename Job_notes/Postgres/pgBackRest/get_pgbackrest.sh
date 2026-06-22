#!/bin/bash

# === Configuration ===
PG_USER="postgres"
PG_DATABASE="postgres"
PG_SCHEMA="dbwatch_cc"
PG_TABLE="pgbackrest_backup_log"
STANZA="main"
VIP_HOST="10.0.1.159"   # <-- change this to your actual Patroni VIP or HAProxy IP
LOG_FILE="/var/log/get_pgbackrest.log"

# === Run pgBackRest info ===
INFO_OUTPUT=$(sudo -u $PG_USER pgbackrest info --stanza=$STANZA 2>&1)
if [ $? -ne 0 ]; then
  echo "[$(date)] ERROR: pgBackRest info failed: $INFO_OUTPUT" | tee -a "$LOG_FILE"
  exit 1
fi

# === Parse and insert backup info ===
echo "$INFO_OUTPUT" | awk -v stanza="$STANZA" '
  BEGIN { RS=""; FS="\n" }
  {
    for (i=1; i<=NF; i++) {
      if ($i ~ /full backup:/) {
        type = "full"; label = $i; sub(/^.*full backup: /, "", label)
      } else if ($i ~ /diff backup:/) {
        type = "diff"; label = $i; sub(/^.*diff backup: /, "", label)
      } else if ($i ~ /incr backup:/) {
        type = "incr"; label = $i; sub(/^.*incr backup: /, "", label)
      } else if ($i ~ /timestamp start\/stop:/) {
        match($i, /timestamp start\/stop:[ ]*([^/]+)[ ]*\/[ ]*(.*)/, ts)
        ts_start = ts[1]; ts_stop = ts[2]
      } else if ($i ~ /wal start\/stop:/) {
        match($i, /wal start\/stop:[ ]*([A-F0-9]+)[ ]*\/[ ]*([A-F0-9]+)/, ws)
        wal_start = ws[1]; wal_stop = ws[2]
      } else if ($i ~ /database size:/) {
        db_size = $i; sub(/^.*database size: /, "", db_size)
      } else if ($i ~ /database backup size:/) {
        db_backup_size = $i; sub(/^.*database backup size: /, "", db_backup_size)
      } else if ($i ~ /repo1: backup set size:/) {
        repo_set_size = $i; sub(/^.*repo1: backup set size: /, "", repo_set_size)
      } else if ($i ~ /repo1: backup size:/) {
        repo_size = $i; sub(/^.*repo1: backup size: /, "", repo_size)
      }
    }

    if (label != "" && ts_start != "") {
      print type "|" label "|" ts_start "|" ts_stop "|" wal_start "|" wal_stop "|" db_size "|" db_backup_size "|" repo_set_size "|" repo_size
    }

    # Reset
    type=""; label=""; ts_start=""; ts_stop=""; wal_start=""; wal_stop=""; db_size=""; db_backup_size=""; repo_set_size=""; repo_size=""
  }
' | while IFS="|" read type label start stop wal_start wal_stop db_size db_backup_size repo_set_size repo_size
do
  SQL="INSERT INTO ${PG_SCHEMA}.${PG_TABLE}
  (stanza, backup_type, backup_label, timestamp_start, timestamp_stop, wal_start, wal_stop, db_size, db_backup_size, repo_backup_set_size, repo_backup_size)
  VALUES
  ('$STANZA', '$type', '$label', '$start', '$stop', '$wal_start', '$wal_stop', '$db_size', '$db_backup_size', '$repo_set_size', '$repo_size')
  ON CONFLICT (stanza, backup_label) DO NOTHING;"

  echo "[$(date)] Logging backup $label to $VIP_HOST" | tee -a "$LOG_FILE"
  echo "$SQL" | PGPASSWORD="postgres" psql -h "$VIP_HOST" -U "$PG_USER" -d "$PG_DATABASE" >> "$LOG_FILE" 2>&1

  if [ $? -eq 0 ]; then
    echo "[$(date)] Inserted backup record for $label." | tee -a "$LOG_FILE"
  else
    echo "[$(date)] ERROR inserting backup record for $label." | tee -a "$LOG_FILE"
  fi
done

