#!/usr/bin/env bash
# Mobilni release build (Android AAB + iOS IPA) za store upload.
#
#   ./scripts/build-mobile-release.sh            # oba (AAB + IPA)
#   ./scripts/build-mobile-release.sh android    # samo AAB
#   ./scripts/build-mobile-release.sh ios        # samo IPA
#
# Embeda Supabase/Meili config preko --dart-define iz .env (isti princip kao
# scripts/deploy.sh za web). Android release zahtijeva android/key.properties
# (vidi android/app/build.gradle.kts) — bez njega build padne nazad na debug
# potpis koji Play odbija.
set -euo pipefail
cd "$(dirname "$0")/.."

if [[ -f .env ]]; then
  set -a; source .env; set +a
else
  echo "GRESKA: .env ne postoji — kopiraj .env.example u .env"; exit 1
fi

DEFINES=""
if [[ -n "${SUPABASE_URL:-}" && -n "${SUPABASE_ANON_KEY:-}" ]]; then
  DEFINES="--dart-define=SUPABASE_URL=${SUPABASE_URL} --dart-define=SUPABASE_ANON_KEY=${SUPABASE_ANON_KEY}"
else
  echo "UPOZORENJE: SUPABASE_URL/ANON_KEY nije u .env — build ide bez Supabase integracije"
fi
[[ -n "${CERTILIA_SERVER_URL:-}" ]] && DEFINES="${DEFINES} --dart-define=CERTILIA_SERVER_URL=${CERTILIA_SERVER_URL}"
[[ -n "${MEILI_URL:-}" ]]          && DEFINES="${DEFINES} --dart-define=MEILI_URL=${MEILI_URL}"
[[ -n "${MEILI_SEARCH_KEY:-}" ]]   && DEFINES="${DEFINES} --dart-define=MEILI_SEARCH_KEY=${MEILI_SEARCH_KEY}"
[[ -n "${MEILI_SEGMENTS_SEARCH_KEY:-}" ]] && DEFINES="${DEFINES} --dart-define=MEILI_SEGMENTS_SEARCH_KEY=${MEILI_SEGMENTS_SEARCH_KEY}"
# RevenueCat publishable SDK keys — public by design (appl_…/goog_… ili test_…
# za TestStore QA). Bez njih mobile build radi, ali paywall purchase je no-op.
[[ -n "${RC_PUBLIC_SDK_KEY_IOS:-}" ]]     && DEFINES="${DEFINES} --dart-define=RC_PUBLIC_SDK_KEY_IOS=${RC_PUBLIC_SDK_KEY_IOS}"
[[ -n "${RC_PUBLIC_SDK_KEY_ANDROID:-}" ]] && DEFINES="${DEFINES} --dart-define=RC_PUBLIC_SDK_KEY_ANDROID=${RC_PUBLIC_SDK_KEY_ANDROID}"

TARGET="${1:-all}"

# Nightly build (scripts/nightly-build.sh) šalje BUILD_NUMBER da izbjegne koliziju
# s već uploadanim buildovima — Info.plist koristi $(FLUTTER_BUILD_NUMBER), a Play
# odbija ponovljeni versionCode. Bez ovih varijabli sve radi kao prije, iz pubspeca.
# BUILD_DERIVED_DATA drži Xcode artefakte na PREDVIDIVOJ putanji. Bez toga Xcode
# svakoj putanji projekta radi zaseban Runner-<hash> u zajedničkom DerivedData —
# nightly worktree bi tako svaku noć ostavljao smeće koje nitko ne čisti.
DD_ARGS=""
[[ -n "${BUILD_DERIVED_DATA:-}" ]] && DD_ARGS="-derivedDataPath ${BUILD_DERIVED_DATA}"

VERSION_ARGS=""
[[ -n "${BUILD_NUMBER:-}" ]] && VERSION_ARGS="${VERSION_ARGS} --build-number=${BUILD_NUMBER}"
[[ -n "${BUILD_NAME:-}" ]]   && VERSION_ARGS="${VERSION_ARGS} --build-name=${BUILD_NAME}"
[[ -n "$VERSION_ARGS" ]] && echo "==> verzija override:${VERSION_ARGS}"

flutter pub get

