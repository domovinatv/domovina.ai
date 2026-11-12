import '../../brand/app_brand.dart';
import '../../l10n/app_localizations.dart';
import '../../models/channel_detail.dart';
import '../../services/channel_cache.dart';
import '../../services/channel_setting_keys.dart';
import '../../services/channel_visibility.dart';

/// Cross-channel video s denormaliziranim channel kontekstom.
typedef FeedVideo = ({String channelId, String channelName, ChannelVideo video});

/// Domenska ocjena epizode (0–100) za ranker naslovnice, ili `null` kad
/// epizoda NIJE ocijenjena. Brend s `flags.domainScore` daje
/// [HomeFeed.magisteriumScore]; brend bez domenske ocjene ne daje ništa
/// (`score == null`) i ranker pada na potpunost obrade + svježinu.
typedef ScoreFn = int? Function(FeedVideo v);

/// Razlog zbog kojeg je epizoda izabrana kao featured.
enum FeaturedReason {
  /// Tier 1: ocijenjena, score ≥ 70, ≤ 14 dana. Najbolji slučaj.
  /// Bez domenske ocjene: potpuno obrađena (članak + poglavlja + govornici)
  /// i ≤ 14 dana.
  hiQualityRecent,

  /// Tier 2: ocijenjena, score ≥ 70, bilo koji datum.
  /// Bez domenske ocjene: potpuno obrađena, bilo koji datum.
  hiQuality,

  /// Tier 3: bilo koja ocijenjena epizoda (hasMagisterium).
  /// Bez domenske ocjene: članak + bar jedno od poglavlja/govornika.
  anyMagisterium,

  /// Tier 4: najnovija epizoda bez ikakve obrade.
  newest;

  String shortLabel(AppLocalizations l) {
    switch (this) {
      case FeaturedReason.hiQualityRecent:
        return l.homeReasonShortHiQualityRecent;
      case FeaturedReason.hiQuality:
        return l.homeReasonShortHiQuality;
      case FeaturedReason.anyMagisterium:
        return l.homeReasonShortAnyMagisterium;
      case FeaturedReason.newest:
        return l.homeReasonShortNewest;
    }
  }
}

/// Featured pick s objasnjenjem — koristi se i za render i za "Zasto?" dialog.
class FeaturedPick {
  final FeedVideo video;
  final FeaturedReason reason;
  final int? magisteriumScore;
  final int? daysAgo;
  final double? combinedScore;
  final int candidatePool;

  const FeaturedPick({
    required this.video,
    required this.reason,
    required this.candidatePool,
    this.magisteriumScore,
    this.daysAgo,
    this.combinedScore,
  });
}

/// Logika za feed sekcije na home screenu (hero, "Najnovije", itd.).
class HomeFeed {
  HomeFeed._();

  /// Epizoda je "spremna za homepage" kad ima generiran članak (`has_article`).
  ///
  /// Članak je zadnji AI korak prije nego pipeline uploada video + screenshotove
  /// na CDN, pa je `has_article` kanonski signal da epizoda ima sliku i sadržaj
  /// za prikaz (isti gate koristi i channel stranica). Channel index je namjerno
  /// permisivan i sadrži i tek-skinute, neobrađene epizode (`has_article:false`,
  /// bez članka/videa/slike) — homepage ih NE smije surfati u hero/"Najnovije".
  /// Channel stranica ih i dalje prikazuje, ali s oznakom "još u obradi".
  static bool isReadyForHome(FeedVideo v) =>
      v.video.pipeline?.hasArticle ?? false;

  /// Epizoda je "tek pristigla" — pipeline je skinuo info + thumbnail, ali još
  /// nije producirao članak (`has_article:false`). Gledljiva je (YouTube), ali
  /// bez sažetka/članka/Magisterium analize. Suprotno od [isReadyForHome] —
  /// ove se NE pojavljuju u "Najnovije epizode", nego u zasebnom "Upravo stiglo"
  /// railu s "U obradi" oznakom.
  static bool isFreshUnprocessed(FeedVideo v) =>
      !(v.video.pipeline?.hasArticle ?? false);

  /// Smije li epizoda na naslovnicu: vlasnik kanala nije isključio
  /// `home_featured` (ni povukao kanal). Kanal ostaje u `/channels`, na
  /// `/c/` i u korisnikovim popisima — ovo filtrira samo urednički izbor
  /// (hero, railovi). Bez retka postavki uvijek `true`.
  static bool isAllowedOnHome(FeedVideo v) =>
      channelCache.channelAllows(v.channelId, ChannelKey.homeFeatured);

