/// Vlastiti Google Cast receiver — App ID i ugovor `customData` koji mu
/// pošiljatelj šalje uz `MediaInformation`.
///
/// Receiver je statična stranica `web/cast-receiver.html` u ljusci (servira je
/// `web/_worker.js` bez COOP/COEP). Televizor iz `customData` crta traku
/// „Sponzorirano · {brand}" za plaćene trenutke (DSA čl. 26) — sam ne dohvaća
/// ništa osim medija i slika koje mu ovdje navedemo. Plan, iteracija C:
/// `docs/plans/2026-10-17-cast-na-tv.md` („Ugovor customData").
///
/// **Ugovor živi na dva mjesta**: ovdje i u `parseMoments` u
/// `web/cast-receiver.html`. Promjena oblika podiže [kCastCustomDataVersion]
/// na obje strane; receiver nepoznatu verziju preskače (bez trake), umjesto da
/// nagađa.
library;

import '../models/sponsored_moment.dart';

/// App ID receivera iz Google Cast SDK Developer Console.
///
/// Prazan dok korisnik ne registrira aplikaciju tipa *Custom Receiver* s URL-om
/// `https://domovina.ai/cast-receiver.html`. Build ga dobiva kroz
/// `--dart-define=CAST_RECEIVER_APP_ID=XXXXXXXX` (8 heksadecimalnih znakova).
/// Bez njega Cast ne postoji: pošiljatelj NE pada na Default Media Receiver,
/// jer taj ne zna za sponzorsku oznaku (odluka u planu, iteracija C).
///
/// Na iOS-u je App ID i u `Info.plist` (`NSBonjourServices`:
/// `_<APP_ID>._googlecast._tcp`), pa promjena traži novi store build.
const String castReceiverAppId = String.fromEnvironment('CAST_RECEIVER_APP_ID');

/// Je li receiver registriran i upisan u ovaj build.
bool get castReceiverConfigured => isValidCastAppId(castReceiverAppId);

/// Cast App ID je 8 heksadecimalnih znakova (velika slova u konzoli).
bool isValidCastAppId(String id) => RegExp(r'^[0-9A-Fa-f]{8}$').hasMatch(id);

/// Verzija oblika [castCustomData]; mora biti jednaka `CUSTOM_DATA_VERSION`
/// u `web/cast-receiver.html`.
const int kCastCustomDataVersion = 1;

/// `customData` za `MediaInformation` jedne epizode.
///
/// [sponsored] su trenuci živi U TRENUTKU SLANJA (`SponsoredMoments.liveAt`)
/// — receiver ne zna za `live_until` i ne osvježava ništa. [sponsoredLabel] je
/// već lokalizirana riječ „Sponzorirano" (`AppLocalizations.sponsoredLabel`),
/// pa receiver nema vlastiti i18n.
///
/// `link_url` se namjerno ne šalje: na televizoru nema što kliknuti. Logo ide
/// samo kao `https://` (receiver drugo odbacuje).
Map<String, Object?> castCustomData({
  required String videoId,
  required SponsoredMoments sponsored,
  required String sponsoredLabel,
}) {
  return {
    'v': kCastCustomDataVersion,
    'videoId': videoId,
    'labels': {'sponsored': sponsoredLabel},
    'sponsored': [
      for (final m in sponsored.moments)
        {
          'slot': m.slotKey,
          'start': m.start,
          'end': m.end,
          'brand': m.brand,
          if (m.tagline != null) 'tagline': m.tagline,
          if (_isHttps(m.logoUrl)) 'logo': m.logoUrl,
        },
    ],
  };
}

bool _isHttps(String? url) {
  if (url == null) return false;
  final uri = Uri.tryParse(url);
  return uri != null && uri.isScheme('https') && uri.host.isNotEmpty;
}
