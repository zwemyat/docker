# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

ITAMS (Infra Ninja) — an IT Asset Management system. Laravel 11 (PHP 8.2+) backend, Blade + Bootstrap 5 views, Vite + Tailwind assets. MySQL/MariaDB in production (XAMPP locally); SQLite is the framework default but not what this app uses.

## Commands

- **Run the app (local dev):** `composer dev` — runs `php artisan serve`, `queue:listen`, `pail`, and `npm run dev` concurrently.
- **Tests:** `php artisan test` (PHPUnit). Single test: `php artisan test --filter=TestName`. Note: only ExampleTest stubs exist so far.
- **Build assets:** `npm run build` (prod) / `npm run dev` (watch).
- **Format PHP:** `./vendor/bin/pint` (Laravel Pint; available after `composer install`).

## Docker (standard deployment)

Production runs as a Docker Compose stack: `docker compose up -d --build`. One multi-stage
image (`itams-app`) is reused by three services; nginx serves a separate `itams-web` image.

- **Services:** `web` (nginx, publishes `${APP_PORT:-80}`), `app` (php-fpm), `queue`
  (`queue:work`), `scheduler` (`schedule:work`), `mysql` (8.0). Queue/cache/session all use
  the `database` driver, so their tables come from migrations.
- **`.env` is required and gitignored** (there is no `.env.example`). Must define `APP_KEY`,
  `DB_DATABASE`/`DB_USERNAME`/`DB_PASSWORD`/`DB_ROOT_PASSWORD`, and `DB_HOST=mysql` (the compose
  service name). `APP_PORT` overrides the published web port.
- **Migrations run on boot only in the `app` container** (`RUN_MIGRATIONS=true`); the
  queue/scheduler containers leave it unset so they don't race the schema.
- **Config is baked at boot:** the entrypoint runs `config:cache`/`route:cache`/`view:cache`
  and OPcache sets `validate_timestamps=0`. Editing `.env` or code in a running container has
  no effect — rebuild/restart (`docker compose up -d --build`) to apply changes.
- **Run artisan in the stack:** `docker compose exec app php artisan <cmd>` (e.g. `migrate`, `tinker`).

## Architecture

The app is four near-identical CRUD modules — **PcAsset** (`pc_assets`), **Device** (`devices`), **Subscription** (`subscriptions`), **LicenseContract** (`licenses_contracts`). Each has a Controller, Model, an `Exports/<Name>Export` + `<Name>Template`, an `Imports/<Name>Import` (Excel via maatwebsite/excel), and Blade views under `resources/views/<module>/`. Replicate this full set of files by hand
when adding a module — there is no scaffolding command.

- **Route authorization:** every module route is gated by `module:<name>,view` (reads) or `module:<name>,edit` (writes) middleware; admin-only routes use a separate `admin` group. Mirror this when adding routes.
- **Activity logging:** mutations are recorded via `App\Support\ActivityLogger` against the model class.

## Gotchas

- **Encrypted model fields:** `PcAsset` casts `admin_password`, `username`, and `password` as `encrypted`. They are unreadable at the DB level — never `where()`/compare them as plaintext; decrypt through the model.
- **.editorconfig:** 4-space indent, LF line endings, trailing whitespace trimmed (except `.md`). Run `./vendor/bin/pint` to format PHP before committing (no auto-format hook is configured).
