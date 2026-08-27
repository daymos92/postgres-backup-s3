#!/bin/sh
# Dump the database, optionally encrypt it, upload it to S3 and prune old
# backups. Safe to run ad-hoc: docker exec <container> sh backup.sh

set -eu

# shellcheck source-path=SCRIPTDIR
. ./env.sh

dump_file="db.dump"
trap 'rm -f "$dump_file" "$dump_file.gpg"' EXIT

echo "Creating backup of the $POSTGRES_DATABASE database..."
# PGDUMP_EXTRA_OPTS is unquoted on purpose: it may carry several flags.
# shellcheck disable=SC2086
pg_dump --format=custom ${PGDUMP_EXTRA_OPTS:-} > "$dump_file"

timestamp=$(date -u +"%Y-%m-%dT%H:%M:%S")
key="${key_prefix}${POSTGRES_DATABASE}_${timestamp}.dump"

if [ -n "${PASSPHRASE:-}" ]; then
  echo "Encrypting backup..."
  gpg --symmetric --batch --yes --passphrase "$PASSPHRASE" "$dump_file"
  rm -f "$dump_file"
  local_file="${dump_file}.gpg"
  key="${key}.gpg"
else
  local_file="$dump_file"
fi

echo "Uploading backup to s3://${S3_BUCKET}/${key}..."
# shellcheck disable=SC2086
aws $aws_args s3 cp "$local_file" "s3://${S3_BUCKET}/${key}"
rm -f "$local_file"

echo "Backup complete."

if [ -n "${BACKUP_KEEP_DAYS:-}" ]; then
  cutoff=$(date -u -d "@$(( $(date -u +%s) - 86400 * BACKUP_KEEP_DAYS ))" +%Y-%m-%d)
  echo "Removing backups of $POSTGRES_DATABASE created before $cutoff..."

  # shellcheck disable=SC2086
  stale=$(aws $aws_args s3api list-objects-v2 \
    --bucket "$S3_BUCKET" \
    --prefix "${key_prefix}${POSTGRES_DATABASE}_" \
    --query "Contents[?LastModified<='${cutoff} 00:00:00'].Key" \
    --output text)

  if [ -z "$stale" ] || [ "$stale" = "None" ]; then
    echo "Nothing to remove."
  else
    echo "$stale" | tr '\t' '\n' | while read -r stale_key; do
      [ -n "$stale_key" ] || continue
      echo "  removing $stale_key"
      # shellcheck disable=SC2086
      aws $aws_args s3 rm "s3://${S3_BUCKET}/${stale_key}"
    done
    echo "Removal complete."
  fi
fi
