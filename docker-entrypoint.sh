#!/usr/bin/env bash
set -euo pipefail

# ---- 1) Require config via env vars ----
required_vars=(
  EMAIL TOKEN HOSTNAME DOMAIN TIMEZONE
  SMTP_HOST SMTP_PORT
  LANDSCAPE_VERSION
)

for v in "${required_vars[@]}"; do
  if [ -z "${!v:-}" ]; then
    echo "ERROR: Missing required env var: $v" >&2
    exit 1
  fi
done

# ---- 3) Start PostgreSQL ----
echo "Starting PostgreSQL..."
service postgresql start

# Wait for Postgres
if command -v pg_isready >/dev/null 2>&1; then
  for i in {1..30}; do
    if pg_isready -q; then
      echo "PostgreSQL is ready."
      break
    fi
    if [ "$i" -eq 30 ]; then
      echo "ERROR: PostgreSQL did not become ready in time." >&2
      exit 1
    fi
    sleep 1
  done
fi

# ---- 4) Start RabbitMQ ----
echo "Starting RabbitMQ..."
rabbitmq-server -detached

# Wait for RabbitMQ node & app to be fully up
for i in {1..30}; do
  # check_running = node + app up
  if rabbitmq-diagnostics -q check_running >/dev/null 2>&1; then
    echo "RabbitMQ is running."
    break
  fi

  # As a fallback, try to start the app if node is up but app isn't
  if rabbitmq-diagnostics -q ping >/dev/null 2>&1; then
    echo "RabbitMQ node is up but app not running yet, trying to start_app..."
    rabbitmqctl start_app >/dev/null 2>&1 || true
  fi

  if [ "$i" -eq 30 ]; then
    echo "ERROR: RabbitMQ did not become fully ready in time." >&2
    rabbitmq-diagnostics check_running || true
    exit 1
  fi

  sleep 1
done

# ---- 5) Run landscape-quickstart once ----
if [ ! -f /var/lib/landscape/.quickstart_done ]; then
  echo "Running landscape-quickstart..."
  if landscape-quickstart; then
    touch /var/lib/landscape/.quickstart_done
    echo "landscape-quickstart completed."
  else
    echo "ERROR: landscape-quickstart failed." >&2
    exit 1
  fi
else
  echo "Skipping landscape-quickstart (already done)."
fi

echo "Starting Apache in foreground..."
exec apachectl -D FOREGROUND &

echo "Starting Landscape services..."
if ! lsctl start; then
  echo "WARNING: 'lsctl start' returned non-zero exit code. Some services may have failed to start."
  # Show detailed status for debugging, but don't break the container
  lsctl status || true
fi

tail -f /var/log/apache2/error.log
