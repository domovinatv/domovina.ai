#!/usr/bin/env bash
# Smoke svih uređaja farme nad buildom koji je nightly upravo uploadao.
#
#   ./scripts/nightly-smoke.sh <build>    # iz nightly worktreea (isti SHA)
#
# Po uređaju dva testa:
#   release  — scripts/release-smoke.sh nad ISTIM binarnim paketom
#              (AAB; za iOS development export istog archivea)
#   ui       — scripts/smoke-device.sh (integration test, portrait + landscape,
#              reprodukcija, overflow)
#
# Ishod ide u <repo>/.nightly/smoke/builds/<build>.txt — prvi redak
# `result=pass|fail|unknown` čitaju smoke-gate.sh, asc-submit.rb i
# play-promote.sh. `pass` traži: nijedan pad I bar jedan Android i jedan iOS
# uređaj koji je prošao oba testa. Stdout = retci za Telegram.
#
# Exit: 0 pass, 1 fail, 2 unknown (nema uređaja, sve „ne mogu provjeriti”).
# Plan: docs/plans/2026-10-13-smoke-testovi-na-uredajima.md
set -uo pipefail
cd "$(dirname "$0")/.."
BN="${1:?build broj}"

# Zapis ide u GLAVNI repo (nightly worktree se briše svake noći).
MAIN=$(git worktree list --porcelain | awk '/^worktree /{print $2; exit}')
OUTDIR="$MAIN/.nightly/smoke/builds"; mkdir -p "$OUTDIR"
LOGDIR="$MAIN/.nightly/smoke/$BN"; rm -rf "$LOGDIR"; mkdir -p "$LOGDIR"

AAB=build/app/outputs/bundle/release/app-release.aab
IPA=$(ls build/ios/ipa-dev/*.ipa 2>/dev/null | head -1)

mapfile -t DEVICES < <(flutter devices --machine --device-timeout 30 2>/dev/null \
  | ruby -rjson -e 'JSON.parse(STDIN.read).each { |d|
      p = d["targetPlatform"].to_s
      kind = p.start_with?("android") ? "android" : (p == "ios" ? "ios" : nil)
      puts "#{kind}|#{d["id"]}|#{d["name"]}" if kind }')

LINES=(); FAIL=0; PASS_ANDROID=0; PASS_IOS=0
label() { case $1 in 0) echo "ok" ;; 1) echo "PAO" ;; *) echo "nije provjereno" ;; esac; }

for row in "${DEVICES[@]}"; do
  IFS='|' read -r kind id name <<<"$row"
  if [[ $kind == android ]]; then
    ./scripts/release-smoke.sh "$id" --aab "$AAB" > "$LOGDIR/$id-release.log" 2>&1; r1=$?
  elif [[ -n "$IPA" ]]; then
    ./scripts/release-smoke.sh "$id" --ipa "$IPA" > "$LOGDIR/$id-release.log" 2>&1; r1=$?
  else
    echo "nema development IPA-e (build/ios/ipa-dev)" > "$LOGDIR/$id-release.log"; r1=2
  fi
  ./scripts/smoke-device.sh "$id" > "$LOGDIR/$id-ui.log" 2>&1; r2=$?

  line="$name: release $(label $r1), ui $(label $r2)"
  # Razlog pada: prvi konkretan redak iz loga.
  for pair in "$r1:$LOGDIR/$id-release.log" "$r2:$LOGDIR/$id-ui.log"; do
    rc=${pair%%:*}; log=${pair#*:}
    [[ $rc -eq 0 ]] && continue
    # Redoslijed je bitan: konkretan razlog prije općenitog „SMOKE: PAO”.
    # (`^  - ` sam po sebi hvata i Flutterov popis pluginova bez SPM-a.)
    why=$(grep -m1 -E 'reprodukcija|overflowed|SMOKE_NATIVE|nativni crash|proces ne postoji|nije u prvom planu|player se nije|Dart greške|GRESKA|ne mogu provjeriti|zastoj' "$log" \
      || grep -m1 -E 'SMOKE: |RELEASE SMOKE' "$log")
    why=$(sed 's/^ *- //' <<<"$why" | cut -c1-160)
    [[ -n "$why" ]] && line+=$'\n'"   ↳ $why"
  done
  LINES+=("$line")

  [[ $r1 -eq 1 || $r2 -eq 1 ]] && FAIL=1
  if [[ $r1 -eq 0 && $r2 -eq 0 ]]; then
    [[ $kind == android ]] && PASS_ANDROID=1 || PASS_IOS=1
  fi
done

if [[ ${#DEVICES[@]} -eq 0 ]]; then
  RESULT=unknown; LINES+=("nijedan uređaj farme nije spojen")
elif [[ $FAIL -eq 1 ]]; then
  RESULT=fail
elif [[ $PASS_ANDROID -eq 1 && $PASS_IOS -eq 1 ]]; then
  RESULT=pass
else
  RESULT=unknown
fi

{ echo "result=$RESULT"; printf '%s\n' "${LINES[@]}"; } > "$OUTDIR/$BN.txt"
printf '%s\n' "${LINES[@]}"
case $RESULT in pass) exit 0 ;; fail) exit 1 ;; *) exit 2 ;; esac
