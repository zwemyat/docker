# syntax=docker/dockerfile:1

# ---------------------------------------------------------------------------
# Stage 1 — build front-end assets (Vite + Tailwind) into public/build
# ---------------------------------------------------------------------------
FROM node:22-alpine AS assets
WORKDIR /app
# No package-lock.json in repo, so use install (swap to `npm ci` once a lock exists)
COPY package.json ./
RUN npm install
COPY vite.config.js tailwind.config.js postcss.config.js ./
COPY resources/ resources/
COPY public/ public/
RUN npm run build

# ---------------------------------------------------------------------------
# Stage 2 — install PHP dependencies (composer.lock => reproducible)
# ---------------------------------------------------------------------------
FROM composer:2 AS vendor
WORKDIR /app
COPY composer.json composer.lock ./
# --no-scripts: artisan isn't present yet at this point in the layer cache
RUN composer install --no-dev --no-scripts --no-autoloader --prefer-dist --no-interaction --ignore-platform-reqs
COPY . .
# Bring in the compiled assets so the manifest ships in the image
COPY --from=assets /app/public/build public/build
# public/storage -> ../storage/app/public ; resolves via the shared storage volume at runtime
RUN ln -sf ../storage/app/public public/storage \
 && composer dump-autoload --optimize --no-dev --classmap-authoritative

# ---------------------------------------------------------------------------
# Stage 3 — php-fpm runtime (the application container)
# ---------------------------------------------------------------------------
FROM php:8.2-fpm-alpine AS app
WORKDIR /var/www/html

# Runtime libs + build deps for the extensions this app uses
# (pdo_mysql, mbstring, bcmath, gd, zip, exif, pcntl, intl — Excel/DomPDF/encryption)
RUN apk add --no-cache fcgi libpng libjpeg-turbo freetype libzip icu-libs oniguruma \
 && apk add --no-cache --virtual .build-deps $PHPIZE_DEPS \
      libpng-dev libjpeg-turbo-dev freetype-dev libzip-dev icu-dev oniguruma-dev \
 && docker-php-ext-configure gd --with-freetype --with-jpeg \
 && docker-php-ext-install -j"$(nproc)" pdo_mysql mbstring bcmath gd zip exif pcntl intl \
 && apk del .build-deps

COPY docker/php/php.ini /usr/local/etc/php/conf.d/zz-app.ini
COPY docker/php/fpm-ping.conf /usr/local/etc/php-fpm.d/zz-ping.conf

# Application code with vendor + built assets baked in
COPY --from=vendor /app /var/www/html
RUN chown -R www-data:www-data storage bootstrap/cache

COPY docker/php/entrypoint.sh /usr/local/bin/entrypoint
RUN chmod +x /usr/local/bin/entrypoint

# Healthcheck: ask php-fpm's status over the fastcgi port via cgi-fcgi
HEALTHCHECK --interval=15s --timeout=5s --start-period=30s --retries=3 \
  CMD REQUEST_METHOD=GET SCRIPT_NAME=/ping SCRIPT_FILENAME=/ping \
      cgi-fcgi -bind -connect 127.0.0.1:9000 || exit 1

USER www-data
ENTRYPOINT ["entrypoint"]
CMD ["php-fpm"]

# ---------------------------------------------------------------------------
# Stage 4 — nginx (serves public/, proxies *.php to the app container)
# ---------------------------------------------------------------------------
FROM nginx:1.27-alpine AS web
COPY docker/nginx/default.conf /etc/nginx/conf.d/default.conf
# Static assets + the public/storage symlink; PHP files are executed by php-fpm
COPY --from=vendor /app/public /var/www/html/public
