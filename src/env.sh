# Validates configuration and exports the settings shared by backup.sh and
# restore.sh. Meant to be sourced, not executed.

require() {
  eval "value=\${$1:-}"
  if [ -z "$value" ]; then
    echo "Missing required environment variable: $1" >&2
    exit 1
  fi
}

# Docker's legacy container links expose the database address this way.
if [ -z "${POSTGRES_HOST:-}" ] && [ -n "${POSTGRES_PORT_5432_TCP_ADDR:-}" ]; then
  POSTGRES_HOST="$POSTGRES_PORT_5432_TCP_ADDR"
  POSTGRES_PORT="$POSTGRES_PORT_5432_TCP_PORT"
fi

require POSTGRES_HOST
require POSTGRES_PORT
require POSTGRES_DATABASE
require POSTGRES_USER
require POSTGRES_PASSWORD
require S3_BUCKET

export PGHOST="$POSTGRES_HOST"
export PGPORT="$POSTGRES_PORT"
export PGUSER="$POSTGRES_USER"
export PGPASSWORD="$POSTGRES_PASSWORD"
export PGDATABASE="$POSTGRES_DATABASE"

if [ -n "${S3_ACCESS_KEY_ID:-}" ]; then
  export AWS_ACCESS_KEY_ID="$S3_ACCESS_KEY_ID"
fi
if [ -n "${S3_SECRET_ACCESS_KEY:-}" ]; then
  export AWS_SECRET_ACCESS_KEY="$S3_SECRET_ACCESS_KEY"
fi
export AWS_DEFAULT_REGION="${S3_REGION:-us-east-1}"

# The two values below are consumed by backup.sh and restore.sh after sourcing.
# shellcheck disable=SC2034

# Left unquoted at the call site so that an empty value expands to nothing
# rather than to an empty argument.
if [ -n "${S3_ENDPOINT:-}" ]; then
  aws_args="--endpoint-url $S3_ENDPOINT"
else
  aws_args=""
fi

# Either empty or exactly one trailing slash, so that object keys can be built
# by plain concatenation.
key_prefix=$(echo "${S3_PREFIX:-}" | sed -e 's:^/*::' -e 's:/*$::')
if [ -n "$key_prefix" ]; then
  key_prefix="${key_prefix}/"
fi
