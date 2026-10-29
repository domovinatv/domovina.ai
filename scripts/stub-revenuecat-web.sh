#!/usr/bin/env bash
# Zamijeni RevenueCat web SDK u buildu praznim JS-om.
#
# purchases_flutter pri registraciji web plugina (prije main()) BEZUVJETNO
# ubaci <script> s purchases_js_hybrid_mappings.js (~186 KB preko žice). Naš
# kod ga na webu ne koristi: revenue_cat_service.dart na webu uvozi no-op stub,
# a web prodaje preko RC Web Billing hosted checkouta. Na Slow 4G ta skripta
# ide u istom prozoru kao fontovi i produlji „Priprema fontova…” za ~1 s
# (docs/2026-10-09-boot-splash.md §8). Prazna datoteka se uredno učita, pa
# plugin ne javlja grešku; handleMethodCall nitko ne zove.
#
#   ./scripts/stub-revenuecat-web.sh [build/web]
set -euo pipefail
dir="${1:-build/web}"
f="$dir/assets/packages/purchases_flutter/assets/web/purchases_js_hybrid_mappings.js"
svc="packages/podcast_core/lib/services/revenue_cat_service.dart"
# Tripwire: stub smije samo dok web ne koristi pravi SDK.
grep -q "if (dart.library.io) 'revenue_cat/revenue_cat_service_native.dart'" "$svc" || {
  echo "stub-revenuecat-web: $svc više ne vodi web na stub — NE stubam" >&2; exit 1; }
[[ -f "$f" ]] || { echo "stub-revenuecat-web: nema $f (preskačem)"; exit 0; }
before=$(wc -c < "$f" | tr -d ' ')
echo '/* RevenueCat web SDK se ne koristi: scripts/stub-revenuecat-web.sh */' > "$f"
echo "stub-revenuecat-web: $before B → $(wc -c < "$f" | tr -d ' ') B"
