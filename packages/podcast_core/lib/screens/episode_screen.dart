import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderViewport, ScrollDirection;
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:go_router/go_router.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../l10n/app_localizations.dart';
import '../brand/app_brand.dart';
import '../src/log.dart' show log;
import '../models/channel_detail.dart' show ChannelVideo;
import '../models/episode_status.dart';
import '../models/person_hub.dart' show personSlug;
import '../models/podcast_article.dart' show PodcastSection;
import '../models/sponsored_moment.dart';
import '../models/sponsors_in_video.dart';
import '../services/sponsored_moments_controller.dart';
import '../services/sponsored_moments_service.dart';
import '../services/background_audio.dart';
import '../services/clip_service.dart' show ClipService;
import '../services/deferred_screenshots.dart';
import '../services/background_playback.dart';
import '../services/episode_language.dart';
import '../services/share_links.dart';
import '../services/media_session.dart';
import '../services/channel_cache.dart';
import '../services/data_service.dart';
import '../services/cdn_config.dart';
import '../services/ebook_service.dart';
import '../services/notification_art.dart';
import '../services/open_url.dart';
import '../services/player_resume.dart';
import '../services/page_meta.dart';
import '../services/person_service.dart';
import '../services/playback_intent.dart';
import '../services/playback_speed.dart';
import '../services/player_mute.dart';
import '../services/remote_playback.dart';
import '../services/seek_undo.dart';
import '../services/analytics/playback_analytics.dart';
import '../services/url_sync.dart';
import '../services/view_mode.dart';
import '../services/watch_progress_service.dart';
import '../widgets/anonymous_signin_bar.dart';
import '../widgets/favorite_button.dart';
import '../widgets/hero_section.dart';
import '../widgets/language_toggle_chip.dart';
import '../pinka_sdk/pinka_sdk.dart';
import '../widgets/summary_section.dart';
import '../widgets/sponsors_in_video_section.dart';
import '../widgets/chapters_section.dart';
import '../widgets/find_in_episode_section.dart';
import '../widgets/article_section.dart';
import '../widgets/magisterium_panel.dart';
import '../widgets/magisterium_v2_view.dart';
import '../widgets/parallel_article_view.dart';
import '../widgets/person_needle_highlight.dart' show hasPersonMention;
import '../widgets/entities_section.dart';
import '../widgets/ebook_sheet.dart';
import '../widgets/episode_status_card.dart';
import '../widgets/youtube_embed.dart';
import '../widgets/resume_hint_banner.dart';
import '../widgets/table_of_contents.dart';
import '../widgets/episode_panel_canvas.dart';
import '../widgets/video_panel.dart';
import '../widgets/view_mode_toggle_button.dart';
import '../router/nav.dart';

class EpisodeScreen extends StatefulWidget {
  final String youtubeId;

  /// Start at position in seconds (from ?t= query param, like YouTube).
  final int? startAtSeconds;

  /// Postavljeno na true kad URL eksplicitno sadrzi `/en` sufiks — overrideuje
  /// sticky pref. Ostavljeno null/false znaci: koristi sticky pref ili HR default.
  final bool initialLanguageEn;

  /// Person slug iz `?p=<slug>` (dolazak s /p/ profila govornika) — sekcija na
  /// koju `/t/<sec>` sleti dobiva crvenu "X govori ovdje" oznaku u članku.
  final String? highlightPersonSlug;

  /// Video panel (endDrawer) kad je video spreman, iz `?video=`:
  /// `null` (bez parametra) — otvori sam samo na užem ekranu;
  /// `false` (`?video=0`) — ne otvaraj, članak ostaje vidljiv;
  /// `true` (`?video=1`) — otvori na svakoj širini, i na tabletu.
  /// Za linkove na članak ili player i za store screenshotove
  /// (`scripts/store-screenshots.sh` u Podcasterium shellu).
  final bool? openVideo;

  const EpisodeScreen({
    super.key,
    required this.youtubeId,
    this.startAtSeconds,
    this.initialLanguageEn = false,
    this.highlightPersonSlug,
    this.openVideo,
  });

  @override
  State<EpisodeScreen> createState() => _EpisodeScreenState();
}

class _EpisodeScreenState extends State<EpisodeScreen> {
  EpisodeData? _data;
  Object? _error;
  final Map<String, (bool done, bool ok)> _assetStatus = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  /// Ruta više ne nosi `startAt`/`person` u `ValueKey`-u (vidi app_router.dart),
  /// pa isti `State` može dobiti novi `youtubeId` samo kad go_router zadrži
  /// stranicu istog ključa — a to se događa jedino pri promjeni jezika
  /// (`/v/<id>` ↔ `/v/<id>/en` imaju RAZLIČIT ključ, dakle ne). Guard je ipak
  /// tu jer bi tiho prikazivanje stare epizode pod novim ID-em bilo teško uočiti.
  @override
  void didUpdateWidget(EpisodeScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.youtubeId != widget.youtubeId) {
      _data = null;
      _error = null;
      _assetStatus.clear();
      _load();
    }
  }

  Future<void> _load() async {
    try {
      final data = await EpisodeData.loadWithProgress(
        youtubeId: widget.youtubeId,
        onProgress: (asset, done, ok) {
          if (mounted) setState(() => _assetStatus[asset] = (done, ok));
        },
        // Članak se crta prije titlova; oni stignu kao zamjena podataka.
        // `_EpisodeContent` ih čita samo u buildu, pa zamjena ne dira player.
        onTimeline: (full) {
          if (mounted && _data?.youtubeId == full.youtubeId) {
            setState(() => _data = full);
          }
        },
      );
      if (mounted) {
        setState(() => _data = data);
        // Runtime <title>/og meta za živu SPA sesiju — isti format kao
        // worker edge-inject za /v/ (crawleri i dalje idu kroz _worker.js).
        setPageMeta(
          title: data.displayTitle,
          description: data.summary?.summary.abstractHr,
        );
      }
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_data != null) {
      return _EpisodeContent(
        data: _data!,
        startAtSeconds: widget.startAtSeconds,
        initialLanguageEn: widget.initialLanguageEn,
        highlightPersonSlug: widget.highlightPersonSlug,
        openVideo: widget.openVideo,
      );
    }

    if (_error != null) {
      // `info.json` 404 ne znaci nuzno da epizoda ne postoji — moze biti tek
      // registrirana u channel listingu, a jos nepreuzeta (faza `queued`).
      // Takvu prepoznaje i objasni _QueuedEpisodeScreen; sve ostalo je greska.
      if (_error is VideoNotFoundException) {
        return _QueuedEpisodeScreen(youtubeId: widget.youtubeId);
      }
      final theme = Theme.of(context);
      final l = AppLocalizations.of(context);
      return Scaffold(
        backgroundColor: theme.colorScheme.surfaceContainerLow,
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.error_outline, size: 48, color: Colors.red),
                  const SizedBox(height: 12),
                  Text(l.episodeLoadError('$_error'), textAlign: TextAlign.center),
                  const SizedBox(height: 20),
                  FilledButton.icon(
                    onPressed: () => context.go('/'),
                    icon: const Icon(Icons.arrow_back),
                    label: Text(l.commonBack),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    // Loading screen with per-asset progress
    return _LoadingScreen(
      youtubeId: widget.youtubeId,
      assetStatus: _assetStatus,
    );
  }
}

/// Ekran za epizodu koja je u katalogu, ali kod nas jos nema NIJEDNU datoteku
/// (`info.json` vraca 404) — faza [EpisodeStage.queued].
///
/// Dosad je takva epizoda zavrsavala na generickom "nije pronadena na CDN-u",
/// sto je bilo i netocno (epizoda POSTOJI, vidi se u railu "Upravo stiglo") i
/// slijepa ulica. Naslov, kanal i sliku uzimamo iz channel listinga, jedinog
/// mjesta gdje takva epizoda uopce postoji, a reprodukciju nudimo kroz
/// ugradeni YouTube player.
///
/// **Rule**: embed se nudi SAMO ako je ID nasao svoj red u channel listingu.
/// Bez te provjere bi `/v/<bilo-koji-YouTube-ID>` ugradivao proizvoljan tudi
/// video pod nasim brandom.
class _QueuedEpisodeScreen extends StatefulWidget {
  final String youtubeId;

  const _QueuedEpisodeScreen({required this.youtubeId});

  @override
  State<_QueuedEpisodeScreen> createState() => _QueuedEpisodeScreenState();
}

class _QueuedEpisodeScreenState extends State<_QueuedEpisodeScreen> {
  ({String channelId, String channelName, ChannelVideo video})? _listed;
  bool _searching = true;

  @override
  void initState() {
    super.initState();
    _find();
  }

  Future<void> _find() async {
    final hit = await channelCache.findVideoAsync(widget.youtubeId);
    if (!mounted) return;
    setState(() {
      _listed = hit;
      _searching = false;
    });
    if (hit != null) {
      setPageMeta(title: hit.video.displayTitle);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l = AppLocalizations.of(context);
    final listed = _listed;

    if (_searching) {
      return Scaffold(
        backgroundColor: theme.colorScheme.surfaceContainerLow,
        body: const SafeArea(child: Center(child: CircularProgressIndicator())),
      );
    }

    // ID nije ni u jednom kanalu — to je prava 404, ne epizoda u obradi.
    if (listed == null) {
      return _NotFoundScreen(youtubeId: widget.youtubeId);
    }

    // Isti raspored kao basic layout: na širokom ekranu player desno, status
    // lijevo. Prag je isti (1100) da prijelaz između faza ne pomiče stupce.
    final wide = MediaQuery.sizeOf(context).width > 1100;

    final content = SingleChildScrollView(
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 860),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  listed.video.displayTitle,
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  listed.video.date ?? listed.channelName,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 16),
                if (!wide) ...[
                  InAppYouTubePlayer(
                    videoId: widget.youtubeId,
                    posterUrl: CdnConfig.thumbnailUrl(widget.youtubeId),
                  ),
                  const SizedBox(height: 20),
                ],
                EpisodeStatusCard(
                  status: EpisodeStatus.measured(
                    hasInfo: false,
                    hasMedia: false,
                    hasTranscript: false,
                    hasSummary: false,
                    hasArticle: false,
                    hasMagisterium: false,
                  ),
                  footnote: l.episodeStatusNotOnCdn(widget.youtubeId),
                ),
                const SizedBox(height: 16),
                TextButton.icon(
                  onPressed: () => openUrl(
                    'https://www.youtube.com/watch?v=${widget.youtubeId}',
                  ),
                  icon: const Icon(Icons.open_in_new, size: 18),
                  label: Text(l.episodeOpenOnYouTube),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    return Scaffold(
      backgroundColor: theme.colorScheme.surfaceContainerLow,
      appBar: AppBar(
        title: _Breadcrumb(
          channelName: listed.channelName,
          channelSlug: listed.channelId,
          episodeTitle: listed.video.displayTitle,
        ),
        titleSpacing: 0,
      ),
      body: SafeArea(
        top: false,
        child: wide
            ? Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: content),
                  _YouTubeSidePanel(youtubeId: widget.youtubeId),
                ],
              )
            : content,
      ),
    );
  }
}

/// Prava 404 — ID ne postoji ni na CDN-u ni u jednom channel listingu.
class _NotFoundScreen extends StatelessWidget {
  final String youtubeId;

