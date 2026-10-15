/// Ugovor između jezgre i ljuske za push obavijesti.
///
/// Jezgra ne zna za Firebase: ljuska koja želi push preda implementaciju kroz
/// `runPodcastApp(pushTransport:)` (DOMOVINA: FCM teme). Bez nje
/// [PushTopics] je ugašen i ekran Obavijesti se nigdje ne nudi — isti obrazac
/// kao `AuthProviderPlugin`, pa Podcasterium ljuska ne vuče Firebase.
///
/// Plan i odluke: `docs/plans/2026-10-15-push-nove-epizode.md`.
library;

/// Stanje sistemske dozvole za obavijesti.
enum PushPermission {
  /// Korisnik još nije pitan (iOS, Android 13+).
  notDetermined,

  /// Obavijesti se smiju prikazivati.
  granted,

  /// Korisnik ih je odbio ili ugasio u postavkama uređaja.
  denied,
}

abstract class PushTransport {
  /// Trenutno stanje dozvole, bez pitanja korisnika.
  Future<PushPermission> permission();

  /// Otvori sistemski dijalog (samo iz korisnikova tapa!) i vrati ishod.
  Future<PushPermission> requestPermission();

  /// Pretplati uređaj na temu. Idempotentno; baca na mrežnu grešku.
  Future<void> subscribe(String topic);

  /// Odjavi uređaj s teme. Idempotentno; baca na mrežnu grešku.
  Future<void> unsubscribe(String topic);

  /// Ruta (npr. `/v/abc`) iz obavijesti na koju je korisnik tapnuo dok je
  /// aplikacija bila živa (u prednjem planu ili u pozadini).
  Stream<String> get openedRoutes;

  /// Ruta iz obavijesti koja je aplikaciju POKRENULA (hladni start); `null`
  /// ako je aplikacija otvorena drukčije. Čita se jednom.
  Future<String?> initialRoute();

  /// Javlja se kad uređaj dobije novi token — pretplate na teme tada treba
  /// ponoviti, jer novi token ne nasljeđuje stare.
  Stream<void> get tokenRefreshed;

  /// Otvori sistemske postavke obavijesti ove aplikacije.
  Future<void> openSystemSettings();
}
