import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../services/cdn_config.dart';
import '../src/log.dart' show log;
import 'web_bitmap_image_stub.dart'
    if (dart.library.js_interop) 'web_bitmap_image_web.dart';

/// Cached network thumbnail s konzistentnim placeholder + error state-om.
///
/// Wraps [CachedNetworkImage] kao drop-in zamjenu za [Image.network].
/// Disk-persistent cache (preživljava app restart) + sivi placeholder dok
/// slika loadira + standardni error widget. Cache key = URL, pa CDN
/// cache-buster URLs (`?v=…`) prirodno invalidiraju stari fajl.
///
/// Default placeholder: `theme.colorScheme.surfaceContainerHighest` sivi
/// pravokutnik bez ikone — diskretan, ne distrahira korisnika dok ceka.
/// Pri error-u prikazuje ikonu (default `broken_image_outlined`) na istoj
/// pozadini.
///
/// ## Automatske WebP varijante
///
/// Ako je [url] kanonski thumbnail (`/images/{id}/thumbnail.png`), widget ga
/// SAM zamijeni WebP varijantom primjerenom stvarnoj render-širini
/// (`thumb-320/640/1280.webp`). Nijedan call-site ne mora znati za varijante —
/// zato logika živi ovdje, a ne u ~12 mjesta koja zovu `CdnConfig.thumbnailUrl`.
///
/// Razlog: PNG original je 1280×720, tipično ~800 KB. Lista od 20 epizoda
/// povlači ~16 MB. Ista slika kao WebP q80 @320px je ~13 KB — 61× manje
/// (mjereno na produkcijskom `KvJlt9ewgTQ`). To je bio pravi uzrok sporog
/// učitavanja listi, a ne broj paralelnih HTTP requestova.
///
/// Varijante su unaprijed generirane (`fetch.domovina.tv/generate_webp_thumbs.js`)
/// i leže na R2 kao statični immutable fajlovi — nema resize servisa u request
/// pathu, sve ide s Cloudflare edge cachea.
///
/// **Fallback**: ako varijanta vrati grešku, widget se tiho vrati na originalni
/// PNG. Pokriva oba uzroka — 404 (epizoda koju backfill još nije pokrio, ili
/// nova epizoda prije nego pipeline odradi KORAK 9.7) i neuspjeh dekodiranja
/// (browser bez WebP podrške). Ne razlikujemo ta dva uzroka i ne moramo —
/// ishod je isti. U sretnom slučaju fallback ne košta nijedan dodatni request —
/// nema probe-a unaprijed. Ako padne i PNG, zove se `onFailed`.
///
/// ## Podrška za WebP dekodiranje
///
/// Na **nativeu** (iOS/Android/macOS) sliku dekodira Skia unutar Flutter
/// enginea — WebP radi bez obzira na OS verziju.
///
/// Na **webu** dekodira BROWSER (Flutter napravi blob i pusti ga kroz
/// `createImageBitmap`/`<img>`), pa podrška prati browser: Chrome 32+,
/// Firefox 65+, Edge 18+, **Safari 14+ / iOS Safari 14+** (rujan 2020.).
/// Realno pokriveno ~97 % prometa, a jedini rupa (iOS ≤ 13) ionako ne vrti
/// Flutter web smisleno. I da pukne, gornji fallback vrati PNG — degradacija
/// je "sporije", ne "prazna slika".
///
/// (Za `og:image` i dijeljenje na društvenim mrežama se NE koristi WebP nego
/// `og-share.jpg` — link-preview crawleri WebP ne dokumentiraju.)
///
/// ## CORS je tvrdi uvjet
///
/// [CachedNetworkImage] povlači bajtove kroz `package:http`, pa URL MORA imati
/// `access-control-allow-origin`. `cdn.domovina.ai` ga ima (`*`) za sve slike.
/// Ne prosljeđuj ovamo URL-ove sa stranih hostova bez provjere — `Image.network`
/// na webu ima `<img>` fallback koji CORS preživi, a ovaj widget nema.
/// Vidi istu zamku u `audio_poster.dart`.
class CachedThumbnail extends StatefulWidget {
  final String url;
  final double? width;
  final double? height;
  final BoxFit fit;

  /// Icon prikazan ako fetch fail-a (npr. `Icons.podcasts_outlined` za
  /// channel cover, `Icons.broken_image_outlined` za episode thumb).
  final IconData errorIcon;
  final double errorIconSize;

  /// Fade-in duration kad slika stigne nakon placeholder-a. Krátko da
  /// rail scroll ostane responsivan.
  final Duration fadeInDuration;

  /// Escape hatch: `false` prisiljava originalni [url] bez WebP nadogradnje.
  /// Koristi samo ako ti stvarno treba baš original (npr. share/export flow).
  final bool useVariants;

  /// Izričita varijanta koja se pokušava PRIJE [url] (npr. WebP screenshota);
  /// kad padne, render ide na [url] istim putem kao automatska thumb varijanta.
  final String? variantUrl;

