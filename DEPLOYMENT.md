# ITAMS — New Server Installation Requirements

How to stand up ITAMS (Infra Ninja) on a fresh server. The app ships as a Docker Compose
stack, so the host only needs Docker — no PHP, Node, Composer, or MySQL installed directly.

---

## 1. Server prerequisites

| Item | Minimum | Recommended | Notes |
|------|---------|-------------|-------|
| OS | Linux x86-64 | Ubuntu 22.04 / 24.04 LTS | Any distro with Docker Engine works. |
| CPU | 2 vCPU | 2–4 vCPU | Build is the heaviest step. |
| RAM | 2 GB | 4 GB | MySQL + php-fpm + 2 workers + nginx; the build stage wants headroom. |
| Disk | 20 GB free | 30 GB+ | Images ≈ 2.4 GB, plus build cache, MySQL data volume, and uploads. |
| Network | Outbound HTTPS | — | Needed at build time to pull base images and npm/Composer packages. |

**Ports**
- **`APP_PORT` (default `80`)** — the only port published to the host (nginx). Set it in `.env`.
- **MySQL (3306) is NOT published** — it's reachable only on the internal Compose network. Keep it that way.
- For public HTTPS, put a reverse proxy / TLS terminator (Caddy, nginx, or a load balancer) in front and point it at `APP_PORT`.

---

## 2. Software to install on the host

Only two things: **Docker Engine** and the **Docker Compose plugin** (v2, the `docker compose` subcommand — not the old `docker-compose` binary).

On Ubuntu/Debian, the official convenience script installs both:

```bash
curl -fsSL https://get.docker.com | sudo sh
sudo usermod -aG docker "$USER"   # log out/in so docker runs without sudo
```

Verify:

```bash
docker --version            # 20.10+ ; tested on 29.x
docker compose version      # v2.x ; tested on 2.40
```

Also install **git** (`sudo apt-get install -y git`) to clone the repo, plus `openssl`
(usually preinstalled) to generate the app key.

---

## 3. Deploy

```bash
# 1. Get the code
git clone https://github.com/zwemyat/docker.git itams
cd itams

# 2. Create the .env (NOT committed — see the reference below)
#    Generate an APP_KEY and strong DB passwords:
echo "APP_KEY=base64:$(openssl rand -base64 32)"
openssl rand -hex 16   # use for DB_PASSWORD
openssl rand -hex 16   # use for DB_ROOT_PASSWORD
#    Then write .env with the variables from section 4.

# 3. Build images and start the stack (first build pulls ~2.4 GB, takes a few minutes)
docker compose up -d --build

# 4. Confirm everything is healthy
docker compose ps

# 5. Create the first admin user (no users exist on a fresh DB)
docker compose exec app php artisan tinker --execute "
  \App\Models\User::updateOrCreate(
    ['email' => 'admin@example.com'],
    ['name' => 'Administrator', 'role' => 'admin', 'password' => 'CHANGE_ME', 'email_verified_at' => now()]
  );"
```

The `app` container runs database migrations automatically on first boot
(`RUN_MIGRATIONS=true`), so there is no separate migrate step. Browse to
`http://<server>:<APP_PORT>/` — it should redirect to the login page.

---

## 4. `.env` reference (required)

The stack will not start without a `.env` file in the repo root. There is **no `.env.example`**,
and `.env` is gitignored — create it per environment. Minimum contents:

```dotenv
APP_NAME=ITAMS
APP_ENV=production
APP_KEY=base64:...            # REQUIRED — generate with: openssl rand -base64 32
APP_DEBUG=false
APP_URL=https://itams.example.com
APP_PORT=80                   # host port nginx publishes
APP_TIMEZONE=UTC

LOG_CHANNEL=stack
LOG_LEVEL=error

DB_CONNECTION=mysql
DB_HOST=mysql                 # the compose service name — do NOT change
DB_PORT=3306
DB_DATABASE=itams
DB_USERNAME=itams
DB_PASSWORD=...               # REQUIRED — strong secret
DB_ROOT_PASSWORD=...          # REQUIRED — strong secret

SESSION_DRIVER=database
QUEUE_CONNECTION=database
CACHE_STORE=database

MAIL_MAILER=log               # switch to smtp + MAIL_* for real expiry-reminder emails
```

> **Mail:** the daily `app:check-expirations` scheduler sends renewal/expiry reminder emails.
> With `MAIL_MAILER=log` they only go to the log. Configure `MAIL_MAILER=smtp` and the
> `MAIL_HOST`/`MAIL_PORT`/`MAIL_USERNAME`/`MAIL_PASSWORD`/`MAIL_FROM_ADDRESS` vars to actually send.

---

## 5. Important behaviors

- **Config is baked at container boot.** The entrypoint runs `config:cache` / `route:cache` /
  `view:cache`, and OPcache uses `validate_timestamps=0`. Editing `.env` or code in a running
  container has **no effect** until you rebuild/restart: `docker compose up -d --build`.
- **Migrations run only in the `app` container.** The `queue` and `scheduler` containers share
  the same image but leave `RUN_MIGRATIONS` unset so they don't race the schema.
- **Persistent state lives in two named volumes:** `mysql-data` (the database) and `storage`
  (uploads, logs, sessions). These survive `docker compose down`; they are deleted by
  `docker compose down -v`.

---

## 6. Operations

```bash
docker compose ps                     # service status / health
docker compose logs -f app            # tail the app log (or web/queue/scheduler/mysql)
docker compose up -d --build          # apply code or .env changes (rebuild)
docker compose restart                # restart without rebuild
docker compose down                   # stop (keeps data volumes)

# Database backup / restore
docker compose exec mysql sh -c 'exec mysqldump -uroot -p"$MYSQL_ROOT_PASSWORD" itams' > backup.sql
docker compose exec -T mysql sh -c 'exec mysql -uroot -p"$MYSQL_ROOT_PASSWORD" itams' < backup.sql

# Run any artisan command
docker compose exec app php artisan <command>
```

---

## 7. Recommended hardening for production

- **TLS:** terminate HTTPS at a reverse proxy in front of nginx; set `APP_URL` to the `https://` URL.
- **Firewall:** allow only 443 (and 22) inbound; never expose 3306.
- **Secrets:** keep `.env` off git (already gitignored), restrict it to `chmod 600`, and use a real secrets manager if available.
- **Backups:** schedule the `mysqldump` above (cron) and snapshot the `storage` volume.
- **Updates:** `git pull` then `docker compose up -d --build` — migrations apply automatically on the `app` container's next boot.
