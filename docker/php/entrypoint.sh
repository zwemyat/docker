#!/bin/sh
set -e

# Recreate the writable storage skeleton (named volume starts from the image,
# but be defensive in case it was wiped) and make sure perms are sane.
mkdir -p \
  storage/framework/cache/data \
  storage/framework/sessions \
  storage/framework/views \
  storage/logs \
  storage/app/public \
  bootstrap/cache

# Only the php-fpm app container should run migrations (RUN_MIGRATIONS=true).
# Workers/scheduler leave it unset so they don't race the schema.
if [ "${RUN_MIGRATIONS:-false}" = "true" ]; then
  echo "[entrypoint] waiting for database ${DB_HOST:-mysql}:${DB_PORT:-3306}..."
  i=0
  until php -r 'exit(@fsockopen(getenv("DB_HOST")?:"mysql", (int)(getenv("DB_PORT")?:3306)) ? 0 : 1);' 2>/dev/null; do
    i=$((i+1)); [ "$i" -ge 60 ] && echo "[entrypoint] db not reachable, giving up" && break
    sleep 2
  done
  php artisan migrate --force
  php artisan storage:link || true
fi

# Rebuild cached config/routes/views from the current .env each boot.
php artisan config:cache
php artisan route:cache
php artisan view:cache

exec "$@"
