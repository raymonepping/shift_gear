#!/usr/bin/env sh
# Credential values stay in the memory volume; never print them.
set -eu
export PGHOST=postgres.sg-workloads.svc PGPORT=5432 PGDATABASE=shiftgear
export PGPASSFILE=/vault/secrets/pgpass PGCONNECT_TIMEOUT=2
export PGOPTIONS='-c statement_timeout=2000'
while :; do
  if [ -s "$PGPASSFILE" ]; then
    PGUSER=$(cut -d: -f4 "$PGPASSFILE")
    export PGUSER
    if [ "$(psql -X -w -tAc 'SELECT COUNT(*) FROM sg_agent.canary' 2>/dev/null)" = 1 ]; then
      touch /tmp/ready
    else
      rm -f /tmp/ready
    fi
  else
    rm -f /tmp/ready
  fi
  sleep 5
done