  /// [all] bez epizoda kanala kojima je isključen `home_featured`. Isti
  /// popis (bez kopiranja) kad nijedan kanal nema ograničenje.
  static List<FeedVideo> onlyHomeAllowed(List<FeedVideo> all) =>
      ChannelVisibility.instance.snapshot.isEmpty
          ? all
          : all.where(isAllowedOnHome).toList();

  /// Zadana domenska ocjena aktivnog brenda: Magisterium score kad je
  /// `flags.domainScore` upaljen, inače `null` (ranker pada na potpunost
  /// obrade). Čita se pri svakom pozivu, pa test smije mijenjati brend kroz
  /// `AppBrand.init`.
  static ScoreFn? get defaultScore =>
      AppBrand.config.flags.domainScore ? magisteriumScore : null;

  /// Magisterium ocjena iz channel listinga. Ocijenjena je samo epizoda s
  /// `has_magisterium`; njoj `magisterium_score` po pipelineu uvijek postoji
  /// (izmjereno 18. 9. 2026. nad 49 kanala / 3227 epizoda: 316 s oznakom,
  /// 0 bez ocjene), a `?? 0` čuva staro pravilo „oznaka bez ocjene = tier 3”.
  static int? magisteriumScore(FeedVideo v) =>
      (v.video.pipeline?.hasMagisterium ?? false)
          ? (v.video.magisteriumScore ?? 0)
          : null;

  /// Epizoda ima poglavlja — channel listing nema zasebnu outline zastavicu
  /// (ključevi `pipeline` bloka izmjereni 18. 9. 2026.: transcript, diarized,
  /// summary, article, magisterium + EN varijante), pa je `has_summary`
  /// (sažetak s pregledom tema) najbliži signal.
  static bool hasChapters(FeedVideo v) => v.video.pipeline?.hasSummary ?? false;

  /// Epizoda ima identificirane govornike — diarizacija ili popis govornika
  /// u listingu.
  static bool hasSpeakers(FeedVideo v) =>
      (v.video.pipeline?.hasDiarized ?? false) || v.video.speakers.isNotEmpty;

  /// Potpunost obrade 0–3: članak, poglavlja, govornici. Bez članka je 0 bez
  /// obzira na ostalo — članak je gate za naslovnicu ([isReadyForHome]).
  static int completeness(FeedVideo v) {
    if (!isReadyForHome(v)) return 0;
    return 1 + (hasChapters(v) ? 1 : 0) + (hasSpeakers(v) ? 1 : 0);
  }

  /// Featured pick s razlogom. Algoritam (4-tier fallback):
  ///
  /// 1. **Hi-quality recent** — `score≥70 && ≤14 dana`, sortirano po
  ///    `score*0.6 + recencyScore*0.4`. Najbolji izbor jer kombinira
  ///    kvalitetu i svjezinu.
  /// 2. **Hi-quality** — `score≥70`, bilo koji datum. Sortirano po score desc.
  /// 3. **Any magisterium** — bilo koja ocijenjena epizoda, sortirano
  ///    po datumu desc.
  /// 4. **Newest** — najnovija epizoda uopce.
  ///
  /// Bez domenske ocjene (`score == null`) tierovi 1–3 rangiraju po potpunosti
  /// obrade — vidi [pickFeaturedCarousel].
  ///
  /// Vraca null ako je `all` prazan.
  ///
  /// Implementiran kao prvi element [pickFeaturedCarousel] — time je jedan-pick
  /// (npr. TV hero) uvijek identičan prvom slideu web hero karusela.
  static FeaturedPick? pickFeatured(
    List<FeedVideo> all, {
    ScoreFn? score,
    bool useDefaultScore = true,
    DateTime? now,
  }) {
    final picks = pickFeaturedCarousel(all,
        score: score, useDefaultScore: useDefaultScore, now: now);
    return picks.isEmpty ? null : picks.first;
  }

