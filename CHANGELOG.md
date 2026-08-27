# Changelog

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).
Releases are tagged `vX.Y.Z` in git; Docker tags track the PostgreSQL major
version, so `17` and `latest` always point at the newest release.

## 1.0.0 - 2026-08-27

First release. Forked from
[eeshugerman/postgres-backup-s3](https://github.com/eeshugerman/postgres-backup-s3)
at PostgreSQL 16 and updated to the PostgreSQL 17 client on Alpine 3.22.

### Changed

- The PostgreSQL client package is installed as `postgresql${POSTGRES_MAJOR}-client`
  rather than `postgresql-client`, so the version does not shift with the Alpine
  release.
- `BACKUP_KEEP_DAYS` is scoped to `$POSTGRES_DATABASE` instead of deleting
  everything under `$S3_PREFIX`.
- Restoring the latest backup sorts keys server-side instead of reading a single
  `s3 ls`, which was capped at 1000 objects.
- Object key timestamps are explicitly UTC.
- The container runs as an unprivileged user.
- go-cron is fetched on the build platform and verified against a pinned
  SHA-256 checksum.

### Fixed

- `S3_PREFIX` is now honoured. The Dockerfile declared `S3_PATH`, which no
  script ever read, so the documented default never applied.
- An empty `S3_PREFIX` no longer produces `//` in object keys.
- Retention no longer passes a literal `None` to `s3 rm` when nothing matches.
- Partial dump files are removed when a step fails.

### Removed

- Empty `ENV` defaults for `POSTGRES_PASSWORD`, `S3_ACCESS_KEY_ID` and
  `S3_SECRET_ACCESS_KEY`.
- `S3_PATH`, which was never read.
