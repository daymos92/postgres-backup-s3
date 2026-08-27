# syntax=docker/dockerfile:1

ARG ALPINE_VERSION=3.22

# go-cron ships as a static binary, so it is fetched once on the build platform
# and copied into the target image. This keeps curl out of the final layer and
# avoids running the download under emulation on cross-platform builds.
FROM --platform=${BUILDPLATFORM} alpine:${ALPINE_VERSION} AS go-cron
ARG TARGETARCH
ARG GO_CRON_VERSION=0.0.5
COPY src/fetch-go-cron.sh /tmp/fetch-go-cron.sh
RUN sh /tmp/fetch-go-cron.sh /out/go-cron

FROM alpine:${ALPINE_VERSION}
ARG POSTGRES_MAJOR=17
ARG SOURCE_URL=""

LABEL org.opencontainers.image.title="postgres-backup-s3" \
      org.opencontainers.image.description="Scheduled PostgreSQL ${POSTGRES_MAJOR} backups to any S3-compatible object storage, restore included." \
      org.opencontainers.image.version="${POSTGRES_MAJOR}" \
      org.opencontainers.image.licenses="MIT" \
      org.opencontainers.image.source="${SOURCE_URL}"

# Package versions are deliberately not pinned: Alpine drops older revisions
# from its index, so a pin turns the next security update into a build failure.
# The Alpine minor release in ALPINE_VERSION is what keeps this reproducible.
# hadolint ignore=DL3018
RUN apk add --no-cache \
      "postgresql${POSTGRES_MAJOR}-client" \
      gnupg \
      aws-cli \
 && adduser -D -u 1000 -h /home/backup backup \
 && mkdir -p /backup \
 && chown backup:backup /backup

COPY --from=go-cron /out/go-cron /usr/local/bin/go-cron

# Defaults only. Every other setting is documented in the README; credentials
# are deliberately left undeclared so they never end up baked into a layer.
ENV POSTGRES_PORT="5432" \
    S3_REGION="us-east-1" \
    S3_PREFIX="backup" \
    S3_S3V4="no"

WORKDIR /backup
COPY src/env.sh src/run.sh src/backup.sh src/restore.sh ./

# Numeric, so that Kubernetes can satisfy runAsNonRoot without a lookup.
USER 1000:1000

CMD ["sh", "run.sh"]
