#!/usr/bin/env bash
# Release smoke: instalira ISTI binarni paket koji ide u store i otvori ga
# nizom deep linkova, u portraitu i landscapeu. Hvata ono što debug
# integration test ne vidi: R8/minifikaciju, AOT, potpis, defineove koji
# fale u release skripti — i nativni crash.
#
#   ./scripts/release-smoke.sh <device-id> --aab build/app/outputs/bundle/release/app-release.aab
#   ./scripts/release-smoke.sh <udid>      --ipa build/ios/ipa-dev/DOMOVINA.ai.ipa
#
# iOS treba DEVELOPMENT export istog archivea (App Store IPA se na uređaj ne
# može instalirati) — build-mobile-release.sh ga radi uz EXPORT_DEV_IPA=1.
#
# Provjera po koraku: proces živ, aplikacija u prvom planu (samo Android),
# nema novog crash zapisa, nema „FLUTTER ERROR” u logu aplikacije
# (log() iz lib/src/log.dart ispisuje i u releaseu).
#
# Exit: 0 prošlo, 1 aplikacija pada, 2 ne mogu provjeriti.
# Screenshotovi: .nightly/smoke/release/<device>/
# Plan: docs/plans/2026-10-13-smoke-testovi-na-uredajima.md
set -uo pipefail
cd "$(dirname "$0")/.."

DEVICE="${1:?device id}"; shift
AAB=""; IPA=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --aab) AAB="$2"; shift 2 ;;
    --ipa) IPA="$2"; shift 2 ;;
    *) echo "nepoznat argument: $1"; exit 2 ;;
  esac
done

PKG=ai.domovina
EPISODE=H-p2Hl6x7I0
ROUTES=(
  "start|"
  "epizoda|/v/$EPISODE"
  "epizoda-seek|/v/$EPISODE/t/120"
  "epizoda-en|/v/$EPISODE/en"
  "kanal|/c/40-dana-za-zivot"
  "osoba|/p/marko-matijasevic"
)
WAIT=10

OUT=".nightly/smoke/release/$DEVICE"
rm -rf "$OUT"; mkdir -p "$OUT"
FAILS=()

# Ista brava kao smoke-device.sh — farmu dijele projekti.
LOCKDIR="$HOME/.device-farm/locks/$DEVICE"
mkdir -p "$HOME/.device-farm/locks"
for _ in $(seq 1 240); do
  if mkdir "$LOCKDIR" 2>/dev/null; then
    echo "domovina.ai release-smoke.sh pid $$ $(date '+%F %T')" > "$LOCKDIR/owner"; break
  fi
  owner_pid=$(awk '{for(i=1;i<=NF;i++) if($i=="pid"){print $(i+1); exit}}' "$LOCKDIR/owner" 2>/dev/null)
  if [[ -n "$owner_pid" ]] && ! kill -0 "$owner_pid" 2>/dev/null; then rm -rf "$LOCKDIR"; continue; fi
  sleep 5
done
[[ "$(cat "$LOCKDIR/owner" 2>/dev/null)" == *"pid $$ "* ]] \
  || { echo "GRESKA: $DEVICE je zauzet: $(cat "$LOCKDIR/owner" 2>/dev/null)"; exit 2; }
trap 'rm -rf "$LOCKDIR"' EXIT

