#!/usr/bin/env bash
#
# DOMOVINA.ai — Build & Deploy
#
# Koristi:
#   ./scripts/deploy.sh          # release build + deploy + purge
#   ./scripts/deploy.sh --debug  # profile build (source maps, no minify) + deploy + purge
#
set -euo pipefail

cd "$(dirname "$0")/.."

# Loadaj .env za Cloudflare tokene
if [[ -f .env ]]; then
  source .env
else
  echo "GRESKA: .env ne postoji — kopiraj .env.example u .env"
  exit 1
fi

# Provjeri da tokeni postoje
if [[ -z "${CLOUDFLARE_ZONE_ID:-}" || -z "${CLOUDFLARE_PURGE_TOKEN:-}" ]]; then
  echo "GRESKA: CLOUDFLARE_ZONE_ID i CLOUDFLARE_PURGE_TOKEN moraju biti u .env"
  exit 1
fi

# Supabase env varijable — embedaju se u Flutter web build preko --dart-define.
# Anon key je javan (designed for client embed) ali ga držimo izvan repo-a
# radi rotation discipline. Ako env nije postavljen, build prolazi ali
# Supabase init je no-op (offline mode).
if [[ -z "${SUPABASE_URL:-}" || -z "${SUPABASE_ANON_KEY:-}" ]]; then
  echo "UPOZORENJE: SUPABASE_URL/ANON_KEY nije u .env — build ide bez Supabase integracije"
  SUPABASE_DEFINES=""
else
  SUPABASE_DEFINES="--dart-define=SUPABASE_URL=${SUPABASE_URL} --dart-define=SUPABASE_ANON_KEY=${SUPABASE_ANON_KEY}"
fi

# Certilia proxy URL (opcionalno — CertiliaService ima default na
# certilia.domovina.ai pa prod radi i bez ovoga; override za dev/staging).
if [[ -n "${CERTILIA_SERVER_URL:-}" ]]; then
  SUPABASE_DEFINES="${SUPABASE_DEFINES} --dart-define=CERTILIA_SERVER_URL=${CERTILIA_SERVER_URL}"
fi

# Meilisearch keyword tražilica (vidi lib/services/meili_client.dart).
# MEILI_SEARCH_KEY je READ-ONLY search-only ključ (nikad master) — siguran za
# bundle. Deterministički je pa MeiliClient ima radni default; override ovdje
# samo ako prod Meili koristi drugi master key. MEILI_URL pokazuje na prod
# (https://search.domovina.ai); bez override-a klijent gađa lokalni dev.
if [[ -n "${MEILI_URL:-}" ]]; then
  SUPABASE_DEFINES="${SUPABASE_DEFINES} --dart-define=MEILI_URL=${MEILI_URL}"
fi
if [[ -n "${MEILI_SEARCH_KEY:-}" ]]; then
  SUPABASE_DEFINES="${SUPABASE_DEFINES} --dart-define=MEILI_SEARCH_KEY=${MEILI_SEARCH_KEY}"
fi
# Ključ samo za index `segments` („Pronađi u epizodi"); default je u
# lib/services/transcript_search.dart.
if [[ -n "${MEILI_SEGMENTS_SEARCH_KEY:-}" ]]; then
  SUPABASE_DEFINES="${SUPABASE_DEFINES} --dart-define=MEILI_SEGMENTS_SEARCH_KEY=${MEILI_SEGMENTS_SEARCH_KEY}"
fi
# RevenueCat Web Billing hosted-checkout base URL (web nema SDK). Supabase UUID
# se appenda kao customer id: <base>/<uuid>. Prazno dok Web Billing/Stripe nije
# spojen u RC dashboardu — paywall tad pokaže "uskoro" umjesto checkout-a.
if [[ -n "${RC_WEB_CHECKOUT_URL:-}" ]]; then
  SUPABASE_DEFINES="${SUPABASE_DEFINES} --dart-define=RC_WEB_CHECKOUT_URL=${RC_WEB_CHECKOUT_URL}"
fi

# Auto-bump verzije na svakom deployu — pomaže korisniku znati treba li
# hard-refresh: ako footer prikazuje istu verziju kao prije, browser servira
# stari cache i potrebno je Cmd+Shift+R; ako je verzija nova, deploy je
# stigao do klijenta.
#
# Bumpa PATCH komponentu (treća) + build broj (+N). Skip s --no-bump flagom
# kad želiš redeployati istu verziju (npr. samo cache purge).
OLD_VERSION=$(grep '^version:' pubspec.yaml | sed 's/version: //')
OLD_APP=$(echo "$OLD_VERSION" | cut -d'+' -f1)
OLD_BUILD=$(echo "$OLD_VERSION" | cut -d'+' -f2)

if [[ "${1:-}" == "--no-bump" ]]; then
  VERSION="$OLD_VERSION"
  APP_VERSION="$OLD_APP"
  echo "=== DOMOVINA.ai v${VERSION} (no bump) ==="
  shift
