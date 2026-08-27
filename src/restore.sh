#!/bin/sh
# Restore the database from a backup in S3.
#
# Usage: docker exec <container> sh restore.sh [timestamp]
#
# Without an argument the most recent backup of $POSTGRES_DATABASE is used.
#
# WARNING: every database object is dropped and re-created.

set -eu

# shellcheck source-path=SCRIPTDIR
. ./env.sh

if [ -n "${PASSPHRASE:-}" ]; then
  suffix=".dump.gpg"
else
  suffix=".dump"
fi

if [ $# -ge 1 ]; then
  key="${key_prefix}${POSTGRES_DATABASE}_${1}${suffix}"
else
  echo "Looking for the latest backup of $POSTGRES_DATABASE..."
  # Keys embed an ISO-8601 timestamp, so lexicographic order is chronological.
  # shellcheck disable=SC2086
  key=$(aws $aws_args s3api list-objects-v2 \
    --bucket "$S3_BUCKET" \
    --prefix "${key_prefix}${POSTGRES_DATABASE}_" \
    --query "reverse(sort(Contents[?ends_with(Key, '${suffix}')].Key))[0]" \
    --output text)

  if [ -z "$key" ] || [ "$key" = "None" ]; then
    echo "No backup of $POSTGRES_DATABASE found in s3://${S3_BUCKET}/${key_prefix}" >&2
    exit 1
  fi
fi

dump_file="db.dump"
trap 'rm -f "$dump_file" "$dump_file.gpg"' EXIT

echo "Fetching s3://${S3_BUCKET}/${key}..."
# shellcheck disable=SC2086
aws $aws_args s3 cp "s3://${S3_BUCKET}/${key}" "${dump_file}${suffix#.dump}"

if [ -n "${PASSPHRASE:-}" ]; then
  echo "Decrypting backup..."
  gpg --decrypt --batch --yes --passphrase "$PASSPHRASE" "${dump_file}.gpg" > "$dump_file"
  rm -f "${dump_file}.gpg"
fi

echo "Restoring $POSTGRES_DATABASE..."
pg_restore --clean --if-exists --dbname "$POSTGRES_DATABASE" "$dump_file"

echo "Restore complete."
