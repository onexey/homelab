# Home Server Docker

Docker Compose files for my home servers.

## Layout

- `ms-nas/`
  - Media stack in `ms-nas/docker-compose.yml`
  - Services: qBittorrent, Bazarr, Jackett, Radarr, Sonarr, Jellyfin
- `ms-srv/`
  - Main server stack in `ms-srv/docker-compose.yml`
  - Portainer stack in `ms-srv/portainer-docker-compose.yml`
  - Services: Homepage, Pi-hole, Caddy, Homebox, InstaKindle, FeedTriage, Redis, SQL Server, PostgreSQL, Miniflux
  - Helper files: `ms-srv/CaddyCloudflareDockerfile`, `ms-srv/scripts/backup-to-s3.sh`

## Run

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

## Notes

- Each compose file has its own project name.
- Environment variables are expected to be set in Portainer for real deployments.
- `miniflux` uses the existing `postgresql` service on `ms-srv`.
- Create the Miniflux database and user once in PostgreSQL before first start.
- `feedtriage` connects to `miniflux` on the internal Docker network and persists state under `config/feedtriage/data`.
- `feedtriage` requires Miniflux and Ollama-compatible API credentials; set the related variables in `ms-srv/.env.example` or in Portainer before starting it.
- PostgreSQL is pinned to `postgres:18` and uses the PostgreSQL 18 volume layout.

## Env Files

- `ms-nas/.env.example`
- `ms-srv/.env.example`

Each sample env file includes comments describing which variables are used by which services.

For `feedtriage`, set these values at minimum:

- `FEEDTRIAGE_FOCUS_TOPICS`
- `FEEDTRIAGE_MINIFLUX_API_TOKEN`
- `FEEDTRIAGE_SCREEN_OLLAMA_API_KEY`
- `FEEDTRIAGE_REVIEW_OLLAMA_API_KEY`

Set `FEEDTRIAGE_MINIFLUX_BASE_URL` only if FeedTriage should reach Miniflux somewhere other than `http://miniflux:8080`.

## Backup To S3

Script:

- [ms-srv/scripts/backup-to-s3.sh](/Users/mesutsoylu/Documents/Repos/homelab/ms-srv/scripts/backup-to-s3.sh)

Requirements:

- AWS CLI installed on `ms-srv`
- AWS credentials configured on the server
- `FOLDER_TO_TAR` set to the config folder you want to back up
- `BUCKET_NAME` set to the target S3 bucket

Manual test:

```bash
FOLDER_TO_TAR=/home/ms/config \
BUCKET_NAME=YOUR_BUCKET_NAME \
S3_PREFIX=configs \
./ms-srv/scripts/backup-to-s3.sh
```

Daily cron job:

```cron
15 3 * * * cd /path/to/mssrv-docker && FOLDER_TO_TAR=/home/ms/config BUCKET_NAME=YOUR_BUCKET_NAME S3_PREFIX=configs ./ms-srv/scripts/backup-to-s3.sh >> /home/ms/logs/docker-config-backup.log 2>&1
```

Before enabling cron:

```bash
mkdir -p /home/ms/logs
chmod +x ms-srv/scripts/backup-to-s3.sh
aws configure
```

## Miniflux DB Setup

Run these once after the PostgreSQL container is up:

```bash
docker exec -it -u postgres PostgreSQL psql
```

Then create the user and database:

```sql
CREATE USER miniflux WITH PASSWORD 'replace-with-strong-password';
CREATE DATABASE miniflux OWNER miniflux;
```

If you changed the values in `ms-srv/.env.example` or in Portainer, use those same values here.

## Practical Reminders

- Keep secrets out of git.
- Prefer pinned image tags over `latest` for important services.
- Only publish ports that really need host access.
- `homepage` has Docker socket access, so treat it as sensitive.
- If PostgreSQL and Redis are only used by containers, consider removing host port bindings later.
