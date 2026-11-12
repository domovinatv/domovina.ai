#!/opt/homebrew/bin/bash
# Dnevni job portala vijesti (S8, odluke 806–809). Pokreće ga launchd
# (launchd/ai.domovina.vijesti-daily.plist); ručno: vijesti/scripts/daily.sh [--dry-run]
#
# 1. SSH tunel do kontejnera produkcijske baze (Postgres nije javno izložen;
#    IP kontejnera se čita svaki put jer se mijenja pri redeployu).
# 2. `npm run daily` kao uloga vijesti_engine: red provjere uredničkih
#    verzija, pa nove epizode dopuštenih kanala, unutar dnevnog limita poziva.
# 3. Telegram SAMO na kraju i samo kad ima što javiti (novi nacrti, provjerene
#    verzije, limit, greška), ISKLJUČIVO kroz scripts/telegram-notify.rb
#    (javna grupa, redakcija tajni). Nikad napredak.
#
# Izlaz: 0 gotovo, 3 dio čeka sutra (limit), 1 greška, 4 već radi.
set -uo pipefail

V="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ROOT="$(cd "$V/.." && pwd)"
export PATH="$HOME/.local/bin:$HOME/.nvm/versions/node/v24.16.0/bin:/opt/homebrew/opt/ruby/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin"

# shellcheck disable=SC1091
set -a; [[ -f "$V/.env" ]] && source "$V/.env"; set +a

DAY="$(TZ=Europe/Zagreb date +%F)"
mkdir -p "$V/.cache/daily"
LOG="$V/.cache/daily/$DAY.log"
NOTIFY="$V/.cache/daily/$DAY.notify.html"
LOCK="$V/.cache/daily/lock"
PORT="${VIJESTI_TUNNEL_PORT:-54329}"
TUNNEL_PID=""

notify() { "$ROOT/scripts/telegram-notify.rb" "$@" || true; }
fail() {
  echo "$(date -u +%FT%TZ) GREŠKA: $1" >>"$LOG"
  notify --text "<b>Vijesti: dnevni job nije prošao</b>
$1
log: vijesti/.cache/daily/$DAY.log"
  exit 1
}
cleanup() {
  [[ -n "$TUNNEL_PID" ]] && kill "$TUNNEL_PID" 2>/dev/null
  rmdir "$LOCK" 2>/dev/null
}

if ! mkdir "$LOCK" 2>/dev/null; then
  echo "dnevni job već radi ($LOCK)" >&2
  exit 4
fi
trap cleanup EXIT

for v in VIJESTI_SSH_TARGET VIJESTI_SSH_KEY VIJESTI_ENGINE_DB_PASSWORD; do
  [[ -n "${!v:-}" ]] || fail "u vijesti/.env nema $v"
done
SSH=(ssh -i "$VIJESTI_SSH_KEY" -o BatchMode=yes -o ConnectTimeout=20 "$VIJESTI_SSH_TARGET")

DB_IP="$("${SSH[@]}" 'docker inspect -f "{{range .NetworkSettings.Networks}}{{.IPAddress}} {{end}}" $(docker ps --format "{{.Names}}" | grep -m1 "^supabase-db")' 2>>"$LOG" | awk '{print $1}')"
[[ "$DB_IP" =~ ^[0-9.]+$ ]] || fail "ne mogu naći IP kontejnera baze (ssh)"

"${SSH[@]}" -N -o ExitOnForwardFailure=yes -o ServerAliveInterval=30 \
  -L "127.0.0.1:$PORT:$DB_IP:5432" 2>>"$LOG" &
TUNNEL_PID=$!
for _ in $(seq 1 30); do
  nc -z 127.0.0.1 "$PORT" 2>/dev/null && break
  kill -0 "$TUNNEL_PID" 2>/dev/null || fail "SSH tunel se nije otvorio"
  sleep 0.5
done
nc -z 127.0.0.1 "$PORT" 2>/dev/null || fail "SSH tunel nije spreman nakon 15 s"

PW="$(node -e 'process.stdout.write(encodeURIComponent(process.argv[1]))' "$VIJESTI_ENGINE_DB_PASSWORD")"
export VIJESTI_DATABASE_URL="postgres://vijesti_engine:$PW@127.0.0.1:$PORT/postgres"

rm -f "$NOTIFY"
cd "$V" || fail "nema $V"
{
  echo "=== $(date -u +%FT%TZ) dnevni job $*"
  npm run -s daily -- --notify-file "$NOTIFY" "$@"
} >>"$LOG" 2>&1
code=$?

if [[ $code -ne 0 && $code -ne 3 ]]; then
  fail "npm run daily izašao s $code: $(tail -n 3 "$LOG" | tr '\n' ' ' | tail -c 300)"
fi
[[ -s "$NOTIFY" ]] && notify <"$NOTIFY"
exit "$code"