  /// Featured **uži izbor** za hero karusel — vraca do [limit] kandidata
  /// (poredanih) umjesto jednog picka. Prvi element je isti kao [pickFeatured]
  /// (današnji dnevni pick), ostali slijede po rangu pa rotiraju natrag.
  ///
  /// [score] je domenska ocjena; kad nije zadan, a [useDefaultScore] je
  /// `true`, uzima se [defaultScore] aktivnog brenda. `useDefaultScore: false`
  /// bez [score] znači „bez domenske ocjene” (testovi, brendovi bez ocjene).
  /// [now] je referentno vrijeme za svježinu i dnevnu rotaciju — zadano
  /// `DateTime.now()`; testovi ga zadaju da budu deterministički.
  ///
  /// S domenskom ocjenom (DOMOVINA, `flags.domainScore`):
  /// 1. **Hi-quality recent** — `score≥70 && ≤14 dana`, sortirano po
  ///    `score*0.6 + recencyScore*0.4`; dnevna rotacija određuje koji je
  ///    kandidat prvi (hero se mijenja u ponoc, deterministicki).
  /// 2. **Hi-quality** — `score≥70`, sortirano po score desc (datum desc za
  ///    jednake ocjene).
  /// 3. **Any magisterium** — bilo koja ocijenjena, sortirano po datumu desc.
  /// 4. **Newest** — najnovije spremne epizode.
  ///
  /// Bez domenske ocjene (`score == null`) ocjenu zamjenjuje potpunost obrade
  /// ([completeness]: članak + poglavlja + govornici), preslikana na 0–100
  /// (3 → 100, 2 → 50; samo članak ili bez članka → neocijenjena):
  /// 1. **Hi-quality recent** — potpuno obrađena i ≤ 14 dana, sortirano po
  ///    svježini (formula je ista, ocjena je svima 100) + dnevna rotacija.
  /// 2. **Hi-quality** — potpuno obrađena, bilo koji datum, datum desc.
  /// 3. **Any magisterium** — članak + bar jedno od poglavlja/govornika,
  ///    datum desc.
  /// 4. **Newest** — najnovije spremne epizode (nepromijenjeno).
  ///
  /// Vraca praznu listu ako je `all` prazan.
  ///
  /// Kad brend ističe kanale ([featuredChannels], zadano
  /// `BrandConfig.featuredChannels`), prvih do [featuredSlots] slideova bira
  /// isti algoritam samo nad epizodama tih kanala, a ostatak do [limit] nad
  /// svim ostalima. Bez istaknutih kanala rezultat je nepromijenjen.
  /// Epizoda koja stoji prva u hero karuselu, a karusel se tada ne vrti
  /// (`--dart-define=HERO_PIN=<youtubeId>`). Samo za store screenshotove;
  /// u pravom buildu je prazna i ništa ne mijenja.
  static const heroPin = String.fromEnvironment('HERO_PIN');

  static List<FeaturedPick> pickFeaturedCarousel(
    List<FeedVideo> all, {
    int limit = 5,
    ScoreFn? score,
    bool useDefaultScore = true,
    DateTime? now,
    List<String>? featuredChannels,
    int featuredSlots = 3,
    String pin = heroPin,
  }) {
    all = onlyHomeAllowed(all);
    final picks = _pickFeaturedCarousel(all,
        limit: limit,
        score: score,
        useDefaultScore: useDefaultScore,
        now: now,
        featuredChannels: featuredChannels,
        featuredSlots: featuredSlots);
    if (pin.isEmpty) return picks;
    final pinned = all.where((v) => v.video.id == pin).firstOrNull;
    if (pinned == null) return picks;
    return [
      FeaturedPick(
          video: pinned,
          reason: FeaturedReason.newest,
          candidatePool: all.length),
      ...picks.where((p) => p.video.video.id != pin),
    ].take(limit).toList();
  }

  static List<FeaturedPick> _pickFeaturedCarousel(
    List<FeedVideo> all, {
    required int limit,
    ScoreFn? score,
    required bool useDefaultScore,
    DateTime? now,
    List<String>? featuredChannels,
    required int featuredSlots,
  }) {
    final featured = featuredChannels ?? AppBrand.config.featuredChannels;
    if (featured.isEmpty) {
      return _pickCarousel(all,
          limit: limit, score: score, useDefaultScore: useDefaultScore, now: now);
    }
    final inFeatured = all.where((v) => featured.contains(v.channelId)).toList();
    final head = [
      ..._pickCarousel(inFeatured.where(isReadyForHome).toList(),
        limit: featuredSlots < limit ? featuredSlots : limit,
        score: score,
        useDefaultScore: useDefaultScore,
        now: now),
    ];
    // Algoritam vraća samo najbolji tier; istaknuti kanali ipak pune sve
    // svoje slotove, dopunom najnovijim spremnim epizodama tih kanala.
    final slots = featuredSlots < limit ? featuredSlots : limit;
    if (head.length < slots) {
      final taken = head.map((p) => p.video.video.id).toSet();
      final extra = inFeatured
          .where(isReadyForHome)
          .where((v) => !taken.contains(v.video.id))
          .toList()
        ..sort((a, b) => (b.video.date ?? '').compareTo(a.video.date ?? ''));
      head.addAll(extra.take(slots - head.length).map((v) => FeaturedPick(
            video: v,
            reason: FeaturedReason.newest,
            candidatePool: inFeatured.length,
          )));
    }
    final rest = _pickCarousel(
        all.where((v) => !featured.contains(v.channelId)).toList(),
        limit: limit - head.length,
        score: score,
        useDefaultScore: useDefaultScore,
        now: now);
    return [...head, ...rest];
  }