  const _NotFoundScreen({required this.youtubeId});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l = AppLocalizations.of(context);
    return Scaffold(
      backgroundColor: theme.colorScheme.surfaceContainerLow,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.video_file_outlined, size: 48),
                const SizedBox(height: 12),
                Text(
                  l.episodeNotFoundDetailed(youtubeId),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 20),
                Text(
                  CdnConfig.infoUrl(youtubeId),
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 20),
                FilledButton.icon(
                  onPressed: () => context.go('/'),
                  icon: const Icon(Icons.arrow_back),
                  label: Text(l.commonBack),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Desni stupac s ugrađenim YouTube playerom — zamjena za [VideoPanel] na
/// epizodama kojima medija još nije kod nas.
///
/// Zašto stupac a ne inline blok: na širokom ekranu je desna strana mjesto na
/// kojem korisnik i inače očekuje player (ondje stoji `VideoPanel`), a status
/// kartica s koracima obrade time ostaje iznad pregiba umjesto da je 16:9 blok
/// gurne dolje. Panel se ne skrola sa sadržajem — kao ni `VideoPanel`.
class _YouTubeSidePanel extends StatelessWidget {
  /// ID epizode — CDN poster (`images/<id>/`).
  final String youtubeId;

  /// Pravi YouTube video ID za player. Za varijantu epizode razlikuje se od
  /// [youtubeId] (sintetički) — vidi `EpisodeData.youtubeVideoId`.
  final String videoId;

  /// Isti raspon kao `VideoPanel` (360), ali malo širi jer je ovdje player
  /// jedini sadržaj stupca, a YouTube kontrole na 360 dp postaju skučene.
  static const double width = 440;

  const _YouTubeSidePanel({required this.youtubeId, String? videoId})
    : videoId = videoId ?? youtubeId;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l = AppLocalizations.of(context);

    // Bez ispune i bez lijevog ruba: `VideoPanel` ih nosi jer je gust panel s
    // kontrolama i poglavljima, a ovdje je sadržaj samo player — obrub na
    // svijetloj temi ispadne bijela crta koja siječe stranicu ni zbog čega.
    return SizedBox(
      width: width,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: InAppYouTubePlayer(
              videoId: videoId,
              posterUrl: CdnConfig.thumbnailUrl(youtubeId),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: Row(
              children: [
                const Icon(Icons.smart_display, size: 16, color: Color(0xFFFF0000)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    l.episodeYouTubeUntilProcessed,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _LoadingScreen extends StatelessWidget {
  final String youtubeId;
  final Map<String, (bool done, bool ok)> assetStatus;

  const _LoadingScreen({required this.youtubeId, required this.assetStatus});

  /// Imena asseta iz `EpisodeData.loadWithProgress` su hrvatski ključevi;
  /// ovdje ih prevodimo na UI jezik. Magisterium i Info su vlastita imena.
  static String _assetLabel(String key, AppLocalizations l) {
    final en = key.endsWith(' (EN)');
    final base = en ? key.substring(0, key.length - 5) : key;
    final label = switch (base) {
      'Sažetak' => l.sectionSummary,
      'Poglavlja' => l.sectionChapters,
      'Članak' => l.sectionArticle,
      'Transkript' => l.episodeStepTranscript,
      _ => base,
    };
    return en ? '$label (EN)' : label;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l = AppLocalizations.of(context);
    final doneCount = assetStatus.values.where((s) => s.$1).length;
    final totalCount = assetStatus.isEmpty ? 7 : assetStatus.length;
    final progress = totalCount > 0 ? doneCount / totalCount : 0.0;

    return Scaffold(
      backgroundColor: theme.colorScheme.surfaceContainerLow,
      body: SafeArea(
        child: Center(
          // Scroll: popis datoteka je viši od mobitela u landscapeu (375 pt)
          // — bez njega stupac je probijao dno za 241 px (smoke test
          // 13.10.2026. na iPhone 12 mini).
          child: SingleChildScrollView(
            child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Progress ring
                  SizedBox(
                    width: 64,
                    height: 64,
                    child: CircularProgressIndicator(
                      value: assetStatus.isEmpty ? null : progress,
                      strokeWidth: 4,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    l.episodeLoading,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    youtubeId,
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontFamily: 'monospace',
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 20),
                  // Asset status list
                  ...assetStatus.entries.map((e) {
                    final (done, ok) = e.value;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 18,
                            height: 18,
                            child: done
                                ? Icon(
                                    ok
                                        ? Icons.check_circle
                                        : Icons.remove_circle_outline,
                                    size: 18,
                                    color: ok
                                        ? const Color(0xFF2E7D32)
                                        : theme.colorScheme.onSurfaceVariant
                                              .withAlpha(100),
                                  )
                                : const SizedBox(
                                    width: 14,
                                    height: 14,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  ),
                          ),
                          const SizedBox(width: 10),
                          Text(
                            _assetLabel(e.key, l),
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: done && !ok
                                  ? theme.colorScheme.onSurfaceVariant
                                        .withAlpha(100)
                                  : null,
                            ),
                          ),
                        ],
                      ),
                    );
                  }),
                ],
              ),
            ),
          ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------

/// Trorazinski breadcrumb koji zamjenjuje obični channel-name title u app baru:
///
///   `Početna  ›  <Kanal>  ›  <Epizoda>`
///
/// Prva dva čvora su tap-abilni (`context.go`), epizoda je trenutni čvor
/// (bold, ne-klikabilan, ellipsis). Derivira se iz same epizode
/// (`info.channelId` / `info.channel`) pa radi neovisno o tome je li korisnik
/// stigao s homepagea, kanala ili izravnog deep-linka — uvijek nudi i "natrag
/// na Početnu" i "natrag na kanal". Navigacija ide preko `context.go` jer app
/// koristi go_router replace-semantiku (nema push stacka).
///
/// [channelSlug] je naš route-ready slug (npr. `muzevni-budite`), razriješen
/// preko `channelCache.channelIdForName` — NIJE YouTube UC… id iz
/// `info.channelId` (taj ne postoji kao `/c/:slug`). Dok se index ne učita
/// (deep-link) slug je null pa se kanal-čvor sakrije.
class _Breadcrumb extends StatelessWidget {
  final String channelName;
  final String? channelSlug;
  final String episodeTitle;

  const _Breadcrumb({
    required this.channelName,
    required this.channelSlug,
    required this.episodeTitle,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final slug = channelSlug;
    final hasChannel =
        slug != null && slug.isNotEmpty && channelName.isNotEmpty;
    final width = MediaQuery.sizeOf(context).width;
    // Mobitel (<600): breadcrumb je horizontalno skrolabilan i prikazuje PUNI
    // put (uklj. epizodu) — konzistentno sa skrolabilnim redom akcija. Na
    // tabletu/desktopu: Flexible + ellipsis, epizoda tek >760.
    final scrollable = width < 600;
    final showEpisode = scrollable || width > 760;

    Widget crumb(String label, {VoidCallback? onTap, bool current = false}) {
      Widget text = Text(
        label,
        maxLines: 1,
        softWrap: false,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.titleMedium?.copyWith(
          fontWeight: current ? FontWeight.w600 : FontWeight.w500,
          color: current ? theme.colorScheme.onSurface : muted,
        ),
      );
      if (onTap == null) return text;
      return InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          child: text,
        ),
      );
    }

    Widget sep() => Icon(Icons.chevron_right, size: 18, color: muted);

    // U scrollable modu NE koristimo Flexible (unbounded width u horizontalnom
    // scrollu bi pucao) — crumbovi idu na intrinzičnu širinu.
    Widget node(Widget child) => scrollable ? child : Flexible(child: child);

    final row = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        crumb(AppLocalizations.of(context).ownershipCrumbHome,
            onTap: () => context.go('/')),
        if (hasChannel) ...[
          sep(),
          node(
            crumb(
              channelName,
              onTap: () => context.go('/c/$slug'),
              // Kad epizodu skrivamo (širina 600–760), kanal je zadnji čvor.
              current: !showEpisode,
            ),
          ),
        ],
        if (showEpisode) ...[sep(), node(crumb(episodeTitle, current: true))],
      ],
    );

    // Rubnih 12px živi OVDJE (content padding unutar scrolla / Padding oko
    // statičnog reda), a _episodeAppBar ima titleSpacing: 0 — inače bi se
    // scrollabilni breadcrumb rezao 12px od ruba ekrana.
    if (scrollable) {
      return SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: row,
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: row,
    );
  }
}

class _EpisodeContent extends StatefulWidget {
  final EpisodeData data;
  final int? startAtSeconds;
  final bool initialLanguageEn;
  final String? highlightPersonSlug;
  final bool? openVideo;

  const _EpisodeContent({
    required this.data,
    this.startAtSeconds,
    this.initialLanguageEn = false,
    this.highlightPersonSlug,
    this.openVideo,
  });

  @override
  State<_EpisodeContent> createState() => _EpisodeContentState();
}

class _EpisodeContentState extends State<_EpisodeContent>
    with WidgetsBindingObserver {
  final _scrollController = ScrollController();
  late final Map<String, GlobalKey> _sectionKeys;
  late final Map<String, GlobalKey> _magSectionKeys;
  String? _activeTimestamp; // prati video player poziciju
  String? _scrollTimestamp; // prati scroll poziciju srednje liste

  /// True kad je aktivan paralelni desktop layout (sticky "Članak ‖ Magisterium"
  /// header). Postavlja se u build(); koristi ga _scrollToSection da odbije
  /// fixed pinned visinu (app bar + sticky header) pri scrollu na sekciju.
  bool _parallelActive = false;

  // Mobile tab switcher: 0 = članak, 1 = Magisterium.
  // Aktivan samo kad je !isWide && hasMag (inače nema tab bara).
  int _mobileTab = 0;

  /// Bočni stupci na uskom ekranu (sadržaj lijevo, player desno) — vidi
  /// [EpisodePanelCanvas]. Do 5.10.2026. su to bili Scaffold `drawer` i
  /// `endDrawer` preko članka.
  final _panelKey = GlobalKey<EpisodePanelCanvasState>();

  /// Sprjecava ponavljanje auto-open playera ako ga korisnik zatvori.
  bool _playerAutoOpened = false;

  // Video
  Player? _player;
  VideoController? _videoController;
  StreamSubscription<Duration>? _positionSub;
  StreamSubscription<bool>? _playingSub;
  bool _videoReady = false;

  /// Sortirane sekcije kao (Duration, timestampString) za sync Video→Text
  late final List<({Duration dur, String ts})> _sortedSections;

  /// Chapters za VideoPanel
  late final List<VideoChapterMark> _videoChapters;

  /// Sprječava auto-scroll iz video listenera dok korisnik ručno scrolla
  DateTime? _lastManualScroll;

  /// Sprjecava auto-sync activeTimestamp iz video position listenera
  /// tijekom rucnog klika na chapter (preroll seek, TOC klik, itd.)
  DateTime? _seekLock;
  static const _seekLockDuration = Duration(milliseconds: 2100);

  /// Kratki lock koji sprjecava scroll listener da overridea scrollTimestamp
  /// dok traje programatski scroll (auto-scroll iz video playbacka).
  DateTime? _scrollLock;

  /// URL sync — zadnja sekunda za koju smo update-ali address bar.
  /// Razlog: position stream fira ~5×/s; želimo update najviše 1×/s i samo
  /// kad se sekunda promijenila.
  int _lastUrlSyncedSec = -1;

  /// Inline resume hint — nije SnackBar (lingera preko ekrana), nego widget
  /// u Stack-u koji se uništava s screenom. null = sakriven.
  int? _resumeHintSeconds;
  Timer? _resumeHintTimer;
  static const _resumeHintDuration = Duration(seconds: 4);

  /// Odgovor na „želi li korisnik da ovo svira?". Ožičen na
  /// `player.stream.playing` (jedini izvor koji hvata i media_kitove interne
  /// kontrole), s prozorom tolerancije oko poznatih framework tranzicija —
  /// fullscreen re-parent i odlazak u pozadinu (SurfaceView teardown). Zamjenjuje raniji snapshot
  /// „je li svirao kad je drawer otvoren", koji je poništavao korisnikovu
  /// Pauzu ako je stisnuta dok je drawer bio otvoren.
  /// Vidi `services/playback_intent.dart`.
  PlaybackIntent? _playbackIntent;

  /// „Vrati me gdje sam bio" nakon ručnog skoka po timelineu. Programske
  /// skokove (resume pri otvaranju, tap na poglavlje — odluka D2) najavljujemo
  /// kroz `suppress()`. Vidi `services/seek_undo.dart`.
  SeekUndo? _seekUndo;
  PlaybackAnalytics? _playbackAnalytics;

  /// Per-episode jezik prikaza. URL `/en` sufix ima prednost nad sticky pref.
  /// Inicijalno HR; ako URL nije EN, ucitaj sticky pref iz prefs-a.
  EpisodeLanguage _language = EpisodeLanguage.hr;

  /// Naš route-ready channel slug (npr. `muzevni-budite`) za breadcrumb `/c/`
  /// link. Razrješava se iz channel indexa po imenu kanala (vidi
  /// `_resolveChannelSlug`). Null dok se index ne učita ili ako nema matcha —
  /// breadcrumb tada sakrije kanal-čvor.
  String? _channelSlug;

  /// Cover-art za audio-only epizode (CORS-safe channel avatar square).
  /// Razrješava se iz channel indexa u [_resolveChannelSlug].
  String? _audioArtUrl;

  /// Person-highlight marker (dolazak s /p/ profila preko `?p=<slug>`):
  /// timestamp sekcije za pill oznaku + razriješeno ime osobe (needle za
  /// inline highlight u tekstu svih sekcija). Pill se prikaže samo kad je
  /// tvrdnja provjerljiva: osoba je diarizirani govornik ("govori ovdje") ILI
  /// ciljna sekcija stvarno sadrži spomen imena ("ovdje se spominje").
  /// Vidi [_initPersonHighlight].
  String? _personHighlightTs;
  String? _personHighlightName;
  bool _personHighlightSpeaks = false;

  /// EPUB e-knjiga epizode — MJERI se HEAD probe-om (vidi [EbookService]), pa
  /// je do odgovora prazna i nijedna ebook površina se ne prikazuje. Nije u
  /// [EpisodeData.load] da ne produžuje kritični put ekrana: knjiga je dodatak,
  /// a ne uvjet da se epizoda prikaže.
  EbookAvailability _ebook = EbookAvailability.none;

  /// Sponzori ugrađeni u snimku (`sponsors_in_video.json`). Kao i e-knjiga,
  /// dohvaćaju se lijeno i izvan [EpisodeData.load] — sekcija je dodatak i ne
  /// smije usporiti prvi prikaz ni srušiti ekran; do odgovora (ili zauvijek,
  /// na 404/grešku) je null i sekcije nema.
  SponsorsInVideo? _sponsorsInVideo;

  /// „Poslušaj poruku sponzora" u tijeku: kad pozicija dođe do kraja raspona,
  /// javi se da je poruka gotova, a reprodukcija teče dalje (odluka 24.9.2026.
  /// — pauza je djelovala kao da je player stao). Null = nema aktivnog isječka.
  SponsorInVideoSegment? _sponsorClip;

  /// Pozicija je barem jednom ušla u raspon isječka. Tek tada kraj raspona
  /// znači „poruka je gotova" — prije toga stream još javlja staru poziciju
  /// (npr. 2:00:00 ako je korisnik bio dalje od poruke) i poruka „završila"
  /// bi iskočila odmah.
  bool _sponsorClipEntered = false;
  DateTime? _sponsorClipStartedAt;

  /// PLAĆENI sponzorski trenuci (`public_live_moments`) — zaseban sloj od
  /// [_sponsorsInVideo]. Dohvat isto lijen i izvan [EpisodeData.load]; null
  /// dok ne stigne, i zauvijek kad ih nema ili dohvat padne.
  SponsoredMomentsController? _sponsored;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _resolveChannelSlug();
    EbookService.probe(widget.data.youtubeId).then((found) {
      if (!mounted || !found.any) return;
      setState(() => _ebook = found);
    });
    DataService(youtubeId: widget.data.youtubeId).loadSponsorsInVideo().then((
      found,
    ) {
      if (!mounted || found == null || !found.hasNamed) return;
      setState(() => _sponsorsInVideo = found);
    });
    SponsoredMomentsService.instance.loadLive(widget.data.youtubeId).then((
      found,
    ) {
      if (!mounted || found == null) return;
      setState(() => _sponsored = SponsoredMomentsController(found));
    });

    // 1) URL forsiranje (npr. /v/<id>/en) — najjaci signal.
    if (widget.initialLanguageEn && widget.data.hasTranslationEn) {
      _language = EpisodeLanguage.en;
    } else {
      // 2) Sticky pref iz prosle sesije — samo ako EN prijevod postoji.
      // Bez prijevoda toggle se i ne prikazuje, pa nema smisla startati u EN.
      loadPreferredLanguage().then((saved) {
        if (!mounted) return;
        if (saved == EpisodeLanguage.en && widget.data.hasTranslationEn) {
          setState(() => _language = EpisodeLanguage.en);
          _syncLanguageUrl(EpisodeLanguage.en);
        }
      });
    }
    final article = widget.data.article;
    _sectionKeys = {
      if (article != null)
        for (final iter in article.iterations)
          for (final sec in iter.sections) sec.screenshotTimestamp: GlobalKey(),
    };

    // Keys za Magisterium stupac — scroll sync (primary variant)
    final magPrimary = widget.data.magisteriumPrimary;
    _magSectionKeys = {
      if (magPrimary != null)
        for (final iter in magPrimary.iterations)
          for (final sec in iter.sections)
            if (sec.magisterium != null) sec.screenshotTimestamp: GlobalKey(),
    };

    _sortedSections = [
      if (article != null)
        for (final iter in article.iterations)
          for (final sec in iter.sections)
            (
              dur: _parseDuration(sec.screenshotTimestamp),
              ts: sec.screenshotTimestamp,
            ),
    ]..sort((a, b) => a.dur.compareTo(b.dur));

    _videoChapters = _sortedSections.map((s) {
      final label = _subtitleForTimestamp(s.ts);
      return VideoChapterMark(position: s.dur, timestamp: s.ts, label: label);
    }).toList();

    _initPersonHighlight();

    _scrollController.addListener(_onScroll);
    // Brzina je globalna postavka (D1) — gumb je mijenja na singletonu, ekran
    // je odavde prenosi na svoj Player. Jedan smjer, bez dvostrukog puta.
    PlaybackSpeed.instance.addListener(_applyPlaybackRate);
    _initVideo();
  }

  /// Ruta zadržava isti `State` kad se promijeni SAMO `startAt` ili `?p=`
  /// (ključ je od 6.9.2026. `video-<id>-<jezik>` — vidi app_router.dart), pa se
  /// ta dva propa moraju primijeniti OVDJE. Prije toga je promjena timestampa
  /// bila novi ključ → novi State → uništen player i ponovno učitavanje svih
  /// artefakata; sada je to seek na živom playeru.
  @override
  void didUpdateWidget(_EpisodeContent oldWidget) {
    super.didUpdateWidget(oldWidget);

    // Nova ciljna sekunda iz URL-a (share link, tap na moment s /p/ profila).
    final startAt = widget.startAtSeconds;
    if (startAt != oldWidget.startAtSeconds && startAt != null) {
      final player = _player;
      if (player != null) {
        // Programski skok — ne smije se ponuditi kao "Vrati me natrag".
        _seekUndo?.suppress();
        player.seek(Duration(seconds: startAt));
      }
    }

    // Novi (ili maknuti) person-highlight marker.
    if (widget.highlightPersonSlug != oldWidget.highlightPersonSlug) {
      _personHighlightTs = null;
      _personHighlightName = null;
      _personHighlightSpeaks = false;
      _initPersonHighlight();
    }
  }

  /// Primijeni trenutnu globalnu brzinu na player + osvježi media sesiju.
  void _applyPlaybackRate() {
    final player = _player;
    if (player == null) return;
    final rate = PlaybackSpeed.instance.rate;
    player.setRate(rate);
    // Native media sesiju ažurira `background_audio.dart` preko
    // `player.stream.rate`; web nema takav stream pa gura odmah.
    MediaSession.setPositionState(
      duration: Duration(seconds: widget.data.info.duration),
      position: player.state.position,
      playbackRate: rate,
    );
  }

  /// Razriješi `?p=<slug>` u (ime osobe za needle highlight, timestamp sekcije
  /// za pill). Ime se matcha protiv diariziranih govornika epizode istim
  /// [personSlug] foldom koji koristi i backend (pa dobijemo pravo ime s
  /// dijakriticima bez dodatnog fetcha); fallback je "otfoldani" slug (Title
  /// Case, bez dijakritika) + async dorada s person API-ja.
  ///
  /// Pill se postavlja SAMO kad je tvrdnja provjerljiva (feedback 2026-07-23:
  /// "govori ovdje" bio prikazan i za osobu koja se samo spominje):
  ///  - osoba je diarizirani govornik → "X govori ovdje"
  ///  - inače, ciljna sekcija sadrži spomen imena → "Ovdje se spominje: X"
  ///  - inače bez pilla — inline needle highlight pokazuje spomene drugdje.
  ///
  /// BEZ `/t/<sec>` u URL-u (epizodni spomen — `mention_ts` se nije razriješio
  /// iz article.json, ~40% spomena) nemamo ciljnu sekundu, pa je sami tražimo:
  /// prva sekcija koja referencira osobu postaje sidro (pill + auto-scroll).
  /// Prije 2026-07-27 se u tom slučaju NIŠTA nije razrješavalo — ni ime ni
  /// pill — pa je jedini trag bio crveni chip u „Osobe" na dnu članka.
  void _initPersonHighlight() {
    final slug = widget.highlightPersonSlug;
    final startAt = widget.startAtSeconds;
    if (slug == null || slug.isEmpty) return;
    if (_sortedSections.isEmpty) return;

    // Sekcija u koju deep-link sekunda pada (zadnja s početkom <= startAt);
    // prije prve sekcije → prva (deep-link na sam uvod). Bez startAt-a sidro
    // tražimo tek dolje, po sadržaju.
    String? ts;
    if (startAt != null) {
      final pos = Duration(seconds: startAt);
      ts = _sortedSections.first.ts;
      for (final s in _sortedSections) {
        if (pos >= s.dur) {
          ts = s.ts;
        } else {
          break;
        }
      }
    }

    var name = slug
        .split('-')
        .where((w) => w.isNotEmpty)
        .map((w) => w[0].toUpperCase() + w.substring(1))
        .join(' ');
    var speaks = false;
    final speakers = widget.data.summary?.summary.speakers ?? const [];
    for (final sp in speakers) {
      final dn = sp.displayName;
      if (dn != null && personSlug(dn) == slug) {
        name = dn;
        speaks = true;
        break;
      }
    }

    _personHighlightName = name;
    // Bez ciljne sekunde ne možemo tvrditi "govori ovdje" ni za diariziranog
    // govornika — sidro nalazimo po spomenu, pa je i tvrdnja "spominje se".
    _personHighlightSpeaks = speaks && ts != null;

    /// Referencira li sekcija osobu: ime u tekstu (dijakritik-neosjetljivo) ILI
    /// među `entities` (AI atribucija — ime često nije u prozi članka).
    bool refersToPerson(String sectionTs) {
      final sec = _sectionFor(sectionTs);
      if (sec == null) return false;
      return hasPersonMention(sec.content, name) ||
          sec.entities.any((e) => personSlug(e) == slug);
    }

    if (ts != null) {
      // Pill samo kad je tvrdnja provjerljiva na TOJ sekciji.
      if (speaks || refersToPerson(ts)) _personHighlightTs = ts;
    } else {
      // Epizodni spomen: prva sekcija koja referencira osobu postaje sidro.
      for (final s in _sortedSections) {
        if (refersToPerson(s.ts)) {
          _personHighlightTs = s.ts;
          break;
        }
      }
      if (_personHighlightTs != null) _scrollToPersonAnchor(_personHighlightTs!);
    }
    log('person highlight: $slug → "$name" @ ${ts ?? _personHighlightTs} '
        '(speaks=$speaks, startAt=$startAt, pill=${_personHighlightTs != null})');

    // Slug nije među govornicima ove epizode (npr. spomen ili drukčije
    // diarizirano ime) → fallback ime iz sluga nema dijakritike ("Stojic").
    // Doradi async s pravim imenom s person API-ja (5-min CDN cache, jeftino).
    if (!speaks) {
      PersonService.fetch(slug).then((hub) {
        final proper = hub?.name.trim();
        if (!mounted || proper == null || proper.isEmpty) return;
        setState(() => _personHighlightName = proper);
      });
    }
  }

  /// Doscrollaj članak na sekciju u kojoj se osoba spominje, kad deep-link nema
  /// `/t/<sec>`. Video se NAMJERNO ne seeka — znamo sekciju, ne sekundu; lažni
  /// seek bi odveo korisnika na krivo mjesto reprodukcije.
  ///
  /// Isti re-scroll safety net kao [_setInitialChapter]: async sadržaj
  /// (Magisterium, web fontovi, kasne slike) pomiče target nakon prvog frame-a.
  /// Svaki pokušaj odustaje čim je korisnik sam počeo scrollati.
  void _scrollToPersonAnchor(String ts) {
    _scrollTimestamp = ts;
    void go() {
      if (!mounted) return;
      if (_lastManualScroll != null) return;
      _scrollLock = DateTime.now();
      _scrollToSection(ts);
    }

    WidgetsBinding.instance.addPostFrameCallback((_) => go());
    Future<void>.delayed(const Duration(milliseconds: 300), go);
    Future<void>.delayed(const Duration(milliseconds: 1200), go);
  }

  /// Sekcija članka s danim screenshot timestampom, ili null.
  PodcastSection? _sectionFor(String ts) {
    final article = widget.data.article;
    if (article == null) return null;
    for (final iter in article.iterations) {
      for (final sec in iter.sections) {
        if (sec.screenshotTimestamp == ts) return sec;
      }
    }
    return null;
  }

  /// `p=<slug>` query string za playback URL sync — čuva person marker u
  /// adresnoj traci da copy-paste link zadrži oznaku. Null bez aktivnog markera.
  String? get _highlightQuery => _personHighlightName != null
      ? 'p=${widget.highlightPersonSlug}'
      : null;

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _creditsProgress.dispose();
    PlaybackSpeed.instance.removeListener(_applyPlaybackRate);
    _positionSub?.cancel();
    _playingSub?.cancel();
    _resumeHintTimer?.cancel();
    WatchProgressService.instance.flush();
    BackgroundAudio.instance.detach();
    MediaSession.clear();
    _playbackIntent?.dispose();
    _seekUndo?.dispose();
    _playbackAnalytics?.dispose();
    _sponsored?.dispose();
    DeferredScreenshots.instance.release();
    final player = _player;
    if (player != null) {
      PlayerMute.instance.detach(player);
      RemotePlayback.instance.detach(player);
      player.dispose();
    }
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      final intent = _playbackIntent;
      // Korisnikova Pauza je neopoziva — odlazak u pozadinu je ne poništava.
      if (intent != null && !intent.wantsPlayback) return;

      if (!BackgroundPlayback.instance.enabled) {
        // Pref iskljucen: pozadina znaci tisinu, isto na webu i nativeu.
        // Namjerno BEZ suppress() — ovu pauzu i zelimo upisati u namjeru, da
        // se reprodukcija ne vrati na sljedecoj framework tranziciji.
        _player?.pause();
        return;
      }

      // Pref ukljucen: pauzu koju izazove sama tranzicija (Android SurfaceView
      // teardown, browser throttling) ne smijemo procitati kao korisnikovu.
      intent?.suppress();
      // Android kill-a SurfaceView kad Video widget ode u bg pa media_kit
      // auto-pauzira. Force-play kratko nakon tranzicije — foreground service
      // iz audio_service-a drzi process zivim, pa play() prodje.
      // Web: ne force-playamo, browser sam drzi audio u pozadinskom tabu.
      if (!kIsWeb) {
        Future<void>.delayed(const Duration(milliseconds: 150), () {
          if (!mounted) return;
          if (intent != null && !intent.shouldResume) return;
          _player?.play();
        });
      }
    }
  }

  /// Je li bočni panel otvoren — čita ga `PopScope.canPop` (vidi build), pa
  /// Back prvo zatvori panel, a tek onda napusti epizodu.
  ///
  /// Zatvaranje panela NE dira reprodukciju: panel ostaje montiran izvan
  /// ekrana, pa `Video` ne prolazi kroz dispose (kod endDrawera je prolazio i
  /// media_kit je pauzirao, zbog čega je postojao resume nakon zatvaranja).
  bool _anyDrawerOpen = false;

  void _onPanelChanged(EpisodePanelSide? side) {
    final isOpen = side != null;
    if (_anyDrawerOpen == isOpen || !mounted) return;
    setState(() => _anyDrawerOpen = isOpen);
  }

  bool get _playerPanelOpen =>
      _panelKey.currentState?.openSide == EpisodePanelSide.right;

  void _openPlayerPanel() =>
      _panelKey.currentState?.open(EpisodePanelSide.right);

  void _togglePanel(EpisodePanelSide side) =>
      _panelKey.currentState?.toggle(side);

  /// Mobitel u landscapeu: header i footer su skriveni dok se čita, pa ekran
  /// dijele samo članak i player. Povlačenje prstom prema dolje (scroll prema
  /// gore) ih vrati, nastavak čitanja ih opet skrije.
  bool _chromeHidden = true;

  bool _onCenterScroll(UserScrollNotification n) {
    if (n.metrics.axis != Axis.vertical || !_isPhoneLandscape(context)) {
      return false;
    }
    final hide = switch (n.direction) {
      ScrollDirection.reverse => true,
      ScrollDirection.forward => false,
      ScrollDirection.idle => null,
    };
    if (hide != null && hide != _chromeHidden) {
      setState(() => _chromeHidden = hide);
    }
    return false;
  }

  /// Footer epizode (gost traka, Zid podrške, mobilna navigacija). U
  /// landscapeu na mobitelu se skupi dok je [_chromeHidden].
  ///
  /// - Ostaje MONTIRAN (samo se odreže na visinu nula): zamjena praznim
  ///   widgetom bi pri svakoj promjeni smjera scrolla ponovno pokretala
  ///   `PinkaSupportBar` (RPC kampanje) i traka bi kasnila za footerom.
  /// - Skriven nosi donji inset: Scaffold tijelu skida donji padding čim
  ///   `bottomNavigationBar` postoji, pa ga tijelo ne bi moglo čuvati.
  /// - Dok je autoplay utišan, footer se NE skriva: gumb „Uključi zvuk" u
  ///   donjoj traci je jedan od tri obavezna izlaza (CLAUDE.md „Muted
  ///   autoplay").
  Widget _immersiveFooter(BuildContext context, Widget footer) {
    final inset = MediaQuery.paddingOf(context).bottom;
    return ListenableBuilder(
      listenable: PlayerMute.instance,
      builder: (context, child) {
        final hidden =
            _chromeHidden &&
            _isPhoneLandscape(context) &&
            !PlayerMute.instance.autoplayBlocked;
        return TweenAnimationBuilder<double>(
          tween: Tween(end: hidden ? 0 : 1),
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          child: child,
          builder: (context, f, child) => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ClipRect(
                child: Align(
                  alignment: Alignment.topCenter,
                  heightFactor: f,
                  child: ExcludeFocus(
                    excluding: f == 0,
                    child: ExcludeSemantics(excluding: f == 0, child: child),
                  ),
                ),
              ),
              SizedBox(height: inset * (1 - f)),
            ],
          ),
        );
      },
      child: footer,
    );
  }

  /// Sidro čitanja dok se članak sužava/širi uz bočni stupac: sekcija koja
  /// presijeca liniju čitanja i KOLIKO je kroz nju linija prošla (0–1).
  /// Prelamanje teksta mijenja visine, pa bi apsolutni offset nakon
  /// otvaranja stupca pokazivao na sasvim drugo mjesto u članku.
  ({String ts, double fraction})? _readingAnchor;

  /// Linija čitanja: 30 % visine viewporta ispod njegova vrha (globalno).
  /// Ne ovisi o visini app bara, koja se mijenja s brojem redova.
  double? _readingLineY() {
    if (!_scrollController.hasClients) return null;
    final vp =
        _scrollController.position.context.notificationContext
                ?.findRenderObject()
            as RenderBox?;
    if (vp == null || !vp.hasSize) return null;
    return vp.localToGlobal(Offset.zero).dy + vp.size.height * 0.3;
  }

  /// Širina stupca članka (scroll viewport), ne ekrana.
  double _columnWidth() {
    final vp =
        _scrollController.position.context.notificationContext
                ?.findRenderObject()
            as RenderBox?;
    return vp != null && vp.hasSize
        ? vp.size.width
        : MediaQuery.sizeOf(context).width;
  }

  ({double top, double height})? _sectionBox(String ts) {
    final box =
        _sectionKeys[ts]?.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize || !box.attached) return null;
    return (top: box.localToGlobal(Offset.zero).dy, height: box.size.height);
  }

  /// Zadnji programski skok na sekciju (tap u sadržaju, praćenje playera).
  /// Skok je NAVIGACIJA: sidro koje bi ga pratilo vratilo bi članak na staro
  /// mjesto — a `jumpTo` se u render stablu vidi tek u sljedećem layoutu, pa
  /// bi snimka uzeta odmah nakon njega pokazivala stari raspored.
  DateTime? _sectionJumpAt;
  String? _sectionJumpTs;

  bool get _sectionJumpRecent {
    final at = _sectionJumpAt;
    return at != null &&
        DateTime.now().difference(at) < const Duration(milliseconds: 500);
  }

  void _captureReadingAnchor() {
    _readingAnchor = null;
    if (_sectionJumpRecent) return;
    // Magisterium tab na mobitelu ima svoj scroll, a `_scrollController` je
    // tada u skrivenom djetetu IndexedStacka.
    if (_mobileTab != 0) return;
    final line = _readingLineY();
    if (line == null) return;
    for (final ts in _sectionKeys.keys) {
      final b = _sectionBox(ts);
      if (b == null || b.height <= 0) continue;
      if (b.top <= line && line < b.top + b.height) {
        _readingAnchor = (ts: ts, fraction: (line - b.top) / b.height);
        return;
      }
    }
  }

  /// Svaki frame u kojem je članak dobio novu širinu. Nedavni skok na
  /// sekciju (tap u sadržaju zatvara panel pa se članak širi DOK skok traje)
  /// ponovno se postavi pod app bar — inače bi prelamanje teksta iznad cilja
  /// odvuklo sekciju s ekrana. Inače vrati sidro čitanja.
  void _onCenterReflow() {
    final ts = _sectionJumpTs;
    if (_sectionJumpRecent && ts != null) {
      if (_scrollController.hasClients &&
          !_scrollController.position.isScrollingNotifier.value) {
        _scrollLock = DateTime.now();
        _jumpSectionToTop(ts);
      }
      return;
    }
    _restoreReadingAnchor();
  }

  void _restoreReadingAnchor() {
    final anchor = _readingAnchor;
    if (anchor == null || !_scrollController.hasClients) return;
    // Korisnik (ili animirani auto-scroll) je preuzeo scroll: `jumpTo` bi mu
    // prekinuo povlačenje ili fling. Njegova pozicija ima prednost.
    if (_scrollController.position.isScrollingNotifier.value ||
        _sectionJumpRecent) {
      _readingAnchor = null;
      return;
    }
    final line = _readingLineY();
    final b = _sectionBox(anchor.ts);
    if (line == null || b == null) return;
    final delta = b.top + anchor.fraction * b.height - line;
    if (delta.abs() < 1) return;
    final pos = _scrollController.position;
    // Programski scroll — ne smije izgledati kao korisnikov (`_onScroll` bi
    // inače blokirao auto-scroll iz playera i preskočio aktivnu sekciju).
    _scrollLock = DateTime.now();
    _scrollController.jumpTo(
      (pos.pixels + delta).clamp(pos.minScrollExtent, pos.maxScrollExtent),
    );
  }

  // ---------- helpers -------------------------------------------------------

  /// Toggle handler — sticky pref + URL sync + setState rebuild kroz scope.
  void _onLanguageChanged(EpisodeLanguage lang) {
    if (lang == _language) return;
    setState(() => _language = lang);
    savePreferredLanguage(lang);
    _syncLanguageUrl(lang);
  }

  /// Update adresne trake za novi jezik bez triggera router refresha.
  /// Cuva timestamp iz playera ako je >0.
  void _syncLanguageUrl(EpisodeLanguage lang) {
    final pos = _player?.state.position ?? Duration.zero;
    final sec = pos.inSeconds;
    replaceLanguage(
      '/v/${widget.data.youtubeId}',
      isEn: lang == EpisodeLanguage.en,
      seconds: sec,
      query: _highlightQuery,
    );
    _lastUrlSyncedSec = sec;
  }

  /// Razriješi naš channel slug iz indexa po imenu kanala (info.json `channel`
  /// ↔ index.json `name`). Index se učita lazy (cache-first) pa ovo radi i na
  /// izravni deep-link na `/v/<id>` bez prethodnog posjeta homepageu.
  Future<void> _resolveChannelSlug() async {
    await channelCache.loadIndex();
    if (!mounted) return;
    final name = widget.data.info.channel;
    final id = channelCache.channelIdForName(name);
    final art = channelCache.avatarSquareForChannelName(name);
    setState(() {
      if (id != null) _channelSlug = id.replaceAll('_', '-');
      _audioArtUrl = art;
    });
  }

  /// Kandidati za kampanju kanala — fallback sticky trake "Zid podrške" kad
  /// epizoda nema vlastitu kampanju (UC… id iz info.json + naš interni
  /// channel id, čim se slug razriješi).
  List<String> get _channelSupportRefs => [
    ?widget.data.info.youtubeChannelId,
    ?_channelSlug?.replaceAll('-', '_'),
  ];

  /// Ruta punog ekrana podrške: epizodna kampanja → `/v/:id/support`,
  /// kampanja kanala (fallback) → `/c/:slug/support` (match ide po `uc`
  /// parametru pa radi i prije nego se slug razriješi).
  String _supportPath({required bool viaChannel}) {
    final data = widget.data;
    if (!viaChannel) {
      return Uri(
        path: '/v/${data.youtubeId}/support',
        queryParameters: {'name': data.displayTitle},
      ).toString();
    }
    final uc = data.info.youtubeChannelId;
    return Uri(
      path: '/c/${_channelSlug ?? 'kanal'}/support',
      queryParameters: {'uc': ?uc, 'name': data.info.channel},
    ).toString();
  }

  Duration _parseDuration(String ts) {
    // "HH:MM:SS" → Duration
    final parts = ts.split(':').map(int.parse).toList();
    if (parts.length == 3) {
      return Duration(hours: parts[0], minutes: parts[1], seconds: parts[2]);
    }
    return Duration.zero;
  }

  String _subtitleForTimestamp(String ts) {
    final article = widget.data.article;
    if (article == null) return ts;
    for (final iter in article.iterations) {
      for (final sec in iter.sections) {
        if (sec.screenshotTimestamp == ts) return sec.subtitle;
      }
    }
    return ts;
  }

  void _showResumeHint(int positionSeconds) {
    if (!mounted) return;
    _resumeHintTimer?.cancel();
    setState(() => _resumeHintSeconds = positionSeconds);
    _resumeHintTimer = Timer(_resumeHintDuration, () {
      if (mounted) setState(() => _resumeHintSeconds = null);
    });
  }

  // ---------- video ---------------------------------------------------------

  Future<void> _initVideo() async {
    final videoUri = widget.data.videoUri;
    // Nema playabilne medije (sva 3 probe-a 404) — ne pokušavaj otvoriti player
    // (izbjegava beskonačni spinner / open na prazan URI). UI ostaje graceful.
    if (!widget.data.hasMedia || videoUri.isEmpty) {
      debugPrint(
        'Video: no media for ${widget.data.youtubeId} — skipping player',
      );
      return;
    }
    // URL explicit timestamp (`/v/<id>/t/<sec>` ili `?t=`) ima prednost nad
    // saved progress-om. Inače resume na zadnju poziciju ako > 5s i ako
    // epizoda nije completed (≥ 90% rewatch konvencija — kreni od početka).
    int? startAt = widget.startAtSeconds;
    bool resumedFromSaved = false;
    if (startAt == null) {
      final saved = WatchProgressService.instance.getSync(
        widget.data.youtubeId,
      );
      if (saved != null && !saved.completed && saved.positionSeconds > 5) {
        startAt = saved.positionSeconds;
        resumedFromSaved = true;
      }
    }
    _holdScreenshots(startAt);
    debugPrint(
      'Video: opening $videoUri'
      '${startAt != null ? ' @${startAt}s' : ''}'
      '${resumedFromSaved ? ' (resumed)' : ''}',
    );

    try {
      final player = Player();
      final controller = VideoController(player);

      // Detekcija skoka mora slušati poziciju PRIJE open/seeka — media_kit
      // streamovi su broadcast (ne replay), pa kasnija pretplata izgubi rane
      // evente.
      _seekUndo = SeekUndo(positionStream: player.stream.position);
      _playbackAnalytics = PlaybackAnalytics(
        playingStream: player.stream.playing,
        positionStream: player.stream.position,
        videoId: widget.data.youtubeId,
        surface: 'v',
        durationSeconds: widget.data.info.duration,
      );
      // Resume-seek pri otvaranju NIJE korisnikov skok. Prozor je namjerno
      // dug: `openAndResume` čeka duration (do 5 s) prije nego seekne, pa bi
      // standardnih 1,2 s isteklo prije samog skoka.
      _seekUndo!.suppress(window: const Duration(seconds: 8));

      // Otvori + pouzdano resume-seek (čeka duration prije seeka — inače libmpv
      // na iOS odbaci seek pa video kreće od 0). Ako je browser odbio unmuted
      // autoplay, helper padne na muted fallback i to zapiše u `PlayerMute`
      // singleton — odatle ga čitaju gumb za zvuk i „Uključi zvuk" CTA.
      // Player se pokazuje ODMAH, ne tek kad je video otvoren: `open` na
      // sporoj vezi traje sekundama (moov + prvi frame), a bez stupca playera
      // ekran izgleda kao da je stao. `Video` do prvog framea crta crnu plohu.
      if (mounted) {
        setState(() {
          _player = player;
          _videoController = controller;
          _videoReady = true;
        });
        _autoOpenPlayerPanel();
      }
      // Ostali screenshotovi kreću tek kad video zasvira (DeferredScreenshots).
      unawaited(
        player.stream.playing
            .firstWhere((p) => p)
            .timeout(const Duration(seconds: 30))
            .then((_) => DeferredScreenshots.instance.release())
            .catchError((Object _) => DeferredScreenshots.instance.release()),
      );

      await openAndResume(player, uri: videoUri, startAtSeconds: startAt);
      if (mounted) {
        // Otvaranje je gotovo → skrati prozor natrag na normalnu duljinu.
        _seekUndo?.suppress();
        // Zapamćena brzina (D1: globalna za uređaj) vrijedi od prve sekunde.
        await player.setRate(PlaybackSpeed.instance.rate);
      }

      _positionSub = player.stream.position.listen(_onVideoPosition);
      // Na pauzi position stream utihne, pa traka špice ne bi nestala sama.
      _playingSub = player.stream.playing.listen((playing) {
        if (!playing) _stopCredits();
      });

      if (mounted) {
        // Namjera se veže tek sad: `openAndResume` je gotov, pa je
        // `state.playing` konačan odgovor je li reprodukcija uopće krenula
        // (web autoplay policy je može odbiti). Sve kasnije promjene — naši
        // gumbi, media_kitov tap-to-pause, tipkovnica, lock screen — stižu
        // kroz stream.
        _playbackIntent = PlaybackIntent(
          playingStream: player.stream.playing,
          isPlayingNow: () => player.state.playing,
          initiallyWants: player.state.playing,
        );
        setState(() {});
        debugPrint('Video: ready');

        if (resumedFromSaved && startAt != null) {
          _showResumeHint(startAt);
        }

        // Background audio session — lock screen + notification na native, no-op na webu.
        // Artwork strategija:
        //   iOS: 1:1 channel avatar (savrseno fit u Now Playing square widget).
        //   Android: 2:1 runtime-composed slika (1:1 avatar + 16:9 thumbnail)
        //     jer Android 13+ MediaStyle crop-a u widescreen; kompozicija ispuni
        //     tile elegantno. Fallback na 1:1 avatar ili YouTube thumbnail.
        await channelCache.loadIndex();
        final channelName = widget.data.info.channel;
        final squareUrl = channelCache.avatarSquareForChannelName(channelName);
        final thumbUrl = widget.data.info.thumbnail;
        final composed = squareUrl != null
            ? await NotificationArt.composeForAndroid(
                videoId: widget.data.youtubeId,
                avatarSquareUrl: squareUrl,
                thumbnail16x9Url: thumbUrl,
              )
            : null;
        final mediaTitle = widget.data.displayTitle;
        BackgroundAudio.instance.attach(
          player: player,
          title: mediaTitle,
          artist: channelName,
          artUri: composed ?? squareUrl ?? thumbUrl,
          duration: Duration(seconds: widget.data.info.duration),
        );

        // Media Session API — web ekvivalent za background audio. Signal
        // OS-u (iOS Now Playing, Android media notification) da je tab
        // "playing media" pa audio nastavlja kad tab izgubi fokus / zaslon
        // se zaključa / korisnik prijeđe na drugi tab. No-op na native.
        MediaSession.attachMetadata(
          title: mediaTitle,
          artist: channelName,
          artUrl: squareUrl ?? thumbUrl,
        );
        MediaSession.setActionHandlers(
          onPlay: () => _player?.play(),
          onPause: () => _player?.pause(),
          onSeekTo: (pos) => _player?.seek(pos),
          onSeekBackward: (off) {
            final cur = _player?.state.position ?? Duration.zero;
            _player?.seek(cur - off);
          },
          onSeekForward: (off) {
            final cur = _player?.state.position ?? Duration.zero;
            _player?.seek(cur + off);
          },
        );
        // Track playing state → playbackState
        player.stream.playing.listen((isPlaying) {
          MediaSession.setPlaybackState(isPlaying);
        });

        // Postavi inicijalni chapter za startAt
        if (startAt != null) {
          _setInitialChapter(Duration(seconds: startAt));
        }

      }
    } catch (e) {
      debugPrint('Video: init failed — $e');
      DeferredScreenshots.instance.release();
    }
  }

  /// Do prvog `playing` vide se samo screenshot prve sekcije i sekcije na
  /// koju vodi [startAt]; ostali čekaju (vidi [DeferredScreenshots]).
  void _holdScreenshots(int? startAt) {
    final sections = <PodcastSection>[
      for (final it in widget.data.article?.iterations ?? const [])
        ...it.sections,
    ].where((s) => s.screenshotTimestamp.isNotEmpty).toList();
    if (sections.isEmpty) return;
    final priority = <String>{sections.first.screenshotTimestamp};
    if (startAt != null) {
      String? at;
      for (final s in sections) {
        if (ClipService.hmsToSeconds(s.screenshotTimestamp) <= startAt) {
          at = s.screenshotTimestamp;
        }
      }
      if (at != null) priority.add(at);
    }
    DeferredScreenshots.instance.hold(priority: priority);
  }

  /// Uži ekran (≤ 1100, player je desni stupac platna): otvori player čim
  /// postoji. Video je autoplay (na webu možda muted zbog browser policy-a,
  /// ali user vidi vizual), korisnik odmah ima video u fokusu. U landscapeu
  /// stoji uz članak; u portretu ga gura s ekrana, a swipe-right ili tap na
  /// rub članka ga zatvara. Šire (> 1100) je player stalni stupac pa
  /// auto-open nije primjenjiv. `?video=0` preskače auto-open, `?video=1` ga
  /// forsira i na tabletu.
  void _autoOpenPlayerPanel() {
    if (_playerAutoOpened || widget.openVideo == false) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (MediaQuery.sizeOf(context).width <= _kPlayerColumnMinWidth ||
          widget.openVideo == true) {
        _openPlayerPanel();
        _playerAutoOpened = true;
      }
    });
  }

  /// Postavi activeTimestamp + scrollTimestamp za inicijalnu poziciju.
  ///
  /// Re-scroll safety net: nakon initial scrolla zakažemo još 2 scrolla
  /// (300ms i 1200ms) jer ostali async content (Magisterium content, web
  /// fonts, late slike koje su tek izračunale visinu nakon prvog frame-a)
  /// mogu pomaknuti target sekciju izvan viewporta. AspectRatio rezervacija
  /// na screenshotima rješava 90% slučajeva — ovo pokriva ostatak.
  void _setInitialChapter(Duration pos) {
    String? ts;
    for (final s in _sortedSections) {
      if (pos >= s.dur) {
        ts = s.ts;
      } else {
        break;
      }
    }
    if (ts != null) {
      setState(() {
        _activeTimestamp = ts;
        _scrollTimestamp = ts;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _scrollToSection(ts!);
      });
      // Re-scroll twice da apsorbiramo late layout shifts (slike, fontovi).
      // Provjeri _lastManualScroll prije svakog poziva — ako je korisnik
      // počeo ručno scrollati, ne overrideaj.
      Future<void>.delayed(const Duration(milliseconds: 300), () {
        if (!mounted) return;
        if (_lastManualScroll != null) return;
        _scrollToSection(ts!);
      });
      Future<void>.delayed(const Duration(milliseconds: 1200), () {
        if (!mounted) return;
        if (_lastManualScroll != null) return;
        _scrollToSection(ts!);
      });
    }
  }

  void _onVideoPosition(Duration pos) {
    _checkSponsorClip(pos);
    _sponsored?.onPosition(pos);
    // URL sync na webu — adresna traka prati player na 1Hz.
    // Nema veze sa seekLockom; želimo da se address bar updatea i tijekom
    // ručno-induciranog seeka (čim novi pos stigne).
    final sec = pos.inSeconds;
    if (sec != _lastUrlSyncedSec) {
      _lastUrlSyncedSec = sec;
      replaceTimestamp(
        '/v/${widget.data.youtubeId}',
        sec,
        langSuffix: _language == EpisodeLanguage.en ? '/en' : null,
        query: _highlightQuery,
      );
      // Media Session position update — drži lock screen scrub bar u syncu.
      // Throttled na sec granularnost (isti gate kao URL sync).
      // playbackRate: bez stvarne brzine scrub bar na lock screenu ekstrapolira
      // na 1,0× i vidno drifta pri 1,5×.
      MediaSession.setPositionState(
        duration: Duration(seconds: widget.data.info.duration),
        position: pos,
        playbackRate: PlaybackSpeed.instance.rate,
      );
      // Watch progress — debounced 5s upsert u localStorage (mock).
      // v3: prosljedjujemo title + thumbnail kao denorm cache (skida sekundarni
      // CDN fetch za "Continue watching" carousel kad backend ode live).
      // Spremi CDN thumbnail URL umjesto `info.thumbnail` koji pokazuje na
      // i.ytimg.com — taj host blokira CORS, pa NetworkImage failirao kad bi
      // se rail "Nastavi slusati" pokusao renderati.
      WatchProgressService.instance.scheduleSave(
        episodeId: widget.data.youtubeId,
        positionSeconds: sec,
        durationSeconds: widget.data.info.duration,
        channelId: widget.data.info.channelId,
        episodeTitle: widget.data.displayTitle,
        episodeThumbnailUrl: CdnConfig.thumbnailUrl(widget.data.youtubeId),
      );
    }

    // Preskoči auto-sync tijekom rucnog klika na chapter
    final lock = _seekLock;
    final now = DateTime.now();
    if (lock != null && now.difference(lock) < _seekLockDuration) {
      return;
    }

    // Pronadji aktivnu sekciju: zadnja sekcija čiji timestamp <= pos
    String? newTs;
    for (final s in _sortedSections) {
      if (pos >= s.dur) {
        newTs = s.ts;
      } else {
        break;
      }
    }
    if (newTs == null) return;
    if (newTs == _activeTimestamp) {
      _creditsScroll(pos, newTs);
      return;
    }

    // Sprjecava flicker: odmah nakon seekLocka, ne dopusti backward jump
    // na raniji chapter (preroll -2s uzrokuje kratki period na prethodnom).
    if (lock != null &&
        now.difference(lock) <
            _seekLockDuration + const Duration(milliseconds: 500)) {
      final currentIdx = _sortedSections.indexWhere(
        (s) => s.ts == _activeTimestamp,
      );
      final newIdx = _sortedSections.indexWhere((s) => s.ts == newTs);
      if (newIdx < currentIdx) return; // ignoriraj backward jump
    }

    // Postavi oba timestampa — video i scroll pointer syncani
    setState(() {
      _activeTimestamp = newTs!;
      _scrollTimestamp = newTs;
    });

    // Auto-scroll teksta samo ako korisnik nije ručno scrollao zadnje 2 sekunde
    // — i ne dok svira poruka sponzora: korisnik je gleda s kartice sponzora,
    // pa bi skok na sekciju članka odvukao stranicu ispod njegova prsta.
    if (_sponsorClip != null) return;
    final lastScroll = _lastManualScroll;
    if (lastScroll == null ||
        DateTime.now().difference(lastScroll) > const Duration(seconds: 2)) {
      _scrollLock = DateTime.now();
      _scrollToSection(newTs);
    }
  }

  // ---------- scroll --------------------------------------------------------

  /// Visina zone koja na vrhu prekriva članak (safe area + app bar; u
  /// paralelnom layoutu i sticky naslovi stupaca). Mobitel u landscapeu ima
  /// floating header koji se na scroll prema dolje skrije — tada samo inset.
  double _pinnedTop() {
    final topInset = MediaQuery.paddingOf(context).top;
    if (_isPhoneLandscape(context)) return topInset;
    // Drugi red akcija postoji kad je STUPAC uži od 600 (vidi
    // `_episodeAppBar`) — i na tabletu kad je player uz članak.
    return _parallelActive
        ? topInset + kToolbarHeight + kParallelStickyHeaderHeight
        : topInset + kToolbarHeight + (_columnWidth() < 600 ? 46 : 0);
  }

  /// Koliko dugo „odjavna špica" miruje nakon što korisnik dodirne članak
  /// ili ga sam scrolla.
  static const _kCreditsPauseAfterTouch = Duration(seconds: 20);

  /// Razmak između dva koraka špice, u vremenu REPRODUKCIJE (prati brzinu i
  /// pauzu). Tekst između koraka stoji mirno da se može čitati.
  static const _kCreditsStep = Duration(seconds: 15);

  /// Trajanje jednog koraka — kratko i mekano, da oko ne izgubi redak.
  static const _kCreditsStepAnim = Duration(milliseconds: 700);

  /// Pozicija reprodukcije od koje se puni traka do sljedećeg koraka. `null`
  /// = špica ne radi (nema trake).
  Duration? _creditsCycleFrom;

  /// Napunjenost trake do sljedećeg koraka (0..1), `null` = traka skrivena.
  /// Notifier, ne `setState`: mijenja se ~5×/s, a crta je samo tanka traka.
  final ValueNotifier<double?> _creditsProgress = ValueNotifier(null);

  /// Do kada traje animirani korak — `_onScroll` ga ne smije pročitati kao
  /// korisnikov scroll (inače bi se špica sama ugasila).
  DateTime? _creditsAnimatingUntil;

  /// Zadnji dodir članka (prst, miš). Dodir = „čitam, ne diraj".
  DateTime? _creditsTouchedAt;

  void _stopCredits() {
    _creditsCycleFrom = null;
    _creditsProgress.value = null;
  }

  /// „Odjavna špica": dok player svira unutar iste sekcije, članak se svakih
  /// [_kCreditsStep] pomakne jednim mekanim korakom do mjesta koje odgovara
  /// vremenu — na početku sekcije naslov je pod app barom, na kraju je dno
  /// teksta na ~60 % ekrana, a onda skok na sljedeću sekciju preuzme
  /// `_onVideoPosition`. Između koraka tekst stoji (čita se), a tanka traka
  /// na dnu članka se puni i najavljuje sljedeći pomak.
  ///
  /// Do v2.0.171 je špica klizila neprekidno (`animateTo` 5×/s). Čitanje
  /// pokretnog teksta je naporno, a na iOS Safariju bez cross-origin
  /// izolacije rasterizacija ide na glavnoj niti, pa je stalno klizanje
  /// dugog članka gušilo i ostatak UI-ja.
  ///
  /// Samo naprijed: korisnik koji je odčitao unaprijed čeka da ga reprodukcija
  /// sustigne. Dodir ili ručni scroll je pauzira [_kCreditsPauseAfterTouch];
  /// ako je korisnik izvan sekcije, čita nešto drugo i ne vučemo ga.
  void _creditsScroll(Duration pos, String ts) {
    if (_sponsorClip != null ||
        // Mobilni tab Magisterium: članak je skriven u IndexedStacku.
        _mobileTab != 0 ||
        _player?.state.playing != true ||
        !_scrollController.hasClients) {
      return _stopCredits();
    }
    final now = DateTime.now();
    for (final at in [_lastManualScroll, _creditsTouchedAt]) {
      if (at != null && now.difference(at) < _kCreditsPauseAfterTouch) {
        return _stopCredits();
      }
    }
    // Skok na sekciju (i snap floating headera nakon njega) mora prvo sjesti.
    final jumpAt = _sectionJumpAt;
    if (jumpAt != null &&
        now.difference(jumpAt) < const Duration(milliseconds: 600)) {
      return;
    }
    final idx = _sortedSections.indexWhere((s) => s.ts == ts);
    if (idx < 0) return _stopCredits();
    final start = _sortedSections[idx].dur;
    final end = idx + 1 < _sortedSections.length
        ? _sortedSections[idx + 1].dur
        : Duration(seconds: widget.data.info.duration);
    final span = (end - start).inMilliseconds;
    if (span <= 0) return _stopCredits();

    final b = _sectionBox(ts);
    if (b == null) return _stopCredits();
    final p = _scrollController.position;
    final pinned = _pinnedTop() + 16;
    final visible = p.viewportDimension - pinned;
    final travel = b.height - visible * 0.6;
    // Sekcija stane na ekran — nema se kamo klizati.
    if (travel <= 0) return _stopCredits();
    final sectionAtTop = p.pixels + (b.top - pinned);
    // Korisnik je izvan sekcije: čita nešto drugo.
    if (p.pixels < sectionAtTop - visible ||
        p.pixels > sectionAtTop + b.height) {
      return _stopCredits();
    }
    double targetAt(Duration t) {
      final progress = ((t - start).inMilliseconds / span).clamp(0.0, 1.0);
      return (sectionAtTop + progress * travel).clamp(0.0, p.maxScrollExtent);
    }

    var from = _creditsCycleFrom;
    // Novi ciklus, ili je korisnik premotao unatrag.
    if (from == null || pos < from) from = _creditsCycleFrom = pos;
    final elapsed = pos - from;

    if (elapsed >= _kCreditsStep) {
      _creditsCycleFrom = pos;
      final delta = targetAt(pos) - p.pixels;
      if (delta >= 8) {
        // Korak nikad dulji od tri četvrtine ekrana — oko mora naći redak
        // koji je upravo čitalo.
        final to = p.pixels + math.min(delta, visible * 0.75);
        _creditsAnimatingUntil =
            now.add(_kCreditsStepAnim + const Duration(milliseconds: 150));
        _scrollLock = now;
        _scrollController.animateTo(
          to,
          duration: _kCreditsStepAnim,
          curve: Curves.easeInOutCubic,
        );
      }
      _creditsProgress.value = 0;
      return;
    }
    // Traka se puni samo ako će se na kraju ciklusa nešto i pomaknuti —
    // korisnik koji je odčitao unaprijed ne treba najavu koraka koji neće doći.
    final willMove = targetAt(from + _kCreditsStep) - p.pixels >= 8;
    _creditsProgress.value = willMove
        ? elapsed.inMilliseconds / _kCreditsStep.inMilliseconds
        : null;
  }

  /// Članak s trakom špice na dnu. Dodir bilo gdje u članku je pauzira —
  /// `Listener` ne hvata gestu, pa tapovi i scroll rade kao i prije.
  Widget _withCreditsBar(Widget scrollBody) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) {
        _creditsTouchedAt = DateTime.now();
        _stopCredits();
      },
      child: Stack(
        children: [
          scrollBody,
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: IgnorePointer(
              child: RepaintBoundary(
                child: ValueListenableBuilder<double?>(
                  valueListenable: _creditsProgress,
                  builder: (context, v, _) {
                    if (v == null) return const SizedBox.shrink();
                    final scheme = Theme.of(context).colorScheme;
                    return LinearProgressIndicator(
                      value: v.clamp(0.0, 1.0),
                      minHeight: 3,
                      backgroundColor: scheme.outlineVariant.withAlpha(60),
                      color: scheme.primary.withAlpha(170),
                    );
                  },
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _onScroll() {
    final now = DateTime.now();
    // Ne reagiraj na programatski scroll (seek ili auto-scroll iz playbacka)
    final sLock = _seekLock;
    if (sLock != null && now.difference(sLock) < _seekLockDuration) return;
    final scLock = _scrollLock;
    if (scLock != null &&
        now.difference(scLock) < const Duration(milliseconds: 300)) {
      return;
    }
    final stepUntil = _creditsAnimatingUntil;
    if (stepUntil != null && now.isBefore(stepUntil)) return;
    _lastManualScroll = now;
    _updateActiveSectionFromScroll();
  }

  void _updateActiveSectionFromScroll() {
    for (final entry in _sectionKeys.entries) {
      final ctx = entry.value.currentContext;
      if (ctx == null) continue;
      final box = ctx.findRenderObject() as RenderBox?;
      if (box == null) continue;
      final pos = box.localToGlobal(Offset.zero);
      final screenH = MediaQuery.sizeOf(context).height;
      if (pos.dy >= 0 && pos.dy < screenH * 0.4) {
        if (_scrollTimestamp != entry.key) {
          setState(() => _scrollTimestamp = entry.key);
        }
        return;
      }
    }
  }

  // Alignment offset — appbar je ~56px, na tipicnom viewportu (800px) to je ~0.08.
  // Scrollamo ispod headera da chapter naslov bude jasno vidljiv.
  static const _scrollAlignment = 0.18;

  void _scrollToSection(String timestamp) {
    _stopCredits();
    _sectionJumpAt = DateTime.now();
    _sectionJumpTs = timestamp;
    _readingAnchor = null;
    _jumpSectionToTop(timestamp);
    _scrollMagToSection(timestamp);
  }

  /// Postavi sekciju pod app bar. Bez bilježenja skoka — zove je i
  /// [_onCenterReflow] da cilj ostane na mjestu dok se članak prelama.
  void _jumpSectionToTop(String timestamp) {
    final ctx = _sectionKeys[timestamp]?.currentContext;
    if (ctx != null) {
      final box = ctx.findRenderObject() as RenderBox?;
      if (box != null && _scrollController.hasClients) {
        // Citamo STVARNU ekransku poziciju cilja (localToGlobal) i korigiramo
        // scroll da sjedne tocno `gap` px ispod pinned zone. Robusno naspram
        // getOffsetToReveal kvirkova (npr. in-group pinned header double-count u
        // paralelnom layoutu) i neovisno o visini ekrana.
        //
        // Pinned zona = safe-area top (SliverAppBar je primary → na mobitelu mu
        // status bar / notch povecava visinu za padding.top) + app bar; u
        // paralelnom desktop layoutu jos i sticky naslovi stupaca. Na desktopu je
        // padding.top == 0 pa je ponasanje identicno prijasnjem.
        final currentY = box.localToGlobal(Offset.zero).dy;
        final topInset = MediaQuery.paddingOf(context).top;
        const gap = 16.0;
        // Mobitel u landscapeu: app bar je floating — vidi
        // `_floatingHeaderJumpDelta`.
        if (_isPhoneLandscape(context)) {
          final delta = _floatingHeaderJumpDelta(currentY, topInset + gap);
          if (delta != null) {
            final pos = _scrollController.position;
            _scrollController.jumpTo(
              (pos.pixels + delta).clamp(0.0, pos.maxScrollExtent),
            );
            // `snap: true` zna nakon skoka sam dovršiti djelomično vidljiv
            // header (animacija ~200 ms) — tada naslov ostane ispod praznine
            // gdje je traka bila. Jedno poravnanje nakon snapa to zatvori.
            Future<void>.delayed(const Duration(milliseconds: 350), () {
              if (!mounted || _sectionJumpTs != timestamp) return;
              if (!_scrollController.hasClients ||
                  _scrollController.position.isScrollingNotifier.value) {
                return;
              }
              final b = _sectionBox(timestamp);
              if (b == null) return;
              final d = _floatingHeaderJumpDelta(b.top, topInset + gap);
              if (d == null || d.abs() < 1) return;
              final p = _scrollController.position;
              _scrollLock = DateTime.now();
              _scrollController.jumpTo(
                (p.pixels + d).clamp(0.0, p.maxScrollExtent),
              );
            });
            return;
          }
        }
        // Drugi red akcija postoji kad je STUPAC uži od 600 (vidi
        // `_episodeAppBar`) — i na tabletu kad je player uz članak.
        final desiredY = _pinnedTop() + gap;
        final target = (_scrollController.offset + (currentY - desiredY)).clamp(
          0.0,
          _scrollController.position.maxScrollExtent,
        );
        _scrollController.jumpTo(target);
      } else {
        Scrollable.ensureVisible(
          ctx,
          duration: Duration.zero,
          alignment: _scrollAlignment,
        );
      }
    }
  }

  /// Pomak scrolla koji sekciju (trenutno na globalnom [sectionY]) postavlja
  /// ispod floating app bara — onoliko koliko ga NAKON skoka bude na ekranu.
  ///
  /// Floating header (`RenderSliverFloatingPersistentHeader.performLayout`) se
  /// na programski skok prema dolje skupi za isti iznos, a na skok prema gore
  /// se NE širi. Zato: ako je skok dovoljno dug da header sakrije, sekcija ide
  /// na vrh ([hiddenY] = inset + razmak). Inače header ostaje kakav jest i
  /// sekcija ide točno ispod njega. Fiksni „najgori slučaj" (puna visina) je
  /// na skrivenom headeru ostavljao ~100 px praznog prostora iznad naslova.
  ///
  /// Null kad se header ne da izmjeriti — tada vrijedi običan izračun.
  double? _floatingHeaderJumpDelta(double sectionY, double hiddenY) {
    final scrollBox =
        _scrollController.position.context.notificationContext
                ?.findRenderObject();
    if (scrollBox is! RenderBox || !scrollBox.hasSize) return null;
    RenderViewport? viewport;
    void find(RenderObject o) {
      if (viewport != null) return;
      if (o is RenderViewport) {
        viewport = o;
        return;
      }
      o.visitChildren(find);
    }

    scrollBox.visitChildren(find);
    final header = viewport?.firstChild;
    final geometry = header?.geometry;
    if (geometry == null) return null;
    final top = scrollBox.localToGlobal(Offset.zero).dy;
    final y = sectionY - top;
    final insetAndGap = hiddenY;
    // Vidljivi dio trake ispod statusnog inseta (paintExtent ga uključuje).
    final topInset = MediaQuery.paddingOf(context).top;
    final visible = math.max(0.0, geometry.paintExtent - topInset);
    final toTop = y - insetAndGap;
    if (toTop >= visible) return toTop;
    return toTop - visible;
  }

  void _scrollMagToSection(String timestamp) {
    final key = _magSectionKeys[timestamp];
    if (key?.currentContext != null) {
      Scrollable.ensureVisible(
        key!.currentContext!,
        duration: Duration.zero,
        alignment: _scrollAlignment,
      );
    }
  }

  /// Kad korisnik seekuje slider, uvijek scrollaj na ispravnu sekciju.
  void _onVideoSeek(Duration pos) {
    String? newTs;
    for (final s in _sortedSections) {
      if (pos >= s.dur) {
        newTs = s.ts;
      } else {
        break;
      }
    }
    if (newTs == null) return;
    setState(() => _activeTimestamp = newTs!);
    _scrollToSection(newTs);
  }

  /// Seek video na timestamp + play + scroll teksta.
  /// [preroll]: ako true, seekaj 2s prije za kontekst (samo video chapter lista).
  Future<void> _seekAndPlay(String timestamp, {bool preroll = false}) async {
    _seekLock = DateTime.now();
    // Tap na poglavlje je namjerna navigacija — Undo se NE nudi (odluka D2).
    // Prozor je 2 s jer na webu `play()` prethodi seeku pa skok može kasniti.
    _seekUndo?.suppress(window: const Duration(seconds: 2));
    // Odmah postavi oba pointera i scrollaj — ne cekaj async seek
    setState(() {
      _activeTimestamp = timestamp;
      _scrollTimestamp = timestamp;
    });
    _scrollToSection(timestamp);

    final dur = _parseDuration(timestamp);
    var seekTo = dur;
    if (preroll) {
      seekTo = dur - const Duration(seconds: 2);
      if (seekTo < Duration.zero) seekTo = Duration.zero;
    }
    if (kIsWeb) {
      await _player?.play();
      await _player?.seek(seekTo);
    } else {
      await _player?.seek(seekTo);
      await _player?.play();
    }
  }

  /// Seek na sekundu + play, bez scrolla teksta (sponzorski gumbi).
  Future<void> _seekToAndPlay(Duration to) async {
    _seekLock = DateTime.now();
    // Namjeran skok s gumba — kao tap na poglavlje, Undo se ne nudi.
    _seekUndo?.suppress(window: const Duration(seconds: 2));
    if (kIsWeb) {
      await _player?.play();
      await _player?.seek(to);
    } else {
      await _player?.seek(to);
      await _player?.play();
    }
  }

  /// Na uskom ekranu je player bočni stupac koji može biti zatvoren — bez
  /// otvaranja bi „Poslušaj" svirao bez ikakvog vizuala (isto kao play u
  /// članku).
  ///
  /// Panel je montiran i dok je zatvoren, pa `<video>` ne bi smio putovati
  /// po DOM-u. `play()` nakon animacije (300/900 ms) ipak ostaje kao osigurač:
  /// kod endDrawera je premještanje elementa pauziralo reprodukciju
  /// (izmjereno 24.9.2026. na 390 px: seek je sjeo, poruka nije krenula).
  void _revealPlayer() {
    if (MediaQuery.sizeOf(context).width > _kPlayerColumnMinWidth) return;
    final wasOpen = _playerPanelOpen;
    _openPlayerPanel();
    if (wasOpen) return;
    for (final ms in const [300, 900]) {
      Future<void>.delayed(Duration(milliseconds: ms), () {
        final player = _player;
        if (!mounted || player == null || player.state.playing) return;
        // Korisnik je u međuvremenu stisnuo Pauzu — osigurač je ne poništava.
        if (_playbackIntent?.wantsPlayback == false) return;
        player.play();
      });
    }
  }

  /// „Poslušaj poruku sponzora": skoči na početak raspona, pusti i javi kad
  /// poruka završi — epizoda nastavlja svirati.
  void _listenSponsor(SponsorInVideoSegment seg) {
    log('SponsorsInVideo: listen ${seg.start}-${seg.end}s (${seg.kind.name})');
    _sponsorClip = seg;
    _sponsorClipEntered = false;
    _sponsorClipStartedAt = DateTime.now();
    _seekToAndPlay(seg.startPosition);
    _revealPlayer();
  }

  /// „Poslušaj" na plaćenom trenutku: skok na početak i reprodukcija. Kraj se
  /// ne javlja — to je oglas, ne poruka koju je korisnik tražio do kraja.
  void _listenSponsored(SponsoredMoment m) {
    log('SponsoredMoment: listen ${m.slotKey}');
    _sponsorClip = null;
    _seekToAndPlay(m.startPosition);
    _revealPlayer();
  }

  /// Plaćeni trenuci po sekciji članka (sidro je vrijeme).
  Map<String, List<SponsoredMoment>> get _sponsoredMarks =>
      _sponsored?.moments.marksBySection([
        for (final s in _sortedSections) (ts: s.ts, seconds: s.dur.inSeconds),
      ]) ??
      const {};

  /// Nepouzdan raspon (zahvala, poglavlje): samo skok na trenutak, bez
  /// zaustavljanja. Adresna traka se sama poravna na `/v/<id>/t/<sec>`.
  void _jumpSponsor(SponsorInVideoSegment seg) {
    _sponsorClip = null;
    _seekToAndPlay(seg.startPosition);
    _revealPlayer();
  }

  void _checkSponsorClip(Duration pos) {
    final clip = _sponsorClip;
    if (clip == null) return;
    const slack = Duration(seconds: 3);
    final inRange = pos >= clip.startPosition - slack && pos < clip.endPosition;
    if (!_sponsorClipEntered) {
      if (inRange) {
        _sponsorClipEntered = true;
      } else if (DateTime.now().difference(_sponsorClipStartedAt!) >
          const Duration(seconds: 8)) {
        // Seek nikad nije stigao (medija se nije dala premotati) — odustani.
        _sponsorClip = null;
      }
      return;
    }
    if (inRange) return;
    _sponsorClip = null;
    // Prirodan kraj = pozicija je upravo prešla `end`. Sve drugo (skok
    // naprijed ili natrag po timelineu) je korisnikov izbor — tada šutimo.
    if (pos >= clip.endPosition && pos < clip.endPosition + slack) {
      log('SponsorsInVideo: message ended at ${pos.inSeconds}s');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context).sponsorsInVideoEnded),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  /// Poruke sponzora razvrstane po sekciji članka (sidro je vrijeme).
  Map<String, List<SponsorInVideoMark>> get _sponsorMarks =>
      _sponsorsInVideo?.marksBySection([
        for (final s in _sortedSections) (ts: s.ts, seconds: s.dur.inSeconds),
      ]) ??
      const {};

  List<({Duration start, Duration end})> get _sponsorRanges =>
      _sponsorsInVideo?.playableRanges ?? const [];

  Widget _sponsorsSection({double horizontalPadding = 20}) =>
      SponsorsInVideoSection(
        data: _sponsorsInVideo,
        horizontalPadding: horizontalPadding,
        onListen: _videoReady ? _listenSponsor : null,
        onJump: _videoReady ? _jumpSponsor : null,
      );

  /// „Pronađi u epizodi" — tap na trenutak skoči u playeru i, na uskom
  /// ekranu, otvori panel playera (isto kao „Poslušaj" sponzora).
  Widget _findInEpisodeSection() => FindInEpisodeSection(
        youtubeId: widget.data.youtubeId,
        onJump: _videoReady
            ? (sec) {
                log('FindInEpisode: jump ${sec}s');
                _sponsorClip = null;
                _seekToAndPlay(Duration(seconds: sec));
                _revealPlayer();
              }
            : null,
      );

  void _drawerTap(String timestamp) {
    _panelKey.currentState?.close();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _seekAndPlay(timestamp);
    });
  }

  /// Kopira share link na trenutnu poziciju playera (path-based `/v/<id>/t/<sec>`).
  /// Ako player nije spreman ili je na ~0s, dijeli base URL bez timestampa.
  /// Worker injecta chapter-aware OG tagove na ovaj path — vidi web/_worker.js.
  void _copyMomentLink(BuildContext context, String youtubeId) {
    final pos = _player?.state.position ?? Duration.zero;
    final sec = pos.inSeconds;
    final url = episodeShareUrl(youtubeId, seconds: sec, lang: _language);
    Clipboard.setData(ClipboardData(text: url));
    final l = AppLocalizations.of(context);
    final label = sec > 5 ? _formatClock(sec) : l.episodeWholeEpisode;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(l.episodeLinkCopied(label)),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  /// AppBar akcija za otvaranje izvora epizode: YouTube za standardne, izvorna
  /// podcast stranica (webpage_url) za audio-only. Null kad nema URL-a.
  Widget? _sourceAction(EpisodeData data) {
    final l = AppLocalizations.of(context);
    final url = data.info.sourceUrl;
    if (url == null) return null;
    // X/Twitter izvor: `id` je sintetički pa `sourceUrl` vodi na webpage_url
    // (x.com/…/status/…) — pokaži 𝕏 oznaku, ne crvenu YouTube ikonu.
    if (data.info.isX) {
      return IconButton(
        icon: const Text('𝕏', style: TextStyle(fontSize: 18)),
        tooltip: l.episodeOpenOnX,
        onPressed: () => openUrl(url),
      );
    }
    if (data.isAudioOnly) {
      return IconButton(
        icon: const Icon(Icons.open_in_new),
        tooltip: l.commonOpenSource,
        onPressed: () => openUrl(url),
      );
    }
    return IconButton(
      icon: const Icon(Icons.smart_display, color: Color(0xFFFF0000)),
      tooltip: l.episodeOpenOnYouTube,
      onPressed: () => openUrl(url),
    );
  }

  String _formatClock(int seconds) {
    final h = seconds ~/ 3600;
    final m = (seconds % 3600) ~/ 60;
    final s = seconds % 60;
    String p(int n) => n.toString().padLeft(2, '0');
    return h > 0 ? '$h:${p(m)}:${p(s)}' : '$m:${p(s)}';
  }

  // ---------- build ---------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final data = widget.data;
    // Basic path — video je dostupan ali AI pipeline jos nije producirao
    // clanak/sazetak/poglavlja. Renderiramo samo player + osnovne info.
    if (!data.hasAiContent) {
      return EpisodeLanguageScope(
        language: _language,
        hasTranslationEn: data.hasTranslationEn,
        child: _buildBasicLayout(context),
      );
    }
    final theme = Theme.of(context);
    final l = AppLocalizations.of(context);
    final width = MediaQuery.sizeOf(context).width;
    final isWide = width > 900;
    final showVideo = _videoReady && width > _kPlayerColumnMinWidth;
    final wantEn = _language == EpisodeLanguage.en;
    // EN je superset HR-a — kad je toggle na EN, koristi EN verzije asseta
    // (sadrze i HR polja za fallback per-field). Inace HR original.
    // hasAiContent guard gore garantira data.article != null; summary postoji
    // zajedno (pipeline ih producira u istom batchu) — pa `!` assertion.
    final summaryForUi = data.summaryFor(wantEn)!;
    final articleForUi = data.articleFor(wantEn)!;
    final magVariants = data.magisteriumVariantsFor(wantEn: wantEn);
    final magV2 = data.magisteriumFullV2For(wantEn: wantEn);
    final magPrimary = data.magisteriumPrimaryFor(wantEn: wantEn);
    final hasMag =
        magVariants.isNotEmpty ||
        data.magisteriumFull != null ||
        data.magisteriumFullPrompt != null ||
        magV2 != null;
    // Magisterium stupac: zasebni scrollable panel na širokim ekranima
    final showMagColumn = hasMag && width > 1500;
    // Paralelni prikaz: clanak i Magisterium per-sekcija jedan uz drugi u
    // dijeljenom scrollu (timestampovi poravnati). Zahtijeva per-sekcija
    // Magisterium podatke; ako epizoda ima samo V2 esej (magPrimary == null),
    // pada na klasicni magColumn (V2 esej nema per-sekcija timestampove).
    final useParallel = showMagColumn && magPrimary != null;
    _parallelActive = useParallel;
    // Mobile: bottom tabovi za switch između článka i Magisteriuma.
    // Bez ovog, Magisterium content je "zakopan" ispod dugačke article liste.
    final showMobileBottomBar = !isWide;
    final isMobileWithTabs = !isWide && hasMag;

    final appBar = _episodeAppBar(
      leading: _backLeading(context),
      title: _Breadcrumb(
        channelName: data.info.channel,
        channelSlug: _channelSlug,
        episodeTitle: data.displayTitle,
      ),
      actions: [
        Padding(
          padding: const EdgeInsets.only(right: 4),
          child: Center(
            child: Text(
              data.info.id,
              style: theme.textTheme.labelSmall?.copyWith(
                fontFamily: 'monospace',
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ),
        FavoriteButton(
          episodeId: data.youtubeId,
          episodeTitle: data.displayTitle,
          channelName: data.info.channel,
        ),
        if (data.hasTranslationEn)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Center(
              child: LanguageToggleChip(
                current: _language,
                onChanged: _onLanguageChanged,
                compact: true,
              ),
            ),
          ),
        EbookAction(
          availability: _ebook,
          title: data.displayTitle,
          preferEn: _language == EpisodeLanguage.en,
          episodeUrl: episodeShareUrl(data.youtubeId, lang: _language),
        ),
        IconButton(
          icon: const Icon(Icons.share_outlined),
          tooltip: l.episodeCopyMomentLink,
          onPressed: () => _copyMomentLink(context, data.youtubeId),
        ),
        if (_sourceAction(data) != null) _sourceAction(data)!,
        ViewModeToggleButton(
          toSimple: true,
          onPressed: () async {
            await saveSimpleModePref(true);
            if (!context.mounted) return;
            final target = _language == EpisodeLanguage.en
                ? '/m/${data.youtubeId}/en'
                : '/m/${data.youtubeId}';
            // Isti sadržaj, druga prezentacija → NE novi history entry.
            swapPresentation(context, target);
          },
        ),
        if (_videoReady && !showVideo)
          Padding(
            padding: const EdgeInsets.only(right: 4),
            child: IconButton(
              icon: const Icon(Icons.ondemand_video),
              tooltip: l.episodeVideo,
              onPressed: () => _togglePanel(EpisodePanelSide.right),
            ),
          ),
      ],
    );

    final standardContent = SliverToBoxAdapter(
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 860),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              HeroSection(
                info: data.info,
                youtubeId: data.youtubeId,
                summary: summaryForUi.summary,
              ),
              // Traka spomenutih osoba odmah ispod naslova. Puna sekcija
              // entiteta je na dnu članka — predaleko da se vidi tko je u
              // epizodi, i predaleko za crveni marker kad se dođe s /p/ profila.
              PeopleRail(
                summary: summaryForUi.summary,
                highlightPersonSlug: widget.highlightPersonSlug,
              ),
              // "Zid podrške" za epizodu — sam se sakrije ako epizoda nema
              // aktivnu pinka kampanju (vidi lib/pinka_sdk/). SEPA QR +
              // on-chain EURe (Gnosis Safe) + in-app DOMOVINA novčanik.
              if (AppBrand.config.flags.pinka)
                PinkaSupportCard.episode(
                youtubeId: data.youtubeId,
                onOpen: (_) => drillDown(
                  context,
                  Uri(
                    path: '/v/${data.youtubeId}/support',
                    queryParameters: {'name': data.displayTitle},
                  ).toString(),
                ),
              ),
              if (data.hasTranslationEn)
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                  child: Row(
                    children: [
                      Text(
                        l.episodeLanguageLabel,
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(width: 10),
                      LanguageToggleChip(
                        current: _language,
                        onChanged: _onLanguageChanged,
                      ),
                    ],
                  ),
                ),
              Divider(height: 1, color: theme.colorScheme.outlineVariant),
              SummarySection(summary: summaryForUi),
              // E-knjiga ide iza sažetka, prije poglavlja: tu je korisnik već
              // odlučio zanima li ga epizoda, a još nije ušao u dugi članak.
              EbookCard(
                availability: _ebook,
                title: data.displayTitle,
                preferEn: _language == EpisodeLanguage.en,
                episodeUrl: episodeShareUrl(data.youtubeId, lang: _language),
              ),
              // Partneri koji su omogućili epizodu — iza sažetka, prije
              // poglavlja; sama se sakrije kad imenovanih sponzora nema.
              _sponsorsSection(),
              Divider(height: 1, color: theme.colorScheme.outlineVariant),
              const SizedBox(height: 12),
              ChaptersSection(
                outline: data.outline!,
                videoId: data.isAudioOnly ? null : data.youtubeId,
              ),
              Divider(height: 1, color: theme.colorScheme.outlineVariant),
              const SizedBox(height: 12),
              _findInEpisodeSection(),
              Divider(height: 1, color: theme.colorScheme.outlineVariant),
              const SizedBox(height: 12),
              ArticleSection(
                article: articleForUi,
                youtubeId: data.youtubeId,
                sectionKeys: _sectionKeys,
                showScreenshot: !data.isAudioOnly,
                highlightTimestamp: _personHighlightTs,
                highlightPersonName: _personHighlightName,
                highlightSpeaks: _personHighlightSpeaks,
                onPlayTap: _videoReady
                    ? (ts) {
                        _seekAndPlay(ts, preroll: true);
                        // Dok je player bočni stupac platna (≤ 1100), klik na
                        // play bez otvorenog playera bio bi "tihi seek" bez
                        // vizuala — otvori ga. Šire je player stalni stupac.
                        // `_revealPlayer` i ponovi `play()` nakon animacije.
                        if (!showVideo) _revealPlayer();
                      }
                    : null,
                magisterium: magPrimary,
                sponsorMarks: _sponsorMarks,
                onSponsorListen: _videoReady ? _listenSponsor : null,
                sponsoredMarks: _sponsoredMarks,
                sponsoredMoments: _sponsored,
                onSponsoredListen: _videoReady ? _listenSponsored : null,
              ),
              Divider(height: 1, color: theme.colorScheme.outlineVariant),
              const SizedBox(height: 12),
              // Magisterium inline: samo kad NIJE prikazan kao stupac
              // i kad nismo u mobile-tab modu (tamo ima svoj zasebni tab).
              if (hasMag && !showMagColumn && !isMobileWithTabs) ...[
                if (magV2 != null)
                  MagisteriumV2View(data: magV2)
                else
                  MagisteriumPanel(
                    variants: magVariants,
                    magisteriumFull: data.magisteriumFull,
                    magisteriumFullPrompt: data.magisteriumFullPrompt,
                  ),
                Divider(height: 1, color: theme.colorScheme.outlineVariant),
                const SizedBox(height: 12),
              ],
              EntitiesSection(
                summary: summaryForUi.summary,
                highlightPersonSlug: widget.highlightPersonSlug,
              ),
              _MetadataFooter(data: data),
            ],
          ),
        ),
      ),
    );

    // Paralelni desktop sadrzaj: hero/sazetak/poglavlja na citkoj sirini (860),
    // pa clanak ‖ Magisterium per-sekcija na siroj (dijele isti scroll →
    // timestampovi poravnati), pa entiteti/footer natrag na 860. Naslovi
    // stupaca su sticky (SliverPersistentHeader) unutar SliverMainAxisGroup-a
    // pa pinaju samo dok je paralelna zona vidljiva i otpinaju kad odscrolla.
    final List<Widget> parallelSlivers = useParallel
        ? [
            SliverToBoxAdapter(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 860),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      HeroSection(
                        info: data.info,
                        youtubeId: data.youtubeId,
                        summary: summaryForUi.summary,
                      ),
                      // Traka osoba — vidi standardni layout iznad.
                      PeopleRail(
                        summary: summaryForUi.summary,
                        highlightPersonSlug: widget.highlightPersonSlug,
                      ),
                      // "Zid podrške" za epizodu — vidi standardni layout iznad.
                      if (AppBrand.config.flags.pinka)
                        PinkaSupportCard.episode(
                        youtubeId: data.youtubeId,
                        onOpen: (_) => drillDown(
                  context,
                          Uri(
                            path: '/v/${data.youtubeId}/support',
                            queryParameters: {'name': data.displayTitle},
                          ).toString(),
                        ),
                      ),
                      if (data.hasTranslationEn)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                          child: Row(
                            children: [
                              Text(
                                l.episodeLanguageLabel,
                                style: theme.textTheme.labelMedium?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                              const SizedBox(width: 10),
                              LanguageToggleChip(
                                current: _language,
                                onChanged: _onLanguageChanged,
                              ),
                            ],
                          ),
                        ),
                      Divider(
                        height: 1,
                        color: theme.colorScheme.outlineVariant,
                      ),
                      SummarySection(summary: summaryForUi),
                      // E-knjiga — isto mjesto kao u standardnom layoutu.
                      EbookCard(
                        availability: _ebook,
                        title: data.displayTitle,
                        preferEn: _language == EpisodeLanguage.en,
                        episodeUrl: episodeShareUrl(
                          data.youtubeId,
                          lang: _language,
                        ),
                      ),
                      // Sponzori u snimci — isto mjesto kao u standardnom.
                      _sponsorsSection(),
                      Divider(
                        height: 1,
                        color: theme.colorScheme.outlineVariant,
                      ),
                      const SizedBox(height: 12),
                      ChaptersSection(
                        outline: data.outline!,
                        videoId: data.isAudioOnly ? null : data.youtubeId,
                      ),
                      Divider(
                        height: 1,
                        color: theme.colorScheme.outlineVariant,
                      ),
                      const SizedBox(height: 12),
                      _findInEpisodeSection(),
                      Divider(
                        height: 1,
                        color: theme.colorScheme.outlineVariant,
                      ),
                    ],
                  ),
                ),
              ),
            ),
            SliverMainAxisGroup(
              slivers: [
                SliverPersistentHeader(
                  pinned: true,
                  delegate: ParallelColumnsStickyDelegate(
                    // Score je jezicno-neovisan; EN overlay varijanta cesto nema
                    // overall_score pa fallbackamo na HR primary score.
                    overallScore:
                        magPrimary.overallScore ??
                        data.magisteriumPrimary?.overallScore,
                  ),
                ),
                SliverToBoxAdapter(
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 1500),
                      child: ParallelArticleView(
                        article: articleForUi,
                        magisterium: magPrimary,
                        youtubeId: data.youtubeId,
                        sectionKeys: _sectionKeys,
                        showScreenshot: !data.isAudioOnly,
                        highlightTimestamp: _personHighlightTs,
                        highlightPersonName: _personHighlightName,
                        highlightSpeaks: _personHighlightSpeaks,
                        onPlayTap: _videoReady
                            ? (ts) => _seekAndPlay(ts, preroll: true)
                            : null,
                        sponsorMarks: _sponsorMarks,
                        onSponsorListen: _videoReady ? _listenSponsor : null,
                        sponsoredMarks: _sponsoredMarks,
                        sponsoredMoments: _sponsored,
                        onSponsoredListen: _videoReady ? _listenSponsored : null,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            SliverToBoxAdapter(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 860),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Divider(
                        height: 1,
                        color: theme.colorScheme.outlineVariant,
                      ),
                      const SizedBox(height: 12),
                      EntitiesSection(
                summary: summaryForUi.summary,
                highlightPersonSlug: widget.highlightPersonSlug,
              ),
                      _MetadataFooter(data: data),
                    ],
                  ),
                ),
              ),
            ),
          ]
        : const [];

    final scrollBody = _withCreditsBar(
      CustomScrollView(
        controller: _scrollController,
        slivers: useParallel
            ? [appBar, ...parallelSlivers]
            : [appBar, standardContent],
      ),
    );

    // Mobile Magisterium tab — zasebni scroll view s istim SliverAppBar patternom
    Widget? mobileMagScroll;
    if (isMobileWithTabs) {
      mobileMagScroll = CustomScrollView(
        slivers: [
          _episodeAppBar(
            leading: _backLeading(context),
            title: _Breadcrumb(
              channelName: data.info.channel,
              channelSlug: _channelSlug,
              episodeTitle: data.displayTitle,
            ),
            actions: [
              Padding(
                padding: const EdgeInsets.only(right: 4),
                child: Center(
                  child: Text(
                    data.info.id,
                    style: theme.textTheme.labelSmall?.copyWith(
                      fontFamily: 'monospace',
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
              FavoriteButton(
          episodeId: data.youtubeId,
          episodeTitle: data.displayTitle,
          channelName: data.info.channel,
        ),
              ViewModeToggleButton(
                toSimple: true,
                onPressed: () async {
                  await saveSimpleModePref(true);
                  if (!context.mounted) return;
                  swapPresentation(context, '/m/${data.youtubeId}');
                },
              ),
              if (_videoReady)
                Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: IconButton(
                    icon: const Icon(Icons.ondemand_video),
                    tooltip: l.episodeVideo,
                    onPressed: () => _togglePanel(EpisodePanelSide.right),
                  ),
                ),
            ],
          ),
          SliverToBoxAdapter(
            child: Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 860),
                // Preferiraj v2 view ako postoji (noviji format), inace stari Panel.
                child: magV2 != null
                    ? MagisteriumV2View(
                        data: magV2,
                        padding: const EdgeInsets.all(16),
                      )
                    : MagisteriumPanel(
                        variants: magVariants,
                        magisteriumFull: data.magisteriumFull,
                        magisteriumFullPrompt: data.magisteriumFullPrompt,
                      ),
              ),
            ),
          ),
        ],
      );
    }

    // Magisterium stupac — neovisno scrollable, blog-post stil. Samo kad NE
    // koristimo paralelni prikaz (tj. epizoda ima samo V2 esej bez per-sekcija
    // timestampova) — inace Magisterium zivi unutar scrollBody-a.
    Widget? magColumn;
    if (showMagColumn && !useParallel) {
      // V2 view nema fillParent/sectionKeys — wrappamo u SingleChildScrollView
      // da bi stupac imao vlastiti scroll, isto kao stari Panel s fillParent.
      final inner = magV2 != null
          ? SingleChildScrollView(
              child: MagisteriumV2View(
                data: magV2,
                padding: const EdgeInsets.all(20),
              ),
            )
          : MagisteriumPanel(
              variants: magVariants,
              magisteriumFull: data.magisteriumFull,
              magisteriumFullPrompt: data.magisteriumFullPrompt,
              fillParent: true,
              sectionKeys: _magSectionKeys,
            );
      magColumn = Container(
        decoration: BoxDecoration(
          border: Border(
            left: BorderSide(
              color: theme.colorScheme.outlineVariant.withAlpha(80),
            ),
          ),
        ),
        child: inner,
      );
    }

    Widget body;
    if (useParallel) {
      // Paralelni stupci zive UNUTAR scrollBody-a (dijele scroll) → nema
      // zasebnog magColumn-a. Samo TOC (+ video) okolo.
      body = Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TableOfContents(
            article: articleForUi,
            activeTimestamp: _activeTimestamp,
            scrollTimestamp: _scrollTimestamp,
            onSectionTap: _seekAndPlay,
          ),
          Expanded(child: scrollBody),
          if (showVideo)
            VideoPanel(
              player: _player!,
              seekUndo: _seekUndo,
              youtubeId: widget.data.youtubeVideoId,
              audioOnly: data.isAudioOnly,
              posterUrl: _audioArtUrl,
              controller: _videoController!,
              chapters: _videoChapters,
              activeTimestamp: _activeTimestamp,
              scrollTimestamp: _scrollTimestamp,
              onChapterTap: _seekAndPlay,
              onSeek: _onVideoSeek,
              sponsorRanges: _sponsorRanges,
              sponsorsInVideo: _sponsorsInVideo,
              onSponsorListen: _listenSponsor,
              sponsoredMoments: _sponsored,
              onSponsoredListen: _listenSponsored,
              totalDurationSeconds: data.info.duration,
              speakerTimeline: data.speakerTimeline,
              speakers: summaryForUi.summary.speakers,
            ),
        ],
      );
    } else if (showVideo && showMagColumn) {
      // Ultrawide: TOC | content | magisterium | video
      body = Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TableOfContents(
            article: articleForUi,
            activeTimestamp: _activeTimestamp,
            scrollTimestamp: _scrollTimestamp,
            onSectionTap: _seekAndPlay,
          ),
          Expanded(flex: 3, child: scrollBody),
          Expanded(flex: 2, child: magColumn!),
          VideoPanel(
            player: _player!,
            seekUndo: _seekUndo,
            youtubeId: widget.data.youtubeVideoId,
            audioOnly: data.isAudioOnly,
            posterUrl: _audioArtUrl,
            controller: _videoController!,
            chapters: _videoChapters,
            activeTimestamp: _activeTimestamp,
            scrollTimestamp: _scrollTimestamp,
            onChapterTap: _seekAndPlay,
            onSeek: _onVideoSeek,
            sponsorRanges: _sponsorRanges,
            sponsorsInVideo: _sponsorsInVideo,
            onSponsorListen: _listenSponsor,
            sponsoredMoments: _sponsored,
            onSponsoredListen: _listenSponsored,
            totalDurationSeconds: data.info.duration,
            speakerTimeline: data.speakerTimeline,
            speakers: summaryForUi.summary.speakers,
          ),
        ],
      );
    } else if (showMagColumn) {
      // Wide bez videa: TOC | content | magisterium
      body = Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TableOfContents(
            article: articleForUi,
            activeTimestamp: _activeTimestamp,
            onSectionTap: (ts) {
              setState(() => _activeTimestamp = ts);
              _seekAndPlay(ts);
            },
          ),
          Expanded(flex: 3, child: scrollBody),
          Expanded(flex: 2, child: magColumn!),
        ],
      );
    } else if (showVideo) {
      // Desktop wide: TOC | content | video
      body = Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TableOfContents(
            article: articleForUi,
            activeTimestamp: _activeTimestamp,
            scrollTimestamp: _scrollTimestamp,
            onSectionTap: _seekAndPlay,
          ),
          Expanded(child: scrollBody),
          VideoPanel(
            player: _player!,
            seekUndo: _seekUndo,
            youtubeId: widget.data.youtubeVideoId,
            audioOnly: data.isAudioOnly,
            posterUrl: _audioArtUrl,
            controller: _videoController!,
            chapters: _videoChapters,
            activeTimestamp: _activeTimestamp,
            scrollTimestamp: _scrollTimestamp,
            onChapterTap: _seekAndPlay,
            onSeek: _onVideoSeek,
            sponsorRanges: _sponsorRanges,
            sponsorsInVideo: _sponsorsInVideo,
            onSponsorListen: _listenSponsor,
            sponsoredMoments: _sponsored,
            onSponsoredListen: _listenSponsored,
            totalDurationSeconds: data.info.duration,
            speakerTimeline: data.speakerTimeline,
            speakers: summaryForUi.summary.speakers,
          ),
        ],
      );
    } else if (isWide) {
      // Desktop narrow: TOC | content (bez video panela)
      body = Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TableOfContents(
            article: articleForUi,
            activeTimestamp: _activeTimestamp,
            onSectionTap: (ts) {
              setState(() => _activeTimestamp = ts);
              _seekAndPlay(ts);
            },
          ),
          Expanded(child: scrollBody),
        ],
      );
    } else if (isMobileWithTabs) {
      // Mobitel s Magisteriumom: IndexedStack — članak (tab 0) ili Magisterium (tab 1)
      body = IndexedStack(
        index: _mobileTab,
        children: [scrollBody, mobileMagScroll!],
      );
    } else {
      // Mobitel bez Magisteriuma: samo scroll content, TOC u lijevom panelu
      body = scrollBody;
    }

    // Platno je UVIJEK u stablu, i kad nema nijednog panela — inače bi se pri
    // `_videoReady` (desktop) tijelo premjestilo u novo podstablo i članak bi
    // izgubio scroll.
    body = EpisodePanelCanvas(
      key: _panelKey,
      onChanged: _onPanelChanged,
      onCenterReflowStart: _captureReadingAnchor,
      onCenterReflow: _onCenterReflow,
      onCenterReflowEnd: () => _readingAnchor = null,
      center: NotificationListener<UserScrollNotification>(
        onNotification: _onCenterScroll,
        child: body,
      ),
      left: isWide
          ? null
          : TableOfContents(
              article: articleForUi,
              activeTimestamp: _activeTimestamp,
              scrollTimestamp: _scrollTimestamp,
              onSectionTap: _drawerTap,
            ),
      right: _videoReady && !showVideo
          ? VideoPanel(
              player: _player!,
              seekUndo: _seekUndo,
              youtubeId: widget.data.youtubeVideoId,
              audioOnly: data.isAudioOnly,
              posterUrl: _audioArtUrl,
              controller: _videoController!,
              chapters: _videoChapters,
              activeTimestamp: _activeTimestamp,
              onChapterTap: _seekAndPlay,
              onSeek: _onVideoSeek,
              sponsorRanges: _sponsorRanges,
              sponsorsInVideo: _sponsorsInVideo,
              onSponsorListen: _listenSponsor,
              sponsoredMoments: _sponsored,
              onSponsoredListen: _listenSponsored,
              totalDurationSeconds: data.info.duration,
              speakerTimeline: data.speakerTimeline,
              speakers: summaryForUi.summary.speakers,
              width: null,
            )
          : null,
    );

    return EpisodeLanguageScope(
      language: _language,
      hasTranslationEn: data.hasTranslationEn,
      child: PopScope(
        // Back mora prvo zatvoriti otvoreni bočni panel, pa tek onda napustiti
        // epizodu. Panel nije ruta, pa ga Navigator ne vidi kao nešto što se
        // ima popati (s endDrawerom je korisnik ISPADAO IZ EPIZODE).
        canPop: !_anyDrawerOpen,
        onPopInvokedWithResult: (didPop, _) {
          if (didPop || !mounted) return;
          _panelKey.currentState?.close();
        },
        child: Scaffold(
          backgroundColor: theme.colorScheme.surfaceContainerLow,
          // SliverAppBar (primary: true) respektira top safe area, pa top: false.
          // Bottom: true samo kad nema bottomNavigationBara (inace bi stvorilo gap).
          body: SafeArea(
            top: false,
            bottom: !showMobileBottomBar,
            child: Stack(
              children: [
                body,
                Positioned(
                  top: 12,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 220),
                      transitionBuilder: (child, anim) => FadeTransition(
                        opacity: anim,
                        child: SlideTransition(
                          position: Tween<Offset>(
                            begin: const Offset(0, -0.2),
                            end: Offset.zero,
                          ).animate(anim),
                          child: child,
                        ),
                      ),
                      child: _resumeHintSeconds == null
                          ? const SizedBox.shrink()
                          : ResumeHintBanner(
                              key: ValueKey(_resumeHintSeconds),
                              seconds: _resumeHintSeconds!,
                            ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Dno ekrana: "gost" traka (samo neprijavljenima) + sticky "Zid
          // podrške" (sam se sakrije bez aktivne kampanje) + postojeća mobilna
          // navigacija. Donji safe area primjenjuje SAMO vanjski SafeArea —
          // pojedine trake se pale/gase pa nijedna ne zna je li najniža.
          bottomNavigationBar: _immersiveFooter(
            context,
            SafeArea(
              top: false,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const AnonymousSignInBar(applyBottomSafeArea: false),
                  if (AppBrand.config.flags.pinka)
                    PinkaSupportBar.episode(
                    youtubeId: data.youtubeId,
                    channelRefs: _channelSupportRefs,
                    applyBottomSafeArea: false,
                    onOpen: (_, viaChannel) => drillDown(
                      context,
                      _supportPath(viaChannel: viaChannel),
                    ),
                  ),
                  if (showMobileBottomBar)
                    Material(
                      color: theme.colorScheme.surface,
                      elevation: 3,
                      child: SizedBox(
                        height: 64,
                        child: Row(
                          children: [
                            _BottomBarButton(
                              icon: Icons.menu,
                              label: l.episodeContents,
                              isActive: false,
                              onTap: () => _togglePanel(EpisodePanelSide.left),
                            ),
                            if (isMobileWithTabs) ...[
                              _BottomBarButton(
                                icon: _mobileTab == 0
                                    ? Icons.article
                                    : Icons.article_outlined,
                                label: l.episodeArticle,
                                isActive: _mobileTab == 0,
                                onTap: () => setState(() => _mobileTab = 0),
                              ),
                              _BottomBarButton(
                                icon: _mobileTab == 1
                                    ? Icons.menu_book
                                    : Icons.menu_book_outlined,
                                label: 'Magisterium',
                                isActive: _mobileTab == 1,
                                onTap: () => setState(() => _mobileTab = 1),
                              ),
                            ],
                            // Na mobitelu player živi u bočnom panelu, pa je ovo
                            // jedina površina koju korisnik vidi kad hladno otvori
                            // share link. Ako je browser nametnuo muted autoplay,
                            // gumb preuzima ulogu unmutea: tap je user gesture koji
                            // browser traži, pa zvuk pali ODMAH (i usput otvara
                            // player). Bez toga je epizoda u mrtvoj točki — vrti se
                            // bez zvuka i nema se gdje kliknuti.
                            ListenableBuilder(
                              listenable: PlayerMute.instance,
                              builder: (context, _) {
                                final blocked =
                                    PlayerMute.instance.autoplayBlocked;
                                return _BottomBarButton(
                                  icon: blocked
                                      ? Icons.volume_off
                                      : Icons.ondemand_video,
                                  label: blocked
                                      ? l.mediaBoostVolume
                                      : l.episodeVideo,
                                  isActive: blocked,
                                  onTap: _videoReady
                                      ? () {
                                          if (blocked) {
                                            PlayerMute.instance.setMuted(false);
                                            if (!(_player?.state.playing ??
                                                true)) {
                                              _player?.play();
                                            }
                                          }
                                          // Unmute uz već otvoren player ga
                                          // ne smije zatvoriti.
                                          if (blocked && _playerPanelOpen) {
                                            return;
                                          }
                                          _togglePanel(EpisodePanelSide.right);
                                        }
                                      : null,
                                );
                              },
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ---------- basic layout (video without AI pipeline content) -------------

  /// Renderiranje epizode koja jos nije prosla AI obradu — samo player +
  /// osnovne info iz info.json. Trigger: `data.hasAiContent == false`
  /// (article.json je 404 na CDN-u).
  Widget _buildBasicLayout(BuildContext context) {
    final data = widget.data;
    final theme = Theme.of(context);
    final l = AppLocalizations.of(context);
    final width = MediaQuery.sizeOf(context).width;
    final isWide = width > 900;
    final showVideo = _videoReady && width > _kPlayerColumnMinWidth;
    // Ugrađeni YouTube ima smisla samo kad kod nas NEMA što pustiti — inače bi
    // na stranici bila dva playera. Sintetički ID-evi (X, ne-YT izvori) nemaju
    // YouTube video iza sebe.
    final youTubeIsTheOnlyWay =
        data.status.needsExternalSource && !data.info.isX && data.info.ytMatched;
    final embedYouTube = youTubeIsTheOnlyWay &&
        InAppYouTubePlayer.canEmbed(
          playableInEmbed: data.info.playableInEmbed,
        );
    // Web bi embed mogao, ali ga je vlasnik kanala isključio — recimo to
    // naglas umjesto da korisnika bez objašnjenja izbacimo na youtube.com.
    final embedBlocked = youTubeIsTheOnlyWay &&
        youTubeEmbedSupported &&
        !data.info.playableInEmbed;
    // Na širokom ekranu embed ide u desni stupac — na isto mjesto gdje stoji
    // `VideoPanel` kad medija postoji, pa reprodukcija uvijek živi na istoj
    // strani ekrana i ne gura status-karticu ispod pregiba.
    final showEmbedPanel =
        embedYouTube && !showVideo && width > _kPlayerColumnMinWidth;

    final scrollBody = CustomScrollView(
      controller: _scrollController,
      slivers: [
        _episodeAppBar(
          leading: _backLeading(context),
          title: _Breadcrumb(
            channelName: data.info.channel,
            channelSlug: _channelSlug,
            episodeTitle: data.displayTitle,
          ),
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: Center(
                child: Text(
                  data.info.id,
                  style: theme.textTheme.labelSmall?.copyWith(
                    fontFamily: 'monospace',
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
            FavoriteButton(
          episodeId: data.youtubeId,
          episodeTitle: data.displayTitle,
          channelName: data.info.channel,
        ),
            IconButton(
              icon: const Icon(Icons.share_outlined),
              tooltip: l.episodeCopyMomentLink,
              onPressed: () => _copyMomentLink(context, data.youtubeId),
            ),
            if (_sourceAction(data) != null) _sourceAction(data)!,
            if (_videoReady && !showVideo)
              Padding(
                padding: const EdgeInsets.only(right: 4),
                child: IconButton(
                  icon: const Icon(Icons.ondemand_video),
                  tooltip: l.episodeVideo,
                  onPressed: () => _togglePanel(EpisodePanelSide.right),
                ),
              ),
          ],
        ),
        SliverToBoxAdapter(
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 860),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    HeroSection(info: data.info, youtubeId: data.youtubeId),
                    const SizedBox(height: 20),
                    // In-app YouTube player — jedina reprodukcija kad medije
                    // kod nas nema (faza `queued`/`fetched`). Facade, pa
                    // iframe krene tek na korisnikov tap.
                    if (embedYouTube && !showEmbedPanel) ...[
                      InAppYouTubePlayer(
                        videoId: data.youtubeVideoId,
                        posterUrl: CdnConfig.thumbnailUrl(data.youtubeId),
                      ),
                      const SizedBox(height: 20),
                    ],
                    EpisodeStatusCard(
                      status: data.status,
                      audioOnly: data.isAudioOnly,
                    ),
                    const SizedBox(height: 16),
                    // Transkript postoji prije članka — pretraga radi već tada,
                    // a s njom i skok na izgovorenu riječ.
                    if (_videoReady &&
                        data.status.stage.index >=
                            EpisodeStage.transcribed.index) ...[
                      FindInEpisodeSection(
                        youtubeId: data.youtubeId,
                        horizontalPadding: 0,
                        onJump: (sec) {
                          _seekToAndPlay(Duration(seconds: sec));
                          _revealPlayer();
                        },
                      ),
                      const SizedBox(height: 16),
                    ],
                    // Primarna radnja slijedi FAZU, ne izvor: kad je medija
                    // kod nas, korisnika vodimo u naš player. Na uskom ekranu
                    // je player u endDraweru, pa bez ovog gumba na mobitelu
                    // nema vidljivog načina da se epizoda uopće pusti — dosad
                    // je i takva epizoda nudila samo odlazak na YouTube.
                    if (_videoReady && !showVideo)
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: _openPlayerPanel,
                          icon: Icon(
                            data.isAudioOnly
                                ? Icons.headphones
                                : Icons.play_arrow,
                          ),
                          label: Text(
                            data.isAudioOnly
                                ? l.episodeListen
                                : l.episodeWatchOurPlayer,
                          ),
                          style: FilledButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                        ),
                      ),
                    // X/Twitter izvor: sintetički `id` — NIKAD YouTube link.
                    // Vodi na izvorni X post (webpage_url).
                    if (data.info.isX && data.info.sourceUrl != null)
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: () => openUrl(data.info.sourceUrl!),
                          icon: const Text('𝕏', style: TextStyle(fontSize: 18)),
                          label: Text(l.episodeOpenOnX),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                        ),
                      )
                    // Odlazak na YouTube nosi crveni naglasak SAMO kad je
                    // doista jedini put do reprodukcije. Kad epizodu možemo
                    // pustiti sami (embed na stranici ili naš player), spušta
                    // se na tihu poveznicu da ne konkurira primarnoj radnji.
                    else if (!data.info.isX && data.info.ytMatched)
                      Padding(
                        padding: EdgeInsets.only(top: _videoReady ? 8 : 0),
                        child: SizedBox(
                          width: double.infinity,
                          child: (embedYouTube || _videoReady)
                              ? TextButton.icon(
                                  onPressed: () => openUrl(
                                    'https://www.youtube.com/watch?v=${data.youtubeVideoId}',
                                  ),
                                  icon: const Icon(Icons.open_in_new, size: 18),
                                  label: Text(l.episodeOpenOnYouTube),
                                )
                              : FilledButton.icon(
                                  onPressed: () => openUrl(
                                    'https://www.youtube.com/watch?v=${data.youtubeVideoId}',
                                  ),
                                  icon: const Icon(Icons.smart_display),
                                  label: Text(l.episodeWatchOnYouTube),
                                  style: FilledButton.styleFrom(
                                    backgroundColor: const Color(0xFFFF0000),
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 14,
                                    ),
                                  ),
                                ),
                        ),
                      )
                    else if (data.info.sourceUrl != null)
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: () => openUrl(data.info.sourceUrl!),
                          icon: const Icon(Icons.open_in_new),
                          label: Text(l.commonOpenSource),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                        ),
                      ),
                    if (embedBlocked)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          l.episodeEmbedBlocked,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );

    Widget body;
    if (showEmbedPanel) {
      body = Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: scrollBody),
          _YouTubeSidePanel(
            youtubeId: data.youtubeId,
            videoId: data.youtubeVideoId,
          ),
        ],
      );
    } else if (showVideo) {
      body = Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: scrollBody),
          VideoPanel(
            player: _player!,
            seekUndo: _seekUndo,
            youtubeId: widget.data.youtubeVideoId,
            audioOnly: data.isAudioOnly,
            posterUrl: _audioArtUrl,
            controller: _videoController!,
            chapters: const [],
            onChapterTap: (_) {},
            onSeek: _onVideoSeek,
            sponsorRanges: _sponsorRanges,
            sponsorsInVideo: _sponsorsInVideo,
            onSponsorListen: _listenSponsor,
            sponsoredMoments: _sponsored,
            onSponsoredListen: _listenSponsored,
            totalDurationSeconds: data.info.duration,
            speakerTimeline: data.speakerTimeline,
          ),
        ],
      );
    } else {
      body = scrollBody;
    }

    // Isti model kao standardni layout: player je desni stupac platna.
    body = EpisodePanelCanvas(
      key: _panelKey,
      onChanged: _onPanelChanged,
      center: NotificationListener<UserScrollNotification>(
        onNotification: _onCenterScroll,
        child: body,
      ),
      right: _videoReady && !showVideo
          ? VideoPanel(
              player: _player!,
              seekUndo: _seekUndo,
              youtubeId: widget.data.youtubeVideoId,
              audioOnly: data.isAudioOnly,
              posterUrl: _audioArtUrl,
              controller: _videoController!,
              chapters: const [],
              onChapterTap: (_) {},
              onSeek: _onVideoSeek,
              sponsorRanges: _sponsorRanges,
              sponsorsInVideo: _sponsorsInVideo,
              onSponsorListen: _listenSponsor,
              sponsoredMoments: _sponsored,
              onSponsoredListen: _listenSponsored,
              totalDurationSeconds: data.info.duration,
              speakerTimeline: data.speakerTimeline,
              width: null,
            )
          : null,
    );

    return PopScope(
      canPop: !_anyDrawerOpen,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop || !mounted) return;
        _panelKey.currentState?.close();
      },
      child: Scaffold(
        backgroundColor: theme.colorScheme.surfaceContainerLow,
        body: SafeArea(
          top: false,
          bottom: !isWide,
          child: Stack(
            children: [
              body,
              Positioned(
                top: 12,
                left: 0,
                right: 0,
                child: Center(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 220),
                    transitionBuilder: (child, anim) => FadeTransition(
                      opacity: anim,
                      child: SlideTransition(
                        position: Tween<Offset>(
                          begin: const Offset(0, -0.2),
                          end: Offset.zero,
                        ).animate(anim),
                        child: child,
                      ),
                    ),
                    child: _resumeHintSeconds == null
                        ? const SizedBox.shrink()
                        : ResumeHintBanner(
                            key: ValueKey(_resumeHintSeconds),
                            seconds: _resumeHintSeconds!,
                          ),
                  ),
                ),
              ),
            ],
          ),
        ),
        // "Gost" traka + sticky "Zid podrške" iznad (opcionalne) mobilne
        // navigacije — vidi standardni layout gore.
        bottomNavigationBar: _immersiveFooter(
          context,
          SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const AnonymousSignInBar(applyBottomSafeArea: false),
                if (AppBrand.config.flags.pinka)
                  PinkaSupportBar.episode(
                  youtubeId: data.youtubeId,
                  channelRefs: _channelSupportRefs,
                  applyBottomSafeArea: false,
                  onOpen: (_, viaChannel) =>
                      drillDown(context, _supportPath(viaChannel: viaChannel)),
                ),
                if (!isWide)
                  Material(
                    color: theme.colorScheme.surface,
                    elevation: 3,
                    child: SizedBox(
                      height: 64,
                      child: Row(
                        children: [
                          _BottomBarButton(
                            icon: Icons.ondemand_video,
                            label: l.episodeVideo,
                            isActive: false,
                            onTap: _videoReady
                                ? () => _togglePanel(EpisodePanelSide.right)
                                : null,
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------

class _MetadataFooter extends StatelessWidget {
  final EpisodeData data;

  const _MetadataFooter({required this.data});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l = AppLocalizations.of(context);
    // Footer se renderira samo iz full layout-a, koji je guarded
    // `data.hasAiContent` granom na vrhu _EpisodeContent.build() — pa su
    // summary/article ovdje garantirano non-null.
    final summary = data.summary!;
    final article = data.article!;

    return Container(
      color: theme.colorScheme.surfaceContainerHighest,
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l.episodeMetadata,
            style: theme.textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.bold,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          _MetaRow('YouTube ID', data.info.id),
          _MetaRow(l.episodeMetaChannel, data.info.channel),
          _MetaRow(l.episodeMetaModelSummary, summary.model),
          _MetaRow(l.episodeMetaModelArticle, article.metadata.model),
          if (data.magisteriumPrimary != null)
            _MetaRow(
              l.episodeMetaModelTheology,
              data.magisteriumPrimary!.model,
            ),
          _MetaRow(
            l.episodeMetaGenerated,
            summary.generatedAt.toIso8601String().substring(0, 10),
          ),
          _MetaRow(
            l.episodeMetaLanguage,
            summary.summary.language.toUpperCase(),
          ),
          _MetaRow(l.episodeMetaContentType, summary.summary.contentType),
          _MetaRow(l.episodeMetaSentiment, summary.summary.sentiment),
        ],
      ),
    );
  }
}

class _BottomBarButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isActive;
  final VoidCallback? onTap;

  const _BottomBarButton({
    required this.icon,
    required this.label,
    required this.isActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final Color color;
    if (onTap == null) {
      color = theme.colorScheme.onSurfaceVariant.withAlpha(80);
    } else if (isActive) {
      color = theme.colorScheme.primary;
    } else {
      color = theme.colorScheme.onSurfaceVariant;
    }

    return Expanded(
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 22, color: color),
              const SizedBox(height: 2),
              Text(
                label,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: color,
                  fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MetaRow extends StatelessWidget {
  final String label;
  final String value;

  const _MetaRow(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          SizedBox(
            width: 140,
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: theme.textTheme.bodySmall?.copyWith(
                fontFamily: 'monospace',
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Episode SliverAppBar s responsivnim rasporedom akcija. Na mobitelu
/// (twoRow=true) breadcrumb ostaje u gornjem redu, a akcije se sele u drugi red
/// (bottom) — inače se breadcrumb + 6-7 akcija prelijeva na uskom ekranu i
/// "većina buttona se ne vidi". Akcije u drugom redu su desno-poravnate i
/// horizontalno skrolabilne (touch), pa nikad ne overflowaju. Desktop/tablet:
/// akcije inline kao prije.
/// [leading] je gumb ← i postoji SAMO kad ima što popati.
///
/// Do 6.9.2026. epizoda nije imala gumb „nazad" uopće (`automaticallyImplyLeading:
/// false`, samo breadcrumb), pa na iOS-u — gdje edge-swipe ne radi jer stog nije
/// postojao — nije bilo izlaza osim breadcrumba „Početna", koji je na uskom
/// ekranu često bio odscrollan izvan vidljivog. `automaticallyImplyLeading`
/// ostaje `false` jer bi Flutterov ugrađeni ← ignorirao `titleSpacing: 0` koji
/// breadcrumb treba.
/// Gumb ← samo kad postoji stog. Bez njega breadcrumb ostaje jedini izlaz, a
/// `titleSpacing: 0` puni rub — pa se ne troši mjesto na prazan slot.
Widget? _backLeading(BuildContext context) {
  if (!context.canPop()) return null;
  return IconButton(
    icon: const Icon(Icons.arrow_back),
    tooltip: AppLocalizations.of(context).commonBack,
    onPressed: () => back(context),
  );
}

/// Iznad ove širine player je stalni desni stupac; ispod nje je bočni panel
/// [EpisodePanelCanvas] koji se otvara/zatvara.
const double _kPlayerColumnMinWidth = 1100;

/// Mobitel položen u landscape: iOS/Android (na webu je to OS preglednika) i
/// kratka strana ispod 600 px. Tu header i footer epizode ustupaju mjesto
/// članku i playeru (vidi `_chromeHidden`). Bez uvjeta platforme bi nizak
/// prozor preglednika na laptopu (1000×560, devtools dolje) izgubio header.
bool _isPhoneLandscape(BuildContext context) {
  final platform = Theme.of(context).platform;
  if (platform != TargetPlatform.iOS && platform != TargetPlatform.android) {
    return false;
  }
  final size = MediaQuery.sizeOf(context);
  return size.width > size.height && size.shortestSide < 600;
}

/// Episode app bar. Dva reda se biraju po širini STUPCA (`crossAxisExtent`),
/// ne ekrana: na mobitelu u landscapeu članak dijeli ekran s playerom
/// ([EpisodePanelCanvas]) pa je 844 px ekrana samo ~480 px app bara.
Widget _episodeAppBar({
  required Widget title,
  required List<Widget> actions,
  Widget? leading,
}) {
  return SliverLayoutBuilder(
    builder: (context, constraints) {
      final w = constraints.crossAxisExtent;
      final immersive = _isPhoneLandscape(context);
      // I `_Breadcrumb` bira raspored po `MediaQuery` širini — dajemo mu
      // širinu stupca, inače u landscapeu crta desktopni breadcrumb u 480 px.
      final mq = MediaQuery.of(context);
      return MediaQuery(
        data: mq.copyWith(size: Size(w, mq.size.height)),
        child: _episodeSliverAppBar(
          title: title,
          actions: actions,
          twoRow: w < 600,
          immersive: immersive,
          leading: leading,
        ),
      );
    },
  );
}

SliverAppBar _episodeSliverAppBar({
  required Widget title,
  required List<Widget> actions,
  required bool twoRow,
  required bool immersive,
  Widget? leading,
}) {
  return SliverAppBar(
    // Landscape na mobitelu: app bar odlazi s čitanjem, a povlačenje prema
    // dolje (scroll prema gore) ga odmah vrati — visina je ondje prevrijedna
    // za stalno prikovanu traku od 102 px.
    pinned: !immersive,
    floating: immersive,
    snap: immersive,
    automaticallyImplyLeading: false,
    leading: leading,
    // 0 jer _Breadcrumb nosi vlastiti rubni padding (na mobitelu kao content
    // padding UNUTAR horizontalnog scrolla — vidi komentar u _Breadcrumb).
    titleSpacing: leading == null ? 0 : null,
    title: title,
    actions: twoRow ? null : actions,
    bottom: twoRow
        ? PreferredSize(
            preferredSize: const Size.fromHeight(46),
            child: SizedBox(
              height: 46,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                reverse: true,
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Row(mainAxisSize: MainAxisSize.min, children: actions),
              ),
            ),
          )
        : null,
  );
}