  /// Poziva se kad slika KONAČNO ne uspije — dakle tek nakon što je i fallback
  /// na originalni PNG pao, ne na neuspjeh same WebP varijante. Za call-siteove
  /// koji na nepostojeću sliku ne crtaju placeholder nego kolabiraju cijeli
  /// blok (hero, screenshot u članku). Poziv je već odgođen post-frame, pa
  /// [setState] unutar njega smiješ zvati izravno.
  final VoidCallback? onFailed;

  /// Zamjenjuje default error prikaz (obojani pravokutnik + [errorIcon]) kad
  /// call-site na nedostupnu sliku crta nešto svoje — npr. gradijentni backdrop
  /// heroa. Zove se SAMO pri konačnom neuspjehu; dok se pokušava fallback s
  /// WebP varijante na PNG i dalje se prikazuje neutralni placeholder, da
  /// korisnik ne vidi bljesak greške prije nego slika sjedne.
  final WidgetBuilder? errorFallbackBuilder;

  const CachedThumbnail({
    super.key,
    required this.url,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.errorIcon = Icons.broken_image_outlined,
    this.errorIconSize = 32,
    this.fadeInDuration = const Duration(milliseconds: 200),
    this.useVariants = true,
    this.variantUrl,
    this.onFailed,
    this.errorFallbackBuilder,
  });

  @override
  State<CachedThumbnail> createState() => _CachedThumbnailState();
}

/// Koliko puta se ista adresa pokušava ponovno prije nego se odustane od nje.
/// Varijanta (WebP) dobiva jedan ponovni pokušaj pa pada na PNG; PNG dva.
const int _kVariantRetries = 1;
const int _kOriginalRetries = 2;
const List<Duration> _kRetryDelays = [
  Duration(milliseconds: 700),
  Duration(seconds: 2),
];

class _CachedThumbnailState extends State<CachedThumbnail> {
  /// Postane `true` kad WebP varijanta konačno pukne → render pada na PNG.
  bool _variantFailed = false;

  /// Redni broj pokušaja za TRENUTNU adresu. Ulazi u ključ
  /// [CachedNetworkImage], pa novi pokušaj gradi novo stablo i ponovno
  /// razrješava sliku (stari `Image` state bi ostao zaglavljen u grešci).
  int _attempt = 0;

  /// Pokušaj za koji je ponovni pokušaj već zakazan — `errorWidget` se zove
  /// iz svakog builda, a zakazati se smije jednom.
  int? _scheduledFor;
  Timer? _retryTimer;

  @override
  void dispose() {
    _retryTimer?.cancel();
    super.dispose();
  }