  static List<FeaturedPick> _pickCarousel(
    List<FeedVideo> all, {
    required int limit,
    ScoreFn? score,
    bool useDefaultScore = true,
    DateTime? now,
  }) {
    if (all.isEmpty || limit <= 0) return const [];

    final scoreFn = score ?? (useDefaultScore ? defaultScore : null);
    final ref = now ?? DateTime.now();

    // Kvaliteta 0–100 ili null (neocijenjena) — domenska ocjena ili
    // potpunost obrade kad ocjene nema.
    int? qualityOf(FeedVideo v) {
      if (scoreFn != null) return scoreFn(v);
      // Samo članak (c == 1) je „neocijenjena” → tier 4, ne tier 3.
      final c = completeness(v);
      return c <= 1 ? null : (c - 1) * 50;
    }

    int? daysAgoFor(String? date) {
      if (date == null) return null;
      try {
        return ref.difference(DateTime.parse(date)).inDays;
      } catch (_) {
        return null;
      }
    }

    double recencyScore(int? daysAgo) {
      if (daysAgo == null) return 0;
      if (daysAgo < 0) return 100;
      if (daysAgo > 14) return 0;
      return 100 - (daysAgo * 7).toDouble();
    }

    double combinedFor(FeedVideo v) =>
        (qualityOf(v) ?? 0) * 0.6 + recencyScore(daysAgoFor(v.video.date)) * 0.4;


    // Tier 1 — Najbolji izbor, s dnevnom rotacijom kroz top N kandidata.
    final hiQualityRecent = all.where((v) {
      final q = qualityOf(v) ?? 0;
      final d = daysAgoFor(v.video.date);
      return q >= 70 && d != null && d <= 14;
    }).toList();

    if (hiQualityRecent.isNotEmpty) {
      hiQualityRecent.sort((a, b) {
        final cmp = combinedFor(b).compareTo(combinedFor(a));
        return cmp != 0 ? cmp : newestFirst(a, b);
      });
      // Izvuci top N i seedaj početak po danu u godini. Karusel počinje od
      // današnjeg dnevnog picka pa nastavlja po rangu (i rotira natrag), tako
      // da je prvi slide deterministicki isti tijekom dana.
      final topN = hiQualityRecent.take(limit).toList();
      final dayOfYear = ref.difference(DateTime(ref.year)).inDays;
      final start = dayOfYear % topN.length;
      final ordered = [...topN.sublist(start), ...topN.sublist(0, start)];
      return ordered.map((v) {
        return FeaturedPick(
          video: v,
          reason: FeaturedReason.hiQualityRecent,
          magisteriumScore: scoreFn?.call(v),
          daysAgo: daysAgoFor(v.video.date),
          combinedScore: combinedFor(v),
          candidatePool: hiQualityRecent.length,
        );
      }).toList();
    }

    // Tier 2
    final hiQuality = all.where((v) => (qualityOf(v) ?? 0) >= 70).toList();
    if (hiQuality.isNotEmpty) {
      hiQuality.sort((a, b) {
        final cmp = (qualityOf(b) ?? 0).compareTo(qualityOf(a) ?? 0);
        return cmp != 0 ? cmp : newestFirst(a, b);
      });
      return hiQuality
          .take(limit)
          .map((v) => FeaturedPick(
                video: v,
                reason: FeaturedReason.hiQuality,
                magisteriumScore: scoreFn?.call(v),
                daysAgo: daysAgoFor(v.video.date),
                candidatePool: hiQuality.length,
              ))
          .toList();
    }

    // Tier 3 — bilo koja ocijenjena (ili, bez ocjene, djelomično obrađena).
    final scored = all.where((v) => qualityOf(v) != null).toList();
    if (scored.isNotEmpty) {
      scored.sort(newestFirst);
      return scored
          .take(limit)
          .map((v) => FeaturedPick(
                video: v,
                reason: FeaturedReason.anyMagisterium,
                magisteriumScore: scoreFn?.call(v),
                daysAgo: daysAgoFor(v.video.date),
                candidatePool: scored.length,
              ))
          .toList();
    }

    // Tier 4 — najnovije SPREMNE epizode (imaju članak). Neobrađene epizode iz
    // permisivnog channel indexa se preskaču. Fallback na cijeli `all` samo u
    // degeneriranom slučaju (nijedna epizoda nema članak — npr. svjež katalog),
    // da homepage ipak nije prazan.
    final readyPool = all.where(isReadyForHome).toList();
    final pool = readyPool.isNotEmpty ? readyPool : all;
    final sorted = List<FeedVideo>.from(pool)..sort(newestFirst);
    return sorted
        .take(limit)
        .map((v) => FeaturedPick(
              video: v,
              reason: FeaturedReason.newest,
              magisteriumScore: scoreFn?.call(v),
              daysAgo: daysAgoFor(v.video.date),
              candidatePool: pool.length,
            ))
        .toList();
  }

