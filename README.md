# postgres-backup-s3

Periodically dump a PostgreSQL 17 database to S3-compatible object storage, and
restore it again when you need to. One small Alpine image does both.

```
docker pull daymos92/postgres-backup-s3:17
```

- `pg_dump` in PostgreSQL's own `custom` format, so `pg_restore` can be selective
- Any S3-compatible backend: AWS S3, MinIO, Backblaze B2, Cloudflare R2, Hetzner
- Optional symmetric GPG encryption before upload
- Optional retention: delete this database's backups older than N days
- Cron-style scheduling, or a single run that exits
- `linux/amd64` and `linux/arm64`, running as an unprivileged user

## Backup

```yaml
services:
  postgres:
    image: postgres:17
    environment:
      POSTGRES_USER: user
      POSTGRES_PASSWORD: password

  backup:
    image: daymos92/postgres-backup-s3:17
    environment:
      SCHEDULE: '@daily'
      BACKUP_KEEP_DAYS: 30
      PASSPHRASE: a-long-random-secret
      POSTGRES_HOST: postgres
      POSTGRES_DATABASE: dbname
      POSTGRES_USER: user
      POSTGRES_PASSWORD: password
      S3_REGION: eu-central-1
      S3_ACCESS_KEY_ID: key
      S3_SECRET_ACCESS_KEY: secret
      S3_BUCKET: my-bucket
      S3_PREFIX: backup
```

Backups are uploaded as `s3://$S3_BUCKET/$S3_PREFIX/<database>_<timestamp>.dump`,
where the timestamp is UTC in ISO-8601 form — for example
`backup/dbname_2026-08-27T03:00:11.dump`. With `PASSPHRASE` set, `.gpg` is
appended.

To take a backup right now, without waiting for the schedule:

```bash
docker compose exec backup sh backup.sh
```

## Restore

> [!CAUTION]
> Restoring drops and re-creates every object in the target database.

From the most recent backup:

```bash
docker compose exec backup sh restore.sh
```

From a specific one, using the timestamp out of the object key:

```bash
docker compose exec backup sh restore.sh 2026-08-27T03:00:11
```

## Configuration

### Database

| Variable | Default | |
| --- | --- | --- |
| `POSTGRES_HOST` | | required |
| `POSTGRES_PORT` | `5432` | |
| `POSTGRES_DATABASE` | | required |
| `POSTGRES_USER` | | required |
| `POSTGRES_PASSWORD` | | required |
| `PGDUMP_EXTRA_OPTS` | | extra flags passed straight to `pg_dump`, e.g. `--schema=public` |

### Object storage

| Variable | Default | |
| --- | --- | --- |
| `S3_BUCKET` | | required |
| `S3_PREFIX` | `backup` | key prefix within the bucket; may be empty |
| `S3_REGION` | `us-east-1` | |
| `S3_ACCESS_KEY_ID` | | omit to use the instance role or `~/.aws` |
| `S3_SECRET_ACCESS_KEY` | | omit to use the instance role or `~/.aws` |
| `S3_ENDPOINT` | | set for anything that is not AWS S3, e.g. `https://s3.us-west-004.backblazeb2.com` |
| `S3_S3V4` | `no` | set to `yes` to force SigV4 signing |

### Behaviour

| Variable | Default | |
| --- | --- | --- |
| `SCHEDULE` | | [go-cron schedule](https://pkg.go.dev/github.com/robfig/cron#hdr-Predefined_schedules), e.g. `@daily` or `0 30 3 * * *`. Omit to back up once and exit. |
| `PASSPHRASE` | | encrypt the dump with GPG (AES-256) before upload |
| `BACKUP_KEEP_DAYS` | | delete this database's backups older than this many days |

`BACKUP_KEEP_DAYS` only removes keys that start with
`$S3_PREFIX/$POSTGRES_DATABASE_`, so several databases can share one prefix
without deleting each other's backups. It relies on the object's
`LastModified` time, which means server-side copies or re-uploads reset the
clock.

## Tags

| Tag | PostgreSQL | Base |
| --- | --- | --- |
| `17`, `latest` | 17 | Alpine 3.22 |

The tag tracks the major version of the PostgreSQL *client tools* in the image.
`pg_dump` refuses to dump a server newer than itself, so pick a tag at or above
your server's major version.

## Development

The Compose file in this repository brings up PostgreSQL, MinIO as a local
stand-in for S3, and the backup container, wired together:

```bash
docker compose up -d --build
docker compose exec backup sh backup.sh
docker compose exec backup sh restore.sh
```

MinIO's console is at http://localhost:9001 (`minioadmin` / `minioadmin`).

Build the image on its own:

```bash
docker build -t postgres-backup-s3:17 .
```

`POSTGRES_MAJOR` and `ALPINE_VERSION` are build arguments, so other
combinations are possible as long as Alpine packages the client for that
version — `--build-arg POSTGRES_MAJOR=16`, for instance.

## Credits

A fork of [eeshugerman/postgres-backup-s3](https://github.com/eeshugerman/postgres-backup-s3),
itself derived from [schickling/dockerfiles](https://github.com/schickling/dockerfiles/tree/master/postgres-backup-s3).
Scheduling is handled by [ivoronin/go-cron](https://github.com/ivoronin/go-cron).

Changes made here:

- PostgreSQL 17 client on Alpine 3.22, with the client package pinned by major
  version rather than inherited from whatever Alpine happens to ship
- runs as an unprivileged user
- the go-cron download is checksum-verified at build time and fetched on the
  build platform, so cross-platform builds do not run it under emulation
- `S3_PREFIX` is honoured by the image (upstream declared `S3_PATH` while the
  scripts read `S3_PREFIX`), and an empty prefix no longer produces `//` in keys
- retention is scoped to the database being backed up instead of the whole
  prefix, and no longer tries to delete a key literally named `None` when
  nothing matches
- "restore latest" sorts server-side, so it is not limited to the first 1000
  objects a single `s3 ls` returns
- credentials are no longer declared as empty `ENV` defaults in the image
- dump files are cleaned up even when a step fails

## License

MIT — see [LICENSE](LICENSE).
