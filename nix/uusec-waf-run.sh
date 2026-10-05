#!/bin/sh
set -eu
prefix="${UUSEC_WAF_PREFIX:-/uuwaf}"
cd "$prefix"
if [ -z "${UUWAF_DB_DSN:-}" ] && [ -n "${UUWAF_DB_PASSWORD_FILE:-}" ]; then
  pw=$(cat "$UUWAF_DB_PASSWORD_FILE")
  host="${UUWAF_DB_HOST:-127.0.0.1}"
  port="${UUWAF_DB_PORT:-3306}"
  user="${UUWAF_DB_USER:-uuwaf}"
  name="${UUWAF_DB_NAME:-uuwaf}"
  export UUWAF_DB_DSN="${user}:${pw}@tcp(${host}:${port})/${name}?charset=utf8mb4&parseTime=true&loc=Local"
fi
exec "$prefix/waf-service"