  /// Najnovije prvo, uz deterministički tie-break.
  ///
  /// `date` je dan (`YYYY-MM-DD`), pa više epizoda istog dana ima jednak ključ.
  /// Bazen ([ChannelCache.feedVideos]) je složen redom kojim su listinzi kanala
  /// STIGLI, a taj je red na svakom učitavanju drukčiji — bez tie-breaka su se
  /// kartice istog dana premetale sa svakim novim listingom i rail „Najnovije
  /// epizode" je treperio (prijava 9.10.2026.). `id` nema značenje, ali je
  /// stabilan: isti bazen uvijek daje isti redoslijed.
  static int newestFirst(FeedVideo a, FeedVideo b) {
    final byDate = (b.video.date ?? '').compareTo(a.video.date ?? '');
    return byDate != 0 ? byDate : a.video.id.compareTo(b.video.id);
  }

  /// "Najnovije epizode" rail — cross-channel sortirano po datumu desc.
  static List<FeedVideo> latestEpisodes(List<FeedVideo> all,
      {int limit = 20, FeedVideo? excludeFeatured}) {
    // Samo spremne epizode (s člankom) — neobrađene iz permisivnog channel
    // indexa se ne prikazuju u "Najnovije epizode".
    final filtered = onlyHomeAllowed(all)
        .where(isReadyForHome)
        .where((v) =>
            excludeFeatured == null || v.video.id != excludeFeatured.video.id)
        .toList();
    final sorted = List<FeedVideo>.from(filtered)
      ..sort(newestFirst);
    return sorted.take(limit).toList();
  }

  /// Rail istaknutih kanala brenda — najnovije spremne epizode, naizmjence po
  /// kanalu redoslijedom iz [featuredChannels] (zadano
  /// `BrandConfig.featuredChannels`), da jedan plodan kanal ne zauzme cijeli
  /// rail. Prazna lista kad brend ništa ne ističe.
  static List<FeedVideo> featuredShows(List<FeedVideo> all,
      {int limit = 12,
      FeedVideo? excludeFeatured,
      List<String>? featuredChannels}) {
    final featured = featuredChannels ?? AppBrand.config.featuredChannels;
    if (featured.isEmpty) return const [];
    all = onlyHomeAllowed(all);
    final queues = [
      for (final id in featured)
        all
            .where((v) => v.channelId == id)
            .where(isReadyForHome)
            .where((v) =>
                excludeFeatured == null ||
                v.video.id != excludeFeatured.video.id)
            .toList()
          ..sort(newestFirst),
    ];
    final out = <FeedVideo>[];
    for (var i = 0; out.length < limit; i++) {
      var added = false;
      for (final q in queues) {
        if (i < q.length && out.length < limit) {
          out.add(q[i]);
          added = true;
        }
      }
      if (!added) break;
    }
    return out;
  }

