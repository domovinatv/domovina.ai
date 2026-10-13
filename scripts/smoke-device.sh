#!/usr/bin/env bash
# Smoke test (integration_test/smoke_test.dart) na spojenom uređaju.
#
#   ./scripts/smoke-device.sh               # prvi spojeni Android/iOS uređaj
#   ./scripts/smoke-device.sh <device-id>   # npr. ZY32M4Q2GJ
#
# Defineovi dolaze iz .env, isti kao u build-mobile-release.sh, da test vidi
# isti backend kao store build. Plan: docs/plans/2026-10-13-smoke-testovi-na-uredajima.md
#
# PAŽNJA: debug build ima drugi potpis od store verzije, pa flutter s uređaja
# deinstalira postojeću aplikaciju (i njezine podatke).
set -euo pipefail
cd "$(dirname "$0")/.."

[[ -f .env ]] || { echo "GRESKA: nema .env"; exit 2; }
set -a; source .env; set +a

DEFINES=()
for k in SUPABASE_URL SUPABASE_ANON_KEY CERTILIA_SERVER_URL MEILI_URL \
         MEILI_SEARCH_KEY MEILI_SEGMENTS_SEARCH_KEY \
         RC_PUBLIC_SDK_KEY_IOS RC_PUBLIC_SDK_KEY_ANDROID; do
  [[ -n "${!k:-}" ]] && DEFINES+=("--dart-define=$k=${!k}")
done

DEVICE="${1:-}"
if [[ -z "$DEVICE" ]]; then
  DEVICE=$(adb devices | awk 'NR>1 && $2=="device" {print $1; exit}')
fi
[[ -n "$DEVICE" ]] || { echo "GRESKA: nijedan uređaj nije spojen"; exit 2; }

# Bez mreže na uređaju test padne na prvom dohvatu s CDN-a — to nije kvar
# aplikacije, pa je exit 2 („ne mogu provjeriti”), ne 1.
if adb -s "$DEVICE" get-state >/dev/null 2>&1; then
  adb -s "$DEVICE" shell ping -c1 -W5 cdn.domovina.ai >/dev/null 2>&1 \
    || { echo "GRESKA: $DEVICE ne dohvaća cdn.domovina.ai"; exit 2; }
  # Aplikacija pokrenuta iza lock screena je za Android POZADINSKA i nema
  # mrežu: getaddrinfo vraća errno 7 („No address associated with
  # hostname”), dok `adb shell ping` s istog uređaja radi. Izmjereno
  # 13.10.2026. na moto g86 (Android 16). Zato: probudi, makni keyguard,
  # i ako je zaključavanje zaštićeno (PIN/uzorak) — exit 2.
  adb -s "$DEVICE" shell svc power stayon usb || true
  adb -s "$DEVICE" shell input keyevent KEYCODE_WAKEUP || true
  adb -s "$DEVICE" shell wm dismiss-keyguard || true
  sleep 2
  if adb -s "$DEVICE" shell dumpsys window | grep -q 'isKeyguardShowing=true'; then
    echo "GRESKA: $DEVICE je zaključan (PIN/uzorak) — postavi zaključavanje zaslona na „Ništa”"
    exit 2
  fi
else
  # iOS: devicectl prima i UDID. Uređaj s postavljenim kodom koji je
  # zaključan ne pokreće aplikaciju — to je „ne mogu provjeriti”.
  LOCK=$(xcrun devicectl device info lockState --device "$DEVICE" 2>&1) \
    || { echo "GRESKA: devicectl ne vidi $DEVICE"; exit 2; }
  if grep -q 'passcodeRequired: true' <<<"$LOCK"; then
    echo "GRESKA: $DEVICE je zaključan — otključaj ga i postavi Auto-Lock na „Nikad”"
    exit 2
  fi
fi

# ── brava po uređaju ────────────────────────────────────────────────────────
# Farmu dijele projekti (13.10.2026. je multicam aplikacija usred smokea
# preuzela prednji plan na iPhoneu i test je visio 20 min). Tko koristi
# uređaj, drži ~/.device-farm/locks/<id> (mkdir je atomaran). Čekamo do
# 20 min, pa exit 2.
LOCKDIR="$HOME/.device-farm/locks/$DEVICE"
mkdir -p "$HOME/.device-farm/locks"
for _ in $(seq 1 240); do
  if mkdir "$LOCKDIR" 2>/dev/null; then
    echo "domovina.ai smoke-device.sh pid $$ $(date '+%F %T')" > "$LOCKDIR/owner"
    break
  fi
  # Brava mrtvog procesa (kill -9, restart) ne smije zauvijek blokirati.
  owner_pid=$(awk '{for(i=1;i<=NF;i++) if($i=="pid"){print $(i+1); exit}}' "$LOCKDIR/owner" 2>/dev/null)
  if [[ -n "$owner_pid" ]] && ! kill -0 "$owner_pid" 2>/dev/null; then
    rm -rf "$LOCKDIR"; continue
  fi
  sleep 5
done
[[ -d "$LOCKDIR" && "$(cat "$LOCKDIR/owner" 2>/dev/null)" == *"pid $$ "* ]] \
  || { echo "GRESKA: $DEVICE je zauzet: $(cat "$LOCKDIR/owner" 2>/dev/null)"; exit 2; }
trap 'rm -rf "$LOCKDIR"' EXIT

IS_ANDROID=0
adb -s "$DEVICE" get-state >/dev/null 2>&1 && IS_ANDROID=1

