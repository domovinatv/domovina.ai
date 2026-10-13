#!/usr/bin/env bash
# Smoke test na SVIM spojenim mobilnim uređajima (Android preko adb, iOS
# preko flutter devices), jedan po jedan — istodobni Flutter buildovi u
# istom projektu dijele build/ i ruše jedni druge.
#
#   ./scripts/smoke-farm.sh
#
# Exit: 0 = svi prošli, 1 = bar jedan pao, 2 = nijedan pad, ali bar jedan
# uređaj nije provjeren. Ishod po uređaju: .nightly/smoke/last.txt
# Plan: docs/plans/2026-10-13-smoke-testovi-na-uredajima.md
set -uo pipefail
cd "$(dirname "$0")/.."

OUT=.nightly/smoke
mkdir -p "$OUT"

# "ime|id" po retku; macOS i web nisu mobilni uređaji.
mapfile -t DEVICES < <(flutter devices --machine --device-timeout 30 2>/dev/null \
  | ruby -rjson -e 'JSON.parse(STDIN.read).each { |d|
      next unless %w[android ios].include?(d["targetPlatform"].to_s.split("-").first) || d["targetPlatform"] == "ios"
      puts "#{d["name"]}|#{d["id"]}" }')

[[ ${#DEVICES[@]} -gt 0 ]] || { echo "nijedan mobilni uređaj"; exit 2; }

SUMMARY=()
WORST=0
for row in "${DEVICES[@]}"; do
  name=${row%%|*}; id=${row##*|}
  start=$(date +%s)
  ./scripts/smoke-device.sh "$id" > "$OUT/$id.log" 2>&1
  rc=$?
  secs=$(( $(date +%s) - start ))
  case $rc in
    0) res="prošlo" ;;
    1) res="PAO"; WORST=1 ;;
    *) res="nije provjereno"; [[ $WORST -eq 0 ]] && WORST=2 ;;
  esac
  line="$name — $res (${secs} s)"
  [[ $rc -eq 1 ]] && line+=$'\n'"    $(grep -m1 -E 'SMOKE step' "$OUT/$id.log" >/dev/null && grep -E 'SMOKE step' "$OUT/$id.log" | tail -1 | sed 's/SMOKE step: /zadnji korak: /')"
  [[ $rc -ne 0 && $rc -ne 1 ]] && line+=$'\n'"    $(grep -m1 -E 'GRESKA|SMOKE:' "$OUT/$id.log")"
  SUMMARY+=("$line")
  echo "$line"
done

printf '%s\n' "${SUMMARY[@]}" > "$OUT/last.txt"
exit $WORST
