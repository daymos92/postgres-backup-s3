#!/bin/sh
# Container entrypoint: run one backup immediately, or hand over to go-cron.

set -eu

if [ "${S3_S3V4:-no}" = "yes" ]; then
  aws configure set default.s3.signature_version s3v4
fi

if [ -z "${SCHEDULE:-}" ]; then
  exec sh backup.sh
else
  exec go-cron "$SCHEDULE" /bin/sh backup.sh
fi
