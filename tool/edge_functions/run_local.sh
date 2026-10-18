#!/usr/bin/env bash
# Local security test of the Edge Functions (admin-create-owner,
# issue-entitlement) against the disposable R1 HTTP stack.
#
#   tool/r1_integration/local_http_stack.sh up     # first
#   tool/edge_functions/run_local.sh               # serves both functions, runs the tests
#
# Each function runs in its own edge-runtime container (the image the local
# dev stack already pulled) as the main service, on the stack's network, with
# SUPABASE_URL pointing at the scratch Kong. The functions are called
# directly, so the platform gateway's verify_jwt check is NOT exercised here:
# these tests prove the functions' own checks. A throwaway RSA key is
# generated per run. Containers are removed on exit; nothing is committed.
set -euo pipefail
export MSYS_NO_PATHCONV=1

PROJECT=POS_store
NETWORK="supabase_network_${PROJECT}"
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
# Native path for docker cp / node on Windows (Git Bash path conversion is off).
HOST_ROOT="$(cygpath -m "$ROOT" 2>/dev/null || echo "$ROOT")"
IMAGE="$(docker images --format '{{.Repository}}:{{.Tag}}' | grep -m1 'supabase/edge-runtime')"
[ -n "$IMAGE" ] || { echo "edge-runtime image not found (run supabase start once)" >&2; exit 1; }
WORK="$(mktemp -d)"; WORK_HOST="$(cygpath -m "$WORK" 2>/dev/null || echo "$WORK")"

secret() { grep -h "^$1=" "$ROOT"/supabase/.temp/start-secrets/*/env/docker.env | head -1 | cut -d= -f2-; }
ANON="$(secret SUPABASE_ANON_KEY)"; SERVICE="$(secret SUPABASE_SERVICE_ROLE_KEY)"
[ -n "$ANON" ] && [ -n "$SERVICE" ] || { echo "local keys not found" >&2; exit 1; }

node -e "const {generateKeyPairSync}=require('crypto');const {privateKey,publicKey}=generateKeyPairSync('rsa',{modulusLength:2048});
require('fs').writeFileSync(process.argv[1],JSON.stringify(privateKey.export({format:'jwk'})));
require('fs').writeFileSync(process.argv[2],JSON.stringify(publicKey.export({format:'jwk'})))" "$WORK_HOST/private.jwk" "$WORK_HOST/public.jwk"

cat > "$WORK/fn.env" <<EOF
SUPABASE_URL=http://r1http_kong:8000
SUPABASE_ANON_KEY=$ANON
SUPABASE_SERVICE_ROLE_KEY=$SERVICE
ENTITLEMENT_PRIVATE_JWK=$(cat "$WORK/private.jwk")
ENTITLEMENT_KEY_ID=edge-test
EOF

cleanup() { docker rm -f edgefn_admin edgefn_entitlement >/dev/null 2>&1 || true; rm -rf "$WORK"; }
trap cleanup EXIT
start_fn() { # name function port
  docker rm -f "$1" >/dev/null 2>&1 || true
  docker create --name "$1" --network "$NETWORK" --env-file "$WORK_HOST/fn.env" -p "127.0.0.1:$3:8081" \
    --entrypoint sh "$IMAGE" -c "edge-runtime start --main-service=/fn --port=8081" >/dev/null
  docker cp "$HOST_ROOT/supabase/functions/$2" "$1:/fn" >/dev/null
  docker start "$1" >/dev/null
}
start_fn edgefn_admin admin-create-owner 54431
start_fn edgefn_entitlement issue-entitlement 54432
for port in 54431 54432; do
  for _ in $(seq 1 90); do
    code=$(curl -s -o /dev/null -w '%{http_code}' -X OPTIONS "http://127.0.0.1:$port/" || true)
    [ "$code" != "000" ] && break; sleep 1
  done
done

EDGE_ADMIN_URL=http://127.0.0.1:54431 EDGE_ENTITLEMENT_URL=http://127.0.0.1:54432 \
R1_HTTP_URL="${R1_HTTP_URL:-http://127.0.0.1:${R1_HTTP_PORT:-54421}}" R1_HTTP_ANON_KEY="$ANON" \
EDGE_SERVICE_ROLE_KEY="$SERVICE" EDGE_PUBLIC_JWK="$(cat "$WORK/public.jwk")" \
  node --test "$HOST_ROOT/tool/edge_functions/edge_security_test.mjs" || { status=$?;
    docker logs edgefn_admin 2>&1 | tail -20; docker logs edgefn_entitlement 2>&1 | tail -20; exit $status; }
