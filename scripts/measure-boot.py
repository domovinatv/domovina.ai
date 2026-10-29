#!/usr/bin/env python3
"""Vremenska crta od prvog bajta HTML-a do prvog Flutter framea.

Reprodukcija brojki iz docs/2026-10-09-boot-splash.md. Hladni cache (svaki run
je novi browser context: bez HTTP cachea, bez service workera), mrežni profil
preko CDP `Network.emulateNetworkConditions`. Headed Chrome namjerno: skrivena
kartica ne crta Flutter frameove pa bi `flutter-first-frame` lagao.

Upotreba:
  python3 scripts/measure-boot.py [URL] [--profile none|4g|slow4g|3g]
                                  [--mobile] [--runs N] [--shots DIR] [--cpu 4]

Profili (download/upload kbit/s, RTT ms) — brojke kao Lighthouse/DevTools:
  4g      9000 / 1500 /  60   (DevTools „Fast 4G")
  slow4g  1600 /  750 / 150   (Lighthouse „Slow 4G", mobilni default)
  3g       780 /  330 / 300   (WebPageTest „3G")
"""
import argparse, json, statistics, sys
from playwright.sync_api import sync_playwright

PROFILES = {
    "none": None,
    "4g": (9000, 1500, 60),
    "slow4g": (1600, 750, 150),
    "3g": (780, 330, 300),
}

# Bilježi trenutke u performance.now() (ms od navigationStart) prije ikakvog
# koda stranice. console.log omotamo jer Dartov print() ide kroz njega.
INIT = r"""
(() => {
  const m = (window.__boot = {});
  const t = () => Math.round(performance.now());
  const log = console.log.bind(console);
  console.log = (...a) => {
    const s = String(a[0] ?? '');
    if (s.includes('main() start') && !m.mainStart) m.mainStart = t();
    if (s.includes('] runApp') && !m.runApp) m.runApp = t();
    return log(...a);
  };
  window.addEventListener('flutter-first-frame', () => { m.firstFrame = t(); });
  // Prvi <canvas> u flutter-viewu = frame je stvarno predan na ekran (skwasm
  // rasterizira u workeru, pa event i slika nisu isti trenutak). Platno je u
  // shadow rootu flt-glass-panea, pa MutationObserver na documentu ne vidi.
  const poll = () => {
    const gp = document.querySelector('flt-glass-pane');
    const c = gp && gp.shadowRoot && gp.shadowRoot.querySelector('canvas');
    if (c && c.width > 0 && !m.canvas) m.canvas = t();
    // Platno postoji ≠ platno nacrtano: presnimi u 8×8 i traži neprozirne piksele.
    if (c && c.width > 0 && window.createImageBitmap) {
      createImageBitmap(c, {resizeWidth: 8, resizeHeight: 8}).then(b => {
        const o = document.createElement('canvas'); o.width = o.height = 8;
        const g = o.getContext('2d'); g.drawImage(b, 0, 0);
        const d = g.getImageData(0, 0, 8, 8).data; let n = 0;
        for (let j = 3; j < d.length; j += 4) if (d[j] > 200) n++;
        if (n > 32) m.painted = t(); else setTimeout(poll, 50);
      }, () => setTimeout(poll, 50));
      return;
    }
    requestAnimationFrame(poll);
  };
  requestAnimationFrame(poll);
  document.addEventListener('DOMContentLoaded', () => {
    m.dcl = t();
    const intro = document.getElementById('boot-intro');
    m.introAtDcl = !!intro;
    new MutationObserver(() => {
      if (!m.introGone && !document.getElementById('boot-intro')) m.introGone = t();
      const el = document.getElementById('boot-intro');
      if (el && el.style.opacity === '0' && !m.introFade) m.introFade = t();
      // Tekst faze ispod trake: [ms, tekst] na svaku promjenu.
      const ld = document.getElementById('bi-load');
      m.stages = m.stages || [];
      const last = m.stages[m.stages.length - 1];
      if (ld && (!last || last[1] !== ld.textContent)) m.stages.push([t(), ld.textContent]);
    }).observe(document.documentElement, {subtree: true, childList: true, characterData: true,
                                          attributes: true, attributeFilter: ['style']});
  });
  new PerformanceObserver(l => {
    for (const e of l.getEntries())
      if (e.name === 'first-contentful-paint') m.fcp = Math.round(e.startTime);
  }).observe({type: 'paint', buffered: true});
})();
"""

WATCH = ["passkeys_bundle.js", "flutter_bootstrap.js", "main.dart.mjs",
         "main.dart.wasm", "main.dart.js", "skwasm.js", "skwasm.wasm",
         "skwasm_heavy.js", "skwasm_heavy.wasm", "canvaskit.wasm",
         "fonts.googleapis.com/css2", "beacon.min.js",
         "auth/v1/token", "rest/v1/", "fonts.gstatic.com"]