# ════════════════════════════════════════════════════════════════════════════
if [[ -n "$AAB" ]]; then
  A=(adb -s "$DEVICE")
  "${A[@]}" get-state >/dev/null 2>&1 || { echo "GRESKA: adb ne vidi $DEVICE"; exit 2; }
  [[ -f "$AAB" ]] || { echo "GRESKA: nema $AAB"; exit 2; }
  "${A[@]}" shell ping -c1 -W5 cdn.domovina.ai >/dev/null 2>&1 \
    || { echo "GRESKA: $DEVICE nema mrežu"; exit 2; }
  "${A[@]}" shell svc power stayon usb
  "${A[@]}" shell input keyevent KEYCODE_WAKEUP
  "${A[@]}" shell wm dismiss-keyguard; sleep 2
  if "${A[@]}" shell dumpsys window | grep -q 'isKeyguardShowing=true'; then
    echo "GRESKA: $DEVICE je zaključan"; exit 2
  fi

  echo "==> APK za $DEVICE iz $(basename "$AAB")"
  APKS=$(mktemp -d)/app.apks
  # Bez --ks bundletool potpiše debug ključem (~/.android/debug.keystore).
  # Kod je isti kao u Play buildu; potpis se razlikuje, pa se prije
  # instalacije miče postojeća verzija.
  bundletool build-apks --bundle="$AAB" --output="$APKS" \
    --connected-device --device-id="$DEVICE" >/dev/null \
    || { echo "GRESKA: bundletool build-apks"; exit 2; }
  "${A[@]}" uninstall "$PKG" >/dev/null 2>&1
  bundletool install-apks --apks="$APKS" --device-id="$DEVICE" \
    || { echo "GRESKA: bundletool install-apks"; exit 2; }
  VER=$("${A[@]}" shell dumpsys package "$PKG" | grep -m1 -oE 'versionName=[^ ]+')
  echo "    instalirano: $VER"

  "${A[@]}" shell settings put system accelerometer_rotation 0
  "${A[@]}" logcat -c; "${A[@]}" logcat -b crash -c; "${A[@]}" logcat -b events -c

  for orient in portrait landscape; do
    "${A[@]}" shell settings put system user_rotation "$([[ $orient == portrait ]] && echo 0 || echo 1)"
    for r in "${ROUTES[@]}"; do
      name="$orient-${r%%|*}"; path="${r#*|}"
      if [[ -z "$path" ]]; then
        "${A[@]}" shell am start -W -n "$PKG/.MainActivity" >/dev/null
      else
        # Eksplicitni paket: intent ide u aplikaciju i bez verifikacije
        # App Linka (inače bi ga otvorio browser i korak lažno prošao).
        "${A[@]}" shell am start -W -a android.intent.action.VIEW \
          -d "https://domovina.ai$path" "$PKG" >/dev/null
      fi
      sleep "$WAIT"
      "${A[@]}" exec-out screencap -p > "$OUT/$name.png" 2>/dev/null
      pid=$("${A[@]}" shell pidof "$PKG" | tr -d '\r')
      fg=$("${A[@]}" shell dumpsys activity activities | grep -m1 -E 'topResumedActivity|mResumedActivity' | grep -o "$PKG" | head -1)
      if [[ -z "$pid" ]]; then FAILS+=("$name: proces ne postoji")
      elif [[ -z "$fg" ]]; then FAILS+=("$name: aplikacija nije u prvom planu")
      fi
      echo "    $name ${pid:+pid $pid}${fg:+ (prvi plan)}"
    done
  done
  "${A[@]}" shell settings put system accelerometer_rotation 1

  CRASH=$("${A[@]}" logcat -b crash -d | grep -A12 -E "Process: $PKG|>>> $PKG <<<" | head -30)
  ANR=$("${A[@]}" logcat -b events -d | grep -E "am_anr.*$PKG" | head -3)
  ERRS=$("${A[@]}" logcat -d -s flutter:I | grep -E 'FLUTTER ERROR' | sort | uniq -c | head -10)
  "${A[@]}" logcat -d -s flutter:I > "$OUT/flutter.log"
  grep -q 'Video: opening' "$OUT/flutter.log" \
    || FAILS+=("epizoda: player se nije otvorio (nema „Video: opening” u logu)")

