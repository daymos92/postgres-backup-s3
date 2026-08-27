#!/bin/sh
# Download, verify and unpack the go-cron binary.
#
# Usage: fetch-go-cron.sh <destination-path>
#
# Expects TARGETARCH and GO_CRON_VERSION in the environment; both are passed in
# as build arguments by the Dockerfile.

set -eu

destination="${1:?destination path is required}"
: "${TARGETARCH:?TARGETARCH build argument is required}"
: "${GO_CRON_VERSION:?GO_CRON_VERSION build argument is required}"

# Published at
# https://github.com/ivoronin/go-cron/releases/download/v0.0.5/go-cron_0.0.5_checksums.txt
case "${GO_CRON_VERSION}:${TARGETARCH}" in
  0.0.5:amd64) checksum='564c8291ef18879b300614e179cca3116506191cbc6b8e50448d274b256f2e67' ;;
  0.0.5:arm64) checksum='adc760e969584a391e3d3d93facbc5a198d76981226f2d8c3b3b0217ac9c57d7' ;;
  *)
    echo "No known checksum for go-cron ${GO_CRON_VERSION} on ${TARGETARCH}." >&2
    exit 1
    ;;
esac

archive="go-cron_${GO_CRON_VERSION}_linux_${TARGETARCH}.tar.gz"
url="https://github.com/ivoronin/go-cron/releases/download/v${GO_CRON_VERSION}/${archive}"

apk add --no-cache curl >/dev/null

cd /tmp
curl --fail --silent --show-error --location --output "$archive" "$url"
echo "${checksum}  ${archive}" | sha256sum -c -
tar -xzf "$archive" go-cron

mkdir -p "$(dirname "$destination")"
install -m 0755 go-cron "$destination"
