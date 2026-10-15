/// Jezgra aplikacije: sve što je zajedničko DOMOVINA.ai i Podcasteriumu.
///
/// Ljuska (aplikacija) uvozi samo ovaj barrel i poziva [runPodcastApp].
/// Ostatak paketa (`src/`, `screens/`, `services/`…) je implementacijski
/// detalj — ne uvoziti ga iz ljuske.
library;

export 'auth/auth_provider_plugin.dart';
export 'push/push_transport.dart';
export 'brand/app_brand.dart' show AppBrand;
export 'brand/brand_config.dart';
export 'brand/domovina_brand.dart' show domovinaBrand;
export 'src/app.dart' show runPodcastApp, PodcastApp, rootScaffoldMessengerKey;
export 'src/log.dart' show log, appVersion;
// Za plugine ljuske: lokalizirane poruke bez BuildContext-a.
export 'services/locale_service.dart' show appStrings;
