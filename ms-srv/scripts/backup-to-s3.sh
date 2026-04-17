#!/usr/bin/env bash

set -euo pipefail

FOLDER_TO_TAR="${FOLDER_TO_TAR:-/home/ms/config}"
BUCKET_NAME="${BUCKET_NAME:-ms-docker-config}"
S3_PREFIX="${S3_PREFIX:-configs}"
TIMESTAMP="$(date +"%Y%m%d%H%M%S")"
TAR_TEMP_PATH="${TAR_TEMP_PATH:-/tmp/docker-config}"
TAR_FILENAME="backup_${TIMESTAMP}.tar.gz"
TAR_FILE="${TAR_TEMP_PATH}/${TAR_FILENAME}"

# Exclusion list
EXCLUDE_LIST=(
    "**/bazarr/config/backup"
    "**/bazarr/config/cache"
    "**/bazarr/config/db"
    "**/bazarr/config/log"
    "**/bazarr/config/restore"
    "**/caddy/config"
    "**/caddy/data"
    "**/caddy/site"
    "**/homepage/logs"
    "**/jellyfin"
    "**/pihole"
    "**/portainer"
    "**/qbittorrent"
    "**/radarr/config/Backups"
    "**/radarr/config/logs"
    "**/radarr/config/MediaCover"
    "**/radarr/config/Sentry"
    "**/sonarr/config/Backups"
    "**/sonarr/config/logs"
    "**/sonarr/config/MediaCover"
    "**/sonarr/config/Sentry"
)

TAR_ARGS=()
for EXCLUDE in "${EXCLUDE_LIST[@]}"; do
    TAR_ARGS+=("--exclude=${EXCLUDE}")
done

if ! command -v aws >/dev/null 2>&1; then
    echo "aws CLI is required but not installed." >&2
    exit 1
fi

if [[ ! -d "${FOLDER_TO_TAR}" ]]; then
    echo "Folder to back up does not exist: ${FOLDER_TO_TAR}" >&2
    exit 1
fi

mkdir -p "${TAR_TEMP_PATH}"

find "${TAR_TEMP_PATH}" -type f -mtime +30 -delete

tar -czf "${TAR_FILE}" "${TAR_ARGS[@]}" -C "$(dirname "${FOLDER_TO_TAR}")" "$(basename "${FOLDER_TO_TAR}")"

aws s3 cp "${TAR_FILE}" "s3://${BUCKET_NAME}/${S3_PREFIX}/${TAR_FILENAME}"

echo "Upload successful. Deleting the local gzipped tar file."
rm -f "${TAR_FILE}"
