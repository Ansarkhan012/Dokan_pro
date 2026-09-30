#!/usr/bin/env bash
# Runs the complete R1 integration layer locally (see test_r1/README.md).
# Uses only local Docker: a per-file scratch database for the direct-DB layer
# and a disposable HTTP stack (local_http_stack.sh) for the HTTP layer. The dev
# database is never written. The HTTP stack is always torn down on exit.
set -euo pipefail
cd "$(dirname "$0")/../.."
OUT="${TMPDIR:-${TEMP:-/tmp}}/r1_local_run"
mkdir -p "$OUT"
trap 'bash tool/r1_integration/local_http_stack.sh down' EXIT

bash tool/r1_integration/local_http_stack.sh up > "$OUT/env.txt"
URL=$(grep '^R1_HTTP_URL=' "$OUT/env.txt" | cut -d= -f2-)
KEY=$(grep '^R1_HTTP_ANON_KEY=' "$OUT/env.txt" | cut -d= -f2-)

echo "== guard"; flutter test test_r1/guard
echo "== tz UTC"; TZ=UTC flutter test test_r1/tz --dart-define=EXPECTED_TZ_OFFSET_MINUTES=0
echo "== tz Asia/Karachi"; TZ=Asia/Karachi flutter test test_r1/tz --dart-define=EXPECTED_TZ_OFFSET_MINUTES=300
echo "== R1.1 checkout durability (green)"; flutter test test_r1/green
echo "== direct-DB (green)"; flutter test test_r1/direct_db --dart-define=R1_SERVER=true
echo "== HTTP (green)"; flutter test test_r1/http \
  --dart-define=R1_HTTP_URL="$URL" --dart-define=R1_HTTP_ANON_KEY="$KEY"
echo "== expected-red (TZ=Asia/Karachi)"
TZ=Asia/Karachi flutter test test_r1/red --concurrency=2 --dart-define=R1_SERVER=true \
  --dart-define=R1_HTTP_URL="$URL" --dart-define=R1_HTTP_ANON_KEY="$KEY" \
  --file-reporter json:"$OUT/red.json" > "$OUT/red.txt" 2>&1 || true
python .github/scripts/expect_red.py "$OUT/red.json" --manifest test_r1/red/EXPECTED_RED.txt