# ── nativni crash: stanje prije ─────────────────────────────────────────────
# Test vidi samo Dart greške. Kad padne nativni dio (libmpv, audio_service),
# proces nestane i test javi samo „did not complete”. Zato crash zapise
# čitamo izravno s uređaja.
if [[ $IS_ANDROID -eq 1 ]]; then
  adb -s "$DEVICE" logcat -b crash -c || true
  adb -s "$DEVICE" logcat -b events -c || true
else
  CRASH_BEFORE=$(gtimeout 60 pymobiledevice3 crash ls --udid "$DEVICE" 2>/dev/null | grep -E '^/Runner-' || true)
fi

LOG=$(mktemp -t smoke-device)
echo "==> smoke na $DEVICE (log: $LOG)"
# Vanjski timeout: nakon pada test runner zna visjeti u tearDownAll
# (izmjereno 13.10.2026.: 10 min). Prvi iOS build zna trajati 10+ min,
# pa je granica 25 min. gtimeout iz coreutils (brew).
run_test() {
gtimeout --kill-after=30s 25m \
  flutter test integration_test/smoke_test.dart -d "$DEVICE" "${DEFINES[@]}" \
  > "$LOG" 2>&1 &
TEST_PID=$!
# Nadzor zastoja: aplikacija koja ode u pozadinu (druga aplikacija u prvom
# planu, zaključan ekran) ne crta frameove i tester.pump nikad ne vrati.
# Log koji 8 min ne raste = zastoj → prekid, exit 2. (Xcode build i
# „Installing and launching” zna šutjeti 3–5 min, pa ne niže.)
STALLED=0
last_size=-1; still=0
while kill -0 $TEST_PID 2>/dev/null; do
  sleep 10
  size=$(wc -c < "$LOG")
  if [[ $size -eq $last_size ]]; then still=$((still + 10)); else still=0; last_size=$size; fi
  if [[ $still -ge 480 ]]; then
    STALLED=1
    pkill -P $TEST_PID 2>/dev/null; kill $TEST_PID 2>/dev/null
    break
  fi
done
wait $TEST_PID; RC=$?
}

set +e
run_test
# Debug build za iOS zna pasti na Xcode module cacheu koji dijeli s release
# archiveom („Module 'Flutter' is defined in both …ModuleCache.noindex”,
# 13.10.2026.). To je cache, ne kod: obriši ga i pokušaj još jednom.
if [[ $IS_ANDROID -eq 0 ]] && grep -q 'Could not build the precompiled application' "$LOG"; then
  MC=$(grep -oE "/[^']*/ModuleCache\.noindex" "$LOG" | head -1)
  echo "==> iOS build pao na module cacheu — brišem ${MC:-build/ios} i ponavljam"
  [[ -n "$MC" && "$MC" == */ModuleCache.noindex ]] && rm -rf "$MC"
  rm -rf build/ios
  run_test
fi
set -e
cat "$LOG"

# ── nativni crash: stanje poslije ───────────────────────────────────────────
NATIVE=""
if [[ $IS_ANDROID -eq 1 ]]; then
  NATIVE=$(adb -s "$DEVICE" logcat -b crash -d 2>/dev/null | grep -A12 -E 'Process: ai\.domovina|>>> ai\.domovina <<<' | head -30 || true)
  ANR=$(adb -s "$DEVICE" logcat -b events -d 2>/dev/null | grep -E 'am_anr.*ai\.domovina' | head -3 || true)
  [[ -n "$ANR" ]] && NATIVE+=$'\n'"ANR: $ANR"
else
  CRASH_AFTER=$(gtimeout 60 pymobiledevice3 crash ls --udid "$DEVICE" 2>/dev/null | grep -E '^/Runner-' || true)
  NEW=$(comm -13 <(sort <<<"$CRASH_BEFORE") <(sort <<<"$CRASH_AFTER") | grep . || true)
  [[ -n "$NEW" ]] && NATIVE="novi iOS crash zapisi: $NEW"
fi
if [[ -n "${NATIVE// /}" ]]; then
  echo "SMOKE_NATIVE_CRASH"
  echo "$NATIVE"
  echo "SMOKE: PAO — nativni crash"; exit 1
fi

# Build ili pokretanje na uređaju nije uspjelo — nightly je isti kod već
# izgradio za store, pa je ovo infrastruktura (cache, potpis, veza), ne kvar
# aplikacije.
if grep -qE 'Could not build the precompiled application|Unable to start the app on the device|Error launching application' "$LOG"; then
  echo "SMOKE: ne mogu provjeriti — build/pokretanje na $DEVICE nije uspjelo"; exit 2
fi
if grep -q SMOKE_NO_NETWORK "$LOG"; then
  echo "SMOKE: ne mogu provjeriti — aplikacija na $DEVICE nema mrežu"; exit 2
fi
# Pad prije visa u tearDownAll je pad, ne timeout.
if grep -q 'Some tests failed' "$LOG"; then
  echo "SMOKE: PAO"; exit 1
fi
if [[ $STALLED -eq 1 ]]; then
  echo "SMOKE: zastoj — log 8 min bez promjene (aplikacija u pozadini? druga aplikacija u prvom planu?)"; exit 2
fi
if [[ $RC -eq 124 || $RC -eq 137 ]]; then
  echo "SMOKE: timeout nakon 25 min"; exit 2
fi
[[ $RC -eq 0 ]] && echo "SMOKE: prošlo" || echo "SMOKE: PAO (rc=$RC)"
exit $([[ $RC -eq 0 ]] && echo 0 || echo 1)