# iOS ide PRIJE Androida kad se builda "all": iOS flow radi `flutter clean`
# (simulator ostaci → x86_64 u objective_c.framework → altool 409), a clean
# bi obrisao već izbuildani AAB.
if [[ "$TARGET" == "all" || "$TARGET" == "ios" ]]; then
  # `flutter build ipa` pada na export koraku (ITalk cert nije u keychainu,
  # Apple ID nije u Xcodeu) — vozimo xcodebuild direktno s App Store Connect
  # API key autentikacijom koja programatski kreira cert + profil.
  # Vidi docs/mobile-release-pipeline.md.
  ASC_KEY_ID="${ASC_KEY_ID:-25KYCN22QD}"
  ASC_ISSUER_ID="${ASC_ISSUER_ID:-69a6de85-f7cc-47e3-e053-5b8c7c11a4d1}"
  ASC_KEY_PATH="${ASC_KEY_PATH:-$HOME/.appstoreconnect/private_keys/AuthKey_${ASC_KEY_ID}.p8}"
  if [[ ! -f "$ASC_KEY_PATH" ]]; then
    echo "GRESKA: nema ASC API key na $ASC_KEY_PATH"; exit 1
  fi
  # `flutter clean` interno zove `xcodebuild clean` nad workspaceom. Pod launchd-om
  # je to 2026-08-14 visjelo 60 min bez ijednog retka ispisa (PID je bio živ, watchdog
  # ga je ubio). Nama treba samo da nema ostataka prethodnog/simulatorskog builda, a
  # to su iste putanje koje `flutter clean` briše — bez zvanja Xcodea.
  if [[ "${FAST_CLEAN:-0}" == "1" ]]; then
    echo "==> iOS: brzo čišćenje (bez xcodebuild clean)…"
    rm -rf build .dart_tool ios/Flutter/ephemeral
  else
    echo "==> iOS: flutter clean…"
    flutter clean
  fi
  echo "==> iOS: config-only…"
  flutter pub get
  flutter build ios --config-only --release $DEFINES $VERSION_ARGS

  echo "==> iOS: xcodebuild archive (ASC API key signing)…"
  xcodebuild archive \
    -workspace ios/Runner.xcworkspace \
    -scheme Runner \
    -configuration Release \
    -destination 'generic/platform=iOS' \
    -archivePath build/ios/archive/Runner.xcarchive \
    $DD_ARGS \
    -allowProvisioningUpdates \
    -authenticationKeyPath "$ASC_KEY_PATH" \
    -authenticationKeyID "$ASC_KEY_ID" \
    -authenticationKeyIssuerID "$ASC_ISSUER_ID"

  echo "==> iOS: exportArchive → IPA…"
  xcodebuild -exportArchive \
    -archivePath build/ios/archive/Runner.xcarchive \
    -exportPath build/ios/ipa \
    -exportOptionsPlist ios/ExportOptions.plist \
    -allowProvisioningUpdates \
    -authenticationKeyPath "$ASC_KEY_PATH" \
    -authenticationKeyID "$ASC_KEY_ID" \
    -authenticationKeyIssuerID "$ASC_ISSUER_ID"
  echo "IPA: build/ios/ipa/*.ipa  (upload: ./scripts/testflight-upload.sh)"

  # Release smoke na uređajima farme treba isti archive s development
  # potpisom (App Store IPA se ne da instalirati). Nightly ga traži prije
  # nego obriše archive; ručni build ga radi samo uz EXPORT_DEV_IPA=1.
  if [[ "${EXPORT_DEV_IPA:-0}" == "1" ]]; then
    echo "==> iOS: exportArchive → development IPA (release smoke)…"
    xcodebuild -exportArchive \
      -archivePath build/ios/archive/Runner.xcarchive \
      -exportPath build/ios/ipa-dev \
      -exportOptionsPlist ios/ExportOptions-dev.plist \
      -allowProvisioningUpdates \
      -authenticationKeyPath "$ASC_KEY_PATH" \
      -authenticationKeyID "$ASC_KEY_ID" \
      -authenticationKeyIssuerID "$ASC_ISSUER_ID" \
      || echo "UPOZORENJE: development export nije uspio — release smoke na iOS-u preskočen"
  fi
fi

if [[ "$TARGET" == "all" || "$TARGET" == "android" ]]; then
  if [[ ! -f android/key.properties ]]; then
    echo "GRESKA: android/key.properties ne postoji — release bi bio debug-potpisan (Play ga odbija)."; exit 1
  fi
  echo "==> Android App Bundle (AAB)…"
  flutter build appbundle --release $DEFINES $VERSION_ARGS
  echo "AAB: build/app/outputs/bundle/release/app-release.aab"
fi

echo "Gotovo."
