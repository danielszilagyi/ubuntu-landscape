#!/usr/bin/env bash
set -euo pipefail

echo "==== Landscape entrypoint starting ===="

# ---------- derive FQDN ----------
: "${HOSTNAME:?HOSTNAME env var is required}"
: "${DOMAIN:?DOMAIN env var is required}"
FQDN="${HOSTNAME}.${DOMAIN}"
echo "Using FQDN: ${FQDN}"

# ---------- validate basic env vars ----------
required_vars=(
  EMAIL
  TIMEZONE
  SMTP_HOST
  SMTP_PORT
  SMTP_USERNAME
  SMTP_PASSWORD
)

for v in "${required_vars[@]}"; do
  if [ -z "${!v:-}" ]; then
    echo "ERROR: Missing required env var: $v" >&2
    exit 1
  fi
done

# ---------- start PostgreSQL ----------
echo "Starting PostgreSQL..."
service postgresql start

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
else
  echo "pg_isready not found, assuming PostgreSQL is up."
fi

# ---------- start RabbitMQ ----------
echo "Starting RabbitMQ..."
rabbitmq-server -detached

for i in {1..30}; do
  if rabbitmq-diagnostics -q check_running >/dev/null 2>&1; then
    echo "RabbitMQ is running."
    break
  fi

  if rabbitmq-diagnostics -q ping >/dev/null 2>&1; then
    rabbitmqctl start_app >/dev/null 2>&1 || true
  fi

  if [ "$i" -eq 30 ]; then
    echo "ERROR: RabbitMQ did not become fully ready in time." >&2
    rabbitmq-diagnostics check_running || true
    exit 1
  fi

  sleep 1
done

# ---------- first-time init: quickstart + Apache patch ----------
if [ ! -f /var/lib/landscape/.quickstart_done ]; then
  echo "Running landscape-quickstart (first-time init)..."
  if ! landscape-quickstart; then
    echo "ERROR: landscape-quickstart failed. Recent logs (if any):" >&2
    find /var/log/landscape -maxdepth 1 -type f -print -exec tail -n 50 {} \; || true
    exit 1
  fi

  echo "Patching Apache config to use FQDN..."


  if [ -f /etc/apache2/sites-available/localhost.conf ]; then
    sed -i "s/^ *ServerName localhost$/    ServerName ${FQDN}/" /etc/apache2/sites-available/localhost.conf
    a2ensite localhost.conf >/dev/null 2>&1 || true
  else
    echo "WARNING: /etc/apache2/sites-available/localhost.conf not found; skipping vhost patch." >&2
  fi

  touch /var/lib/landscape/.quickstart_done
  echo ".quickstart_done created."
else
  echo "Skipping landscape-quickstart (already done)."

  # Ensure global ServerName and site enablement persist (idempotent)
  mkdir -p /etc/apache2/conf-available
  echo "ServerName ${FQDN}" > /etc/apache2/conf-available/servername.conf
  a2enconf servername >/dev/null 2>&1 || true

  if [ -f /etc/apache2/sites-available/localhost.conf ]; then
    a2ensite localhost.conf >/dev/null 2>&1 || true
  fi
fi

# ---------- start Landscape services (best-effort) ----------
echo "Starting Landscape services with lsctl..."
if ! lsctl start; then
  echo "WARNING: 'lsctl start' returned non-zero. Current service status:" >&2
  lsctl status || true
fi

# ---------- ensure we control Apache as PID 1 ----------
# landscape-quickstart may have started Apache already; stop it so we can run in foreground.
if pgrep -x apache2 >/dev/null 2>&1; then
  echo "Stopping background Apache instance before starting in foreground..."
  apachectl -k stop || true
fi

# ---------- start Apache in foreground only if initialized ----------
if [ -f /var/lib/landscape/.quickstart_done ]; then
  echo "Starting Apache in foreground..."
  exec apachectl -D FOREGROUND
else
  echo "ERROR: .quickstart_done is missing; not starting Apache." >&2
  exit 1
fi
