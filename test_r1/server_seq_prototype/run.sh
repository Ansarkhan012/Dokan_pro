#!/usr/bin/env bash
# R1 Stage A design validation for the per-shop server_seq mechanism.
# Uses a disposable database inside the local Supabase container; never the
# dev database or any hosted project. Scenarios A-E and the prefix stress test
# from docs/recovery/r1-stage-a-design.md section F.
set -euo pipefail
export MSYS_NO_PATHCONV=1
C=supabase_db_POS_store; DB=r1_seq_proto
Q() { docker exec -i "$C" psql -X -q -At -U postgres -d "$DB" "$@"; }
SA=00000000-0000-0000-0000-00000000000a; SB=00000000-0000-0000-0000-00000000000b
docker exec -i "$C" psql -X -q -U postgres -d postgres -c "drop database if exists $DB" -c "create database $DB"
Q -v ON_ERROR_STOP=1 < "$(dirname "$0")/prototype.sql"

echo "A: same shop blocks, commit order = seq order"
Q -c "select sync_sale('$SA','11111111-0000-0000-0000-000000000001',3000)" >/dev/null &
sleep 0.5; Q -c "select sync_sale('$SA','22222222-0000-0000-0000-000000000002',0)" >/dev/null &
sleep 1; Q -c "select 'waiting on lock:', count(*) from pg_stat_activity where datname='$DB' and wait_event_type='Lock'"
Q -c "select 'visible while A open:', count(*) from sales"; wait
Q -c "select id, server_seq from sales order by server_seq"

echo "B: rollback releases, no gap"
printf "begin;\nselect sync_sale('$SA','33333333-0000-0000-0000-000000000003',2000);\nrollback;\n" | Q >/dev/null &
sleep 0.5; Q -c "select sync_sale('$SA','44444444-0000-0000-0000-000000000004',0)" >/dev/null; wait
Q -c "select 'seqs', string_agg(server_seq::text, ',' order by server_seq) from sales"

echo "C: different shops do not block"
Q -c "select sync_sale('$SA','55555555-0000-0000-0000-000000000005',3000)" >/dev/null &
sleep 0.5; Q -c "select 'shop B done at', clock_timestamp()::time, sync_sale('$SB','66666666-0000-0000-0000-000000000006',0)"; wait
Q -c "select 'shop A done at', clock_timestamp()::time"

echo "E: replay consumes nothing"
Q -c "select last_seq from shop_sync_state where shop_id='$SA'" -c "select sync_sale('$SA','11111111-0000-0000-0000-000000000001',0)" -c "select last_seq from shop_sync_state where shop_id='$SA'"

echo "Prefix stress: 8 writers, ~10% rollback, reader must never see N+1 without N"
printf '%s\n' '\set hold random(0, 15)' '\set r random(1, 100)' 'BEGIN;' "SELECT sync_sale('$SA', gen_random_uuid(), :hold);" '\if :r <= 10' 'ROLLBACK;' '\else' 'COMMIT;' '\endif' | docker exec -i "$C" sh -c 'cat > /tmp/w.sql'
( v=0; for i in $(seq 1 200); do r=$(Q -c "select max(server_seq), count(*) from sales where shop_id='$SA'"); [ "${r%|*}" != "${r#*|}" ] && v=$((v+1)); done; echo "reader violations=$v" ) &
docker exec -i "$C" pgbench -U postgres -d "$DB" -n -f /tmp/w.sql -c 8 -j 4 -T 20 | grep -E "processed|failed"; wait
Q -c "select 'max', max(server_seq), 'count', count(*) from sales where shop_id='$SA'"
docker exec -i "$C" psql -X -q -U postgres -d postgres -c "drop database $DB"
