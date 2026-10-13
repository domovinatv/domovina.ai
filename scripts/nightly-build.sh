#!/usr/bin/env bash
# Nightly store build — ako je bilo commitova od zadnjeg uspješnog builda, izgradi
# iOS + Android iz HEAD-a i pošalji ih na TestFlight i Play internal track.
# Rezultat ide u Telegram grupu. Pokreće ga launchd u 01:00 (vidi
# launchd/ai.domovina.nightly-build.plist), ali radi i ručno.
#
#   ./scripts/nightly-build.sh                 # normalan run (skip ako nema promjena)
#   ./scripts/nightly-build.sh --force         # gradi i bez novih commitova
#   ./scripts/nightly-build.sh --skip-upload   # gradi i testira, ne dira storeove
#   ./scripts/nightly-build.sh --no-telegram   # bez notifikacije
#
# Dizajn (puno obrazloženje: docs/nightly-build-pipeline.md):
#   * Gradi iz ODVOJENOG git worktreea na HEAD shi — nikad ne dira tvoj radni
#     direktorij i ne može pokupiti nedovršeni WIP koji leži u njemu u 01:00.
#   * Build broj = max(ASC, Play, pubspec) + 1 — pubspec se NE mijenja i ne
#     commita; kolizija s već uploadanim buildom je nemoguća.
#   * Testovi su TVRDA vrata: pad → nema uploada. Poznati padovi žive u
#     .nightly/test-baseline.txt i izuzeti su iz vrata (ali se i dalje vrte i
#     javljaju, da se primijeti kad prorade).
set -uo pipefail

# macOS /bin/bash je 3.2 (nema mapfile), a launchd plist tipično zove baš njega.
# Prebaci se na homebrew bash 5 prije nego išta drugo napravimo.
if [[ -z "${BASH_VERSINFO:-}" || ${BASH_VERSINFO[0]} -lt 4 ]]; then
  if [[ -x /opt/homebrew/bin/bash ]]; then
    exec /opt/homebrew/bin/bash "${BASH_SOURCE[0]}" "$@"
  fi
  echo "GRESKA: treba bash >= 4 (brew install bash)"; exit 1
fi

# launchd ne postavlja ni LANG — bez ovoga Ruby uzme US-ASCII i pukne na emojiju
# u izvještaju (izmjereno 2026-08-14: obavijest o padu nije poslana).
export LANG="${LANG:-en_US.UTF-8}" LC_ALL="${LC_ALL:-en_US.UTF-8}"

# `flutter clean` -> `xcodebuild clean` je pod launchd-om visio 60 min; nightly
# zato koristi brzo čišćenje putanja umjesto poziva Xcodea.
export FAST_CLEAN=1

# launchd daje minimalan PATH — sve alate razriješi eksplicitno.
export PATH="$HOME/fvm/default/bin:$HOME/google-cloud-sdk/bin:/opt/homebrew/bin:/Library/Frameworks/Python.framework/Versions/3.13/bin:/opt/homebrew/opt/ruby/bin:/usr/bin:/bin:/usr/sbin:/sbin:$PATH"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STATE="$ROOT/.nightly"
# WT se razrješava TEK nakon montiranja build kontejnera (korak 2b) —
# worktree ide na APFS kontejner da nightly uopće ne dira tijesan boot disk.
WT="${NIGHTLY_WORKTREE:-}"
BASELINE="$STATE/test-baseline.txt"
LAST_SHA_FILE="$STATE/last-built-sha"
RUN_TS="$(date +%Y-%m-%d-%H%M)"
LOG="$STATE/logs/$RUN_TS.log"

FORCE=0; SKIP_UPLOAD=0; TELEGRAM=1
for arg in "$@"; do
  case "$arg" in
    --force)       FORCE=1 ;;
    --skip-upload) SKIP_UPLOAD=1 ;;
    --no-telegram) TELEGRAM=0 ;;
    --help|-h)     sed -n '2,20p' "${BASH_SOURCE[0]}"; exit 0 ;;
    *)             echo "nepoznat flag: $arg"; exit 2 ;;
  esac
done

mkdir -p "$STATE/logs" "$STATE/reports"
exec > >(tee -a "$LOG") 2>&1

