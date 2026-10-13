/// Iz lokacije rutera izvlači ono po čemu se u analitici filtrira: video,
/// kanal, osobu. Čista funkcija — ugovor čuva `test/analytics_test.dart`.
///
/// Popis putanja prati `lib/router/app_router.dart`; nova content ruta koja
/// nosi ID epizode ili kanala ide i ovamo.
library;

class ScreenInfo {
  const ScreenInfo({
    required this.route,
    this.videoId,
    this.channel,
    this.person,
  });

  /// Putanja bez `/t/<sec>` sufiksa i bez query stringa: pomak u epizodi nije
  /// novi ekran, a `url_sync` ga ionako prepisuje bez rutera.
  final String route;
  final String? videoId;
  final String? channel;
  final String? person;

  /// Ključ za odbacivanje uzastopnog istog ekrana.
  String get key => route;
}

final _videoRoute = RegExp(r'^/(v|m|yt)/([A-Za-z0-9_-]{1,64})(/|$)');
final _channelRoute = RegExp(r'^/c/([^/?#]{1,128})');
final _personRoute = RegExp(r'^/p/([^/?#]{1,128})');
final _timestamp = RegExp(r'/t/\d+(?=/|$)');

ScreenInfo screenInfoFor(Uri uri) {
  var path = uri.path.isEmpty ? '/' : uri.path;
  path = path.replaceFirst(_timestamp, '');
  if (path.length > 1 && path.endsWith('/')) {
    path = path.substring(0, path.length - 1);
  }
  final video = _videoRoute.firstMatch(path)?.group(2);
  final channel = _channelRoute.firstMatch(path)?.group(1);
  final person = _personRoute.firstMatch(path)?.group(1);
  return ScreenInfo(
    route: path,
    videoId: video,
    channel: channel == null ? null : Uri.decodeComponent(channel),
    person: person == null ? null : Uri.decodeComponent(person),
  );
}
