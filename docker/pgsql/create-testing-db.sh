#!/bin/sh
set -e

# Allow this script to run both inside the PostgreSQL init container and from
# a one-shot setup container that connects over the Docker network.
# Inside postgres image init, the temporary server listens on a Unix socket.
# For external setup containers, POSTGRES_HOST is explicitly provided.
POSTGRES_HOST="${POSTGRES_HOST:-/var/run/postgresql}"
POSTGRES_PORT="${POSTGRES_PORT:-5432}"

pg_cmd() {
  psql -h "${POSTGRES_HOST}" -p "${POSTGRES_PORT}" -U "${POSTGRES_USER}" -d postgres "$@"
}

database_exists() {
  pg_cmd -tAc "SELECT 1 FROM pg_database WHERE datname = '$1'" | grep -q 1
}

ensure_database() {
  database_name="$1"

  if [ -z "${database_name}" ]; then
    return 0
  fi

  if database_exists "${database_name}"; then
    echo "Database ${database_name} already exists."
    return 0
  fi

  echo "Creating database ${database_name} ..."
  pg_cmd -c "CREATE DATABASE \"${database_name}\";"
}

# Wait for PostgreSQL server to be ready (connect to postgres db which always exists)
until pg_isready -h "${POSTGRES_HOST}" -p "${POSTGRES_PORT}" -U "${POSTGRES_USER}" -d postgres; do
  echo "Waiting for PostgreSQL to start..."
  sleep 1
done

if [ -z "${POSTGRES_DB}" ] && [ -z "${POSTGRES_DB_TEST}" ]; then
  echo "POSTGRES_DB and POSTGRES_DB_TEST are not set, skipping database creation."
  exit 0
fi

ensure_database "${POSTGRES_DB}"
ensure_database "${POSTGRES_DB_TEST}"

echo "Database bootstrap complete!"
