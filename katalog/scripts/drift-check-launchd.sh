#!/usr/bin/env bash
# Tripwire: R2 članci (fetch pipeline) ↔ katalog u D1. launchd omotač oko
# `npm run drift-check -- --sync`.
#
# Katalog je PROJEKCIJA R2-a: epizoda s `data/<id>/article.json` koju nitko nije
# poslao na ingest ne postoji u aplikaciji, i ništa to ne javi (isti obrazac
# kao glasački bazen ↔ registar, vidi ../scripts/voting-drift-check.sh). Ovaj
# job svako jutro izmjeri razliku i, kad je ima, pošalje puni plan na
# `POST /api/katalog/v1/ingest` (idempotentno), pa ponovno izmjeri.
#
#   ./scripts/drift-check-launchd.sh               # tiho kad je poravnato (exit 0 bez synca)
#   ./scripts/drift-check-launchd.sh --verbose     # uvijek ispiši izvještaj
#   ./scripts/drift-check-launchd.sh --no-telegram
#
# Telegram (SAMO kroz ../scripts/telegram-notify.rb, koji redigira tajne iz .env):
#   exit 0 bez synca          → ništa
#   exit 0 nakon synca        → „poravnat nakon synca” + izvještaj
#   exit 1 (drift)            → ne bi se smio dogoditi uz --sync; javi
#   exit 2 / ostalo           → „ne mogu provjeriti” ili „sync pao”, rep izvještaja
#
# Instalacija (NE radi je agent):
#   cp katalog/launchd/ai.domovina.katalog-drift.plist ~/Library/LaunchAgents/
#   launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/ai.domovina.katalog-drift.plist
# Ručni okidač:  launchctl kickstart -k gui/$(id -u)/ai.domovina.katalog-drift
# Deinstalacija: launchctl bootout gui/$(id -u)/ai.domovina.katalog-drift
# Log: ~/Library/Logs/ai.domovina.katalog-drift.{out,err}.log
#
# Token: `INGEST_TOKEN` iz okoline ili redak u katalog/.dev.vars (čita ga sama
# skripta; ovdje se ne dira i ne ispisuje). Base: `KATALOG_BASE` (zadano
# https://domovina.ai).
set -uo pipefail

export LANG="${LANG:-en_US.UTF-8}" LC_ALL="${LC_ALL:-en_US.UTF-8}"
# launchd daje minimalan PATH — alate razriješi eksplicitno.
export PATH="/opt/homebrew/bin:/opt/homebrew/opt/ruby/bin:/usr/bin:/bin:/usr/sbin:/sbin:$PATH"

# node živi pod nvm-om, koji se pod launchdom ne aktivira (izmjereno 25.8.2026.
# na voting tripwireu). Najnovija instalirana verzija; skripta traži Node 24+.
if ! command -v node >/dev/null 2>&1; then
  NVM_BIN="$(/bin/ls -d "$HOME"/.nvm/versions/node/*/bin 2>/dev/null | sort -V | tail -1)"
  [[ -n "${NVM_BIN:-}" ]] && export PATH="$NVM_BIN:$PATH"
fi

KATALOG="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPO="$(cd "$KATALOG/.." && pwd)"
NOTIFIER="$REPO/scripts/telegram-notify.rb"
BASE="${KATALOG_BASE:-https://domovina.ai}"

VERBOSE=0; TELEGRAM=1
for a in "$@"; do
  case "$a" in
    --verbose)     VERBOSE=1 ;;
    --no-telegram) TELEGRAM=0 ;;
    *) echo "Nepoznat flag: $a" >&2; exit 2 ;;
  esac
done

notify() {  # nikad ne obara skriptu — notifikacija je posljedica, ne uvjet
  [[ $TELEGRAM -eq 1 ]] || { echo "(telegram isključen)"; return 0; }
  printf '%s' "$1" | "$NOTIFIER" || true
}