  /// "Upravo stiglo" rail — tek pristigle epizode (info + thumbnail, bez
  /// članka) sortirano po datumu desc. Kronološki su među najnovijima, ali ih
  /// "Najnovije epizode" sakriva jer nemaju članak. Ovdje ih surfamo gledljive
  /// uz "U obradi" oznaku.
  ///
  /// Gate na svježinu ([maxAgeDays]) sprječava da stari, nikad-obrađeni stubovi
  /// iz permisivnog channel indexa zatrpaju rail — prikazuju se samo epizode
  /// koje su doista nedavno pristigle. Zahtijeva i datum i thumbnail signal
  /// (svaka epizoda u listingu ima thumbnail URL, pa je dovoljan datum).
  static List<FeedVideo> freshlyArrived(List<FeedVideo> all,
      {int limit = 12, int maxAgeDays = 30, FeedVideo? excludeFeatured}) {
    final now = DateTime.now();
    bool recent(String? date) {
      if (date == null) return false;
      try {
        final d = now.difference(DateTime.parse(date)).inDays;
        return d <= maxAgeDays;
      } catch (_) {
        return false;
      }
    }

    final filtered = onlyHomeAllowed(all)
        .where(isFreshUnprocessed)
        .where((v) => recent(v.video.date))
        .where((v) =>
            excludeFeatured == null || v.video.id != excludeFeatured.video.id)
        .toList();
    final sorted = List<FeedVideo>.from(filtered)
      ..sort(newestFirst);
    return sorted.take(limit).toList();
  }

  /// Prozor svježine za tier 1 hero izbora (dana).
  static const int heroRecentDays = 14;

  static bool _isHiQualityRecent(FeedVideo v, DateTime now) {
    // Tier 1 bez domenske ocjene ide po potpunosti obrade, pa rani zaključak
    // o konačnom bazenu ovdje ne vrijedi — takav brend čeka `done`.
    if (!AppBrand.config.flags.domainScore) return false;
    final score = v.video.magisteriumScore ?? 0;
    final hasMag = v.video.pipeline?.hasMagisterium ?? false;
    final date = DateTime.tryParse(v.video.date ?? '');
    if (date == null) return false;
    return hasMag && score >= 70 && now.difference(date).inDays <= heroRecentDays;
  }

  /// Je li bazen hero izbora **dokazivo konačan** prije nego je prefetch
  /// svih kanala gotov.
  ///
  /// Najbrži put je `home.json` (`HomeSnapshot`), koji po ugovoru nosi sve
  /// kandidate. Bez njega:
  ///
  /// `index.json` nosi datum zadnje epizode svakog kanala
  /// (`latest_video.date`, izmjereno 9.10.2026.: na svih 50 kanala jednak
  /// najnovijem datumu u listingu). Kanal čija je zadnja epizoda starija od
  /// [heroRecentDays] ne može dati tier 1 kandidata, pa kad su učitani svi
  /// kanali koji MOGU (tog dana 11 od 50), nijedan kanal koji stigne kasnije
  /// više ne mijenja tier 1 — a samim tim ni izbor, jer se tier 2–4 koriste
  /// samo kad je tier 1 prazan.
  ///
  /// Zato vrijedi samo uz neprazan tier 1. Prazan tier 1 znači pad na tier 2
  /// („bilo koji datum"), koji traži cijeli katalog → čeka se `done`. Kanal
  /// bez datuma ili s nečitljivim datumom tretira se kao „može" (ne
  /// zaključujemo iz izostanka podatka). Kanal kojem dohvat padne nikad nije
  /// učitan, pa i tada odlučuje `done`.
  static bool heroPoolComplete(ChannelCache cache, {DateTime? now}) {
    // `home.json` po ugovoru nosi sve tier 1/2 kandidate (`HomeSnapshot`).
    if (cache.done || cache.homeSnapshot != null) return true;
    final index = cache.index;
    if (index == null) return false;
    final at = now ?? DateTime.now();
    for (final c in index.channels) {
      if (cache.isLoaded(c.id)) continue;
      final latest = DateTime.tryParse(c.latestVideo?.date ?? '');
      if (latest == null) return false;
      if (at.difference(latest).inDays <= heroRecentDays) return false;
    }
    return onlyHomeAllowed(cache.allVideos)
        .any((v) => _isHiQualityRecent(v, at));
  }

  /// Provjeri ima li dovoljno podataka da feed nije prazan/skeleton.
  static bool hasMinimumData(ChannelCache cache) {
    if (cache.homeSnapshot != null) return true;
    if (cache.total == 0) return false;
    return cache.loaded >= (cache.total * 0.3).ceil() || cache.done;
  }
}
