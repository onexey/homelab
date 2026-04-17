# mssrv-docker

Compose files for rebuilding my home server with Docker across multiple nodes.

## Repository Layout

- `ms-nas/`
  - NAS-hosted media stack in `ms-nas/docker-compose.yml`.
  - Includes `qbittorrent`, `bazarr`, `jackett`, `radarr`, `sonarr`, and `jellyfin`.
- `ms-srv/`
  - Server-hosted stacks.
  - Main services live in `ms-srv/docker-compose.yml`.
  - Portainer lives in `ms-srv/portainer-docker-compose.yml`.
  - Server-only helpers live here too, including `ms-srv/CaddyCloudflareDockerfile` and `ms-srv/scripts/backup-to-s3.sh`.

## Repository Conventions

- Container data should live under a predictable local path via `DataRootPath` and `MediaRootPath`.
- Secrets should come from environment variables or Docker secrets, not be committed into compose files.
- Treat each compose file as one logical stack per node.
- Each compose file now has an explicit Compose project name so stacks from the same repo do not accidentally share the default network.
- Prefer service-name DNS inside a stack instead of connecting apps to host IPs.

## Running The Stacks

NAS:

```bash
docker compose --env-file ms-nas/.env.example -f ms-nas/docker-compose.yml up -d
```

Server:

```bash
docker compose --env-file ms-srv/.env.example -f ms-srv/docker-compose.yml up -d
```

Portainer:

```bash
docker compose --env-file ms-srv/.env.example -f ms-srv/portainer-docker-compose.yml up -d
```

## Server App Dependencies

`ms-srv/docker-compose.yml` combines the former dev stack and better-home stack into one Compose project. That gives you normal Docker DNS between services and lets new apps depend on PostgreSQL cleanly.

For a future service that needs Postgres, use:

```env
DB_HOST=postgresql
DB_PORT=5432
```

and add a dependency like:

```yaml
depends_on:
  postgresql:
    condition: service_healthy
```

That keeps database traffic inside the project network and makes startup behavior much easier to reason about than splitting dependent apps across separate Compose projects.

## Environment Variables

Example env files:

- NAS: `ms-nas/.env.example`
- Server: `ms-srv/.env.example`

Common variables:

- `DataRootPath`
  - Base path for config and persistent app data.
- `MediaRootPath`
  - Base path for media content on the NAS node.
- `InternalIP`
  - Used by Pi-hole and Jellyfin where explicit host binding is needed.
- `MSSQL_PASSWORD`, `POSTGRES_PASSWORD`, `WebPassword`
  - Sensitive values that should be set per host and never committed with real values.
- `CF_API_TOKEN`
  - Cloudflare API token for the custom Caddy image.

## Best Practices

- Pin image versions for important infrastructure.
  - `:latest` is convenient but makes rebuilds less predictable.
- Avoid publishing ports unless the service must be reachable from the LAN or internet.
  - Internal-only databases should ideally stay off host ports.
- Use reverse proxying for web apps instead of exposing many direct ports.
- Add health checks for services other containers depend on.
- Keep service names lowercase in future additions.
  - Docker DNS is simpler and less surprising when names are lowercase and stable.
- Keep host-specific files together.
  - Putting NAS and server compose files in separate folders makes it much harder to deploy the wrong stack on the wrong machine.

## Security Notes

- `docker.sock` access is powerful.
  - `homepage` has read-only socket access, which is still sensitive.
- `CF_API_TOKEN` should be scoped as narrowly as possible in Cloudflare.
- Pi-hole and Caddy are internet- or LAN-facing and should be patched regularly.
- Portainer should not be exposed broadly without strong auth and TLS.
- Databases should not be published to the host unless you actually need host access.
  - If PostgreSQL is only used by containers on `ms-srv`, consider removing `5432:5432` later.
- Redis should also stay off the host unless you intentionally need LAN access.
- Use backups for the mounted data directories before large upgrades.

