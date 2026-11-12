/*
 * Vrata Cast receivera za postavke kanala (postavke-kanala S6, odluka 110).
 *
 * Televizor reproducira medij s našeg CDN-a izravno, pa mu aplikacija koja je
 * pokrenula Cast nije jedina zaštita: stari pošiljatelj ili ručno sastavljen
 * LOAD i dalje dođu ovamo. Prije reprodukcije receiver pita:
 *   1. čiji je ovo video — `info.json` epizode (`channel_id`, UC kanala);
 *   2. što je vlasnik isključio — katalog `GET /v1/settings` (isti izvor kao
 *      aplikacija i worker).
 * Povučen ili obrisan kanal i isključen `cdn_playback` → LOAD se odbija.
 *
 * Fail-open, kao aplikacija (odluka 500): bez video ID-a, na mrežnoj grešci ili
 * nakon GATE_TIMEOUT_MS reprodukcija ide. Bolje pustiti nego televizor koji
 * zbog nedostupnog kataloga ništa ne pušta.
 *
 * Čista logika bez CAF-a, da je Node test (scripts/test-worker-postavke-kanala.mjs)
 * može izvesti s lažnim `fetch`.
 */
(function (root) {
  'use strict';

  var GATE_TIMEOUT_MS = 2500;
  var SETTINGS_PATH = '/api/katalog/v1/settings';
  var ID_RE = /^[A-Za-z0-9_-]{6,20}$/;

  /** Video ID iz LOAD medija: customData.videoId, inače iz `/data/<id>/` URL-a. */
  function videoIdFrom(media) {
    if (!media) return null;
    var cd = media.customData;
    if (cd && typeof cd.videoId === 'string' && ID_RE.test(cd.videoId)) return cd.videoId;
    var urls = [media.contentUrl, media.contentId];
    for (var i = 0; i < urls.length; i++) {
      var m = typeof urls[i] === 'string' && urls[i].match(/\/data\/([A-Za-z0-9_-]{6,20})\//);
      if (m) return m[1];
    }
    return null;
  }

  /** Origin CDN-a iz URL-a medija (https), inače zadani. */
  function cdnOrigin(media, fallback) {
    var urls = media ? [media.contentUrl, media.contentId] : [];
    for (var i = 0; i < urls.length; i++) {
      try {
        var u = new URL(urls[i]);
        if (u.protocol === 'https:' && /\/data\//.test(u.pathname)) return u.origin;
      } catch (e) { /* nije URL */ }
    }
    return fallback;
  }

  /**
   * Odluka za jedan LOAD → Promise<{ allowed, reason }>; `reason` je
   * 'withdrawn' | 'deleted' | 'cdn_playback' kad nije dopušteno, inače razlog
   * propuštanja ('no_video_id', 'unknown', 'active').
   *
   * opts: { fetch, siteOrigin, cdnFallback, now }
   */
  function decide(media, opts) {
    var f = opts.fetch;
    var id = videoIdFrom(media);
    if (!id) return Promise.resolve({ allowed: true, reason: 'no_video_id' });
    var cdn = cdnOrigin(media, opts.cdnFallback);
    // Isti cache-buster kao aplikacija (odluka 510): nova minuta = svjež odgovor.
    var minute = Math.floor((opts.now || Date.now()) / 60000);
    function json(url) {
      return f(url).then(function (r) { return r && r.ok ? r.json() : null; });
    }
    var work = Promise.all([
      json(cdn + '/data/' + id + '/info.json'),
      json(opts.siteOrigin + SETTINGS_PATH + '?t=' + minute),
    ]).then(function (res) {
      var info = res[0];
      var body = res[1];
      var uc = info && typeof info.channel_id === 'string' ? info.channel_id : null;
      var map = body && body.version === '1' && body.settings && typeof body.settings === 'object'
        ? body.settings : null;
      var entry = uc && map ? map[uc] : null;
      if (!entry) return { allowed: true, reason: uc && map ? 'active' : 'unknown' };
      if (entry.status === 'withdrawn' || entry.status === 'deleted') {
        return { allowed: false, reason: entry.status };
      }
      var off = Array.isArray(entry.off) ? entry.off : [];
      if (off.indexOf('channel_enabled') !== -1) return { allowed: false, reason: 'withdrawn' };
      if (off.indexOf('cdn_playback') !== -1) return { allowed: false, reason: 'cdn_playback' };
      return { allowed: true, reason: 'active' };
    }).catch(function () {
      return { allowed: true, reason: 'unknown' };
    });
    var timeout = new Promise(function (resolve) {
      setTimeout(function () { resolve({ allowed: true, reason: 'unknown' }); }, GATE_TIMEOUT_MS);
    });
    return Promise.race([work, timeout]);
  }

  root.DomovinaCastGate = { videoIdFrom: videoIdFrom, decide: decide, GATE_TIMEOUT_MS: GATE_TIMEOUT_MS };
})(typeof globalThis !== 'undefined' ? globalThis : this);
