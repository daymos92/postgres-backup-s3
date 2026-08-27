A Docker image that dumps a PostgreSQL database to S3-compatible object storage
on a schedule, and restores from those dumps. It contains `pg_dump` and
`pg_restore`, the AWS CLI, GnuPG and
[go-cron](https://github.com/ivoronin/go-cron), on Alpine. The image tag selects
the PostgreSQL major version.

Source, issues and full documentation:
[github.com/daymos92/postgres-backup-s3](https://github.com/daymos92/postgres-backup-s3).

## Tags

| Tag | PostgreSQL client | Base | Platforms |
| --- | --- | --- | --- |
| `17`, `latest` | 17 | Alpine 3.22 | `linux/amd64`, `linux/arm64` |

The tag is the major version of the PostgreSQL *client tools* in the image, not
a release number of this project; `latest` follows the newest major published
here. `pg_dump` refuses to dump a server newer than itself, so choose a tag
greater than or equal to the server's major version.

## Usage

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

Objects are written to
`s3://$S3_BUCKET/$S3_PREFIX/<database>_<timestamp>.dump`, with the timestamp in
UTC ISO-8601 form, for example `backup/dbname_2026-08-27T03:00:11.dump`. When
`PASSPHRASE` is set, `.gpg` is appended to the key.

If `SCHEDULE` is unset the container takes one backup and exits, which is useful
under an external scheduler. To run a backup on demand in a scheduled
container:

```bash
docker compose exec backup sh backup.sh
```

## Restore

Restoring runs `pg_restore --clean --if-exists`, which drops and re-creates
every object the dump contains.

```bash
docker compose exec backup sh restore.sh                       # latest backup
docker compose exec backup sh restore.sh 2026-08-27T03:00:11   # a specific one
```

`PASSPHRASE` must match the one the backup was taken with; the script looks for
`.dump.gpg` when it is set and `.dump` when it is not.

## Configuration

### Database

| Variable | Default | |
| --- | --- | --- |
| `POSTGRES_HOST` | | required |
| `POSTGRES_PORT` | `5432` | |
| `POSTGRES_DATABASE` | | required |
| `POSTGRES_USER` | | required |
| `POSTGRES_PASSWORD` | | required |
| `PGDUMP_EXTRA_OPTS` | | passed through to `pg_dump`, for example `--schema=public` |

### Object storage

| Variable | Default | |
| --- | --- | --- |
| `S3_BUCKET` | | required |
| `S3_PREFIX` | `backup` | key prefix inside the bucket; may be empty |
| `S3_REGION` | `us-east-1` | |
| `S3_ACCESS_KEY_ID` | | leave unset to use an instance role or a mounted `~/.aws` |
| `S3_SECRET_ACCESS_KEY` | | as above |
| `S3_ENDPOINT` | | required for non-AWS providers, for example `https://s3.us-west-004.backblazeb2.com` |
| `S3_S3V4` | `no` | `yes` forces SigV4 signing |

### Scheduling and retention

| Variable | Default | |
| --- | --- | --- |
| `SCHEDULE` | | cron expression or descriptor, for example `@daily`, `30 3 * * *`, `0 30 3 * * *`. Unset means a single run. |
| `PASSPHRASE` | | symmetric GPG encryption (AES-256) before upload |
| `BACKUP_KEEP_DAYS` | | delete backups of this database older than N days |

The schedule is parsed by [robfig/cron v3](https://pkg.go.dev/github.com/robfig/cron/v3#hdr-CRON_Expression_Format);
the seconds field is optional, so both five- and six-field expressions are
accepted.

## Notes

- A failing scheduled backup is logged, but go-cron neither exits nor changes
  the container's status. Watch the logs or the age of the newest object in the
  bucket; do not treat a running container as evidence that backups are
  succeeding.
- `pg_dump` covers one database. Cluster-wide objects such as roles and
  tablespaces are not included, so a restore into an empty cluster needs those
  re-created first.
- The dump is written to the container filesystem before upload, so the
  container needs free space for one full dump.
- `BACKUP_KEEP_DAYS` only deletes keys beginning with
  `$S3_PREFIX/$POSTGRES_DATABASE_`, so several databases can share a prefix
  without deleting each other's backups. It compares against the object's
  `LastModified` time rather than the timestamp in the key, so a server-side
  copy or re-upload resets the clock.
- The container runs as UID 1000.

## Credits and license

A fork of [eeshugerman/postgres-backup-s3](https://github.com/eeshugerman/postgres-backup-s3),
which in turn derives from
[schickling/dockerfiles](https://github.com/schickling/dockerfiles/tree/master/postgres-backup-s3).
The environment variables are unchanged, so it is a drop-in replacement, except
that `S3_PATH` is gone: it was declared in upstream's Dockerfile but never read
by the scripts, which have always used `S3_PREFIX`. The full list of behavioural
differences is in the
[README](https://github.com/daymos92/postgres-backup-s3#relation-to-upstream).

MIT.
