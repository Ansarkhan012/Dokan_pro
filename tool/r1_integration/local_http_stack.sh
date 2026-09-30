#!/usr/bin/env bash
# Disposable LOCAL HTTP stack for the R1 integration suite (developer machines).
#
# CI does not use this script: it runs `supabase start` on a fresh ephemeral
# stack. Locally the Supabase CLI is not required. This script reuses the Docker
# images and configuration of the already-running local dev stack
# (project_id POS_store) and starts separate GoTrue, PostgREST and Kong
# containers against a scratch database `r1_http`, published only on
# 127.0.0.1:54421. The dev database is never written.
#
#   tool/r1_integration/local_http_stack.sh up     # prints R1_HTTP_URL / R1_HTTP_ANON_KEY lines
#   tool/r1_integration/local_http_stack.sh down   # removes containers and scratch database
#
# Secrets are read at runtime from the running local stack and written only to
# a temporary directory that is deleted on `down`. Nothing is committed.
set -euo pipefail
export MSYS_NO_PATHCONV=1

PROJECT=POS_store
DB_CONTAINER="supabase_db_${PROJECT}"
NETWORK="supabase_network_${PROJECT}"
SCRATCH_DB=r1_http
# Override with R1_HTTP_PORT when Windows reserves the default (netsh excludedportrange).
PORT="${R1_HTTP_PORT:-54421}"
PREFIX=r1http
WORK="${TMPDIR:-${TEMP:-/tmp}}/${PREFIX}_stack"
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"

psql_as() { docker exec -i "$DB_CONTAINER" psql -X -q -At -v ON_ERROR_STOP=1 -U "$1" -d "$2"; }

down() {
  docker rm -f "${PREFIX}_kong" "${PREFIX}_rest" "${PREFIX}_auth" >/dev/null 2>&1 || true
  echo "drop database if exists ${SCRATCH_DB} with (force);" | psql_as postgres postgres >/dev/null 2>&1 || true
  rm -rf "$WORK"
}

env_of() {
  docker inspect "$1" --format '{{range .Config.Env}}{{println .}}{{end}}' | grep -v '^PATH='
}

up() {
  docker inspect -f '{{.State.Running}}' "$DB_CONTAINER" 2>/dev/null | grep -q true \
    || { echo "local dev stack (${DB_CONTAINER}) is not running" >&2; exit 1; }
  down
  mkdir -p "$WORK"

  # 1. Scratch database with the objects the Supabase image normally provides.
  printf 'create database %s;\n' "$SCRATCH_DB" | psql_as postgres postgres
  psql_as supabase_admin "$SCRATCH_DB" <<'SQL'
create schema auth authorization supabase_auth_admin;
grant usage on schema auth to anon, authenticated, service_role, postgres;
create schema graphql_public;
grant usage on schema graphql_public to anon, authenticated, service_role;
SQL

  # 2. GoTrue: same image and configuration, different database.
  env_of "supabase_auth_${PROJECT}" \
    | sed -E "s#(GOTRUE_DB_DATABASE_URL=postgres(ql)?://[^@]+@[^/]+/)[^?]*#\1${SCRATCH_DB}#" > "$WORK/auth.env"
  docker run -d --name "${PREFIX}_auth" --network "$NETWORK" --env-file "$WORK/auth.env" \
    "$(docker inspect -f '{{.Config.Image}}' "supabase_auth_${PROJECT}")" >/dev/null
  for _ in $(seq 1 60); do
    n=$(echo "select count(*) from information_schema.tables where table_schema='auth' and table_name='users';" \
      | psql_as postgres "$SCRATCH_DB" 2>/dev/null || true)
    [ "$n" = "1" ] && break; sleep 1
  done
  [ "$n" = "1" ] || { echo "GoTrue did not create auth.users" >&2; exit 1; }
  psql_as supabase_admin "$SCRATCH_DB" <<'SQL'
grant all on all tables in schema auth to postgres;
grant execute on all functions in schema auth to postgres, anon, authenticated, service_role;
SQL

  # 3. Application migrations from zero, then seed (as the CLI would).
  for f in "$ROOT"/supabase/migrations/*.sql; do psql_as postgres "$SCRATCH_DB" < "$f" >/dev/null; done
  psql_as postgres "$SCRATCH_DB" < "$ROOT/supabase/seed.sql" >/dev/null

  # 4. PostgREST.
  env_of "supabase_rest_${PROJECT}" \
    | sed -E "s#(PGRST_DB_URI=postgres(ql)?://[^@]+@[^/]+/)[^?]*#\1${SCRATCH_DB}#" > "$WORK/rest.env"
  docker run -d --name "${PREFIX}_rest" --network "$NETWORK" --env-file "$WORK/rest.env" \
    "$(docker inspect -f '{{.Config.Image}}' "supabase_rest_${PROJECT}")" >/dev/null

  # 5. Kong gateway with the dev routes re-pointed at the scratch services.
  env_of "supabase_kong_${PROJECT}" > "$WORK/kong.env"
  docker exec "supabase_kong_${PROJECT}" cat /home/kong/kong.yml \
    | sed -e "s#supabase_auth_${PROJECT}#${PREFIX}_auth#g" -e "s#supabase_rest_${PROJECT}#${PREFIX}_rest#g" > "$WORK/kong.yml"
  for f in custom_nginx.template localhost.crt localhost.key; do
    docker cp "supabase_kong_${PROJECT}:/home/kong/$f" "$WORK/$f"
  done
  docker create --name "${PREFIX}_kong" --network "$NETWORK" --env-file "$WORK/kong.env" \
    -p "127.0.0.1:${PORT}:8000" --entrypoint /docker-entrypoint.sh \
    "$(docker inspect -f '{{.Config.Image}}' "supabase_kong_${PROJECT}")" \
    kong docker-start --nginx-conf /home/kong/custom_nginx.template >/dev/null
  for f in kong.yml custom_nginx.template localhost.crt localhost.key; do
    docker cp "$WORK/$f" "${PREFIX}_kong:/home/kong/$f"
  done
  docker start "${PREFIX}_kong" >/dev/null

  anon=$(grep -h '^SUPABASE_ANON_KEY=' "$ROOT"/supabase/.temp/start-secrets/*/env/docker.env | head -1 | cut -d= -f2-)
  [ -n "$anon" ] || { echo "local anon key not found" >&2; exit 1; }
  for _ in $(seq 1 60); do
    code=$(curl -s -o /dev/null -w '%{http_code}' -X POST "http://127.0.0.1:${PORT}/rest/v1/rpc/is_active_owner" \
      -H "apikey: ${anon}" -H "Content-Type: application/json" -d '{"p_shop_id":"00000000-0000-0000-0000-000000000000"}' || true)
    # anon may not execute the helper (401/403/404) but a PGRST002 schema-cache
    # outage returns 503; anything else means the full path is serving.
    [ -n "$code" ] && [ "$code" != "000" ] && [ "$code" != "503" ] && [ "$code" != "502" ] && break
    sleep 1
  done
  echo "R1_HTTP_URL=http://127.0.0.1:${PORT}"
  echo "R1_HTTP_ANON_KEY=${anon}"
}

case "${1:-}" in
  up) up ;;
  down) down ;;
  *) echo "usage: $0 up|down" >&2; exit 2 ;;
esac