# Sve što ide u <pre> MORA kroz ovo: parse_mode=HTML bi `<` pročitao kao tag.
esc() { sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g'; }

if ! command -v node >/dev/null 2>&1; then
  echo "GRESKA: nema node u PATH-u" >&2
  notify "⚠️ <b>Katalog — drift tripwire ne radi</b>
<code>node</code> nije u PATH-u (nvm se ne aktivira pod launchdom)."
  exit 2
fi

REPORT_DIR="$(mktemp -d "${TMPDIR:-/tmp}/katalog-drift.XXXXXX")"
trap 'rm -rf "$REPORT_DIR"' EXIT
REPORT="$REPORT_DIR/report.json"

# Dani objave (odluka 1200): nightly piše automatic/watchlist/backfill.json TEK NAKON
# obrade, pa je katalog ingest iz pipelinea (KORAK 13.5) nove epizode upisao s
# datumom iz info.json/listinga. Drift-check gleda samo ID-eve i promjenu dana ne
# vidi, pa ovdje ide puni plan (idempotentan: nepromijenjen redak = 0 promjena).
# Neuspjeh javi, ali ne preskače drift-check.
DANI="$(cd "$KATALOG" && npm run -s ingest-episode -- --all --base "$BASE" 2>&1)"
DANI_STATUS=$?
if [[ $DANI_STATUS -ne 0 ]]; then
  echo "$DANI" >&2
  notify "⚠️ <b>Katalog — usklađivanje dana objave nije uspjelo</b> (exit $DANI_STATUS)
<pre>$(printf '%s' "$DANI" | tail -c 1200 | esc)</pre>"
elif [[ $VERBOSE -eq 1 ]]; then
  echo "$DANI"
fi

IZVJESTAJ="$(cd "$KATALOG" && npm run -s drift-check -- --sync --base "$BASE" --json "$REPORT" 2>&1)"
STATUS=$?

# Polje iz JSON izvještaja (prazno kad ga nema — npr. skripta pala prije pisanja).
field() {
  [[ -s "$REPORT" ]] || return 0
  node -e 'const r=JSON.parse(require("fs").readFileSync(process.argv[1],"utf8"));const v=process.argv[2].split(".").reduce((o,k)=>o==null?undefined:o[k],r);if(v!=null)process.stdout.write(String(v))' "$REPORT" "$1" 2>/dev/null || true
}

SAZETAK="$(printf '%s' "$IZVJESTAJ" | grep -v '^katalog drift-check' | sed 's/^  //' | tail -c 1500 | esc)"

case $STATUS in
  0)
    if [[ "$(field status)" == "synced" ]]; then
      echo "$IZVJESTAJ"
      notify "✅ <b>Katalog — poravnat nakon synca</b>
<pre>$SAZETAK</pre>"
    else
      [[ $VERBOSE -eq 1 ]] && echo "$IZVJESTAJ"
    fi
    exit 0
    ;;
  1)
    echo "$IZVJESTAJ"
    # Uz `--sync` epizodni drift završi kao 0 ili 2, pa je 1 ovdje drift
    # postavki kanala ili slugova (izvještaj, ne popravlja se ovdje).
    if [[ "$(field settings.status)" == "drift" ]]; then
      notify "⚠️ <b>Katalog — postavke kanala ili slugovi nisu poravnati</b>
<pre>$SAZETAK</pre>
Postavke poravnava poller (minuta); trajni drift = pogledaj <code>settings_poll_state</code>.
Slugovi: <code>npm run channel-slugs-sync -- --commit --confirm-production</code>"
    else
      notify "⚠️ <b>Katalog — D1 zaostaje za R2</b>
<pre>$SAZETAK</pre>
Pokreni u <code>katalog/</code>:
<code>npm run drift-check -- --sync</code>"
    fi
    exit 1
    ;;
  *)
    echo "$IZVJESTAJ" >&2
    if [[ -n "$(field sync.planEpisodes)" ]]; then
      NASLOV="❌ <b>Katalog — sync pao ili nije konvergirao</b>"
    else
      NASLOV="❌ <b>Katalog — provjera drifta pukla</b>"
    fi
    notify "$NASLOV
<pre>$SAZETAK</pre>"
    exit 2
    ;;
esac
