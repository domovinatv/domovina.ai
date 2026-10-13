#!/usr/bin/env bash
# Promovira VEĆ UPLOADANI versionCode na Play track (bez re-uploada AAB-a —
# edits.bundles.upload istog versionCodea pada, zato ovo nije play-upload.sh).
#   ./scripts/play-promote.sh <versionCode> [track] [release-notes-hr]
#   ./scripts/play-promote.sh 96 production "Novosti: …"
#
# Od 13.10.2026. production ide kao STAGED rollout (zadano 20 %): Play
# Console mjeri crash/ANR rate na tom dijelu korisnika, a
# scripts/play-rollout.sh ga podiže, zaustavlja ili dovršava.
#   ROLLOUT=1   ./scripts/play-promote.sh …   # odmah 100 % (svjesna iznimka)
#   ROLLOUT=0.5 ./scripts/play-promote.sh …
# Production traži i smoke vrata (scripts/smoke-gate.sh); SKIP_SMOKE_GATE=1
# ih preskače.
set -euo pipefail
cd "$(dirname "$0")/.."

PKG=ai.domovina
VC="${1:?versionCode obavezan (npr. 96)}"
TRACK="${2:-production}"
NOTES="${3:-}"
KEY="${PLAY_SA_KEY:-$HOME/.config/play-publisher/domovina-play-publisher.json}"
API=https://androidpublisher.googleapis.com/androidpublisher/v3/applications/$PKG
APP_VER=$(grep '^version:' pubspec.yaml | sed 's/version: //' | cut -d'+' -f1)

ROLLOUT="${ROLLOUT:-}"
if [[ "$TRACK" == "production" ]]; then
  ROLLOUT="${ROLLOUT:-0.2}"
  if [[ "${SKIP_SMOKE_GATE:-0}" != "1" ]]; then
    ./scripts/smoke-gate.sh "$VC" || { echo "smoke vrata zatvorena za $VC (SKIP_SMOKE_GATE=1 za iznimku)"; exit 1; }
  fi
fi
ROLLOUT="${ROLLOUT:-1}"

gcloud auth activate-service-account --key-file="$KEY" >/dev/null 2>&1
TOKEN=$(gcloud auth print-access-token --scopes=https://www.googleapis.com/auth/androidpublisher)
auth=(-H "Authorization: Bearer $TOKEN")

RELEASE=$(ROLLOUT="$ROLLOUT" ruby -rjson -e 'f=ENV["ROLLOUT"].to_f;
r={"name"=>"'"$APP_VER"' ('"$VC"')","versionCodes"=>["'"$VC"'"],"status"=>(f<1 ? "inProgress" : "completed")};
r["userFraction"]=f if f<1;
n=ARGV[0]; r["releaseNotes"]=[{"language"=>"hr","text"=>n}] unless n.to_s.empty?;
puts({"track"=>"'"$TRACK"'","releases"=>[r]}.to_json)' -- "$NOTES")

echo "==> edits.insert"
EDIT=$(curl -s --retry 3 "${auth[@]}" -H "Content-Length: 0" -X POST "$API/edits" | ruby -rjson -e 'puts JSON.parse(STDIN.read)["id"]')
echo "    editId=$EDIT"

echo "==> tracks.update ($TRACK ← versionCode $VC, rollout $ROLLOUT)"
curl -s --retry 3 "${auth[@]}" -H "Content-Type: application/json" -X PUT \
  "$API/edits/$EDIT/tracks/$TRACK" -d "$RELEASE" \
  | ruby -rjson -e 'd=JSON.parse(STDIN.read); abort("ERR: "+d["error"]["message"]) if d["error"]; puts "    track="+d["track"]'

echo "==> edits.commit"
curl -s --retry 3 "${auth[@]}" -H "Content-Length: 0" -X POST "$API/edits/$EDIT:commit" \
  | ruby -rjson -e 'd=JSON.parse(STDIN.read); abort("ERR: "+d["error"]["message"]) if d["error"]; puts "    committed editId="+d["id"]'
echo "GOTOVO — versionCode $VC na '$TRACK' tracku."