  @override
  void didUpdateWidget(CachedThumbnail oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Novi URL = nova slika; prošli neuspjeh se ne prenosi (recikliranje
    // widgeta u ListView-u bi inače trajno zaključalo fallback na PNG).
    if (oldWidget.url != widget.url ||
        oldWidget.variantUrl != widget.variantUrl) {
      _variantFailed = false;
      _resetAttempts();
    }
  }

  void _resetAttempts() {
    _retryTimer?.cancel();
    _retryTimer = null;
    _attempt = 0;
    _scheduledFor = null;
  }

  /// Greška pri učitavanju [url]. Prije je PRVA greška bila konačna: WebP je
  /// trajno prelazio na PNG (~800 KB), a pad PNG-a ostavljao ikonu do
  /// ponovnog otvaranja ekrana. Na iOS pregledniku greške su često prolazne
  /// (memorija/grafički kontekst), pa se ista adresa prvo pokuša ponovno.
  void _onLoadError(String url, Object error, {required bool isVariant}) {
    if (_scheduledFor == _attempt) return;
    _scheduledFor = _attempt;
    final cache = PaintingBinding.instance.imageCache;
    final maxRetries = isVariant ? _kVariantRetries : _kOriginalRetries;
    final willRetry = _attempt < maxRetries;
    log('CachedThumbnail: greška (${isVariant ? 'varijanta' : 'original'}, '
        'pokušaj ${_attempt + 1}/${maxRetries + 1}'
        '${willRetry ? '' : isVariant ? ', prelazim na PNG' : ', ODUSTAJEM'}) '
        '$url — ${error.runtimeType}: $error | imageCache '
        '${cache.currentSize} slika / '
        '${(cache.currentSizeBytes / 1048576).toStringAsFixed(1)} MB, '
        'live ${cache.liveImageCount}, pending ${cache.pendingImageCount}');

    if (willRetry) {
      final delay = _kRetryDelays[_attempt.clamp(0, _kRetryDelays.length - 1)];
      _retryTimer?.cancel();
      _retryTimer = Timer(delay, () {
        if (!mounted) return;
        // Web: ImageCache neuspjelu sliku ne zadržava, novi ključ je dosta.
        if (!kIsWeb) unawaited(CachedNetworkImage.evictFromCache(url));
        setState(() => _attempt++);
      });
      return;
    }
    if (isVariant) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _variantFailed) return;
        setState(() {
          _variantFailed = true;
          _resetAttempts();
        });
      });
      return;
    }
    if (widget.onFailed != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) widget.onFailed!.call();
      });
    }
  }

  /// Je li za trenutnu adresu iscrpljen broj pokušaja (konačna greška).
  bool _exhausted(bool isVariant) {
    final maxRetries = isVariant ? _kVariantRetries : _kOriginalRetries;
    return _scheduledFor == _attempt && _attempt >= maxRetries;
  }

  /// Efektivna render-širina u logičkim pikselima. Ako [widget.width] nije
  /// zadan (slika puni parent), koristimo širinu ekrana kao gornju ogradu —
  /// pesimistično, ali nikad premalo.
  double _renderWidthLogical(BuildContext context) {
    final w = widget.width;
    if (w != null && w.isFinite && w > 0) return w;
    return MediaQuery.sizeOf(context).width;
  }

  /// Vraća URL koji stvarno treba dohvatiti: WebP varijantu ako je moguće,
  /// inače originalni [widget.url].
  String _resolveUrl(BuildContext context, double dpr) {
    if (!widget.useVariants || _variantFailed) return widget.url;
    if (widget.variantUrl != null) return widget.variantUrl!;

    final match = CdnConfig.thumbnailUrlPattern.firstMatch(widget.url);
    if (match == null) return widget.url;

    final ytId = match.group(1)!;
    final targetPx = _renderWidthLogical(context) * dpr;
    return CdnConfig.thumbnailVariantUrl(
      ytId,
      CdnConfig.pickThumbWidth(targetPx),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final resolvedUrl = _resolveUrl(context, dpr);
    final isVariant = resolvedUrl != widget.url;
    // Resample na render-širinu — HD thumbovi (1280×720) na ~128–360 dp
    // karticama ne trebaju puni bitmap u memoriji.
    final memWidth = widget.width != null && widget.width!.isFinite
        ? (widget.width! * dpr).round()
        : null;

    final placeholder = Container(
      width: widget.width,
      height: widget.height,
      color: theme.colorScheme.surfaceContainerHighest,
    );

    // Greška ide kroz error builder, a ne kroz listener: on SIGURNO prolazi
    // kroz build kad load padne. Dok traju ponovni pokušaji i prijelaz s
    // WebP-a na PNG, crta se neutralni placeholder, da korisnik ne vidi
    // bljesak greške prije slike. `_onLoadError` sve promjene stanja odgađa
    // (timer / post-frame), jer se zove iz build faze.
    //
    // NAPOMENA: ovaj put nije pokriven automatskim testom; pokriven je samo
    // izbor URL-a u `test/cdn_thumbnail_variants_test.dart`. Ako mijenjaš ovu
    // granu, provjeri ručno na epizodi kojoj `thumb-*.webp` 404-a a
    // `thumbnail.png` postoji.
    Widget errorView(BuildContext ctx, String url, Object error) {
      _onLoadError(url, error, isVariant: isVariant);
      if (isVariant || !_exhausted(false)) return placeholder;
      final custom = widget.errorFallbackBuilder;
      if (custom != null) return custom(ctx);
      return Container(
        width: widget.width,
        height: widget.height,
        color: theme.colorScheme.surfaceContainerHighest,
        alignment: Alignment.center,
        child: Icon(
          widget.errorIcon,
          color: theme.colorScheme.onSurfaceVariant,
          size: widget.errorIconSize,
        ),
      );
    }

    final key = ValueKey('$resolvedUrl#$_attempt');

    // Web: vlastiti provider kroz `createImageBitmap`, NE CachedNetworkImage.
    // Paket na webu (oba načina, `HtmlImage` i `HttpGet`) završi u enginovom
    // `<img>` dekoderu, koji na iOS WebKitu pri ponovnom prikazu pada. Vidi
    // `web_bitmap_image_web.dart`.
    if (kIsWeb) {
      return Image(
        key: key,
        image: WebBitmapImage(resolvedUrl, targetWidth: memWidth),
        width: widget.width,
        height: widget.height,
        fit: widget.fit,
        frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
          if (wasSynchronouslyLoaded) return child;
          return AnimatedSwitcher(
            duration: widget.fadeInDuration,
            child: frame == null
                ? KeyedSubtree(key: const ValueKey(0), child: placeholder)
                : KeyedSubtree(key: const ValueKey(1), child: child),
          );
        },
        errorBuilder: (ctx, error, _) => errorView(ctx, resolvedUrl, error),
      );
    }

    return CachedNetworkImage(
      key: key,
      imageUrl: resolvedUrl,
      width: widget.width,
      height: widget.height,
      fit: widget.fit,
      fadeInDuration: widget.fadeInDuration,
      memCacheWidth: memWidth,
      placeholder: (_, _) => placeholder,
      errorWidget: errorView,
    );
  }
}
