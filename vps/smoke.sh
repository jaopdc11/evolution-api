#!/usr/bin/env bash
# Smoke test for the vps patches: build, migrate, boot, /saude, data dir.
# Needs Docker (throwaway Postgres 17). Run from the repo root:
#   bash vps/smoke.sh                 # with EVOLUTION_DADOS (data outside the repo)
#   SMOKE_SEM_DADOS=1 bash vps/smoke.sh   # without it (upstream behavior)
set -euo pipefail
cd "$(dirname "$0")/.."

PG=evo-smoke-pg
PORTA=18080
DADOS=$(mktemp -d)
LOG=$(mktemp)
PID=""

limpar() {
  [[ -n $PID ]] && kill "$PID" 2>/dev/null || true
  docker rm -f "$PG" >/dev/null 2>&1 || true
  rm -rf "$DADOS" .env
}
trap limpar EXIT
falha() { echo "FAIL: $*" >&2; tail -40 "$LOG" >&2 || true; exit 1; }

docker rm -f "$PG" >/dev/null 2>&1 || true
docker run -d --name "$PG" -e POSTGRES_PASSWORD=smoke -e POSTGRES_DB=evolution \
  -p 127.0.0.1:54330:5432 postgres:17 >/dev/null
for _ in $(seq 30); do docker exec "$PG" pg_isready -U postgres >/dev/null 2>&1 && break; sleep 1; done

rm -rf instances store
{
  echo "SERVER_PORT=$PORTA"
  echo "SERVER_URL=http://127.0.0.1:$PORTA"
  echo "DATABASE_PROVIDER=postgresql"
  echo "DATABASE_CONNECTION_URI=postgresql://postgres:smoke@127.0.0.1:54330/evolution"
  echo "CACHE_REDIS_ENABLED=false"
  echo "CACHE_LOCAL_ENABLED=true"
  echo "AUTHENTICATION_API_KEY=smoke"
  echo "TELEMETRY_ENABLED=false"
  echo "DATABASE_SAVE_DATA_INSTANCE=true"
  [[ -z ${SMOKE_SEM_DADOS:-} ]] && echo "EVOLUTION_DADOS=$DADOS"
} > .env
set -a; source .env; set +a

[[ -d node_modules ]] || npm ci --no-audit --no-fund >"$LOG" 2>&1 || falha "npm ci"
npm run typecheck >"$LOG" 2>&1 || falha "npm run typecheck"
npm run build >"$LOG" 2>&1 || falha "npm run build"
test -f dist/index.js || falha "dist/index.js not built"
npm run db:migrar >"$LOG" 2>&1 || falha "npm run db:migrar"

node dist/index.js >"$LOG" 2>&1 &
PID=$!
for _ in $(seq 60); do curl -fsS "127.0.0.1:$PORTA/saude" >/dev/null 2>&1 && break; sleep 1; done

saude=$(curl -fsS "127.0.0.1:$PORTA/saude") || falha "/saude did not answer"
[[ $saude == '{"status":"ok"}' ]] || falha "/saude body: $saude"

codigo=$(curl -s -o /dev/null -w '%{http_code}' -X POST "127.0.0.1:$PORTA/instance/create" \
  -H 'apikey: smoke' -H 'Content-Type: application/json' \
  -d '{"instanceName":"smoke","integration":"WHATSAPP-BAILEYS","qrcode":true}')
[[ $codigo == 201 ]] || falha "instance/create returned $codigo"
sleep 3

if [[ -z ${SMOKE_SEM_DADOS:-} ]]; then
  test -d "$DADOS/instances" || falha "no instances dir under EVOLUTION_DADOS"
  test ! -e instances || falha "./instances created inside the repo"
else
  test -d instances || falha "without EVOLUTION_DADOS, ./instances should be in cwd"
  rm -rf instances store
fi
echo "PASS"