# ════════════════════════════════════════════════════════════════════════════
elif [[ -n "$IPA" ]]; then
  [[ -f "$IPA" ]] || { echo "GRESKA: nema $IPA"; exit 2; }
  LOCK=$(xcrun devicectl device info lockState --device "$DEVICE" 2>&1) \
    || { echo "GRESKA: devicectl ne vidi $DEVICE"; exit 2; }
  grep -q 'passcodeRequired: true' <<<"$LOCK" && { echo "GRESKA: $DEVICE je zaključan"; exit 2; }

  TMP=$(mktemp -d)
  unzip -q "$IPA" -d "$TMP"
  APP=$(ls -d "$TMP"/Payload/*.app | head -1)
  echo "==> instaliram $(basename "$APP") na $DEVICE"
  xcrun devicectl device uninstall app --device "$DEVICE" "$PKG" >/dev/null 2>&1
  xcrun devicectl device install app --device "$DEVICE" "$APP" >/dev/null \
    || { echo "GRESKA: devicectl install (development potpis?)"; exit 2; }

  CRASH_BEFORE=$(gtimeout 60 pymobiledevice3 crash ls --udid "$DEVICE" 2>/dev/null | grep -E '^/Runner-' || true)
  # Release print() na iOS-u ide u sistemski log, ne na stdout — zato
  # idevicesyslog filtriran na proces Runner, u pozadini cijelo vrijeme.
  CONSOLE="$OUT/console.log"
  idevicesyslog -u "$DEVICE" -p Runner > "$CONSOLE" 2>&1 &
  SYSLOG_PID=$!
  trap 'kill $SYSLOG_PID 2>/dev/null; rm -rf "$LOCKDIR"' EXIT

  # Svaka ruta je hladni start s URL-om (--terminate-existing): devicectl
  # ne zna predati URL živoj aplikaciji. Usput pokriva deep link na hladni
  # start. iOS orijentaciju ne može postaviti izvana — release smoke ide u
  # onoj u kojoj uređaj stoji; obje pokriva integration smoke.
  for r in "${ROUTES[@]}"; do
    name="${r%%|*}"; path="${r#*|}"
    # Prazan host (tri kose crte): `ai.domovina://v/<id>` bi „v” pročitao
    # kao host i ruter bi dobio samo `/<id>` (izmjereno 13.10.2026.).
    url="ai.domovina://${path:-/}"
    xcrun devicectl device process launch --device "$DEVICE" \
      --terminate-existing --payload-url "$url" "$PKG" >/dev/null 2>&1 \
      || FAILS+=("$name: devicectl launch nije uspio")
    sleep "$WAIT"
    gtimeout 60 pymobiledevice3 developer dvt screenshot --userspace \
      --udid "$DEVICE" "$OUT/$name.png" >/dev/null 2>&1
    running=$(xcrun devicectl device info processes --device "$DEVICE" 2>/dev/null | grep -c 'Runner.app/Runner')
    [[ "$running" -ge 1 ]] || FAILS+=("$name: proces ne postoji")
    echo "    $name (${running} proces)"
  done
  kill $SYSLOG_PID 2>/dev/null
  # Epizoda se mora stvarno otvoriti: iOS-u se ne vidi prvi plan izvana, a
  # tuđi sistemski dijalog (13.10.: dozvola za kameru druge aplikacije) zna
  # prekriti sve. Ekran epizode logira „Video: opening” kad pokrene player.
  grep -q 'Video: opening' "$CONSOLE" \
    || FAILS+=("epizoda: player se nije otvorio (nema „Video: opening” u logu)")

  CRASH_AFTER=$(gtimeout 60 pymobiledevice3 crash ls --udid "$DEVICE" 2>/dev/null | grep -E '^/Runner-' || true)
  CRASH=$(comm -13 <(sort <<<"$CRASH_BEFORE") <(sort <<<"$CRASH_AFTER") | grep . || true)
  ANR=""
  ERRS=$(grep -E 'FLUTTER ERROR' "$CONSOLE" | sort | uniq -c | head -10)
else
  echo "treba --aab ili --ipa"; exit 2
fi

# ── ishod ───────────────────────────────────────────────────────────────────
[[ -n "${CRASH// /}" ]] && FAILS+=("nativni crash: $(head -3 <<<"$CRASH" | tr '\n' ' ')")
[[ -n "${ANR// /}" ]] && FAILS+=("ANR: $ANR")
[[ -n "${ERRS// /}" ]] && FAILS+=("Dart greške u release logu: $(tr '\n' ' ' <<<"$ERRS")")

if [[ ${#FAILS[@]} -eq 0 ]]; then
  echo "RELEASE SMOKE: prošlo"; exit 0
fi
echo "RELEASE SMOKE: PAO"
printf '  - %s\n' "${FAILS[@]}"
exit 1