def run_once(pw, url, profile, mobile, shots=None, cpu=1):
    browser = pw.chromium.launch(channel="chrome", headless=False)
    ctx = browser.new_context(
        viewport={"width": 390, "height": 844} if mobile else {"width": 1440, "height": 900},
        device_scale_factor=3 if mobile else 1,
        is_mobile=mobile, has_touch=mobile,
        service_workers="block")
    page = ctx.new_page()
    page.add_init_script(INIT)
    cdp = ctx.new_cdp_session(page)
    cdp.send("Network.enable")
    cdp.send("Network.setCacheDisabled", {"cacheDisabled": True})
    if PROFILES[profile]:
        down, up, rtt = PROFILES[profile]
        cdp.send("Network.emulateNetworkConditions", {
            "offline": False, "latency": rtt,
            "downloadThroughput": down * 1000 / 8,
            "uploadThroughput": up * 1000 / 8})
    if cpu > 1:
        cdp.send("Emulation.setCPUThrottlingRate", {"rate": cpu})
    page.bring_to_front()
    page.goto(url, wait_until="commit")
    # --shots: snimka ekrana svake 2 s do prvog framea (vizualna potvrda da
    # nijedna faza nije prazna/bijela).
    deadline, n = 180, 0
    while n * 2 < deadline:
        if page.evaluate("!!(window.__boot && window.__boot.firstFrame)"):
            break
        if shots:
            page.screenshot(path=f"{shots}/{profile}-{n * 2:03d}s.png")
        page.wait_for_timeout(2000)
        n += 1
    page.wait_for_timeout(500)
    marks = page.evaluate("window.__boot")
    marks["visibility"] = page.evaluate("document.visibilityState")
    res = page.evaluate("""() => performance.getEntriesByType('resource').map(e => ({
        name: e.name, start: Math.round(e.startTime), end: Math.round(e.responseEnd),
        ttfb: Math.round(e.responseStart - e.requestStart),
        kb: Math.round((e.transferSize || 0) / 1024)}))""")
    nav = page.evaluate("""() => { const n = performance.getEntriesByType('navigation')[0];
        return {ttfb: Math.round(n.responseStart), html: Math.round(n.responseEnd)}; }""")
    browser.close()
    return marks, res, nav


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("url", nargs="?", default="https://domovina.ai/")
    ap.add_argument("--profile", default="slow4g", choices=PROFILES)
    ap.add_argument("--mobile", action="store_true")
    ap.add_argument("--runs", type=int, default=1)
    ap.add_argument("--json", action="store_true")
    ap.add_argument("--cpu", type=float, default=1, help="CPU throttling (4 = DevTools 4x slowdown)")
    ap.add_argument("--shots", help="direktorij za snimke svake 2 s")
    a = ap.parse_args()
    out = []
    with sync_playwright() as pw:
        for i in range(a.runs):
            marks, res, nav = run_once(pw, a.url, a.profile, a.mobile, a.shots, a.cpu)
            out.append(marks)
            print(f"\n== run {i+1}  {a.url}  profil={a.profile}  "
                  f"{'mobile 390' if a.mobile else 'desktop 1440'}  "
                  f"visibility={marks.get('visibility')}")
            print(f"  html ttfb {nav['ttfb']:>6} ms   html gotov {nav['html']:>6}")
            for k in ["fcp", "dcl", "introFade", "introGone", "mainStart",
                      "runApp", "firstFrame", "canvas", "painted"]:
                v = marks.get(k)
                print(f"  {k:<10} {('—' if v is None else str(v)):>6} ms")
            for ms, txt in marks.get("stages") or []:
                print(f"  faza {ms:>6} ms  {txt}")
            if marks.get("mainStart") and marks.get("runApp"):
                print(f"  main()→runApp {marks['runApp'] - marks['mainStart']} ms")
            gap = None
            if marks.get("introFade") and marks.get("firstFrame"):
                gap = marks["firstFrame"] - marks["introFade"]
                print(f"  PRAZNINA (splash maknut → prvi frame): {max(gap, 0)} ms")
            for r in sorted(res, key=lambda r: r["start"]):
                if any(w in r["name"] for w in WATCH):
                    print(f"    {r['start']:>6}–{r['end']:>6} ms  ttfb {r['ttfb']:>5}  "
                          f"{r['kb']:>5} KB  {r['name'][:90]}")
    if a.runs > 1:
        for k in ["introFade", "mainStart", "runApp", "firstFrame", "canvas", "painted"]:
            vals = [m[k] for m in out if m.get(k)]
            if vals:
                print(f"median {k:<10} {statistics.median(vals):>8.0f} ms  (n={len(vals)})")
    if a.json:
        print(json.dumps(out))


if __name__ == "__main__":
    sys.exit(main())
