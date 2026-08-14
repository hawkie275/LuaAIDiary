#!/bin/sh
set -eu

MIGRATIONS_DIR="${MIGRATIONS_DIR:-/app/postgresql/migrations}"
LOCK_KEY="${MIGRATION_ADVISORY_LOCK_KEY:-424242275}"

log() {
    printf '[migrate] %s\n' "$*"
}

fail() {
    printf '[migrate][error] %s\n' "$*" >&2
    exit 1
}

require_env() {
    name="$1"
    eval "value=\${$name:-}"
    if [ -z "$value" ]; then
        fail "required environment variable is empty: $name"
    fi
}

require_cmd() {
    if ! command -v "$1" >/dev/null 2>&1; then
        fail "required command not found: $1"
    fi
}

require_cmd psql
require_env POSTGRES_HOST
require_env POSTGRES_PORT
require_env POSTGRES_DB
require_env POSTGRES_USER
require_env POSTGRES_PASSWORD

case "$POSTGRES_PORT" in
    ''|*[!0-9]*) fail "POSTGRES_PORT must be numeric: $POSTGRES_PORT" ;;
esac

if [ ! -d "$MIGRATIONS_DIR" ]; then
    fail "migration directory not found: $MIGRATIONS_DIR"
fi

export PGPASSWORD="$POSTGRES_PASSWORD"

PSQL="psql -v ON_ERROR_STOP=1 -h $POSTGRES_HOST -p $POSTGRES_PORT -U $POSTGRES_USER -d $POSTGRES_DB"

log "Ensuring schema_migrations table exists"
$PSQL <<'SQL'
CREATE TABLE IF NOT EXISTS schema_migrations (
    version VARCHAR(255) PRIMARY KEY,
    applied_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);
SQL

found=0
for migration_file in "$MIGRATIONS_DIR"/*.sql; do
    if [ ! -e "$migration_file" ]; then
        continue
    fi

    found=1
    filename="$(basename "$migration_file")"
    version="${filename%.sql}"

    log "Checking migration: $version"
    $PSQL \
        -v migration_file="$migration_file" \
        -v migration_version="$version" \
        -v lock_key="$LOCK_KEY" <<'SQL'
SELECT CASE
    WHEN pg_try_advisory_lock(:lock_key::bigint) THEN '1'
    ELSE '0'
END AS migration_lock_acquired
\gset

\if :migration_lock_acquired
SELECT EXISTS (
    SELECT 1
    FROM schema_migrations
    WHERE version = :'migration_version'
) AS migration_already_applied
\gset

\if :migration_already_applied
SELECT format('migration %s already applied; skipping', :'migration_version') AS message;
\else
\echo Applying migration :migration_version from :migration_file
\i :migration_file
INSERT INTO schema_migrations(version)
VALUES (:'migration_version')
ON CONFLICT (version) DO NOTHING;
\endif

SELECT pg_advisory_unlock(:lock_key::bigint);
\else
SELECT format('another migration runner is active; could not acquire advisory lock %s', :'lock_key') AS error;
\quit 75
\endif
SQL
done

if [ "$found" -eq 0 ]; then
    fail "no migration SQL files found in: $MIGRATIONS_DIR"
fi

log "Database migrations completed"