## Backup Script

The S3 backup script now lives at [ms-srv/scripts/backup-to-s3.sh](/Users/mesutsoylu/Documents/Repos/mssrv-docker/ms-srv/scripts/backup-to-s3.sh).
The S3 backup script now lives at `ms-srv/scripts/backup-to-s3.sh`.

What it needs to work:

- AWS CLI installed on the server
- AWS credentials available on the server
  - Either `aws configure`
  - Or an IAM role / instance profile if the server runs in AWS
- `FOLDER_TO_TAR` pointing at the real config directory on the server
- `BUCKET_NAME` set to your S3 bucket

Example:

```bash
FOLDER_TO_TAR=/home/ms/config \
BUCKET_NAME=ms-docker-config \
S3_PREFIX=configs \
bash ms-srv/scripts/backup-to-s3.sh
```

### One-Time Setup

1. Install AWS CLI on `ms-srv`.
1. Create or choose an S3 bucket for backups.
1. Create AWS credentials with the smallest permissions you can.
   A minimal policy is `s3:PutObject`, `s3:GetBucketLocation`, and optionally `s3:ListBucket` for just the backup bucket.
1. Configure credentials on the server:

```bash
aws configure
```

1. Test access:

```bash
aws s3 ls s3://YOUR_BUCKET_NAME
```

1. Make the script executable:

```bash
chmod +x ms-srv/scripts/backup-to-s3.sh
```

1. Run a manual backup test:

```bash
FOLDER_TO_TAR=/home/ms/config \
BUCKET_NAME=YOUR_BUCKET_NAME \
S3_PREFIX=configs \
./ms-srv/scripts/backup-to-s3.sh
```

1. Confirm the archive appears in S3 before automating it.

### Daily Automatic Backup

The simplest option is cron on `ms-srv`.

Open the crontab:

```bash
crontab -e
```

Add a daily 03:15 job:

```cron
15 3 * * * cd /path/to/mssrv-docker && FOLDER_TO_TAR=/home/ms/config BUCKET_NAME=YOUR_BUCKET_NAME S3_PREFIX=configs ./ms-srv/scripts/backup-to-s3.sh >> /home/ms/logs/docker-config-backup.log 2>&1
```

That will:

- run every day at 03:15 server time
- write logs to `/home/ms/logs/docker-config-backup.log`
- keep the bucket path under `configs/`

Before using that cron line, make sure the log folder exists:

```bash
mkdir -p /home/ms/logs
```

### Suggested Hardening

- Use a dedicated IAM user or role just for backups.
- Turn on S3 bucket versioning if you want protection from accidental overwrite or deletion.
- Consider an S3 lifecycle rule to expire old backups after a set retention period.
- If the config contains secrets, consider server-side encryption on the bucket.
- Periodically test restore, not just backup.

Why it may have been broken before:

- The old script built `tar` exclude arguments as a quoted string, which is brittle and often fails to exclude what you think it excludes.
- It had hard-coded paths and bucket values, so any host path change could silently break it.
- It did not check for `aws` being installed or the source folder existing before running.

## Gotchas

- `depends_on` does not guarantee database readiness.
  - For apps needing Postgres, also use retries or wait-for-db behavior.
- `container_name` makes ad hoc scaling harder.
  - It is fine for a homelab, but it is one reason to avoid over-coupling stacks.
- The server stack now assumes a single `DataRootPath` rooted under `ms-srv/`.
  - If your old setup stored config one directory above the repo, double-check those locations before the first rollout.
- Portainer file paths may need to be refreshed in Portainer itself after this repo move.
  - The compose file location changed, and Portainer sometimes caches old paths or git-stack settings.

## Suggested Next Cleanup

- Decide which services truly need host ports and remove the rest.
- Pin key images to tested tags.
- Consider moving secrets from env files to Docker secrets or a password manager-backed bootstrap step.
