# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

ITAMS (Infra Ninja) — an IT Asset Management system. Laravel 11 (PHP 8.2+) backend, Blade + Bootstrap 5 views, Vite + Tailwind assets. MySQL/MariaDB in production (XAMPP locally); SQLite is the framework default but not what this app uses.

## Commands

- **Run the app (local dev):** `composer dev` — runs `php artisan serve`, `queue:listen`, `pail`, and `npm run dev` concurrently.
- **Tests:** `php artisan test` (PHPUnit). Single test: `php artisan test --filter=TestName`. Note: only ExampleTest stubs exist so far.
- **Build assets:** `npm run build` (prod) / `npm run dev` (watch).
- **Format PHP:** `./vendor/bin/pint` (Laravel Pint; available after `composer install`).

## Architecture

The app is four near-identical CRUD modules — **PcAsset** (`pc_assets`), **Device** (`devices`), **Subscription** (`subscriptions`), **LicenseContract** (`licenses_contracts`). Each has a Controller, Model, an `Exports/<Name>Export` + `<Name>Template`, an `Imports/<Name>Import` (Excel via maatwebsite/excel), and Blade views under `resources/views/<module>/`. Use `/new-module` to scaffold a new one following this pattern.

- **Route authorization:** every module route is gated by `module:<name>,view` (reads) or `module:<name>,edit` (writes) middleware; admin-only routes use a separate `admin` group. Mirror this when adding routes.
- **Activity logging:** mutations are recorded via `App\Support\ActivityLogger` against the model class.

## Gotchas

- **Encrypted model fields:** `PcAsset` casts `admin_password`, `username`, and `password` as `encrypted`. They are unreadable at the DB level — never `where()`/compare them as plaintext; decrypt through the model.
- **.editorconfig:** 4-space indent, LF line endings, trailing whitespace trimmed (except `.md`). Pint and the format hook keep PHP in line.