TIMEOUT_BIN="$(command -v gtimeout || command -v timeout || true)"
[[ -z "$TIMEOUT_BIN" ]] && echo "UPOZORENJE: nema timeout(1) — koraci nemaju watchdog"

REPORT=()          # linije za Telegram/report
FAILED_STEP=""
START_TS=$SECONDS

esc() { sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g'; }
dur() { printf '%d min %02d s' $(($1 / 60)) $(($1 % 60)); }
# `"${REPORT[@]}"` na praznom polju puca pod `set -u` — uvijek kroz ovo.
report_lines_raw() { [[ ${#REPORT[@]} -eq 0 ]] || printf '%s\n' "${REPORT[@]}"; }
# Za Telegram MORA ići kroz esc: vlastiti retci sadrže `<` i `>` ("(< 20 GB)"),
# a parse_mode=HTML to čita kao tag → 400 "Unsupported start tag" i poruka propadne
# (izmjereno 2026-08-14). HTML u poruci pišemo samo mi, u predlošcima.
report_lines() { report_lines_raw | esc; }

# ── lock ─────────────────────────────────────────────────────────────────────
LOCK="$STATE/lock"
if ! mkdir "$LOCK" 2>/dev/null; then
  if [[ -n "$(find "$LOCK" -maxdepth 0 -mmin +360 2>/dev/null)" ]]; then
    echo "UPOZORENJE: lock stariji od 6 h — preuzimam ga."
    rmdir "$LOCK" 2>/dev/null || true
    mkdir "$LOCK" 2>/dev/null || { echo "ne mogu uzeti lock"; exit 1; }
  else
    echo "Već traje nightly (ili ručni) build — izlazim."
    exit 0
  fi
fi
trap 'rmdir "$LOCK" 2>/dev/null || true' EXIT

# ── notifikacija ─────────────────────────────────────────────────────────────
notify() {
  [[ $TELEGRAM -eq 1 ]] || { echo "(telegram isključen)"; return 0; }
  printf '%s' "$1" | "$ROOT/scripts/telegram-notify.rb" || true
}

finish_fail() {
  local step="$1" rc="$2"
  local tail_txt
  tail_txt="$(tail -c 1800 "$LOG" | esc)"
  local msg="🌙❌ <b>Nightly pao — ${step}</b>
<code>${SHA_SHORT:-?}</code> · ${SUBJECT_ESC:-?}
$(report_lines)
⏱️ $(dur $((SECONDS - START_TS))) · izlazni kod ${rc}
<pre>${tail_txt}</pre>
📄 log: <code>.nightly/logs/${RUN_TS}.log</code>"
  notify "$msg"
  write_report "PAO ($step)"
  exit 1
}

write_report() {
  local status="$1"
  {
    echo "# Nightly $RUN_TS — $status"
    echo
    echo "- commit: ${SHA_SHORT:-?} — ${SUBJECT:-?}"
    echo "- build: ${BUILD_NAME:-?} (${BN:-?})"
    report_lines_raw | sed 's/^/- /'
    [[ -s "${BOOT_MIN_FILE:-}" ]] && \
      echo "- boot disk: ${BOOT_FREE} GB na startu, najmanje $(cat "$BOOT_MIN_FILE") GB tijekom builda"
    echo "- trajanje: $(dur $((SECONDS - START_TS)))"
    echo "- log: .nightly/logs/$RUN_TS.log"
  } > "$STATE/reports/$RUN_TS.md"
}

# step <naziv> <timeout_min> <cmd…>
step() {
  local name="$1" tmo="$2"; shift 2
  echo
  echo "############ KORAK: $name (timeout ${tmo} min) ############"
  local t0=$SECONDS rc=0
  if [[ -n "$TIMEOUT_BIN" ]]; then
    "$TIMEOUT_BIN" -k 30 "${tmo}m" "$@" || rc=$?
  else
    "$@" || rc=$?
  fi
  local el=$((SECONDS - t0))
  if [[ $rc -ne 0 ]]; then
    [[ $rc -eq 124 ]] && echo "!! korak '$name' prekinut watchdogom nakon ${tmo} min"
    REPORT+=("❌ ${name} — pao nakon $(dur $el)")
    return $rc
  fi
  REPORT+=("✅ ${name} — $(dur $el)")
  return 0
}

# ── 1. ima li novih commitova ────────────────────────────────────────────────
SHA="$(git -C "$ROOT" rev-parse "${NIGHTLY_REF:-HEAD}")"
SHA_SHORT="${SHA:0:7}"
SUBJECT="$(git -C "$ROOT" log -1 --format=%s "$SHA")"
SUBJECT_ESC="$(printf '%s' "$SUBJECT" | esc)"
LAST_SHA="$(cat "$LAST_SHA_FILE" 2>/dev/null || echo '')"

echo "=== nightly $RUN_TS · HEAD=$SHA_SHORT · zadnji izgrađen=${LAST_SHA:0:7} ==="
if [[ "$SHA" == "$LAST_SHA" && $FORCE -eq 0 ]]; then
  echo "Nema novih commitova — izlazim."
  # Poruka se šalje i na prazan dan: njezin IZOSTANAK je signal da je launchd crknuo.
  [[ "${NIGHTLY_QUIET_SKIP:-0}" == "1" ]] || \
    notify "🌙💤 <b>Nightly preskočen</b> — nema novih commitova od <code>$SHA_SHORT</code>."
  exit 0
fi

# ── 2. tvrdi preduvjeti (da build ne ode tiho degradiran) ────────────────────
[[ -f "$ROOT/.env" ]] || { echo "GRESKA: nema .env"; finish_fail "preduvjeti" 1; }
set -a; source "$ROOT/.env"; set +a
MISSING=()
for k in SUPABASE_URL SUPABASE_ANON_KEY RC_PUBLIC_SDK_KEY_IOS RC_PUBLIC_SDK_KEY_ANDROID; do
  [[ -n "${!k:-}" ]] || MISSING+=("$k")
done
if [[ ${#MISSING[@]} -gt 0 ]]; then
  echo "GRESKA: u .env nedostaje: ${MISSING[*]}"
  REPORT+=("❌ .env nepotpun: ${MISSING[*]}")
  finish_fail "preduvjeti (.env)" 1
fi
[[ -f "$ROOT/android/key.properties" ]] || { echo "GRESKA: nema android/key.properties"; finish_fail "preduvjeti" 1; }

# ── 2b. disk ─────────────────────────────────────────────────────────────────
# Pun disk se NE prijavi kao "nema mjesta": Gradle javi "Failed to release lock"
# i "Could not add entry to cache", što izgleda kao pokvaren build. Izmjereno
# 2026-08-13 — boot volumen na 3 GiB je oborio AAB nakon 3 min. Provjeri unaprijed.
#
# Prag je bio 20 GB dok su DerivedData i Gradle cache (14+ GB) živjeli na boot
# disku. Od 14.8. su u sparsebundleu, a boot disku ostaje worktree (~2 GB) — ali
# prag je ostao, pa je od 13.8. do 23.9. odbio 18 noći (više nego što ih je
# prošlo), uz 7–14 GB slobodno. Veći dio toga pojede swap, koji raste s uptimeom.
# Stvarni vrh potrošnje mjeri sampler niže i piše ga u izvještaj — prag spuštati
# dalje tek uz te brojke.
free_gb() { df -g "$1" 2>/dev/null | awk 'NR==2 {print $4}'; }
MIN_FREE_BOOT="${NIGHTLY_MIN_FREE_BOOT_GB:-8}"
MIN_FREE_DD="${NIGHTLY_MIN_FREE_DD_GB:-15}"

BOOT_FREE="$(free_gb "$HOME")"
if [[ -z "$BOOT_FREE" || "$BOOT_FREE" -lt "$MIN_FREE_BOOT" ]]; then
  echo "GRESKA: na boot volumenu je ${BOOT_FREE:-?} GB slobodno (minimum ${MIN_FREE_BOOT} GB)."
  REPORT+=("❌ disk: boot volumen ${BOOT_FREE:-?} GB slobodno (< ${MIN_FREE_BOOT} GB)")
  finish_fail "preduvjeti (disk)" 1
fi

# Sampler: najmanji slobodni prostor na boot disku tijekom cijelog builda.
BOOT_MIN_FILE="$STATE/.boot-min"
echo "$BOOT_FREE" > "$BOOT_MIN_FILE"
(
  while sleep 20; do
    f="$(free_gb "$HOME")"; m="$(cat "$BOOT_MIN_FILE" 2>/dev/null || echo "$f")"
    [[ -n "$f" && "$f" -lt "$m" ]] && echo "$f" > "$BOOT_MIN_FILE"
  done
) &
BOOT_SAMPLER_PID=$!
trap 'kill "$BOOT_SAMPLER_PID" 2>/dev/null; rmdir "$LOCK" 2>/dev/null || true' EXIT

# Xcode DerivedData ovdje živi na vanjskom disku; ako nije montiran, xcodebuild
# padne s 2000 redaka ispisa koji nigdje ne kažu "nema diska".
DD_LOC="$(defaults read com.apple.dt.Xcode IDECustomDerivedDataLocation 2>/dev/null || true)"
if [[ -n "$DD_LOC" ]]; then
  if [[ ! -d "$DD_LOC" ]]; then
    echo "GRESKA: Xcode DerivedData '$DD_LOC' ne postoji — disk nije montiran?"
    REPORT+=("❌ disk: DerivedData nedostupan ($DD_LOC)")
    finish_fail "preduvjeti (DerivedData disk)" 1
  fi
  DD_FREE="$(free_gb "$DD_LOC")"
  if [[ -z "$DD_FREE" || "$DD_FREE" -lt "$MIN_FREE_DD" ]]; then
    echo "GRESKA: na DerivedData volumenu je ${DD_FREE:-?} GB slobodno (minimum ${MIN_FREE_DD} GB)."
    REPORT+=("❌ disk: DerivedData volumen ${DD_FREE:-?} GB slobodno (< ${MIN_FREE_DD} GB)")
    finish_fail "preduvjeti (DerivedData prostor)" 1
  fi
  echo "==> disk: boot ${BOOT_FREE} GB · DerivedData ${DD_FREE} GB slobodno"
else
  echo "==> disk: boot ${BOOT_FREE} GB slobodno (DerivedData je na default lokaciji)"
fi

# Gradle cache (14 GB i raste) i nightly DerivedData žive na vanjskom APFS
# disku DOMOVINA1TB — boot volumen je pretijesan. Nightly postavlja
# GRADLE_USER_HOME eksplicitno da ne ovisi o simlinku ~/.gradle.
# Do 26.9.2026 je ovo bio APFS sparsebundle DOMOVINA_BUILD na DOMOVINA2TB; I/O
# kroz njega pao je na ~6 MB/s, pa je ugašen. Obje mape su cache: kad nedostaju,
# nastaju prazne i pune se same (nikad ih ne kopirati s diska na disk).
BUILD_FILES="${NIGHTLY_BUILD_FILES:-/Volumes/DOMOVINA1TB/domovina_build}"
if [[ -d "$(dirname "$BUILD_FILES")" ]]; then
  mkdir -p "$BUILD_FILES/gradle"
fi
if [[ -d "$BUILD_FILES/gradle" ]]; then
  export GRADLE_USER_HOME="$BUILD_FILES/gradle"
  BF_FREE="$(free_gb "$BUILD_FILES")"
  if [[ -z "$BF_FREE" || "$BF_FREE" -lt "$MIN_FREE_DD" ]]; then
    echo "GRESKA: na ${BUILD_FILES} je ${BF_FREE:-?} GB slobodno (minimum ${MIN_FREE_DD} GB)."
    REPORT+=("❌ disk: build-files volumen ${BF_FREE:-?} GB slobodno")
    finish_fail "preduvjeti (build-files prostor)" 1
  fi
  echo "==> GRADLE_USER_HOME=$GRADLE_USER_HOME (${BF_FREE} GB slobodno)"

  # Xcode artefakti na predvidivoj putanji (inače Runner-<hash> po putanji projekta,
  # koji nitko ne čisti — zatečeno 66 GB naslaga). GC kad disk postane tijesan:
  # jedna arhiva traži desetke GB, a `flutter clean` svejedno gradi iznova.
  export BUILD_DERIVED_DATA="$BUILD_FILES/derived-data"
  if [[ -d "$BUILD_DERIVED_DATA" && "$BF_FREE" -lt "${NIGHTLY_DD_GC_GB:-60}" ]]; then
    echo "==> GC: brišem $BUILD_DERIVED_DATA ($(du -sh "$BUILD_DERIVED_DATA" 2>/dev/null | cut -f1)) jer je slobodno samo ${BF_FREE} GB"
    rm -rf "$BUILD_DERIVED_DATA"
    REPORT+=("🧹 GC: DerivedData obrisan (bilo ${BF_FREE} GB slobodno)")
  fi
elif [[ -L "$HOME/.gradle" && ! -e "$HOME/.gradle" ]]; then
  echo "GRESKA: ~/.gradle je slomljen simlink — vanjski disk nije montiran."
  REPORT+=("❌ disk: ~/.gradle simlink pokazuje u prazno")
  finish_fail "preduvjeti (Gradle cache disk)" 1
fi

# ── 3. izolirani worktree na HEAD shi ────────────────────────────────────────
# Rule: worktree MORA biti sestra glavnog repoa. pubspec ima path ovisnost
# (`flutter_certilia: ../../stepanic/flutter_certilia`) koja se razrješava
# relativno na lokaciju worktreea — probano 2026-08-14 premjestiti ga u APFS
# kontejner i `pub get` je odmah pao ("could not find package flutter_certilia").
# Build mora razrješavati putanje identično ručnom buildu; ušteda ~2 GB na boot
# disku to ne opravdava. Gradle cache i DerivedData su ionako u kontejneru.
[[ -n "$WT" ]] || WT="$(dirname "$ROOT")/.nightly-domovina"
echo "==> worktree: $WT"
if ! git -C "$ROOT" worktree list --porcelain | grep -qx "worktree $WT"; then
  echo "==> kreiram worktree $WT"
  rm -rf "$WT"
  git -C "$ROOT" worktree add --detach "$WT" "$SHA" || finish_fail "worktree" 1
else
  echo "==> osvježavam worktree na $SHA_SHORT"
  git -C "$WT" checkout --detach --force "$SHA" || finish_fail "worktree" 1
  # bez -x: ignorirani artefakti (build/, .dart_tool/, .env, key.properties) ostaju
  git -C "$WT" clean -fd >/dev/null
fi
ln -sfn "$ROOT/.env" "$WT/.env"
ln -sfn "$ROOT/android/key.properties" "$WT/android/key.properties"

cd "$WT"

# ── 4. analyze + testovi (tvrda vrata) ───────────────────────────────────────
step "pub get" 10 flutter pub get || finish_fail "pub get" $?
step "flutter analyze" 10 flutter analyze || finish_fail "flutter analyze" $?

# Testovi žive u paketu packages/podcast_core (pub workspace); putanje u
# .nightly/test-baseline.txt su relativne na taj direktorij.
CORE_DIR="packages/podcast_core"
mapfile -t ALL_TESTS < <(cd "$CORE_DIR" && find test -name '*_test.dart' | sort)
BASE_TESTS=(); GATED_TESTS=()
if [[ -f "$BASELINE" ]]; then
  mapfile -t BASE_TESTS < <(grep -vE '^\s*(#|$)' "$BASELINE" | tr -d '\r')
fi
for t in "${ALL_TESTS[@]}"; do
  skip=0
  if [[ ${#BASE_TESTS[@]} -gt 0 ]]; then
    for b in "${BASE_TESTS[@]}"; do [[ "$t" == "$b" ]] && skip=1; done
  fi
  [[ $skip -eq 0 ]] && GATED_TESTS+=("$t")
done
echo "testovi u vratima: ${#GATED_TESTS[@]} · baseline (izuzeti): ${#BASE_TESTS[@]}"

cd "$CORE_DIR"
step "testovi (${#GATED_TESTS[@]} fajlova)" 25 flutter test "${GATED_TESTS[@]}" \
  || finish_fail "testovi" $?

# Baseline se i dalje vrti — informativno. Ako prorade, javi da ih se makne.
if [[ ${#BASE_TESTS[@]} -gt 0 ]]; then
  if flutter test "${BASE_TESTS[@]}" >/dev/null 2>&1; then
    REPORT+=("🎉 baseline testovi sad PROLAZE — makni ih iz .nightly/test-baseline.txt")
  else
    REPORT+=("➖ baseline: ${#BASE_TESTS[@]} poznato crvenih (izuzeti iz vrata)")
  fi
fi
cd "$WT"

# ── 4b. tripwire: Podcasterium ljuska nad ovim coreom ───────────────────────
# Druga ljuska (sestrinski repo) mora se graditi nad PR-ovim podcast_core;
# ako je nema na disku, korak se preskače (izlaz 2), inače je tvrda vrata.
PODCASTERIUM_RC=0
"$ROOT/scripts/build-podcasterium-shell.sh" "$WT/packages/podcast_core" || PODCASTERIUM_RC=$?
if [[ $PODCASTERIUM_RC -eq 2 ]]; then
  REPORT+=("➖ Podcasterium ljuska: nije na disku, tripwire preskočen")
elif [[ $PODCASTERIUM_RC -ne 0 ]]; then
  finish_fail "Podcasterium ljuska (white-label tripwire)" $PODCASTERIUM_RC
else
  REPORT+=("✅ Podcasterium ljuska se gradi nad ovim coreom")
fi

# ── 5. build broj ────────────────────────────────────────────────────────────
BUILD_NAME="$(grep '^version:' pubspec.yaml | sed 's/version: //' | cut -d'+' -f1)"
PUB_BUILD="$(grep '^version:' pubspec.yaml | sed 's/.*+//')"
STORE_MAX="$("$ROOT/scripts/store-status.rb" --max-build 2>/dev/null || echo 0)"
BN=$(( (STORE_MAX > PUB_BUILD ? STORE_MAX : PUB_BUILD) + 1 ))
echo "==> verzija ${BUILD_NAME} · build ${BN} (store max ${STORE_MAX}, pubspec ${PUB_BUILD})"
export BUILD_NUMBER="$BN"

# ── 6. build ─────────────────────────────────────────────────────────────────
# Uz App Store IPA i development export istog archivea — za release smoke
# na iPhoneima farme (korak 8b). Mora prije `rm -rf build/ios/archive`.
export EXPORT_DEV_IPA=1
step "iOS build (IPA)"     60 ./scripts/build-mobile-release.sh ios     || finish_fail "iOS build" $?
# IPA je izvezen (dSYM-ovi su otišli s uploadSymbols) — arhiva je samo balast.
rm -rf build/ios/archive
step "Android build (AAB)" 30 ./scripts/build-mobile-release.sh android || finish_fail "Android build" $?

if [[ $SKIP_UPLOAD -eq 1 ]]; then
  REPORT+=("⏭️ upload preskočen (--skip-upload)")
  notify "🌙🔧 <b>Nightly build OK (bez uploada)</b> ${BUILD_NAME} (${BN})
<code>$SHA_SHORT</code> · ${SUBJECT_ESC}
$(report_lines)
⏱️ $(dur $((SECONDS - START_TS)))"
  write_report "OK (bez uploada)"
  exit 0
fi

# ── 7. upload ────────────────────────────────────────────────────────────────
TF_RC=0
step "TestFlight upload"   30 ./scripts/testflight-upload.sh    || TF_RC=$?
if [[ $TF_RC -eq 3 ]]; then
  REPORT+=("🍏❌ Apple je zatvorio train ${BUILD_NAME} (verzija već odobrena) — bumpaj verziju u pubspec.yaml")
fi
[[ $TF_RC -eq 0 ]] || finish_fail "TestFlight upload" $TF_RC
step "Play internal upload" 20 ./scripts/play-upload.sh internal || finish_fail "Play upload" $?

# ── 8. verifikacija (upload 200 ≠ build je dobar) ────────────────────────────
# Apple obrađuje asinkrono; ITMS odbijenice stižu tek ovdje, ne na uploadu.
# Prozor: izmjereno 2026-08-13 da build ni 25 min nakon uploada još nije bio
# vidljiv u /v1/builds. 20 min je davalo lažni ⚠️ gotovo svaku noć.
# NOT_FOUND ≠ PROCESSING: build kojeg ASC ne poznaje možda nikad nije stigao.
# Do 24.9.2026. su se ta dva stanja stapala, pa je odbijen upload (13.8., 18.8.)
# javljen kao "Apple ga još obrađuje — nije greška".
IOS_STATE="NOT_FOUND"
for _ in $(seq 1 "${NIGHTLY_TF_POLL_MIN:-45}"); do
  sleep 60
  IOS_STATE="$("$ROOT/scripts/store-status.rb" --json 2>/dev/null \
    | ruby -rjson -e 'd=JSON.parse(STDIN.read); b=(d.dig("ios","builds")||[]).find{|x| x["build"].to_i==ARGV[0].to_i}; puts(b ? b["processing"] : "NOT_FOUND")' "$BN" \
    || echo "$IOS_STATE")"
  echo "    TestFlight build $BN: $IOS_STATE"
  [[ "$IOS_STATE" == "VALID" || "$IOS_STATE" == "INVALID" || "$IOS_STATE" == "FAILED" ]] && break
done
case "$IOS_STATE" in
  VALID)   REPORT+=("🍏 TestFlight build ${BN}: VALID") ;;
  PROCESSING) REPORT+=("🍏 TestFlight build ${BN}: Apple ga još obrađuje (>${NIGHTLY_TF_POLL_MIN:-45} min) — nije greška, provjeri ujutro sa store-status.rb") ;;
  NOT_FOUND)  REPORT+=("🍏⚠️ TestFlight build ${BN}: App Store Connect ga NE VIDI ni nakon ${NIGHTLY_TF_POLL_MIN:-45} min — upload možda nije stigao, provjeri store-status.rb") ;;
  *)       REPORT+=("🍏❌ TestFlight build ${BN}: ${IOS_STATE}") ;;
esac

PLAY_OK="$("$ROOT/scripts/store-status.rb" --json 2>/dev/null \
  | ruby -rjson -e 'd=JSON.parse(STDIN.read); t=(d.dig("play","tracks")||[]).find{|x| x["track"]=="internal"}; puts((t&&t["releases"].any?{|r| r["codes"].include?(ARGV[0])}) ? "da" : "ne")' "$BN" \
  || echo '?')"
[[ "$PLAY_OK" == "da" ]] && REPORT+=("🤖 Play internal: versionCode ${BN} potvrđen") \
                         || REPORT+=("🤖⚠️ Play internal: versionCode ${BN} NIJE potvrđen čitanjem")

# ── 8b. smoke na uređajima farme ─────────────────────────────────────────────
# Isti binarni paket koji je upravo uploadan, na 2 Androida + 2 iPhonea
# spojena na ovaj Mac (docs/plans/2026-10-13-smoke-testovi-na-uredajima.md).
# NE blokira upload — build je već interni; vrata su na promociji
# (smoke-gate.sh u asc-submit.rb / play-promote.sh). NIGHTLY_SMOKE=0 gasi.
SMOKE_RC=0
if [[ "${NIGHTLY_SMOKE:-1}" == "1" ]]; then
  echo; echo "############ KORAK: smoke na uređajima (timeout 120 min) ############"
  SMOKE_T0=$SECONDS
  SMOKE_OUT=$("${TIMEOUT_BIN:-command}" ${TIMEOUT_BIN:+-k 30 120m} ./scripts/nightly-smoke.sh "$BN" 2>&1) || SMOKE_RC=$?
  echo "$SMOKE_OUT"
  case $SMOKE_RC in
    0) REPORT+=("🧪 Smoke ${BN}: prošao na svim uređajima — $(dur $((SECONDS - SMOKE_T0)))") ;;
    1) REPORT+=("🧪❌ Smoke ${BN}: PAO — ovaj build NE promovirati") ;;
    *) REPORT+=("🧪⚠️ Smoke ${BN}: nije potpuno provjeren (uređaj zauzet/odspojen?)") ;;
  esac
  while IFS= read -r l; do [[ -n "$l" ]] && REPORT+=("   $l"); done \
    < <(grep -E '^(.+: release |   ↳ |nijedan uređaj)' <<<"$SMOKE_OUT")
fi

# ── 9. gotovo ────────────────────────────────────────────────────────────────
echo "$SHA" > "$LAST_SHA_FILE"
ICON="🌙✅"; [[ "$IOS_STATE" == "VALID" && "$PLAY_OK" == "da" && $SMOKE_RC -eq 0 ]] || ICON="🌙⚠️"
notify "${ICON} <b>Nightly ${BUILD_NAME} (${BN})</b>
<code>$SHA_SHORT</code> · ${SUBJECT_ESC}
$(report_lines)
⏱️ ukupno $(dur $((SECONDS - START_TS)))"
write_report "OK"
echo "=== gotovo: $(dur $((SECONDS - START_TS))) ==="