else
  # Inkrementiraj patch (treća komponenta) i build broj
  MAJOR=$(echo "$OLD_APP" | cut -d'.' -f1)
  MINOR=$(echo "$OLD_APP" | cut -d'.' -f2)
  PATCH=$(echo "$OLD_APP" | cut -d'.' -f3)
  NEW_PATCH=$((PATCH + 1))
  NEW_BUILD=$((OLD_BUILD + 1))
  APP_VERSION="${MAJOR}.${MINOR}.${NEW_PATCH}"
  VERSION="${APP_VERSION}+${NEW_BUILD}"

  echo "=== DOMOVINA.ai v${OLD_VERSION} → v${VERSION} ==="

  # Sync u pubspec.yaml (.bak fallback za macOS sed kompatibilnost)
  sed -i.bak "s/^version: ${OLD_VERSION}$/version: ${VERSION}/" pubspec.yaml
  rm -f pubspec.yaml.bak

  # Sync u packages/podcast_core/lib/src/log.dart — appVersion konstanta koja se prikazuje u footeru.
  # Regex matcha BILO KOJU postojeću vrijednost ('[^']*') umjesto OLD_APP iz
  # pubspec-a: ako appVersion driftne od pubspec verzije, exact-match sed bi
  # tiho no-opao i footer bi zauvijek pokazivao staru verziju (bug do v2.0.60).
  sed -i.bak "s/const String appVersion = '[^']*';/const String appVersion = '${APP_VERSION}';/" packages/podcast_core/lib/src/log.dart
  rm -f packages/podcast_core/lib/src/log.dart.bak
fi

# 1. Flutter pub get
echo ""
echo "--- flutter pub get ---"
flutter pub get

# 2. Analyze
echo ""
echo "--- flutter analyze ---"
flutter analyze || true

# 3. Build
# Flagovi:
#   --wasm: build dart2wasm + skwasm (GPU rendering preko WebGL/WebGPU,
#     Safari → Metal) s automatskim canvaskit/dart2js fallback-om za
#     browsere bez WasmGC. Worker već emita COOP/COEP za SharedArrayBuffer.
#   (SW se generira default — strategija "offline-first" je preuvjet za
#   iOS PWA "Add to Home Screen" + standalone display + cross-app
#   background audio. User feedback 2026-05-17: Media Session API alone
#   nije dovoljan za audio while in WhatsApp.)
echo ""
if [[ "${1:-}" == "--debug" ]]; then
  echo "--- flutter build web (profile + source-maps + O0, wasm) ---"
  # shellcheck disable=SC2086
  flutter build web --profile --source-maps -O0 --wasm $SUPABASE_DEFINES
else
  echo "--- flutter build web (release, wasm) ---"
  # shellcheck disable=SC2086
  flutter build web --release --wasm $SUPABASE_DEFINES
fi
# Traka napretka u boot splashu treba veličine wasma iz OVOG builda.
./scripts/stamp-boot-sizes.sh build/web

# 3b. Kopiraj fajlove koje Flutter build ne kopira automatski (robots.txt, ...)
#     Flutter web build kopira samo poznate fajlove iz web/ (index.html, manifest.json,
#     favicon.png, icons/, _headers, _worker.js, social-test.html). Ostalo dodajemo ovdje.
echo ""
echo "--- Copy extra web assets ---"
for f in robots.txt; do
  if [[ -f "web/$f" ]]; then
    cp "web/$f" "build/web/$f"
    echo "  copied $f"
  fi
done

# 4. Deploy na Cloudflare Pages
echo ""
echo "--- wrangler pages deploy ---"
wrangler pages deploy build/web --project-name=domovina-ai --commit-dirty=true

# 5. Purge Cloudflare cache
echo ""
echo "--- Purge CDN cache ---"
PURGE_RESULT=$(curl -s -X POST \
  "https://api.cloudflare.com/client/v4/zones/${CLOUDFLARE_ZONE_ID}/purge_cache" \
  -H "Authorization: Bearer ${CLOUDFLARE_PURGE_TOKEN}" \
  -H "Content-Type: application/json" \
  --data '{"purge_everything":true}')

if echo "$PURGE_RESULT" | grep -q '"success":true'; then
  echo "Cache purged OK"
else
  echo "UPOZORENJE: Cache purge failed: $PURGE_RESULT"
fi

# 6. Verificiraj deployment
echo ""
echo "--- Verifikacija ---"
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" https://domovina.ai/)
echo "https://domovina.ai/ -> HTTP $HTTP_CODE"

# Regresijski tripwire (2026-07-22): AASA MORA excludati /auth/* — inače iOS
# s instaliranom appom otima OAuth povratak (https://domovina.ai/auth/callback)
# i otvara native app umjesto da web prijava završi u browseru.
AASA=$(curl -s https://domovina.ai/.well-known/apple-app-site-association)
if echo "$AASA" | grep -q '"/auth/\*"' && echo "$AASA" | grep -q '"exclude": true'; then
  echo "AASA /auth/* exclusion OK"
else
  echo "UPOZORENJE: AASA više ne excluda /auth/* — web login na iOS-u s"
  echo "instaliranom appom će se opet prekidati! Vidi AASA_JSON u web/_worker.js."
fi

echo ""
echo "=== Deployed v${APP_VERSION} ==="
echo "Hard refresh: Cmd+Shift+R / Ctrl+Shift+R"
