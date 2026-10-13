#!/usr/bin/env bash
# Smoke vrata za promociju: je li build <N> prošao smoke na uređajima farme?
#
#   ./scripts/smoke-gate.sh 206     # exit 0 = prošao, 1 = pao, 2 = nema zapisa
#
# Zapis piše nightly-build.sh nakon uploada: .nightly/smoke/builds/<N>.txt
# (prvi redak `result=pass|fail|unknown`, ostatak je sažetak po uređaju).
# Zovu ga asc-submit.rb i play-promote.sh prije promocije u produkciju.
set -uo pipefail
cd "$(dirname "$0")/.."
BN="${1:?build broj}"
F=".nightly/smoke/builds/$BN.txt"
if [[ ! -f "$F" ]]; then
  echo "smoke: nema zapisa za build $BN ($F) — nightly ga nije testirao"
  exit 2
fi
result=$(sed -n '1s/^result=//p' "$F")
sed -n '2,$p' "$F"
case "$result" in
  pass) echo "smoke: build $BN prošao"; exit 0 ;;
  fail) echo "smoke: build $BN PAO"; exit 1 ;;
  *)    echo "smoke: build $BN nije provjeren ($result)"; exit 2 ;;
esac
