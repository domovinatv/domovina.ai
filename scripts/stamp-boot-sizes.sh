#!/usr/bin/env bash
# Upiše veličine wasm datoteka iz builda u build/web/index.html, umjesto
# komentara /*BOOT_SIZES*/. Boot splash po njima puni traku napretka 0–100 %
# dok broji pristigle bajtove (docs/2026-10-09-boot-splash.md §7).
#
# Veličine su NEKOMPRIMIRANE: splash broji bajtove tijela odgovora, a fetch
# ih predaje već dekomprimirane. skwasm*.wasm stiže s gstatic.com, ali je ista
# datoteka (ista revizija enginea) kao lokalna kopija u canvaskit/.
#
#   ./scripts/stamp-boot-sizes.sh [build/web]
set -euo pipefail
dir="${1:-build/web}"
html="$dir/index.html"
grep -q '/\*BOOT_SIZES\*/' "$html" || { echo "stamp-boot-sizes: nema /*BOOT_SIZES*/ u $html" >&2; exit 1; }
size() { [[ -f "$dir/$1" ]] && stat -f%z "$dir/$1" 2>/dev/null || stat -c%s "$dir/$1" 2>/dev/null || echo 0; }
json="\"main.dart.wasm\":$(size main.dart.wasm),\"skwasm.wasm\":$(size canvaskit/skwasm.wasm),\"skwasm_heavy.wasm\":$(size canvaskit/skwasm_heavy.wasm)"
sed -i.bak "s|/\*BOOT_SIZES\*/|$json|" "$html" && rm -f "$html.bak"
echo "stamp-boot-sizes: {$json}"
