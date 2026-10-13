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

LOG=$(mktemp -t smoke-device)
echo "==> smoke na $DEVICE (log: $LOG)"
# Vanjski timeout: nakon pada test runner zna visjeti u tearDownAll
# (izmjereno 13.10.2026.: 10 min). Prvi iOS build zna trajati 10+ min,
# pa je granica 25 min. gtimeout iz coreutils (brew).
set +e
gtimeout --kill-after=30s 25m \
  flutter test integration_test/smoke_test.dart -d "$DEVICE" "${DEFINES[@]}" \
  2>&1 | tee "$LOG"
RC=${PIPESTATUS[0]}
set -e

if grep -q SMOKE_NO_NETWORK "$LOG"; then
  echo "SMOKE: ne mogu provjeriti — aplikacija na $DEVICE nema mrežu"; exit 2
fi
# Pad prije visa u tearDownAll je pad, ne timeout.
if grep -q 'Some tests failed' "$LOG"; then
  echo "SMOKE: PAO"; exit 1
fi
if [[ $RC -eq 124 || $RC -eq 137 ]]; then
  echo "SMOKE: timeout nakon 25 min"; exit 2
fi
[[ $RC -eq 0 ]] && echo "SMOKE: prošlo" || echo "SMOKE: PAO (rc=$RC)"
exit $([[ $RC -eq 0 ]] && echo 0 || echo 1)
