import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_hr.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('hr'),
  ];

  /// Naziv aplikacije — dolazi iz BrandConfig.appName, ne prevodi se.
  ///
  /// In hr, this message translates to:
  /// **'{app}'**
  String appTitle(String app);

  /// SnackBar poruka kad je dostupan noviji build aplikacije.
  ///
  /// In hr, this message translates to:
  /// **'Dostupna je nova verzija'**
  String get updateAvailable;

  /// Akcijski gumb koji ponovno učitava aplikaciju na novu verziju.
  ///
  /// In hr, this message translates to:
  /// **'Osvježi'**
  String get updateRefresh;

  /// Univerzalni gumb za odustajanje iz dijaloga.
  ///
  /// In hr, this message translates to:
  /// **'Odustani'**
  String get commonCancel;

  /// Zatvori dijalog ili panel.
  ///
  /// In hr, this message translates to:
  /// **'Zatvori'**
  String get commonClose;

  /// Povratak na prethodni ekran.
  ///
  /// In hr, this message translates to:
  /// **'Natrag'**
  String get commonBack;

  /// Spremi promjene.
  ///
  /// In hr, this message translates to:
  /// **'Spremi'**
  String get commonSave;

  /// Potvrdna akcija.
  ///
  /// In hr, this message translates to:
  /// **'Potvrdi'**
  String get commonConfirm;

  /// Završi/zatvori nakon dovršene radnje.
  ///
  /// In hr, this message translates to:
  /// **'Gotovo'**
  String get commonDone;

  /// Nastavi na sljedeći korak.
  ///
  /// In hr, this message translates to:
  /// **'Nastavi'**
  String get commonContinue;

  /// Ponovi neuspjelu radnju.
  ///
  /// In hr, this message translates to:
  /// **'Pokušaj ponovno'**
  String get commonRetry;

  /// Akcija uz naslov raila koja otvara puni popis.
  ///
  /// In hr, this message translates to:
  /// **'Prikaži sve'**
  String get commonSeeAll;

  /// Akcija u SnackBaru koja vraća upravo poništenu radnju.
  ///
  /// In hr, this message translates to:
  /// **'Poništi'**
  String get commonUndo;

  /// Kopiraj u međuspremnik.
  ///
  /// In hr, this message translates to:
  /// **'Kopiraj'**
  String get commonCopy;

  /// Podijeli sadržaj.
  ///
  /// In hr, this message translates to:
  /// **'Podijeli'**
  String get commonShare;

  /// Context menu item (right-click / long-press on a card) to copy that item's public link.
  ///
  /// In hr, this message translates to:
  /// **'Kopiraj poveznicu'**
  String get commonCopyLink;

  /// Snackbar confirmation shown after a link is copied to the clipboard.
  ///
  /// In hr, this message translates to:
  /// **'Poveznica kopirana'**
  String get commonLinkCopied;

  /// Potvrda obavijesti.
  ///
  /// In hr, this message translates to:
  /// **'U redu'**
  String get commonOk;

  /// Pokreni prijavu.
  ///
  /// In hr, this message translates to:
  /// **'Prijavi se'**
  String get commonSignIn;

  /// Odjava korisnika.
  ///
  /// In hr, this message translates to:
  /// **'Odjavi se'**
  String get commonSignOut;

  /// Generičko stanje učitavanja.
  ///
  /// In hr, this message translates to:
  /// **'Učitavanje…'**
  String get commonLoading;

  /// Vrati korisnika na početni ekran.
  ///
  /// In hr, this message translates to:
  /// **'Natrag na početnu'**
  String get commonGoHome;

  /// Otvori izvorni dokument / poveznicu.
  ///
  /// In hr, this message translates to:
  /// **'Otvori izvor'**
  String get commonOpenSource;

  /// Zahvala nakon donacije/podrške.
  ///
  /// In hr, this message translates to:
  /// **'Hvala na podršci'**
  String get commonThanksForSupport;

  /// Prikaz greške s detaljem/porukom.
  ///
  /// In hr, this message translates to:
  /// **'Greška: {details}'**
  String commonErrorWithDetails(String details);

  /// Naslov ekrana za upravljanje računom (/account).
  ///
  /// In hr, this message translates to:
  /// **'Moj račun'**
  String get authAccountTitle;

  /// Naslov praznog stanja na ekranu računa kad korisnik nije prijavljen.
  ///
  /// In hr, this message translates to:
  /// **'Još nisi prijavljen·a'**
  String get authAnonTitle;

  /// Podnaslov praznog stanja na ekranu računa.
  ///
  /// In hr, this message translates to:
  /// **'Prijavi se kako bi upravljao svojim računom, pristupnim ključevima i podacima.'**
  String get authAnonSubtitle;

  /// Gumb koji otvara paywall s informacijama o pretplati.
  ///
  /// In hr, this message translates to:
  /// **'Saznaj više o {plus}'**
  String authLearnAboutPlus(String plus);

  /// Oznaka sekcije: pretplata.
  ///
  /// In hr, this message translates to:
  /// **'Pretplata'**
  String get authSectionSubscription;

  /// Oznaka sekcije: povezane prijavne metode.
  ///
  /// In hr, this message translates to:
  /// **'Prijavne metode'**
  String get authSectionSignInMethods;

  /// Oznaka sekcije: pristupni ključevi (passkeyji).
  ///
  /// In hr, this message translates to:
  /// **'Pristupni ključevi'**
  String get authSectionPasskeys;

  /// Oznaka sekcije: uređaji / prijenos na drugi uređaj.
  ///
  /// In hr, this message translates to:
  /// **'Uređaji'**
  String get authSectionDevices;

  /// Oznaka sekcije: nepovratne radnje kao brisanje računa.
  ///
  /// In hr, this message translates to:
  /// **'Opasna zona'**
  String get authSectionDangerZone;

  /// Poruka zahvale aktivnom Plus pretplatniku.
  ///
  /// In hr, this message translates to:
  /// **'Hvala što podržavaš hrvatsku arhivu.'**
  String get authPlusThanks;

  /// Brand-neutral variant of authPlusThanks for brands without a domain score.
  ///
  /// In hr, this message translates to:
  /// **'Hvala ti na podršci.'**
  String get supportThanksGeneric;

  /// Gumb koji otvara detalje pretplate.
  ///
  /// In hr, this message translates to:
  /// **'Detalji'**
  String get authDetails;

  /// Naslov kartice s pozivom na pretplatu.
  ///
  /// In hr, this message translates to:
  /// **'Postani {plus}'**
  String authBecomePlus(String plus);

  /// Popis pogodnosti Plus pretplate.
  ///
  /// In hr, this message translates to:
  /// **'Šira pretraga, bedž podupiratelja i podrška arhivi.'**
  String get authPlusBenefits;

  /// Rezervno ime kad korisnik nema postavljeno ime ni e-mail.
  ///
  /// In hr, this message translates to:
  /// **'Korisnik'**
  String get authUserFallback;

  /// Oznaka uz profil kad je identitet potvrđen hrvatskom e-osobnom.
  ///
  /// In hr, this message translates to:
  /// **'Provjereni identitet (eOsobna)'**
  String get authVerifiedIdentity;

  /// Prazno stanje liste povezanih prijavnih metoda.
  ///
  /// In hr, this message translates to:
  /// **'Nema povezanih prijavnih metoda.'**
  String get authNoLinkedMethods;

  /// Podnaslov stavke: prijava Google računom.
  ///
  /// In hr, this message translates to:
  /// **'Google račun'**
  String get authProviderGoogle;

  /// Podnaslov stavke: prijava Apple računom.
  ///
  /// In hr, this message translates to:
  /// **'Apple račun'**
  String get authProviderApple;

  /// Podnaslov stavke: prijava putem e-maila.
  ///
  /// In hr, this message translates to:
  /// **'Poveznica ili kôd na e-mail'**
  String get authProviderEmail;

  /// Naziv prijavne metode / rezervni naziv pristupnog ključa.
  ///
  /// In hr, this message translates to:
  /// **'Pristupni ključ'**
  String get authProviderPasskey;

  /// Podnaslov stavke: prijava hrvatskom e-osobnom.
  ///
  /// In hr, this message translates to:
  /// **'Hrvatska e-osobna (Certilia / NIAS)'**
  String get authProviderCertilia;

  /// Poruka kad backend za listanje pristupnih ključeva još nije dostupan.
  ///
  /// In hr, this message translates to:
  /// **'Pregled i uklanjanje pristupnih ključeva stiže uskoro. Novi ključ možeš dodati već sada.'**
  String get authPasskeysSoon;

  /// Prazno stanje liste pristupnih ključeva.
  ///
  /// In hr, this message translates to:
  /// **'Nemaš nijedan pristupni ključ. Pristupni ključ je najsigurniji i najbrži način prijave — bez lozinke, uz Face ID ili otisak prsta.'**
  String get authNoPasskeys;

  /// Greška pri dohvaćanju liste pristupnih ključeva.
  ///
  /// In hr, this message translates to:
  /// **'Dohvaćanje pristupnih ključeva nije uspjelo.'**
  String get authPasskeyFetchFailed;

  /// Opis ikone / tooltip za uklanjanje pristupnog ključa.
  ///
  /// In hr, this message translates to:
  /// **'Ukloni pristupni ključ'**
  String get authRemovePasskey;

  /// Gumb za dodavanje novog pristupnog ključa.
  ///
  /// In hr, this message translates to:
  /// **'Dodaj pristupni ključ na ovom uređaju'**
  String get authAddPasskeyHere;

  /// Naslov upute o pohrani pristupnog ključa.
  ///
  /// In hr, this message translates to:
  /// **'Gdje se sprema pristupni ključ?'**
  String get authWherePasskeyStored;

  /// Uputa o tome gdje se sprema pristupni ključ; {site} je domena brenda, {steps} su koraci ovisni o platformi.
  ///
  /// In hr, this message translates to:
  /// **'Preporučujemo Apple Passwords ili Google Password Manager — tako je pristupni ključ vezan uz Face ID ili otisak prsta i sinkroniziran na svim tvojim uređajima. Ako koristiš proširenje poput LastPassa ili 1Passworda, isključi ga za {site} (ili ga ukloni kao zadani upravitelj ključeva) jer presreće prozor pristupnog ključa i ometa prijavu.\n\n{steps}'**
  String authPasskeyHintBody(String site, String steps);

  /// Koraci za odabir upravitelja pristupnih ključeva na iOS-u / macOS-u.
  ///
  /// In hr, this message translates to:
  /// **'Postavke → Aplikacije → Lozinke → Opcije lozinki → „Automatski popunjavaj\" — odaberi Lozinke (iCloud).'**
  String get authPasskeyStepsApple;

  /// Koraci za odabir upravitelja pristupnih ključeva na Androidu.
  ///
  /// In hr, this message translates to:
  /// **'Postavke → Lozinke i računi → Zadana usluga za pristupne ključeve → odaberi Google Password Manager.'**
  String get authPasskeyStepsAndroid;

  /// Koraci za odabir upravitelja pristupnih ključeva na ostalim platformama.
  ///
  /// In hr, this message translates to:
  /// **'U postavkama operativnog sustava odaberi sustavski upravitelj pristupnih ključeva (Apple Passwords ili Google Password Manager).'**
  String get authPasskeyStepsGeneric;

  /// Meta podatak uz pristupni ključ: datum dodavanja.
  ///
  /// In hr, this message translates to:
  /// **'dodan {date}'**
  String authPasskeyAdded(String date);

  /// Meta podatak uz pristupni ključ: datum zadnjeg korištenja.
  ///
  /// In hr, this message translates to:
  /// **'zadnje korišten {date}'**
  String authPasskeyLastUsed(String date);

  /// Potvrda nakon uspješnog dodavanja pristupnog ključa.
  ///
  /// In hr, this message translates to:
  /// **'Pristupni ključ je dodan.'**
  String get authPasskeyAddedToast;

  /// Poruka kad dodavanje pristupnog ključa ne uspije.
  ///
  /// In hr, this message translates to:
  /// **'Pristupni ključ nije dodan.'**
  String get authPasskeyAddFailed;

  /// Naslov dijaloga za potvrdu uklanjanja pristupnog ključa.
  ///
  /// In hr, this message translates to:
  /// **'Ukloniti pristupni ključ?'**
  String get authRemovePasskeyTitle;

  /// Tekst dijaloga za potvrdu uklanjanja pristupnog ključa; {name} je naziv ključa/uređaja.
  ///
  /// In hr, this message translates to:
  /// **'„{name}\" više neće moći prijaviti ovaj račun. Ova je radnja trajna.'**
  String authRemovePasskeyBody(String name);

  /// Gumb za potvrdu uklanjanja.
  ///
  /// In hr, this message translates to:
  /// **'Ukloni'**
  String get authRemove;

  /// Potvrda nakon uspješnog uklanjanja pristupnog ključa.
  ///
  /// In hr, this message translates to:
  /// **'Pristupni ključ je uklonjen.'**
  String get authPasskeyRemoved;

  /// Naslov / stavka za prijenos prijave na drugi uređaj.
  ///
  /// In hr, this message translates to:
  /// **'Prebaci na drugi uređaj'**
  String get authSwitchDevice;

  /// Podnaslov stavke za prijenos na drugi uređaj.
  ///
  /// In hr, this message translates to:
  /// **'Generiraj kôd i prijavi se na TV-u ili mobitelu'**
  String get authDevicesSubtitle;

  /// Podnaslov stavke za odjavu.
  ///
  /// In hr, this message translates to:
  /// **'Nastavi kao gost — podaci ostaju spremljeni na računu'**
  String get authSignOutSubtitle;

  /// Stavka / gumb za brisanje računa.
  ///
  /// In hr, this message translates to:
  /// **'Izbriši račun'**
  String get authDeleteAccount;

  /// Podnaslov stavke za brisanje računa.
  ///
  /// In hr, this message translates to:
  /// **'Trajno briše račun, favorite, napredak i sve povezane podatke.'**
  String get authDeleteAccountSubtitle;

  /// Potvrda nakon uspješnog brisanja računa.
  ///
  /// In hr, this message translates to:
  /// **'Račun je izbrisan.'**
  String get authAccountDeleted;

  /// Poruka kad brisanje računa ne uspije.
  ///
  /// In hr, this message translates to:
  /// **'Brisanje nije uspjelo.'**
  String get authDeleteFailed;

  /// Naslov dijaloga za potvrdu odjave.
  ///
  /// In hr, this message translates to:
  /// **'Odjaviti se?'**
  String get authSignOutTitle;

  /// Tekst dijaloga za potvrdu odjave.
  ///
  /// In hr, this message translates to:
  /// **'Tvoj napredak i favoriti ostaju spremljeni na računu — vraćaju se kad se ponovno prijaviš.'**
  String get authSignOutBody;

  /// Naslov dijaloga za upisom potvrđeno brisanje računa.
  ///
  /// In hr, this message translates to:
  /// **'Trajno izbrisati račun?'**
  String get authDeleteConfirmTitle;

  /// Riječ koju korisnik mora upisati da potvrdi brisanje računa.
  ///
  /// In hr, this message translates to:
  /// **'IZBRIŠI'**
  String get authDeleteConfirmWord;

  /// Tekst dijaloga za brisanje računa; {word} je riječ za potvrdu.
  ///
  /// In hr, this message translates to:
  /// **'Brišu se račun, favoriti, napredak gledanja, pristupni ključevi i sve povezane postavke. Ova je radnja nepovratna.\n\nZa potvrdu upiši {word}:'**
  String authDeleteConfirmBody(String word);

  /// Gumb za konačnu potvrdu brisanja računa.
  ///
  /// In hr, this message translates to:
  /// **'Trajno izbriši'**
  String get authDeletePermanently;

  /// Greška kad je magic link istekao.
  ///
  /// In hr, this message translates to:
  /// **'Poveznica za prijavu je istekla — zatraži novu.'**
  String get authErrLinkExpired;

  /// Greška kad je račun blokiran.
  ///
  /// In hr, this message translates to:
  /// **'Ovaj je račun privremeno blokiran.'**
  String get authErrUserBanned;

  /// Greška kad je registracija onemogućena.
  ///
  /// In hr, this message translates to:
  /// **'Registracija novih računa trenutno nije moguća.'**
  String get authErrSignupDisabled;

  /// Greška kad je prijava odbijena/otkazana.
  ///
  /// In hr, this message translates to:
  /// **'Prijava je odbijena ili otkazana.'**
  String get authErrAccessDenied;

  /// Greška na poslužitelju tijekom prijave.
  ///
  /// In hr, this message translates to:
  /// **'Greška na poslužitelju — pokušaj ponovo za minutu.'**
  String get authErrServerError;

  /// Generička greška prijave na callback ekranu.
  ///
  /// In hr, this message translates to:
  /// **'Prijava nije uspjela. Pokušaj ponovo.'**
  String get authErrGeneric;

  /// Greška kad sesija ne stigne unutar vremenskog ograničenja.
  ///
  /// In hr, this message translates to:
  /// **'Prijava traje predugo ili je prekinuta. Pokušaj ponovo.'**
  String get authErrTimeout;

  /// Potvrda uspješne prijave; {name} je ime ili e-mail korisnika.
  ///
  /// In hr, this message translates to:
  /// **'Prijavljen si kao {name}.'**
  String authSignedInAs(String name);

  /// Poruka dok se obrađuje povratak s prijave.
  ///
  /// In hr, this message translates to:
  /// **'Prijava u tijeku…'**
  String get authSigningIn;

  /// Naslov ekrana za prihvaćanje pozivnice.
  ///
  /// In hr, this message translates to:
  /// **'Prihvati pozivnicu'**
  String get authInviteTitle;

  /// Poruka dok se obrađuje pozivnica.
  ///
  /// In hr, this message translates to:
  /// **'Obrađujemo pozivnicu…'**
  String get authInviteProcessing;

  /// Greška pri obradi pozivnice.
  ///
  /// In hr, this message translates to:
  /// **'Došlo je do pogreške ili je poveznica istekla.'**
  String get authInviteError;

  /// Toast nakon prvog dodavanja favorita.
  ///
  /// In hr, this message translates to:
  /// **'Spremljeno na ovaj uređaj. Sinkronizirati favorite na sve uređaje?'**
  String get authM3Toast;

  /// Akcija u toastu: pokreni sinkronizaciju (otvara prijavu).
  ///
  /// In hr, this message translates to:
  /// **'Sinkroniziraj'**
  String get authSync;

  /// Kartica: pošalji prijavu na drugi uređaj.
  ///
  /// In hr, this message translates to:
  /// **'Pošalji'**
  String get authTabSend;

  /// Kartica: primi prijavu s drugog uređaja.
  ///
  /// In hr, this message translates to:
  /// **'Primi'**
  String get authTabReceive;

  /// Naslov kad anonimni korisnik pokuša poslati prijavu na drugi uređaj.
  ///
  /// In hr, this message translates to:
  /// **'Prvo se prijavi'**
  String get authHandoffSignInFirst;

  /// Objašnjenje zašto je potrebna prijava prije slanja na drugi uređaj.
  ///
  /// In hr, this message translates to:
  /// **'Da bi prenio cijeli svoj napredak na drugi uređaj, prvo se prijavi na ovom — tada i drugi uređaj može pristupiti istom računu.'**
  String get authHandoffSignInFirstBody;

  /// Naslov kartice za slanje prijave.
  ///
  /// In hr, this message translates to:
  /// **'Pošalji prijavu na drugi uređaj'**
  String get authHandoffSendTitle;

  /// Podnaslov prijavnog lista otvorenog iz kartice za slanje prijave.
  ///
  /// In hr, this message translates to:
  /// **'Za slanje prijave na drugi uređaj prvo se prijavi na ovom.'**
  String get authHandoffSendSheetSub;

  /// Upute za slanje prijave na drugi uređaj.
  ///
  /// In hr, this message translates to:
  /// **'Otvori {app}/handoff na drugom uređaju i unesi kôd ispod. Kôd vrijedi 5 minuta.'**
  String authHandoffSendBody(String app);

  /// Gumb za generiranje koda za prijenos.
  ///
  /// In hr, this message translates to:
  /// **'Generiraj kôd'**
  String get authGenerateCode;

  /// Gumb za generiranje novog koda.
  ///
  /// In hr, this message translates to:
  /// **'Novi kôd'**
  String get authNewCode;

  /// Napomena o trajanju valjanosti koda.
  ///
  /// In hr, this message translates to:
  /// **'Vrijedi 5 minuta'**
  String get authValid5Min;

  /// Potvrda da je kôd kopiran u međuspremnik.
  ///
  /// In hr, this message translates to:
  /// **'Kôd je kopiran'**
  String get authCodeCopied;

  /// Naslov kartice za unos koda.
  ///
  /// In hr, this message translates to:
  /// **'Imaš kôd s drugog uređaja?'**
  String get authHandoffReceiveTitle;

  /// Upute za unos koda primljenog s drugog uređaja.
  ///
  /// In hr, this message translates to:
  /// **'Unesi šesteroznamenkasti kôd s drugog uređaja da ovdje preuzmeš njegov račun.'**
  String get authHandoffReceiveBody;

  /// Gumb za preuzimanje prijave pomoću koda.
  ///
  /// In hr, this message translates to:
  /// **'Preuzmi prijavu'**
  String get authReceiveSignIn;

  /// Validacija unosa koda.
  ///
  /// In hr, this message translates to:
  /// **'Kôd mora imati 6 znamenki.'**
  String get authCode6Digits;

  /// Poruka dok se otvara prijava nakon unosa koda.
  ///
  /// In hr, this message translates to:
  /// **'Otvaramo prijavu…'**
  String get authOpeningSignIn;

  /// Upute korisniku tijekom otvaranja prijave.
  ///
  /// In hr, this message translates to:
  /// **'Ako se otvori preglednik, potvrdi prijavu pa se vrati u aplikaciju.'**
  String get authOpeningSignInBody;

  /// Naslov ekrana nakon uspješnog preuzimanja prijave.
  ///
  /// In hr, this message translates to:
  /// **'Uspješno!'**
  String get authSuccess;

  /// Primarni gumb za prijavu pristupnim ključem.
  ///
  /// In hr, this message translates to:
  /// **'Nastavi pristupnim ključem'**
  String get authSignInWithPasskey;

  /// Podnaslov stavke za prijavu pristupnim ključem.
  ///
  /// In hr, this message translates to:
  /// **'Face ID ili otisak — ako si ključ već dodao·la'**
  String get authPasskeyTileSub;

  /// Oznaka (badge) na preporučenoj prijavnoj metodi.
  ///
  /// In hr, this message translates to:
  /// **'Preporučeno'**
  String get authBadgeRecommended;

  /// Oznaka (badge) na zadnje korištenoj prijavnoj metodi.
  ///
  /// In hr, this message translates to:
  /// **'Zadnji put'**
  String get authBadgeLastUsed;

  /// Stavka za prijavu hrvatskom e-osobnom.
  ///
  /// In hr, this message translates to:
  /// **'Nastavi eOsobnom'**
  String get authSignInWithEid;

  /// Stavka za prijavu Google računom.
  ///
  /// In hr, this message translates to:
  /// **'Nastavi s Googleom'**
  String get authContinueWithGoogle;

  /// Stavka za prijavu Apple računom.
  ///
  /// In hr, this message translates to:
  /// **'Nastavi s Apple računom'**
  String get authContinueWithApple;

  /// Stavka za prijavu putem e-maila.
  ///
  /// In hr, this message translates to:
  /// **'Nastavi e-mailom'**
  String get authEmailMagicLink;

  /// Podnaslov stavke za prijavu putem e-maila.
  ///
  /// In hr, this message translates to:
  /// **'Pošaljemo ti poveznicu i kôd za prijavu'**
  String get authEmailTileSub;

  /// Rezervni tekst (hint) za polje e-mail adrese.
  ///
  /// In hr, this message translates to:
  /// **'ime@primjer.com'**
  String get authEmailHint;

  /// Gumb za slanje koda na e-mail.
  ///
  /// In hr, this message translates to:
  /// **'Pošalji kôd'**
  String get authSendCode;

  /// Gumb za ponovno slanje koda.
  ///
  /// In hr, this message translates to:
  /// **'Pošalji novi kôd'**
  String get authResendCode;

  /// Gumb za ponovno slanje koda dok traje odbrojavanje; {seconds} su preostale sekunde.
  ///
  /// In hr, this message translates to:
  /// **'Pošalji novi kôd ({seconds} s)'**
  String authResendCodeIn(int seconds);

  /// Gumb za povratak na unos e-maila.
  ///
  /// In hr, this message translates to:
  /// **'Promijeni e-mail'**
  String get authChangeEmail;

  /// Naslov koraka za unos e-maila.
  ///
  /// In hr, this message translates to:
  /// **'Prijava e-mailom'**
  String get authEmailTitle;

  /// Naslov koraka za unos koda iz e-maila.
  ///
  /// In hr, this message translates to:
  /// **'Provjeri e-mail'**
  String get authCheckEmail;

  /// Podnaslov koraka za unos e-maila.
  ///
  /// In hr, this message translates to:
  /// **'Pošaljemo ti poveznicu i šesteroznamenkasti kôd za prijavu — bez lozinke.'**
  String get authEmailEntrySub;

  /// Neupadljiva poveznica na koraku e-maila i naslov koraka s lozinkom (računi s postavljenom lozinkom, npr. račun za pregled u storeu).
  ///
  /// In hr, this message translates to:
  /// **'Prijava lozinkom'**
  String get authUsePassword;

  /// Podnaslov koraka prijave lozinkom.
  ///
  /// In hr, this message translates to:
  /// **'Za račune kojima je postavljena lozinka.'**
  String get authPasswordEntrySub;

  /// Placeholder polja za lozinku.
  ///
  /// In hr, this message translates to:
  /// **'Lozinka'**
  String get authPasswordHint;

  /// Podnaslov koraka za unos koda; {email} je adresa.
  ///
  /// In hr, this message translates to:
  /// **'Poslali smo poveznicu i kôd na {email}. Upiši kôd — ili otvori poveznicu u e-mailu.'**
  String authOtpSentTo(String email);

  /// Naslov prijavnog lista (kontekst: račun).
  ///
  /// In hr, this message translates to:
  /// **'Prijavi se na {app}'**
  String authHeadlineAccount(String app);

  /// Naslov prijavnog lista (kontekst: nakon dodavanja favorita).
  ///
  /// In hr, this message translates to:
  /// **'Spremi favorite u svoj račun'**
  String get authHeadlineMoment3;

  /// Naslov prijavnog lista (kontekst: prijenos s drugog uređaja).
  ///
  /// In hr, this message translates to:
  /// **'Završi prijavu na ovom uređaju'**
  String get authHeadlineHandoff;

  /// Podnaslov prijavnog lista (kontekst: račun).
  ///
  /// In hr, this message translates to:
  /// **'Bez lozinke. Prvom prijavom automatski nastaje tvoj račun.'**
  String get authSubAccount;

  /// Naslov prijavnog lista (kontekst: anonimni gost).
  ///
  /// In hr, this message translates to:
  /// **'Spremi napredak i favorite'**
  String get authHeadlineGuest;

  /// Podnaslov prijavnog lista (kontekst: anonimni gost).
  ///
  /// In hr, this message translates to:
  /// **'Slušaš kao gost — napredak i favoriti ostaju samo na ovom uređaju.'**
  String get authSubGuest;

  /// Naslov trajne trake na dnu ekrana epizode za neprijavljenog korisnika.
  ///
  /// In hr, this message translates to:
  /// **'Slušaš kao gost'**
  String get authGuestBarTitle;

  /// Podnaslov trajne trake na dnu ekrana epizode za neprijavljenog korisnika.
  ///
  /// In hr, this message translates to:
  /// **'Napredak, favoriti i postavke ostaju samo na ovom uređaju'**
  String get authGuestBarBody;

  /// Podnaslov prijavnog lista (kontekst: nakon dodavanja favorita).
  ///
  /// In hr, this message translates to:
  /// **'Da ti favoriti ostanu dostupni na svim uređajima.'**
  String get authSubMoment3;

  /// Podnaslov prijavnog lista (kontekst: prijenos s drugog uređaja).
  ///
  /// In hr, this message translates to:
  /// **'Kôd je provjeren — odaberi kako želiš nastaviti.'**
  String get authSubHandoff;

  /// Obavijest kad na uređaju nema pristupnog ključa za prijavu.
  ///
  /// In hr, this message translates to:
  /// **'Na ovom uređaju još nema pristupnog ključa za {app}. Prijavi se drugom metodom — ključ zatim dodaš u Moj račun.'**
  String authPasskeyMissingNotice(String app);

  /// Validacija e-mail adrese.
  ///
  /// In hr, this message translates to:
  /// **'Unesi ispravnu e-mail adresu.'**
  String get authInvalidEmail;

  /// Greška kad slanje koda/poveznice ne uspije.
  ///
  /// In hr, this message translates to:
  /// **'Slanje nije uspjelo.'**
  String get authSendFailed;

  /// Obavijest da je novi kôd poslan; {email} je adresa.
  ///
  /// In hr, this message translates to:
  /// **'Novi kôd poslan na {email}.'**
  String authNewCodeSentTo(String email);

  /// Greška kad uneseni kôd nije ispravan.
  ///
  /// In hr, this message translates to:
  /// **'Kôd nije ispravan.'**
  String get authCodeInvalid;

  /// Generička greška prijave u prijavnom listu.
  ///
  /// In hr, this message translates to:
  /// **'Prijava nije uspjela.'**
  String get authSignInFailed;

  /// Rezervni izraz za adresu kad konkretna nije poznata.
  ///
  /// In hr, this message translates to:
  /// **'tvoj e-mail'**
  String get authYourEmail;

  /// Potvrda da su poveznica i kôd poslani; {email} je adresa.
  ///
  /// In hr, this message translates to:
  /// **'Poveznica i kôd poslani su na {email} — provjeri sandučić.'**
  String authLinkCodeSent(String email);

  /// Početak pravne rečenice ispod prijavnih metoda (prije poveznica).
  ///
  /// In hr, this message translates to:
  /// **'Nastavkom prihvaćaš '**
  String get authLegalPrefix;

  /// Tekst poveznice na uvjete korištenja.
  ///
  /// In hr, this message translates to:
  /// **'Uvjete korištenja'**
  String get authLegalTerms;

  /// Veznik između dviju pravnih poveznica.
  ///
  /// In hr, this message translates to:
  /// **' i '**
  String get authLegalAnd;

  /// Tekst poveznice na pravila privatnosti.
  ///
  /// In hr, this message translates to:
  /// **'Pravila privatnosti'**
  String get authLegalPrivacy;

  /// Završetak pravne rečenice (točka).
  ///
  /// In hr, this message translates to:
  /// **'.'**
  String get authLegalSuffix;

  /// Umirujuća napomena o čuvanju napretka pri prijavi.
  ///
  /// In hr, this message translates to:
  /// **'Tvoj trenutačni napredak ostaje sačuvan i sigurno se povezuje s računom.'**
  String get authReassurance;

  /// Razdjelnik „ili" između prijavnih metoda.
  ///
  /// In hr, this message translates to:
  /// **'ili'**
  String get authOr;

  /// Tooltip on the channel screen action that lets a verified owner claim a YouTube channel.
  ///
  /// In hr, this message translates to:
  /// **'Preuzmi vlasništvo'**
  String get channelClaimOwnership;

  /// Placeholder label on episode cards that have no thumbnail because the source is audio-only.
  ///
  /// In hr, this message translates to:
  /// **'Samo zvuk'**
  String get channelAudioOnly;

  /// Badge shown on a video card when the AI pipeline has not yet produced an article for it.
  ///
  /// In hr, this message translates to:
  /// **'U obradi'**
  String get channelInProcessing;

  /// Title of the full-page screen listing every channel.
  ///
  /// In hr, this message translates to:
  /// **'Svi kanali'**
  String get channelAllChannels;

  /// Hint text in the channel-list search field.
  ///
  /// In hr, this message translates to:
  /// **'Pretraži kanale…'**
  String get channelSearchChannelsHint;

  /// Tooltip on the button that clears the search field.
  ///
  /// In hr, this message translates to:
  /// **'Očisti'**
  String get channelClear;

  /// Count of channels currently shown in the list.
  ///
  /// In hr, this message translates to:
  /// **'{count, plural, one{{count} kanal} few{{count} kanala} other{{count} kanala}}'**
  String channelChannelsCount(int count);

  /// Count of search results in the channel list filter.
  ///
  /// In hr, this message translates to:
  /// **'{count, plural, one{{count} rezultat} few{{count} rezultata} other{{count} rezultata}}'**
  String channelResultsCount(int count);

  /// Empty state when the channel list is empty.
  ///
  /// In hr, this message translates to:
  /// **'Nema kanala.'**
  String get channelNoChannels;

  /// Empty state when a channel search returns nothing.
  ///
  /// In hr, this message translates to:
  /// **'Nema kanala za „{query}”.'**
  String channelNoChannelsForQuery(String query);

  /// Tooltip on the channel sort menu button.
  ///
  /// In hr, this message translates to:
  /// **'Sortiraj kanale'**
  String get channelSortChannels;

  /// Menu item that randomly reorders the channel list.
  ///
  /// In hr, this message translates to:
  /// **'Promiješaj'**
  String get channelShuffle;

  /// Title of the keyword (Meilisearch) search screen.
  ///
  /// In hr, this message translates to:
  /// **'Pretraga po riječima'**
  String get channelKeywordSearch;

  /// Hint text in the keyword search field; the search tolerates typos.
  ///
  /// In hr, this message translates to:
  /// **'Traži po riječima (otporno na pogreške)…'**
  String get channelKeywordSearchHint;

  /// Developer-facing banner shown when the local Meilisearch service is unreachable.
  ///
  /// In hr, this message translates to:
  /// **'Meilisearch nije dostupan na {url}. Pokreni Docker kontejner i napuni indeks (repozitorij domovina-rag).'**
  String channelSearchUnavailable(String url);

  /// Status shown while a search request is in flight.
  ///
  /// In hr, this message translates to:
  /// **'Tražim…'**
  String get channelSearching;

  /// Search stats line: how many results were found and how long the query took.
  ///
  /// In hr, this message translates to:
  /// **'{count, plural, one{{count} rezultat u {ms} ms · otporno na pogreške} few{{count} rezultata u {ms} ms · otporno na pogreške} other{{count} rezultata u {ms} ms · otporno na pogreške}}'**
  String channelResultsInMs(int count, int ms);

  /// Prompt shown before the user has typed anything in keyword search.
  ///
  /// In hr, this message translates to:
  /// **'Upiši pojam za trenutnu pretragu epizoda.'**
  String get channelSearchPrompt;

  /// Channel filter chip that clears the channel filter (shows results from all channels).
  ///
  /// In hr, this message translates to:
  /// **'Svi'**
  String get channelAll;

  /// Empty state on the keyword search results area before a query is entered.
  ///
  /// In hr, this message translates to:
  /// **'Pretraga po riječima — počni tipkati.'**
  String get channelSearchStart;

  /// Empty state when a keyword search returns no episodes.
  ///
  /// In hr, this message translates to:
  /// **'Nema rezultata za „{query}”.'**
  String channelNoResultsForQuery(String query);

  /// Paywall headline for the generic upgrade trigger.
  ///
  /// In hr, this message translates to:
  /// **'Postani {plus}'**
  String channelTriggerGenericHeadline(String plus);

  /// Paywall subtitle for the generic upgrade trigger.
  ///
  /// In hr, this message translates to:
  /// **'Podrži hrvatsku arhivu i otključaj sve pogodnosti.'**
  String get channelTriggerGenericSubtitle;

  /// Brand-neutral variant of channelTriggerGenericSubtitle for brands without a domain score.
  ///
  /// In hr, this message translates to:
  /// **'Otključaj sve Plus pogodnosti.'**
  String get channelTriggerGenericSubtitleNeutral;

  /// Paywall headline for the search upgrade trigger.
  ///
  /// In hr, this message translates to:
  /// **'Šira pretraga'**
  String get channelTriggerSearchHeadline;

  /// Paywall subtitle for the search upgrade trigger.
  ///
  /// In hr, this message translates to:
  /// **'Do 30 rezultata pretrage umjesto 12.'**
  String get channelTriggerSearchSubtitle;

  /// Paywall headline for the supporter-badge upgrade trigger.
  ///
  /// In hr, this message translates to:
  /// **'Postani podupiratelj arhive'**
  String get channelTriggerBadgeHeadline;

  /// Paywall subtitle for the supporter-badge upgrade trigger.
  ///
  /// In hr, this message translates to:
  /// **'Bedž podupiratelja na tvom računu.'**
  String get channelTriggerBadgeSubtitle;

  /// Name of the annual subscription plan.
  ///
  /// In hr, this message translates to:
  /// **'Godišnje'**
  String get channelPlanAnnual;

  /// Billing cadence suffix for the annual plan.
  ///
  /// In hr, this message translates to:
  /// **'/ god.'**
  String get channelPlanPerYear;

  /// Badge on the annual plan highlighting savings versus monthly.
  ///
  /// In hr, this message translates to:
  /// **'~33 % povoljnije'**
  String get channelPlanSaveBadge;

  /// Name of the monthly subscription plan.
  ///
  /// In hr, this message translates to:
  /// **'Mjesečno'**
  String get channelPlanMonthly;

  /// Billing cadence suffix for the monthly plan.
  ///
  /// In hr, this message translates to:
  /// **'/ mj.'**
  String get channelPlanPerMonth;

  /// Name of the one-time lifetime plan.
  ///
  /// In hr, this message translates to:
  /// **'Zauvijek'**
  String get channelPlanLifetime;

  /// Billing cadence label for the lifetime plan (single payment).
  ///
  /// In hr, this message translates to:
  /// **'jednokratno'**
  String get channelPlanOneTime;

  /// Free-trial disclosure under a paywall plan: trial length in days, then the regular price.
  ///
  /// In hr, this message translates to:
  /// **'{days} dana besplatno, zatim {price}'**
  String channelTrialThen(int days, String price);

  /// Badge on the lifetime plan marking early supporters.
  ///
  /// In hr, this message translates to:
  /// **'Osnivač'**
  String get channelPlanFounderBadge;

  /// Plus benefit: broader search result limit.
  ///
  /// In hr, this message translates to:
  /// **'Šira pretraga — do 30 rezultata umjesto 12'**
  String get channelBenefitSearch;

  /// Plus benefit: supporter badge.
  ///
  /// In hr, this message translates to:
  /// **'Bedž podupiratelja na tvom računu'**
  String get channelBenefitBadge;

  /// Plus benefit: supporting the archive's development and running costs.
  ///
  /// In hr, this message translates to:
  /// **'Podržavaš razvoj i troškove arhive'**
  String get channelBenefitSupport;

  /// Title of the paywall roadmap section listing planned, not-yet-built directions.
  ///
  /// In hr, this message translates to:
  /// **'U planu'**
  String get plusRoadmapTitle;

  /// Disclaimer stating the roadmap is not part of the purchase and has no timeline.
  ///
  /// In hr, this message translates to:
  /// **'Ovo su smjerovi razvoja, a ne dio onoga što danas kupuješ. Bez rokova — ako i kad stignu, bit će uključeni u Plus bez doplate.'**
  String get plusRoadmapDisclaimer;

  /// Roadmap item: offline downloads.
  ///
  /// In hr, this message translates to:
  /// **'Preuzimanje epizoda za slušanje bez interneta'**
  String get plusRoadmapOffline;

  /// Roadmap item: exporting transcripts and summaries.
  ///
  /// In hr, this message translates to:
  /// **'Izvoz transkripata i sažetaka'**
  String get plusRoadmapExport;

  /// Auth sheet headline shown before a purchase so it attaches to an account.
  ///
  /// In hr, this message translates to:
  /// **'Prijavi se za nastavak'**
  String get channelSignInToContinue;

  /// Explains why an account is required before subscribing.
  ///
  /// In hr, this message translates to:
  /// **'Pretplata se veže uz tvoj račun kako bi radila na svim uređajima.'**
  String get channelSubscriptionTiedToAccount;

  /// Snackbar confirming a successful purchase.
  ///
  /// In hr, this message translates to:
  /// **'Dobro došao u {plus}! Hvala na podršci.'**
  String channelWelcomeToPlus(String plus);

  /// Snackbar when in-app purchase is unsupported on the current platform.
  ///
  /// In hr, this message translates to:
  /// **'Kupnja nije dostupna na ovom uređaju.'**
  String get channelPurchaseUnavailableDevice;

  /// Fallback snackbar when a purchase fails.
  ///
  /// In hr, this message translates to:
  /// **'Kupnja nije uspjela. Pokušaj ponovno.'**
  String get channelPurchaseFailed;

  /// Snackbar after a successful restore.
  ///
  /// In hr, this message translates to:
  /// **'Pretplata je vraćena.'**
  String get channelSubscriptionRestored;

  /// Fallback snackbar when restore finds nothing.
  ///
  /// In hr, this message translates to:
  /// **'Nismo pronašli kupnju za vraćanje.'**
  String get channelNoPurchaseToRestore;

  /// Snackbar when web checkout is not yet configured.
  ///
  /// In hr, this message translates to:
  /// **'Web naplata stiže uskoro. Zasad se pretplati u mobilnoj aplikaciji.'**
  String get channelWebBillingSoon;

  /// Title of the card prompting an anonymous user to sign in before subscribing.
  ///
  /// In hr, this message translates to:
  /// **'Najprije se prijavi'**
  String get channelSignInFirst;

  /// Button that restores previous purchases (store requirement).
  ///
  /// In hr, this message translates to:
  /// **'Vrati kupnje'**
  String get channelRestorePurchases;

  /// Button/link to the store subscription management page.
  ///
  /// In hr, this message translates to:
  /// **'Upravljaj pretplatom'**
  String get channelManageSubscription;

  /// Note under indicative web pricing explaining where the authoritative price appears.
  ///
  /// In hr, this message translates to:
  /// **'Naplatu vodi sigurni RevenueCat / Stripe checkout. Konačna cijena prikazuje se na stranici za naplatu.'**
  String get channelCheckoutNote;

  /// Note under indicative pricing on platforms where the store sets the price.
  ///
  /// In hr, this message translates to:
  /// **'Cijene su okvirne; konačna cijena prikazuje se u trgovini.'**
  String get channelPricesIndicative;

  /// Heading shown to a user who is already subscribed.
  ///
  /// In hr, this message translates to:
  /// **'Već imaš {plus}'**
  String channelAlreadyPlus(String plus);

  /// Message of thanks shown to existing subscribers.
  ///
  /// In hr, this message translates to:
  /// **'Hvala na podršci hrvatskoj arhivi.'**
  String get channelThanksSupportingArchive;

  /// Legal fine print about auto-renewal and cancellation.
  ///
  /// In hr, this message translates to:
  /// **'Pretplata se automatski obnavlja dok je ne otkažeš. Otkazati je možeš bilo kada u postavkama trgovine. Doživotni paket jednokratna je kupnja.'**
  String get channelLegalAutoRenew;

  /// Auto-renewal notice for brands that sell subscriptions only (no lifetime plan).
  ///
  /// In hr, this message translates to:
  /// **'Pretplata se automatski obnavlja dok je ne otkažeš. Otkazati je možeš bilo kada u postavkama trgovine.'**
  String get channelLegalAutoRenewSubscriptionsOnly;

  /// Tooltip on the floating founder-booking button.
  ///
  /// In hr, this message translates to:
  /// **'Razgovaraj s osnivačem'**
  String get channelTalkToFounder;

  /// Error fallback when fetching booking slots fails.
  ///
  /// In hr, this message translates to:
  /// **'Ne možemo dohvatiti termine.'**
  String get channelCannotFetchSlots;

  /// Cal.com rezervacija odbijena bez poruke servera.
  ///
  /// In hr, this message translates to:
  /// **'Rezervacija nije uspjela. Pokušaj drugi termin.'**
  String get channelBookingFailed;

  /// Cal.com proxy vratio odgovor bez očekivanih polja.
  ///
  /// In hr, this message translates to:
  /// **'Neočekivan odgovor servera.'**
  String get channelBookingUnexpectedResponse;

  /// Empty state when no booking slots are available.
  ///
  /// In hr, this message translates to:
  /// **'Trenutačno nema slobodnih termina u sljedeća tri tjedna.'**
  String get channelNoSlotsThreeWeeks;

  /// Section label above the day selector in the booking flow.
  ///
  /// In hr, this message translates to:
  /// **'Odaberi dan'**
  String get channelPickDay;

  /// Section label above the time-slot selector in the booking flow.
  ///
  /// In hr, this message translates to:
  /// **'Slobodni termini'**
  String get channelAvailableSlots;

  /// Label for the name field in the booking form.
  ///
  /// In hr, this message translates to:
  /// **'Ime i prezime'**
  String get channelFullName;

  /// Validation message when the name field is empty.
  ///
  /// In hr, this message translates to:
  /// **'Upiši svoje ime'**
  String get channelEnterName;

  /// Label for the email field in the booking form.
  ///
  /// In hr, this message translates to:
  /// **'E-mail'**
  String get channelEmail;

  /// Validation message when the email field is empty.
  ///
  /// In hr, this message translates to:
  /// **'Upiši e-mail'**
  String get channelEnterEmail;

  /// Validation message when the email format is invalid.
  ///
  /// In hr, this message translates to:
  /// **'Neispravan e-mail'**
  String get channelInvalidEmail;

  /// Label for the optional notes field in the booking form.
  ///
  /// In hr, this message translates to:
  /// **'Tema razgovora (neobavezno)'**
  String get channelTopicOptional;

  /// Button that submits the booking.
  ///
  /// In hr, this message translates to:
  /// **'Potvrdi termin'**
  String get channelConfirmSlot;

  /// Error when a booking submission fails due to network issues.
  ///
  /// In hr, this message translates to:
  /// **'Pogreška u mreži. Pokušaj ponovno.'**
  String get channelNetworkError;

  /// Success heading after a booking is confirmed.
  ///
  /// In hr, this message translates to:
  /// **'Termin potvrđen!'**
  String get channelSlotConfirmed;

  /// Formats a confirmed booking as day and time. NOTE: {day} is rendered by an in-file Croatian date helper (weekday/month names not yet localized).
  ///
  /// In hr, this message translates to:
  /// **'{day} u {time}'**
  String channelDayAtTime(String day, String time);

  /// Confirmation that the meeting invite was emailed.
  ///
  /// In hr, this message translates to:
  /// **'Pozivnicu i Google Meet poveznicu poslali smo na {email}.'**
  String channelInviteSentTo(String email);

  /// Button that opens the Google Meet link for the booked call.
  ///
  /// In hr, this message translates to:
  /// **'Otvori Google Meet'**
  String get channelOpenGoogleMeet;

  /// Header title of the founder-booking sheet.
  ///
  /// In hr, this message translates to:
  /// **'Budi dio priče {brand}'**
  String channelFounderCallTitle(String brand);

  /// Header subtitle of the founder-booking sheet.
  ///
  /// In hr, this message translates to:
  /// **'15 min Google Meeta · osobno s osnivačem · pomozi oblikovati platformu'**
  String get channelFounderCallSubtitle;

  /// Button to change the previously selected booking slot.
  ///
  /// In hr, this message translates to:
  /// **'Promijeni'**
  String get channelChange;

  /// Detailed not-found error on the full episode screen, shows the requested episode ID and a hint to verify the upload.
  ///
  /// In hr, this message translates to:
  /// **'Epizoda „{id}” nije pronađena na CDN-u.\n\nProvjerite je li identifikator ispravan i jesu li datoteke postavljene.'**
  String episodeNotFoundDetailed(String id);

  /// Short not-found error on the simple episode screen, shows the requested episode ID.
  ///
  /// In hr, this message translates to:
  /// **'Epizoda „{id}” nije pronađena.'**
  String episodeNotFound(String id);

  /// Generic load error shown when episode data fails to load; details holds the raw error text.
  ///
  /// In hr, this message translates to:
  /// **'Greška pri učitavanju:\n{details}'**
  String episodeLoadError(String details);

  /// Title shown on the episode loading screen while assets are being fetched.
  ///
  /// In hr, this message translates to:
  /// **'Učitavanje epizode'**
  String get episodeLoading;

  /// Snackbar confirming a share link was copied; label is either the timestamp or the whole-episode label.
  ///
  /// In hr, this message translates to:
  /// **'Link kopiran ({label})'**
  String episodeLinkCopied(String label);

  /// Lowercase label used inside the link-copied snackbar when sharing the episode without a specific timestamp.
  ///
  /// In hr, this message translates to:
  /// **'cijela epizoda'**
  String get episodeWholeEpisode;

  /// Overline heading of the chapter-clip share sheet, above the chapter theme.
  ///
  /// In hr, this message translates to:
  /// **'Poglavlje kao isječak'**
  String get clipShareTitle;

  /// Tooltip/accessibility label for the clip action button on a chapter header.
  ///
  /// In hr, this message translates to:
  /// **'Preuzmi ili podijeli poglavlje'**
  String get clipTooltip;

  /// Primary action in the clip sheet: download this chapter as an MP4 file.
  ///
  /// In hr, this message translates to:
  /// **'Preuzmi poglavlje'**
  String get clipDownload;

  /// Subtitle under the download action: file format, estimated size in megabytes, and chapter duration in minutes.
  ///
  /// In hr, this message translates to:
  /// **'MP4 · ~{size} MB · {minutes} min'**
  String clipDownloadSubtitle(int size, int minutes);

  /// Second action in the clip sheet: copy a shareable link to the chapter clip.
  ///
  /// In hr, this message translates to:
  /// **'Kopiraj vezu na isječak'**
  String get clipCopyLink;

  /// Subtitle under the copy-link action explaining the link is meant to be pasted into a message or chat.
  ///
  /// In hr, this message translates to:
  /// **'Za slanje u poruci ili chatu'**
  String get clipCopyLinkSubtitle;

  /// Snackbar confirming the chapter-clip link was copied to the clipboard.
  ///
  /// In hr, this message translates to:
  /// **'Veza na isječak kopirana'**
  String get clipLinkCopied;

  /// Note at the bottom of the clip sheet warning that the first request cuts the clip on demand and takes a few seconds.
  ///
  /// In hr, this message translates to:
  /// **'Prvi se put isječak priprema nekoliko sekundi.'**
  String get clipHint;

  /// Tooltip for the action that opens the episode's YouTube source.
  ///
  /// In hr, this message translates to:
  /// **'Otvori na YouTubeu'**
  String get episodeOpenOnYouTube;

  /// Tooltip/label for the action that opens the episode's X (Twitter) post source.
  ///
  /// In hr, this message translates to:
  /// **'Otvori na 𝕏'**
  String get episodeOpenOnX;

  /// Tooltip for the share action that copies a link to the current playback position.
  ///
  /// In hr, this message translates to:
  /// **'Kopiraj link na ovaj trenutak'**
  String get episodeCopyMomentLink;

  /// Label/tooltip for the action that opens the video player panel.
  ///
  /// In hr, this message translates to:
  /// **'Video'**
  String get episodeVideo;

  /// Inline label preceding the HR/EN language toggle chip on the episode screen.
  ///
  /// In hr, this message translates to:
  /// **'Jezik:'**
  String get episodeLanguageLabel;

  /// Bottom-bar label that opens the table of contents drawer.
  ///
  /// In hr, this message translates to:
  /// **'Sadržaj'**
  String get episodeContents;

  /// Bottom-bar tab label for the AI-written article view.
  ///
  /// In hr, this message translates to:
  /// **'Članak'**
  String get episodeArticle;

  /// Button that (re)opens the audio player for audio-only episodes.
  ///
  /// In hr, this message translates to:
  /// **'Slušaj epizodu'**
  String get episodeListen;

  /// Button that opens the episode on YouTube when the video isn't on the CDN yet.
  ///
  /// In hr, this message translates to:
  /// **'Gledaj na YouTubeu'**
  String get episodeWatchOnYouTube;

  /// Short badge on episode cards: the episode is registered but nothing has been downloaded yet.
  ///
  /// In hr, this message translates to:
  /// **'U redu čekanja'**
  String get episodeStageQueuedBadge;

  /// Short badge on episode cards: metadata is here, audio/video is still being downloaded.
  ///
  /// In hr, this message translates to:
  /// **'Preuzimamo'**
  String get episodeStageFetchedBadge;

  /// Short badge on episode cards: media is playable, transcription is next.
  ///
  /// In hr, this message translates to:
  /// **'Prepisujemo'**
  String get episodeStageMediaReadyBadge;

  /// Short badge on episode cards: transcript exists, the article is being written.
  ///
  /// In hr, this message translates to:
  /// **'Pišemo članak'**
  String get episodeStageTranscribedBadge;

  /// Status card headline when info.json is missing from the CDN.
  ///
  /// In hr, this message translates to:
  /// **'Epizoda još nije preuzeta'**
  String get episodeStageQueuedHeadline;

  /// Status card headline when metadata exists but no media is on the CDN.
  ///
  /// In hr, this message translates to:
  /// **'Preuzimamo zvuk i sliku'**
  String get episodeStageFetchedHeadline;

  /// Status card headline when media is playable but there is no transcript yet.
  ///
  /// In hr, this message translates to:
  /// **'Radimo prijepis govora'**
  String get episodeStageMediaReadyHeadline;

  /// Status card headline when a transcript exists but the article does not.
  ///
  /// In hr, this message translates to:
  /// **'Pišemo sažetak i članak'**
  String get episodeStageTranscribedHeadline;

  /// Status card headline when the full pipeline is done.
  ///
  /// In hr, this message translates to:
  /// **'Epizoda je obrađena'**
  String get episodeStagePublishedHeadline;

  /// Status card body for the queued stage.
  ///
  /// In hr, this message translates to:
  /// **'Znamo za nju iz kanala, ali datoteke još nisu kod nas — preuzimanje nije uspjelo ili tek slijedi. Do tada je pogledaj izravno s izvora.'**
  String get episodeStageQueuedBody;

  /// Status card body for the fetched stage.
  ///
  /// In hr, this message translates to:
  /// **'Naslov, opis i sličica su kod nas; zvuk i slika još nisu. Reprodukcija kod nas zato još ne radi — pogledaj epizodu s izvora dok je ne prenesemo.'**
  String get episodeStageFetchedBody;

  /// Status card body when playable video exists but there is no AI text layer.
  ///
  /// In hr, this message translates to:
  /// **'Video možeš gledati odmah. Prijepis, sažetak, poglavlja, članak i teološka analiza stižu čim ih obrada pripremi.'**
  String get episodeStageMediaReadyBodyVideo;

  /// Status card body when playable audio exists but there is no AI text layer.
  ///
  /// In hr, this message translates to:
  /// **'Zvuk možeš slušati odmah. Prijepis, sažetak, poglavlja, članak i teološka analiza stižu čim ih obrada pripremi.'**
  String get episodeStageMediaReadyBodyAudio;

  /// Status card body for the transcribed stage.
  ///
  /// In hr, this message translates to:
  /// **'Prijepis je gotov. Sažetak, poglavlja, članak i teološka analiza stižu čim ih obrada pripremi.'**
  String get episodeStageTranscribedBody;

  /// Status card body for the published stage.
  ///
  /// In hr, this message translates to:
  /// **'Sav sadržaj je spreman.'**
  String get episodeStagePublishedBody;

  /// Progress step label: episode metadata fetched from the source.
  ///
  /// In hr, this message translates to:
  /// **'Preuzeta epizoda'**
  String get episodeStepFetch;

  /// Progress step label: playable media uploaded to the CDN.
  ///
  /// In hr, this message translates to:
  /// **'Zvuk i slika'**
  String get episodeStepMedia;

  /// Progress step label: diarized transcript.
  ///
  /// In hr, this message translates to:
  /// **'Prijepis govora'**
  String get episodeStepTranscript;

  /// Progress step label: AI summary.
  ///
  /// In hr, this message translates to:
  /// **'Sažetak'**
  String get episodeStepSummary;

  /// Progress step label: AI-written article.
  ///
  /// In hr, this message translates to:
  /// **'Članak'**
  String get episodeStepArticle;

  /// Progress step label: Magisterium theological analysis.
  ///
  /// In hr, this message translates to:
  /// **'Teološka analiza'**
  String get episodeStepMagisterium;

  /// Heading above the per-step pipeline progress checklist.
  ///
  /// In hr, this message translates to:
  /// **'Napredak obrade'**
  String get episodeStatusStepsTitle;

  /// Primary button that reveals the in-app YouTube player.
  ///
  /// In hr, this message translates to:
  /// **'Gledaj ovdje'**
  String get episodeWatchHere;

  /// Label of the play overlay on the in-app YouTube facade.
  ///
  /// In hr, this message translates to:
  /// **'Gledaj u aplikaciji'**
  String get episodeWatchInApp;

  /// Primary button that opens our own player for an episode whose media is on the CDN.
  ///
  /// In hr, this message translates to:
  /// **'Gledaj epizodu'**
  String get episodeWatchOurPlayer;

  /// Explains why the in-app YouTube player is unavailable for this episode.
  ///
  /// In hr, this message translates to:
  /// **'Vlasnik je za ovu epizodu isključio ugrađeni player, pa se otvara na YouTubeu.'**
  String get episodeEmbedBlocked;

  /// Short not-found line used above the queued status card, with the episode id.
  ///
  /// In hr, this message translates to:
  /// **'Epizoda „{id}” nije pronađena na CDN-u.'**
  String episodeStatusNotOnCdn(String id);

  /// Caption under the embedded YouTube player in the desktop side panel, shown while the episode has no media on our CDN.
  ///
  /// In hr, this message translates to:
  /// **'Gledaj s YouTubea dok epizodu ne obradimo.'**
  String get episodeYouTubeUntilProcessed;

  /// Placeholder shown in the player area when no playable media exists for the episode.
  ///
  /// In hr, this message translates to:
  /// **'Medijski zapis nije dostupan za ovu epizodu.'**
  String get episodeMediaUnavailable;

  /// Empty-state shown in the Chapters tab when the episode has no chapters.
  ///
  /// In hr, this message translates to:
  /// **'Nema poglavlja za ovu epizodu.'**
  String get episodeNoChapters;

  /// Section title for the list of key topics in the episode Info tab.
  ///
  /// In hr, this message translates to:
  /// **'Ključne teme'**
  String get episodeKeyTopics;

  /// Section title for the list of key takeaways in the episode Info tab.
  ///
  /// In hr, this message translates to:
  /// **'Ključne točke'**
  String get episodeKeyTakeaways;

  /// Section title for the list of speakers in the episode Info tab.
  ///
  /// In hr, this message translates to:
  /// **'Govornici'**
  String get episodeSpeakers;

  /// Navigation tab label for the player view on the simple episode screen.
  ///
  /// In hr, this message translates to:
  /// **'Reprodukcija'**
  String get episodeTabPlayer;

  /// Navigation tab label for the chapters list on the simple episode screen.
  ///
  /// In hr, this message translates to:
  /// **'Poglavlja'**
  String get episodeTabChapters;

  /// Navigation tab label for the episode info view on the simple episode screen.
  ///
  /// In hr, this message translates to:
  /// **'Info'**
  String get episodeTabInfo;

  /// Heading of the technical metadata footer at the bottom of the full episode screen.
  ///
  /// In hr, this message translates to:
  /// **'Metapodaci'**
  String get episodeMetadata;

  /// Metadata row label for the channel name.
  ///
  /// In hr, this message translates to:
  /// **'Kanal'**
  String get episodeMetaChannel;

  /// Metadata row label for the AI model used to generate the summary.
  ///
  /// In hr, this message translates to:
  /// **'Model (sažetak)'**
  String get episodeMetaModelSummary;

  /// Metadata row label for the AI model used to generate the article.
  ///
  /// In hr, this message translates to:
  /// **'Model (članak)'**
  String get episodeMetaModelArticle;

  /// Metadata row label for the AI model used for the theological analysis.
  ///
  /// In hr, this message translates to:
  /// **'Model (teologija)'**
  String get episodeMetaModelTheology;

  /// Metadata row label for the date the AI content was generated.
  ///
  /// In hr, this message translates to:
  /// **'Generirano'**
  String get episodeMetaGenerated;

  /// Metadata row label for the content language.
  ///
  /// In hr, this message translates to:
  /// **'Jezik'**
  String get episodeMetaLanguage;

  /// Metadata row label for the classified content type.
  ///
  /// In hr, this message translates to:
  /// **'Tip sadržaja'**
  String get episodeMetaContentType;

  /// Metadata row label for the detected sentiment.
  ///
  /// In hr, this message translates to:
  /// **'Sentiment'**
  String get episodeMetaSentiment;

  /// Metadata row label for the episode publication date in the Info tab.
  ///
  /// In hr, this message translates to:
  /// **'Datum'**
  String get episodeMetaDate;

  /// Metadata row label for the episode duration in the Info tab.
  ///
  /// In hr, this message translates to:
  /// **'Trajanje'**
  String get episodeMetaDuration;

  /// Channel card eyebrow meta line (uppercased in UI): label, episode count, total duration.
  ///
  /// In hr, this message translates to:
  /// **'Kanal · {count} ep · {duration}'**
  String homeChannelCardMeta(int count, String duration);

  /// Tooltip on the channel card Magisterium pill; {label} is the score band name.
  ///
  /// In hr, this message translates to:
  /// **'{label}\nProcjena usklađenosti s katoličkim naukom (0–100).'**
  String homeChannelMagisteriumTooltip(String label);

  /// Footer column header: about the project.
  ///
  /// In hr, this message translates to:
  /// **'O projektu'**
  String get homeFooterAbout;

  /// Footer about-the-project paragraph.
  ///
  /// In hr, this message translates to:
  /// **'{app} uz pomoć umjetne inteligencije transkribira, sažima i analizira hrvatske katoličke podcaste. Agent Magisterium AI ocjenjuje usklađenost s katoličkim naukom.'**
  String homeFooterAboutText(String app);

  /// Footer about-the-project paragraph for brands without a domain score.
  ///
  /// In hr, this message translates to:
  /// **'{app} uz pomoć umjetne inteligencije transkribira podcaste, dijeli ih na poglavlja i od njih piše članke koje možeš čitati, s govornicima i pretragom po smislu.'**
  String homeFooterAboutTextGeneric(String app);

  /// Footer column header: links.
  ///
  /// In hr, this message translates to:
  /// **'Poveznice'**
  String get homeFooterLinks;

  /// Footer link that opens an email to suggest an episode.
  ///
  /// In hr, this message translates to:
  /// **'Predloži epizodu'**
  String get homeFooterSuggestEpisode;

  /// Subject line of the suggest-an-episode email.
  ///
  /// In hr, this message translates to:
  /// **'{app} — prijedlog epizode'**
  String homeFooterEpisodeSuggestionSubject(String app);

  /// Footer link: contact.
  ///
  /// In hr, this message translates to:
  /// **'Kontakt'**
  String get homeFooterContact;

  /// Footer link: privacy policy.
  ///
  /// In hr, this message translates to:
  /// **'Privatnost'**
  String get homeFooterPrivacy;

  /// Footer link: terms of use.
  ///
  /// In hr, this message translates to:
  /// **'Uvjeti korištenja'**
  String get homeFooterTerms;

  /// Footer column header: aggregate statistics.
  ///
  /// In hr, this message translates to:
  /// **'Statistika'**
  String get homeFooterStats;

  /// Footer stat label for number of channels (number shown separately).
  ///
  /// In hr, this message translates to:
  /// **'{count, plural, one{kanal} few{kanala} other{kanala}}'**
  String homeFooterStatChannels(int count);

  /// Footer stat label for number of episodes (number shown separately).
  ///
  /// In hr, this message translates to:
  /// **'{count, plural, one{epizoda} few{epizode} other{epizoda}}'**
  String homeFooterStatEpisodes(int count);

  /// Footer stat label for hours processed (number shown separately).
  ///
  /// In hr, this message translates to:
  /// **'{count, plural, one{sat obrađen} few{sata obrađena} other{sati obrađeno}}'**
  String homeFooterStatHours(int count);

  /// Footer stat label for the average Magisterium score.
  ///
  /// In hr, this message translates to:
  /// **'prosječna Magisterium ocjena'**
  String get homeFooterStatAvgScore;

  /// Small badge on a footer link that is not yet available.
  ///
  /// In hr, this message translates to:
  /// **'Uskoro'**
  String get homeFooterSoon;

  /// Footer copyright line.
  ///
  /// In hr, this message translates to:
  /// **'© {year} {app}'**
  String homeFooterCopyright(int year, String app);

  /// Footer tagline.
  ///
  /// In hr, this message translates to:
  /// **'Stvoreno u Hrvatskoj'**
  String get homeFooterMadeIn;

  /// Placeholder text inside the app bar search trigger (desktop).
  ///
  /// In hr, this message translates to:
  /// **'Pretraži kanale i epizode'**
  String get homeSearchPlaceholderFull;

  /// Tooltip on the mobile search icon button.
  ///
  /// In hr, this message translates to:
  /// **'Pretraži'**
  String get homeSearchTooltip;

  /// Channel sort option: by most recent episode.
  ///
  /// In hr, this message translates to:
  /// **'Najnoviji'**
  String get homeSortNewest;

  /// Channel sort option: by episode count.
  ///
  /// In hr, this message translates to:
  /// **'Najviše epizoda'**
  String get homeSortMostEpisodes;

  /// Channel sort option: by average Magisterium score.
  ///
  /// In hr, this message translates to:
  /// **'Magisterium ocjena'**
  String get homeSortMagisterium;

  /// Channel sort option: alphabetical by name.
  ///
  /// In hr, this message translates to:
  /// **'Abecedno'**
  String get homeSortAlphabetical;

  /// Channel sort option: the user's saved custom order.
  ///
  /// In hr, this message translates to:
  /// **'Moj redoslijed'**
  String get homeSortCustom;

  /// Short label for the featured reason: high-quality and recent.
  ///
  /// In hr, this message translates to:
  /// **'Najbolji izbor'**
  String get homeReasonShortHiQualityRecent;

  /// Short label for the featured reason: high Magisterium score.
  ///
  /// In hr, this message translates to:
  /// **'Visoka Magisterium ocjena'**
  String get homeReasonShortHiQuality;

  /// Short label for the featured reason: any AI-processed episode.
  ///
  /// In hr, this message translates to:
  /// **'AI-obrađeno'**
  String get homeReasonShortAnyMagisterium;

  /// Short label for the featured reason: newest episode.
  ///
  /// In hr, this message translates to:
  /// **'Najnovije'**
  String get homeReasonShortNewest;

  /// Tooltip on the hero carousel rotation badge.
  ///
  /// In hr, this message translates to:
  /// **'{count, plural, one{Svaki dan biramo najbolju epizodu — automatski se izmjenjuju.} few{Svaki dan biramo {count} najbolje epizode — automatski se izmjenjuju.} other{Svaki dan biramo {count} najboljih epizoda — automatski se izmjenjuju.}}'**
  String homeHeroRotationTooltip(int count);

  /// Hero carousel badge (uppercased in UI) signalling daily rotation.
  ///
  /// In hr, this message translates to:
  /// **'U rotaciji'**
  String get homeHeroRotationBadge;

  /// Hero section eyebrow label (uppercased in UI).
  ///
  /// In hr, this message translates to:
  /// **'Istaknuto'**
  String get homeHeroEyebrow;

  /// Hero play button label.
  ///
  /// In hr, this message translates to:
  /// **'Slušaj'**
  String get homeHeroListen;

  /// Small hero button (uppercased in UI) opening the featured-criteria dialog.
  ///
  /// In hr, this message translates to:
  /// **'Zašto?'**
  String get homeHeroWhyButton;

  /// Title (uppercased in UI) of the dialog explaining why an episode is featured.
  ///
  /// In hr, this message translates to:
  /// **'Kriteriji za isticanje'**
  String get homeWhyDialogTitle;

  /// Heading (uppercased in UI) above the algorithm tier list.
  ///
  /// In hr, this message translates to:
  /// **'Kako algoritam bira'**
  String get homeWhyAlgorithmHeading;

  /// Closing paragraph of the featured-criteria dialog.
  ///
  /// In hr, this message translates to:
  /// **'Istaknuta se epizoda mijenja svaki dan u ponoć — algoritam izdvaja pet najboljih kandidata iz aktivnog razreda i bira jednoga prema danu u godini. Tijekom dana izbor ostaje isti (deterministički).'**
  String get homeWhyDialogExplainer;

  /// Dismiss action of the featured-criteria dialog.
  ///
  /// In hr, this message translates to:
  /// **'Razumijem'**
  String get homeWhyGotIt;

  /// Dialog headline for the featured reason: high-quality and recent.
  ///
  /// In hr, this message translates to:
  /// **'Visoka ocjena, svježa epizoda'**
  String get homeReasonHeadlineHiQualityRecent;

  /// Dialog headline for the featured reason: high Magisterium score.
  ///
  /// In hr, this message translates to:
  /// **'Visoka Magisterium ocjena'**
  String get homeReasonHeadlineHiQuality;

  /// Dialog headline for the featured reason: any AI-processed episode.
  ///
  /// In hr, this message translates to:
  /// **'AI-obrađena epizoda'**
  String get homeReasonHeadlineAnyMagisterium;

  /// Dialog headline for the featured reason: newest episode.
  ///
  /// In hr, this message translates to:
  /// **'Najnovija epizoda'**
  String get homeReasonHeadlineNewest;

  /// Facts table label: channel.
  ///
  /// In hr, this message translates to:
  /// **'Kanal'**
  String get homeWhyFactChannel;

  /// Facts table label: Magisterium score.
  ///
  /// In hr, this message translates to:
  /// **'Magisterium ocjena'**
  String get homeWhyFactScore;

  /// Facts table label: publication date.
  ///
  /// In hr, this message translates to:
  /// **'Objavljeno'**
  String get homeWhyFactPublished;

  /// Facts table label: whether the episode has AI processing.
  ///
  /// In hr, this message translates to:
  /// **'AI obrada'**
  String get homeWhyFactAiProcessing;

  /// Facts table value when the episode is AI-processed.
  ///
  /// In hr, this message translates to:
  /// **'Da (transkript, sažetak i Magisterium analiza)'**
  String get homeWhyFactAiYes;

  /// Brand-neutral variant of homeWhyFactAiYes for brands without a domain score.
  ///
  /// In hr, this message translates to:
  /// **'Da (transkript, članak i poglavlja)'**
  String get homeWhyFactAiYesGeneric;

  /// Facts table value when the episode is not AI-processed.
  ///
  /// In hr, this message translates to:
  /// **'Ne'**
  String get homeWhyFactAiNo;

  /// Facts table label: the computed algorithm weight.
  ///
  /// In hr, this message translates to:
  /// **'Algoritamska težina'**
  String get homeWhyFactWeight;

  /// Facts table value showing the weight and its formula.
  ///
  /// In hr, this message translates to:
  /// **'{weight} (ocjena × 0,6 + svježina × 0,4)'**
  String homeWhyFactWeightValue(String weight);

  /// Facts table label: the candidate pool size.
  ///
  /// In hr, this message translates to:
  /// **'Skupina kandidata'**
  String get homeWhyFactPool;

  /// Facts table value: number of candidate episodes in the same tier.
  ///
  /// In hr, this message translates to:
  /// **'{count, plural, one{{count} epizoda u istom razredu} few{{count} epizode u istom razredu} other{{count} epizoda u istom razredu}}'**
  String homeWhyFactPoolValue(int count);

  /// Algorithm tier 1 title.
  ///
  /// In hr, this message translates to:
  /// **'1. Najbolji izbor'**
  String get homeTier1Title;

  /// Algorithm tier 1 description.
  ///
  /// In hr, this message translates to:
  /// **'AI obrada + ocjena ≥ 70 + objavljeno u zadnjih 14 dana. Poredano po (ocjena × 0,6 + svježina × 0,4). Pet najboljih ulazi u dnevnu rotaciju.'**
  String get homeTier1Desc;

  /// Algorithm tier 2 title.
  ///
  /// In hr, this message translates to:
  /// **'2. Visoka ocjena'**
  String get homeTier2Title;

  /// Algorithm tier 2 description.
  ///
  /// In hr, this message translates to:
  /// **'AI obrada + ocjena ≥ 70 (bilo koji datum). Poredano po ocjeni.'**
  String get homeTier2Desc;

  /// Algorithm tier 3 title.
  ///
  /// In hr, this message translates to:
  /// **'3. AI-obrađeno'**
  String get homeTier3Title;

  /// Algorithm tier 3 description.
  ///
  /// In hr, this message translates to:
  /// **'Bilo koja epizoda s AI obradom. Poredano po datumu.'**
  String get homeTier3Desc;

  /// Algorithm tier 4 title.
  ///
  /// In hr, this message translates to:
  /// **'4. Najnovije'**
  String get homeTier4Title;

  /// Algorithm tier 4 description.
  ///
  /// In hr, this message translates to:
  /// **'Pričuva — najnovija epizoda bez ikakve obrade.'**
  String get homeTier4Desc;

  /// Relative time: published today.
  ///
  /// In hr, this message translates to:
  /// **'danas'**
  String get homeAgoToday;

  /// Relative time: published yesterday.
  ///
  /// In hr, this message translates to:
  /// **'jučer'**
  String get homeAgoYesterday;

  /// Relative time: N days ago.
  ///
  /// In hr, this message translates to:
  /// **'{days, plural, one{prije {days} dan} few{prije {days} dana} other{prije {days} dana}}'**
  String homeAgoDays(int days);

  /// Relative time: N weeks ago.
  ///
  /// In hr, this message translates to:
  /// **'{weeks, plural, one{prije {weeks} tjedan} few{prije {weeks} tjedna} other{prije {weeks} tjedana}}'**
  String homeAgoWeeks(int weeks);

  /// Relative time: N months ago.
  ///
  /// In hr, this message translates to:
  /// **'{months, plural, one{prije {months} mjesec} few{prije {months} mjeseca} other{prije {months} mjeseci}}'**
  String homeAgoMonths(int months);

  /// Relative time: N years ago.
  ///
  /// In hr, this message translates to:
  /// **'{years, plural, one{prije {years} godinu} few{prije {years} godine} other{prije {years} godina}}'**
  String homeAgoYears(int years);

  /// Snackbar shown when tapping a feature that is not yet available.
  ///
  /// In hr, this message translates to:
  /// **'Ova značajka uskoro stiže'**
  String get homeComingSoonSnack;

  /// Error message shown when the channel index fails to load.
  ///
  /// In hr, this message translates to:
  /// **'Pogreška pri učitavanju kanala:\n{error}'**
  String homeChannelsLoadError(String error);

  /// Eyebrow title (uppercased in UI) of the continue-listening rail.
  ///
  /// In hr, this message translates to:
  /// **'Nastavi slušati'**
  String get homeRailContinue;

  /// Eyebrow title (uppercased in UI) of the latest-episodes rail.
  ///
  /// In hr, this message translates to:
  /// **'Najnovije epizode'**
  String get homeRailLatest;

  /// Home rail with the latest episodes of the brand's featured channels.
  ///
  /// In hr, this message translates to:
  /// **'Istaknuti podcasti'**
  String get homeRailFeaturedShows;

  /// Eyebrow title (uppercased in UI) of the saved/liked episodes rail.
  ///
  /// In hr, this message translates to:
  /// **'Tvoje spremljeno'**
  String get homeRailFavorites;

  /// Naslov ekrana s punim popisom spremljenih (favorit) epizoda.
  ///
  /// In hr, this message translates to:
  /// **'Spremljene epizode'**
  String get favoritesTitle;

  /// Broj spremljenih epizoda iznad popisa.
  ///
  /// In hr, this message translates to:
  /// **'{count, plural, one{{count} epizoda} few{{count} epizode} other{{count} epizoda}}'**
  String favoritesCount(int count);

  /// Naslov praznog stanja na ekranu spremljenih epizoda.
  ///
  /// In hr, this message translates to:
  /// **'Još nemaš spremljenih epizoda'**
  String get favoritesEmptyTitle;

  /// Objašnjenje praznog stanja na ekranu spremljenih epizoda.
  ///
  /// In hr, this message translates to:
  /// **'Dodirni srce na epizodi i naći ćeš je ovdje — najnovije prvo.'**
  String get favoritesEmptyBody;

  /// Gumb iz praznog stanja koji vodi na naslovnicu.
  ///
  /// In hr, this message translates to:
  /// **'Istraži epizode'**
  String get favoritesBrowse;

  /// Stanje gumba i potvrda nakon što je epizoda spremljena među favorite.
  ///
  /// In hr, this message translates to:
  /// **'Spremljeno'**
  String get favoritesSaved;

  /// SnackBar potvrda nakon uklanjanja epizode s popisa spremljenih.
  ///
  /// In hr, this message translates to:
  /// **'Uklonjeno iz spremljenih'**
  String get favoritesRemoved;

  /// Podnaslov stavke na ekranu računa koja vodi na spremljene epizode.
  ///
  /// In hr, this message translates to:
  /// **'Cijeli popis, najnovije prvo'**
  String get favoritesAccountSubtitle;

  /// Naslov sekcije na ekranu računa koja skuplja korisnikov spremljeni sadržaj.
  ///
  /// In hr, this message translates to:
  /// **'Moja knjižnica'**
  String get authSectionLibrary;

  /// Eyebrow title (uppercased in UI) of the freshly-arrived rail.
  ///
  /// In hr, this message translates to:
  /// **'Upravo stiglo'**
  String get homeRailFreshlyArrived;

  /// Badge on freshly-arrived episode cards that are still being processed.
  ///
  /// In hr, this message translates to:
  /// **'U obradi'**
  String get homeStatusProcessing;

  /// Eyebrow (uppercased in UI) above the all-channels call-to-action.
  ///
  /// In hr, this message translates to:
  /// **'Kanali'**
  String get homeChannelsEyebrow;

  /// Title of the all-channels call-to-action card.
  ///
  /// In hr, this message translates to:
  /// **'Svi kanali'**
  String get homeAllChannelsTitle;

  /// Subtitle of the all-channels call-to-action card.
  ///
  /// In hr, this message translates to:
  /// **'{count, plural, one{Pretraži i pregledaj {count} kanal} few{Pretraži i pregledaj svih {count} kanala} other{Pretraži i pregledaj svih {count} kanala}}'**
  String homeAllChannelsSubtitle(int count);

  /// Progress label shown while channel details are loading.
  ///
  /// In hr, this message translates to:
  /// **'Učitavam {loaded}/{total} kanala…'**
  String homeLoadingChannels(int loaded, int total);

  /// Accessibility label for the search overlay barrier.
  ///
  /// In hr, this message translates to:
  /// **'Zatvori pretragu'**
  String get homeSearchBarrierLabel;

  /// Hint text in the search overlay input.
  ///
  /// In hr, this message translates to:
  /// **'Pretraži kanale, epizode i sadržaj…'**
  String get homeSearchHint;

  /// Tooltip for the clear (×) button inside the full-screen mobile search field.
  ///
  /// In hr, this message translates to:
  /// **'Obriši upit'**
  String get homeSearchClear;

  /// Shown when a search returns nothing.
  ///
  /// In hr, this message translates to:
  /// **'Nema rezultata za „{query}”'**
  String homeSearchNoResults(String query);

  /// Loading state shown in the content-search column.
  ///
  /// In hr, this message translates to:
  /// **'Pretražujem…'**
  String get homeSearchSearching;

  /// Search results section header (uppercased in UI): channels.
  ///
  /// In hr, this message translates to:
  /// **'Kanali'**
  String get homeSearchSectionChannels;

  /// Search results section header (uppercased in UI): episodes.
  ///
  /// In hr, this message translates to:
  /// **'Epizode'**
  String get homeSearchSectionEpisodes;

  /// Search overlay empty-state title.
  ///
  /// In hr, this message translates to:
  /// **'Počni tipkati za pretragu'**
  String get homeSearchEmptyTitle;

  /// Search overlay empty-state subtitle.
  ///
  /// In hr, this message translates to:
  /// **'Pretražuje kanale, epizode i sam sadržaj razgovora'**
  String get homeSearchEmptySubtitle;

  /// Keyboard navigation hint in the search overlay empty state.
  ///
  /// In hr, this message translates to:
  /// **'↑ ↓ kroz popis · ↵ za odabir'**
  String get homeSearchKeyboardHint;

  /// Channel result row meta: episode count and total duration.
  ///
  /// In hr, this message translates to:
  /// **'{count, plural, one{{count} epizoda · {duration}} few{{count} epizode · {duration}} other{{count} epizoda · {duration}}}'**
  String homeSearchChannelMeta(int count, String duration);

  /// Expander label to open an episode by entering its YouTube ID.
  ///
  /// In hr, this message translates to:
  /// **'Otvori po YouTube ID-u'**
  String get homeSearchOpenById;

  /// Link at the bottom of the search overlay to the full results screen (/search).
  ///
  /// In hr, this message translates to:
  /// **'Prikaži sve rezultate'**
  String get homeSearchShowAll;

  /// Tooltip on a moment chip under a search result; jumps to that second of the episode.
  ///
  /// In hr, this message translates to:
  /// **'Pusti od {time}'**
  String homeSearchJumpTo(String time);

  /// Hint text in the YouTube ID input field.
  ///
  /// In hr, this message translates to:
  /// **'npr. H-p2Hl6x7I0'**
  String get homeSearchIdHint;

  /// Label preceding the date a legal document was last revised; shown on the privacy and terms pages.
  ///
  /// In hr, this message translates to:
  /// **'Zadnje ažurirano: {date}'**
  String legalLastUpdated(String date);

  /// Naslov odjeljka politike privatnosti o push obavijestima.
  ///
  /// In hr, this message translates to:
  /// **'Push obavijesti'**
  String get legalPrivacyPushTitle;

  /// Odjeljak politike privatnosti o push obavijestima (Obrada F).
  ///
  /// In hr, this message translates to:
  /// **'Ako u aplikaciji za iOS ili Android uključite obavijesti, javljamo Vam kad stigne nova epizoda — sve nove ili samo s kanala koje izaberete na ekranu Obavijesti. Za dostavu koristimo Google Firebase Cloud Messaging: uređaj dobiva registracijski token i pretplaćuje se na teme koje ste izabrali (npr. „sve nove epizode” ili pojedini kanal). Token i popis tema ne spremamo uz Vaš račun; izbor tema čuva se samo na Vašem uređaju, a pretplate drži Google kao izvršitelj obrade.\n\nObavijesti šaljemo na temelju Vaše privole (čl. 6. st. 1. t. a) GDPR-a), koju dajete uključivanjem obavijesti i sistemskom dozvolom. Možete je povući u svakom trenutku na ekranu Obavijesti ili u postavkama uređaja. Između 22 i 7 sati obavijesti ne šaljemo.'**
  String get legalPrivacyPushBody;

  /// Section heading for the contact details on legal pages (privacy and terms).
  ///
  /// In hr, this message translates to:
  /// **'Kontakt'**
  String get legalContactTitle;

  /// Page title and app bar title for the privacy policy screen.
  ///
  /// In hr, this message translates to:
  /// **'Politika privatnosti'**
  String get legalPrivacyTitle;

  /// Introductory paragraph on the privacy policy screen describing the app and noting the page is a placeholder.
  ///
  /// In hr, this message translates to:
  /// **'{app} aplikacija je koja transkribira, sažima i analizira hrvatske katoličke podcaste pomoću umjetne inteligencije.'**
  String legalPrivacyIntro(String app);

  /// Brand-neutral variant of legalPrivacyIntro for brands without a domain score.
  ///
  /// In hr, this message translates to:
  /// **'{app} je aplikacija koja uz pomoć umjetne inteligencije transkribira podcaste, dijeli ih na poglavlja i od njih piše članke za čitanje.'**
  String legalPrivacyIntroGeneric(String app);

  /// Section heading on the privacy policy screen for the data-collection paragraph.
  ///
  /// In hr, this message translates to:
  /// **'Koje podatke prikupljamo'**
  String get legalPrivacyDataTitle;

  /// Body paragraph on the privacy policy screen explaining which user data is collected and why.
  ///
  /// In hr, this message translates to:
  /// **'ITalk d.o.o. za informacijske tehnologije, kao voditelj obrade, prikuplja i obrađuje vaše podatke u skladu s Općom uredbom o zaštiti podataka (GDPR).\n\nKada se prijavite (putem Certilia IDP sustava, Googlea, Applea ili e-pošte), prikupljamo osnovne identifikacijske podatke (e-mail adresu, ime i prezime, te OIB ukoliko se prijavljujete putem e-Građani/Certilia sustava) isključivo u svrhu pružanja usluge. Vaš napredak slušanja, omiljene oznake i glasovanja pohranjuju se kako bi se sinkronizirali među uređajima.\n\nZa obradu \"Plus\" pretplata koristimo vanjske izvršitelje (Apple, Google, RevenueCat) te ne pohranjujemo niti imamo pristup podacima vaših bankovnih kartica. Primjenjujemo najviše tehničke i organizacijske mjere sigurnosti (enkripcija u prijenosu i pohrani).\n\nKao korisnik, imate pravo na pristup, ispravak, ograničenje obrade, prijenos i brisanje svojih podataka (svoj račun možete trajno obrisati u aplikaciji u svakom trenutku). Za sva pitanja o privatnosti ili ostvarivanje prava obratite se na {email}. U slučaju sumnje na povredu podataka, imate pravo podnijeti pritužbu Agenciji za zaštitu osobnih podataka (AZOP).'**
  String legalPrivacyDataBody(String email);

  /// No description provided for @legalPrivacyAnalyticsTitle.
  ///
  /// In hr, this message translates to:
  /// **'Analitika korištenja'**
  String get legalPrivacyAnalyticsTitle;

  /// Privacy policy section on first-party usage analytics: what is recorded, legal basis, storage location, 25-month retention.
  ///
  /// In hr, this message translates to:
  /// **'Kako bismo razumjeli kako se aplikacija koristi i mogli je poboljšavati, bilježimo događaje korištenja: pokretanje aplikacije, stranice i epizode koje otvarate, reprodukciju (pokretanje, pauzu, premotavanje, brzinu i koliko ste epizode odslušali), upite koje upišete u pretragu i što iz rezultata otvorite, trajanje sesije te prikaze i klikove na sponzorske poruke. Uz svaki događaj spremamo nasumični identifikator uređaja (aplikacija ga stvara pri prvom pokretanju i čuva u pohrani preglednika ili uređaja), identifikator sesije, vrstu uređaja i preglednika, verziju aplikacije, jezik, veličinu zaslona te približnu lokaciju (država, regija i grad), koju određuje Cloudflare. Ako ste prijavljeni, događaje povezujemo i s identifikatorom Vašeg računa. IP adresu ne spremamo.\n\nPodatke obrađujemo na temelju legitimnog interesa (čl. 6. st. 1. t. f) GDPR-a): mjerimo i poboljšavamo uslugu, uključujući pretragu, i bilježimo prikazivanje sponzorskih poruka. Ne koristimo alate trećih strana za praćenje (poput Google Analyticsa). Podatke pohranjujemo na vlastitom poslužitelju u Europskoj uniji (Frankfurt), a Cloudflare ih kao izvršitelj obrade prenosi do njega. Ne prodajemo ih i ne dijelimo s trećim stranama radi oglašavanja. Čuvamo ih 25 mjeseci. Identifikator uređaja možete ukloniti brisanjem podataka aplikacije ili pohrane preglednika. Za brisanje događaja povezanih s Vašim računom obratite se na {email}.'**
  String legalPrivacyAnalyticsBody(String email);

  /// Contact paragraph on the privacy policy screen with the support email address.
  ///
  /// In hr, this message translates to:
  /// **'Aplikacijom upravlja ITalk d.o.o. za informacijske tehnologije, IX. Južna obala 20, 10000 Zagreb, OIB: 54872935051. Za pitanja u vezi s privatnošću obratite se Matiji Stepaniću na {email}.'**
  String legalPrivacyContactBody(String email);

  /// Page title and app bar title for the terms of use screen.
  ///
  /// In hr, this message translates to:
  /// **'Uvjeti korištenja'**
  String get legalTermsTitle;

  /// Introductory paragraph on the terms of use screen stating that using the app constitutes acceptance.
  ///
  /// In hr, this message translates to:
  /// **'Korištenjem aplikacije {app} prihvaćate ove Uvjete korištenja.'**
  String legalTermsIntro(String app);

  /// Section heading on the terms of use screen for the content/copyright paragraph.
  ///
  /// In hr, this message translates to:
  /// **'Sadržaj'**
  String get legalTermsContentTitle;

  /// Body paragraph on the terms of use screen describing the educational use of content and copyright ownership.
  ///
  /// In hr, this message translates to:
  /// **'Svi audio i video materijali preuzimaju se iz javnih i slobodno dostupnih izvora. Aplikacija se pruža \"kakva jest\" (as-is) i bez ikakvih jamstava u pogledu neprekidne dostupnosti. ITalk d.o.o. ne odgovara za izravnu ili neizravnu štetu nastalu korištenjem aplikacije, a ukupna odgovornost ograničena je na iznos pretplate u zadnja 3 mjeseca. Pretplata na \"Plus\" opciju obnavlja se sukladno uvjetima vanjskih pružatelja (Apple/Google) te povrat sredstava reguliraju njihova pravila. Na ove uvjete primjenjuje se pravo Republike Hrvatske, a za sporove je nadležan sud u Zagrebu.'**
  String get legalTermsContentBody;

  /// Section heading on the terms of use screen for the AI-generated content disclaimer.
  ///
  /// In hr, this message translates to:
  /// **'AI analiza'**
  String get legalTermsAiTitle;

  /// Disclaimer paragraph on the terms of use screen noting that AI-generated analysis may contain errors and is not an official Church position.
  ///
  /// In hr, this message translates to:
  /// **'Magisterium AI ocjene i sažetci strojno su generirani i mogu sadržavati pogreške. Ne predstavljaju službeno stajalište Katoličke Crkve.'**
  String get legalTermsAiBody;

  /// Brand-neutral variant of legalTermsAiBody for brands without a domain score.
  ///
  /// In hr, this message translates to:
  /// **'Članci, sažeci, poglavlja i oznake govornika generiraju se automatski uz pomoć umjetne inteligencije (AI) i mogu sadržavati pogreške ili netočnosti (halucinacije). Korisnik AI značajke koristi na vlastitu odgovornost, a ITalk d.o.o. ne odgovara za točnost i pravne posljedice tako generiranog sadržaja.'**
  String get legalTermsAiBodyGeneric;

  /// Contact paragraph on the terms of use screen with the support email address.
  ///
  /// In hr, this message translates to:
  /// **'Aplikacijom upravlja ITalk d.o.o. za informacijske tehnologije, IX. Južna obala 20, 10000 Zagreb, OIB: 54872935051. Za upite kontaktirajte Matiju Stepanića na {email}.'**
  String legalTermsContactBody(String email);

  /// Magisterium score band label (>=90): the analysed content actively promotes Catholic teaching. Fallback when CDN scoreInterpretation is absent.
  ///
  /// In hr, this message translates to:
  /// **'Aktivno promiče katolički nauk'**
  String get magisteriumScoreActivelyPromotes;

  /// Magisterium score band label (>=70): mostly aligned with Catholic teaching. Fallback for CDN scoreInterpretation.
  ///
  /// In hr, this message translates to:
  /// **'Uglavnom usklađeno'**
  String get magisteriumScoreMostlyAligned;

  /// Magisterium score band label (>=50): partially aligned with Catholic teaching. Fallback for CDN scoreInterpretation.
  ///
  /// In hr, this message translates to:
  /// **'Djelomično usklađeno'**
  String get magisteriumScorePartiallyAligned;

  /// Magisterium score band label (>=30): departs from Catholic teaching. Fallback for CDN scoreInterpretation.
  ///
  /// In hr, this message translates to:
  /// **'Odstupanje od nauka'**
  String get magisteriumScoreDeviates;

  /// Magisterium score band label (lowest band): contradicts Catholic teaching. Fallback for CDN scoreInterpretation.
  ///
  /// In hr, this message translates to:
  /// **'Proturječi nauku'**
  String get magisteriumScoreContradicts;

  /// Subtitle under the overall Magisterium score card, describing what the score measures.
  ///
  /// In hr, this message translates to:
  /// **'Usklađenost s katoličkim naukom i Svetim pismom'**
  String get magisteriumAlignmentSubtitle;

  /// Count of theological concerns flagged across the Magisterium analysis.
  ///
  /// In hr, this message translates to:
  /// **'{count, plural, one{{count} teološka zabrinutost} few{{count} teološke zabrinutosti} other{{count} teoloških zabrinutosti}}'**
  String magisteriumTheologicalConcerns(int count);

  /// Header title of the chronological Magisterium AI article section. 'Magisterium AI' is a brand name kept literal.
  ///
  /// In hr, this message translates to:
  /// **'Magisterium AI — Teološka analiza'**
  String get magisteriumArticleHeaderTitle;

  /// Header subtitle of the chronological Magisterium AI article section.
  ///
  /// In hr, this message translates to:
  /// **'Kronološki pregled usklađenosti s katoličkim naukom'**
  String get magisteriumArticleHeaderSubtitle;

  /// Footer attribution showing which model generated the analysis and on what date.
  ///
  /// In hr, this message translates to:
  /// **'Analiza generirana modelom {model} • {date}'**
  String magisteriumAnalysisGeneratedBy(String model, String date);

  /// Toggle/label for the number of Church-document sources (citations) cited in a Magisterium section or full evaluation.
  ///
  /// In hr, this message translates to:
  /// **'{count, plural, one{{count} izvor iz crkvenih dokumenata} few{{count} izvora iz crkvenih dokumenata} other{{count} izvora iz crkvenih dokumenata}}'**
  String magisteriumSourcesFromChurchDocs(int count);

  /// Tab label for the full Magisterium AI evaluation view.
  ///
  /// In hr, this message translates to:
  /// **'Evaluacija'**
  String get magisteriumTabEvaluation;

  /// Tab label for the raw Magisterium prompt (developer/transparency view). 'Prompt' is a technical term kept in both languages.
  ///
  /// In hr, this message translates to:
  /// **'Prompt'**
  String get magisteriumTabPrompt;

  /// Gradient header title of the full Magisterium AI evaluation panel. 'Magisterium AI' is a brand name kept literal.
  ///
  /// In hr, this message translates to:
  /// **'Magisterium AI — Teološka evaluacija'**
  String get magisteriumFullHeaderTitle;

  /// Subtitle in the full evaluation header: model name followed by the citation count.
  ///
  /// In hr, this message translates to:
  /// **'{model}  •  {count, plural, one{{count} citat} few{{count} citata} other{{count} citata}}'**
  String magisteriumModelCitations(String model, int count);

  /// Section title above the list of cited sources in the Magisterium v2 view.
  ///
  /// In hr, this message translates to:
  /// **'Izvori'**
  String get magisteriumSourcesTitle;

  /// Subtitle under the Sources title: number of citations from Church documents (v2 view).
  ///
  /// In hr, this message translates to:
  /// **'{count, plural, one{{count} citat iz crkvenih dokumenata} few{{count} citata iz crkvenih dokumenata} other{{count} citata iz crkvenih dokumenata}}'**
  String magisteriumCitationsFromChurchDocs(int count);

  /// Small caption above the interpretation text on the Magisterium score badge. 'Magisterium' is a brand name kept literal.
  ///
  /// In hr, this message translates to:
  /// **'Magisterium ocjena'**
  String get magisteriumScoreCaption;

  /// Button in the citation detail sheet that opens the source on Magisterium.com. 'Magisterium.com' kept literal.
  ///
  /// In hr, this message translates to:
  /// **'Otvori na Magisterium.com'**
  String get magisteriumOpenOnMagisterium;

  /// Oznaka citiranog broja (paragrafa) crkvenog dokumenta, npr. „br. 74”.
  ///
  /// In hr, this message translates to:
  /// **'br. {ref}'**
  String magisteriumRefNumber(String ref);

  /// Oznaka citirane stranice crkvenog dokumenta (Acta Apostolicae Sedis), npr. „str. 65”.
  ///
  /// In hr, this message translates to:
  /// **'str. {ref}'**
  String magisteriumRefPage(String ref);

  /// Oznaka na kartici izvora: tap otvara Magisterium.com, koji nema hrvatsko izdanje dokumenta. 'Magisterium.com' ostaje doslovno.
  ///
  /// In hr, this message translates to:
  /// **'Magisterium.com · nije na hrvatskom'**
  String get magisteriumSourceNotCroatian;

  /// Napomena u sheetu izvora kad pipeline nije spremio citirani tekst.
  ///
  /// In hr, this message translates to:
  /// **'Doslovni odlomak nije preuzet. Magisterium.com nema hrvatsko izdanje, pa se dokument otvara na jeziku izvornika ili u engleskom prijevodu.'**
  String get magisteriumNoQuotedText;

  /// Tooltip na gumbu koji prebacuje s ugrađenog playera na YouTube embed radi veće kvalitete.
  ///
  /// In hr, this message translates to:
  /// **'YouTube player (viša kvaliteta)'**
  String get mediaYouTubeHigherQuality;

  /// Tooltip na CC gumbu kad su titlovi uključeni; (C) je tipkovnička kratica.
  ///
  /// In hr, this message translates to:
  /// **'Isključi titlove (C)'**
  String get mediaSubtitlesOff;

  /// Tooltip na CC gumbu kad su titlovi isključeni; (C) je tipkovnička kratica.
  ///
  /// In hr, this message translates to:
  /// **'Titlovi (C)'**
  String get mediaSubtitlesOn;

  /// CTA preko videa pri muted autoplayu (browser politika) — klik uključuje zvuk. Isti tekst nosi i tooltip gumba za zvuk dok je mutirano.
  ///
  /// In hr, this message translates to:
  /// **'Uključi zvuk'**
  String get mediaBoostVolume;

  /// No description provided for @mediaRemotePlay.
  ///
  /// In hr, this message translates to:
  /// **'Reproduciraj na televizoru'**
  String get mediaRemotePlay;

  /// No description provided for @mediaRemoteConnecting.
  ///
  /// In hr, this message translates to:
  /// **'Spajanje s televizorom…'**
  String get mediaRemoteConnecting;

  /// No description provided for @mediaRemoteConnected.
  ///
  /// In hr, this message translates to:
  /// **'Reproducira se na televizoru'**
  String get mediaRemoteConnected;

  /// Tooltip na gumbu za zvuk dok zvuk svira; (M) je tipkovnička kratica.
  ///
  /// In hr, this message translates to:
  /// **'Isključi zvuk (M)'**
  String get mediaMute;

  /// Tooltip na gumbu za Picture-in-Picture.
  ///
  /// In hr, this message translates to:
  /// **'Slika u slici'**
  String get mediaPictureInPicture;

  /// Snackbar kad uređaj ne podržava Picture-in-Picture.
  ///
  /// In hr, this message translates to:
  /// **'Slika u slici nije podržana na ovom uređaju.'**
  String get mediaPictureInPictureUnsupported;

  /// Tooltip na središnjem play/pause gumbu kad video svira.
  ///
  /// In hr, this message translates to:
  /// **'Pauziraj'**
  String get mediaPause;

  /// Tooltip na središnjem play/pause gumbu kad je video pauziran.
  ///
  /// In hr, this message translates to:
  /// **'Reproduciraj'**
  String get mediaPlay;

  /// Naslov liste poglavlja u video panelu.
  ///
  /// In hr, this message translates to:
  /// **'Poglavlja'**
  String get mediaChapters;

  /// Napomena u traci dok je aktivan YouTube embed mod.
  ///
  /// In hr, this message translates to:
  /// **'YouTube player — kvalitetu biraš u postavkama playera'**
  String get mediaYouTubeQualityHint;

  /// Oznaka gumba za povratak s YouTube embeda na ugrađeni player; {brand} je wordmark brenda.
  ///
  /// In hr, this message translates to:
  /// **'{brand} player'**
  String mediaNativePlayerLabel(String brand);

  /// Semantics oznaka za HR/EN prekidač jezika prikaza sadržaja.
  ///
  /// In hr, this message translates to:
  /// **'Odabir jezika prikaza'**
  String get mediaLanguageSelection;

  /// Tooltip uz prekidač jezika koji jamči vjernost prijevoda.
  ///
  /// In hr, this message translates to:
  /// **'Prijevod je doslovan, bez AI halucinacija.'**
  String get mediaTranslationDisclaimer;

  /// Semantics oznaka HR segmenta u prekidaču jezika prikaza.
  ///
  /// In hr, this message translates to:
  /// **'Prebaci na hrvatski'**
  String get mediaSwitchToCroatian;

  /// Semantics oznaka EN segmenta u prekidaču jezika prikaza.
  ///
  /// In hr, this message translates to:
  /// **'Prebaci na engleski'**
  String get mediaSwitchToEnglish;

  /// Tooltip na gumbu srca kad je epizoda već u favoritima.
  ///
  /// In hr, this message translates to:
  /// **'Ukloni iz favorita'**
  String get mediaRemoveFavorite;

  /// Tooltip na gumbu srca kad epizoda nije u favoritima.
  ///
  /// In hr, this message translates to:
  /// **'Dodaj u favorite'**
  String get mediaAddFavorite;

  /// Kratka obavijest kad player automatski nastavi reprodukciju s posljednje pozicije.
  ///
  /// In hr, this message translates to:
  /// **'Nastavljam od {time}'**
  String mediaResumingFrom(String time);

  /// Tooltip na gumbu za temu kad je trenutno aktivna tamna tema.
  ///
  /// In hr, this message translates to:
  /// **'Prebaci na svijetlu temu'**
  String get mediaSwitchToLightTheme;

  /// Tooltip na gumbu za temu kad je trenutno aktivna svijetla tema.
  ///
  /// In hr, this message translates to:
  /// **'Prebaci na tamnu temu'**
  String get mediaSwitchToDarkTheme;

  /// Oznaka gumba koji vodi na jednostavni prikaz epizode.
  ///
  /// In hr, this message translates to:
  /// **'Jednostavno'**
  String get mediaViewSimple;

  /// Oznaka gumba koji vodi na detaljni prikaz epizode.
  ///
  /// In hr, this message translates to:
  /// **'Detaljno'**
  String get mediaViewDetailed;

  /// Tooltip koji objašnjava jednostavni prikaz epizode.
  ///
  /// In hr, this message translates to:
  /// **'Prebaci na jednostavni prikaz — veliki player i poglavlja, bez članka (idealno za slušanje u autu)'**
  String get mediaViewSimpleTooltip;

  /// Tooltip koji objašnjava detaljni prikaz epizode (Magisterium = brend).
  ///
  /// In hr, this message translates to:
  /// **'Prebaci na detaljni prikaz — članak, Magisterium ocjena i poglavlja uz video'**
  String get mediaViewDetailedTooltip;

  /// Brand-neutral variant of mediaViewDetailedTooltip for brands without a domain score.
  ///
  /// In hr, this message translates to:
  /// **'Prebaci na detaljni prikaz — članak i poglavlja uz video'**
  String get mediaViewDetailedTooltipGeneric;

  /// Zamjensko ime u izborniku računa kad korisnik nema postavljeno ime.
  ///
  /// In hr, this message translates to:
  /// **'Korisnik'**
  String get mediaUserFallback;

  /// Pokazuje kojim je pružateljem (Google, Apple…) korisnik prijavljen.
  ///
  /// In hr, this message translates to:
  /// **'preko {provider}'**
  String mediaViaProvider(String provider);

  /// Oznaka uz korisnika koji je prošao eID/KYC verifikaciju identiteta.
  ///
  /// In hr, this message translates to:
  /// **'Verificiran identitet'**
  String get mediaVerifiedIdentity;

  /// Stavka izbornika računa koja vodi na ekran računa.
  ///
  /// In hr, this message translates to:
  /// **'Moj račun'**
  String get mediaMyAccount;

  /// Stavka izbornika računa koja vodi na korisnikove kanale.
  ///
  /// In hr, this message translates to:
  /// **'Moji kanali'**
  String get mediaMyChannels;

  /// Stavka izbornika računa za predaju sesije na drugi uređaj.
  ///
  /// In hr, this message translates to:
  /// **'Prebaci na drugi uređaj'**
  String get mediaSwitchDevice;

  /// Greška pri donaciji kad je upisani iznos manji od minimuma kampanje.
  ///
  /// In hr, this message translates to:
  /// **'Najmanji iznos je {amount} €'**
  String mediaMinAmount(String amount);

  /// Greška kad kreiranje donacije ne uspije.
  ///
  /// In hr, this message translates to:
  /// **'Stvaranje uplate nije uspjelo. Pokušaj ponovno.'**
  String get mediaPaymentCreateFailed;

  /// Naslov panela za donaciju autoru epizode.
  ///
  /// In hr, this message translates to:
  /// **'Podrži ovu epizodu'**
  String get mediaSupportEpisode;

  /// Opis ispod naslova panela za donaciju.
  ///
  /// In hr, this message translates to:
  /// **'Doniraj jednim skenom — SEPA, bez naknade. Sredstva idu izravno autoru, transparentno na lancu.'**
  String get mediaSupportBlurb;

  /// Napredak kampanje: prikupljeni iznos, cilj i broj podržavatelja.
  ///
  /// In hr, this message translates to:
  /// **'Prikupljeno {raised} € od {goal} € · {count, plural, one{# podržavatelj} few{# podržavatelja} other{# podržavatelja}}'**
  String mediaRaisedProgress(String raised, String goal, int count);

  /// Oznaka gumba za donaciju dok se uplata priprema.
  ///
  /// In hr, this message translates to:
  /// **'Pripremam…'**
  String get mediaPreparing;

  /// Oznaka gumba za potvrdu donacije s odabranim iznosom.
  ///
  /// In hr, this message translates to:
  /// **'Podrži s {amount} €'**
  String mediaSupportWithAmount(String amount);

  /// Naslov koraka s EPC QR kodom za SEPA uplatu.
  ///
  /// In hr, this message translates to:
  /// **'Skeniraj u svojoj bankovnoj aplikaciji'**
  String get mediaScanInBankApp;

  /// Prikaz iznosa uplate iznad QR koda.
  ///
  /// In hr, this message translates to:
  /// **'Iznos: {amount} €'**
  String mediaAmountValue(String amount);

  /// Oznaka retka s imenom primatelja uplate.
  ///
  /// In hr, this message translates to:
  /// **'Primatelj'**
  String get mediaRecipient;

  /// Oznaka retka s opisom/pozivom na broj uplate.
  ///
  /// In hr, this message translates to:
  /// **'Opis plaćanja'**
  String get mediaPaymentReference;

  /// Poruka dok sustav čeka potvrdu uplate na lancu.
  ///
  /// In hr, this message translates to:
  /// **'Čekam potvrdu plaćanja…'**
  String get mediaAwaitingPayment;

  /// Potvrda nakon uspješne donacije.
  ///
  /// In hr, this message translates to:
  /// **'Plaćanje je potvrđeno na lancu.'**
  String get mediaPaymentConfirmedOnChain;

  /// SnackBar potvrda nakon kopiranja vrijednosti (IBAN, primatelj, opis).
  ///
  /// In hr, this message translates to:
  /// **'Kopirano: {label}'**
  String mediaCopiedLabel(String label);

  /// Hint u polju za upis prilagođenog iznosa donacije.
  ///
  /// In hr, this message translates to:
  /// **'Ostalo'**
  String get mediaOtherAmount;

  /// Breadcrumb label for the home screen in the ownership flow.
  ///
  /// In hr, this message translates to:
  /// **'Početna'**
  String get ownershipCrumbHome;

  /// Breadcrumb label for the channel ownership step (current, non-tappable).
  ///
  /// In hr, this message translates to:
  /// **'Vlasništvo'**
  String get ownershipCrumbOwnership;

  /// Fallback label when a channel name is not yet loaded.
  ///
  /// In hr, this message translates to:
  /// **'Kanal'**
  String get ownershipChannelFallback;

  /// Title/label for the user's list of claimed channels.
  ///
  /// In hr, this message translates to:
  /// **'Moji kanali'**
  String get ownershipMyChannels;

  /// Error shown when the channel data fails to load.
  ///
  /// In hr, this message translates to:
  /// **'Učitavanje kanala nije uspjelo.'**
  String get ownershipLoadChannelFailed;

  /// Error shown when launching the YouTube OAuth URL fails.
  ///
  /// In hr, this message translates to:
  /// **'Otvaranje autorizacije nije uspjelo.'**
  String get ownershipOpenAuthFailed;

  /// Prompt shown to signed-out users on the claim screen.
  ///
  /// In hr, this message translates to:
  /// **'Za preuzimanje kanala prvo se prijavi.'**
  String get ownershipSignInToClaim;

  /// Shown when a channel has no resolvable YouTube channel ID.
  ///
  /// In hr, this message translates to:
  /// **'Ovaj kanal još nema povezan YouTube identifikator pa preuzimanje trenutno nije moguće.'**
  String get ownershipNoYoutubeId;

  /// Shown when the requested channel can't be found.
  ///
  /// In hr, this message translates to:
  /// **'Kanal nije pronađen.'**
  String get ownershipChannelNotFound;

  /// Title of the card inviting a non-owner to notify the real owner.
  ///
  /// In hr, this message translates to:
  /// **'Niste vlasnik kanala?'**
  String get ownershipNotOwnerTitle;

  /// Body text encouraging the user to invite the channel owner.
  ///
  /// In hr, this message translates to:
  /// **'Ako poznajete vlasnika, pošaljite mu poruku da preuzme vlasništvo i verificira se na {app}.'**
  String ownershipNotOwnerBody(String app);

  /// Button that opens WhatsApp with a prefilled invitation message.
  ///
  /// In hr, this message translates to:
  /// **'Pozovite vlasnika (WhatsApp)'**
  String get ownershipInviteOwnerWhatsApp;

  /// Prefilled WhatsApp message inviting a channel owner to claim their channel.
  ///
  /// In hr, this message translates to:
  /// **'Pozdrav! Vaš YouTube kanal „{channelTitle}” nalazi se na {app}. Možete besplatno preuzeti vlasništvo te upravljati svojim sadržajem i isplatama — verificirajte se kao vlasnik kanala ovdje: {link}'**
  String ownershipInviteMessage(String channelTitle, String link, String app);

  /// Title of the ownership verification step.
  ///
  /// In hr, this message translates to:
  /// **'Potvrdi vlasništvo'**
  String get ownershipStepConfirmTitle;

  /// Subtitle prompting re-verification of an expired ownership claim.
  ///
  /// In hr, this message translates to:
  /// **'Vlasništvo je starije od 90 dana — potvrdite ga ponovno.'**
  String get ownershipReverifySubtitle;

  /// Subtitle shown when ownership is verified.
  ///
  /// In hr, this message translates to:
  /// **'Vlasništvo je potvrđeno putem YouTube računa.'**
  String get ownershipOwnershipVerifiedSubtitle;

  /// Subtitle instructing the user to sign in with the owning YouTube account.
  ///
  /// In hr, this message translates to:
  /// **'Prijavi se YouTube računom koji je vlasnik ovog kanala.'**
  String get ownershipSignInYoutubeSubtitle;

  /// Explanatory note about who is eligible to claim ownership.
  ///
  /// In hr, this message translates to:
  /// **'Vlasništvo može preuzeti samo Google račun koji je vlasnik kanala. Uređivači i menadžeri dodani u YouTube postavkama (Channel permissions) to ne mogu — YouTube ih ne prikazuje kao vlasnike. Ako kanal pripada Brand računu, prijavite se Google računom koji njime upravlja.'**
  String get ownershipOwnershipNote;

  /// Button/menu action to re-verify ownership.
  ///
  /// In hr, this message translates to:
  /// **'Ponovite potvrdu'**
  String get ownershipReverifyAction;

  /// Button to start YouTube OAuth ownership verification.
  ///
  /// In hr, this message translates to:
  /// **'Prijava putem YouTubea'**
  String get ownershipLoginYoutube;

  /// Title of the identity (KYC) verification step.
  ///
  /// In hr, this message translates to:
  /// **'Verificiraj identitet'**
  String get ownershipStepVerifyIdentityTitle;

  /// Subtitle shown when identity is verified.
  ///
  /// In hr, this message translates to:
  /// **'Identitet je verificiran (eOsobna).'**
  String get ownershipIdentityVerifiedSubtitle;

  /// Subtitle prompting eID identity verification.
  ///
  /// In hr, this message translates to:
  /// **'Poveži eOsobnu (Certilia) — nužno prije isplate.'**
  String get ownershipConnectEosobnaSubtitle;

  /// Button to start eID (Certilia) identity verification.
  ///
  /// In hr, this message translates to:
  /// **'Verificiraj eOsobnom'**
  String get ownershipVerifyWithEosobna;

  /// Title of the payout wallet step.
  ///
  /// In hr, this message translates to:
  /// **'Poveži novčanik'**
  String get ownershipStepConnectWalletTitle;

  /// Subtitle shown when the wallet step is locked.
  ///
  /// In hr, this message translates to:
  /// **'Dostupno nakon potvrde vlasništva i verifikacije identiteta.'**
  String get ownershipWalletLockedSubtitle;

  /// Subtitle prompting wallet registration.
  ///
  /// In hr, this message translates to:
  /// **'Registrirajte adresu novčanika za isplatu (odredište).'**
  String get ownershipWalletSubtitle;

  /// Button to open the wallet management screen.
  ///
  /// In hr, this message translates to:
  /// **'Upravljajte novčanikom'**
  String get ownershipManageWallet;

  /// Progress message shown while completing the OAuth claim.
  ///
  /// In hr, this message translates to:
  /// **'Provjeravamo vlasništvo…'**
  String get ownershipCheckingOwnership;

  /// Error shown when the OAuth callback is missing code or state.
  ///
  /// In hr, this message translates to:
  /// **'Nedostaju podaci autorizacije.'**
  String get ownershipMissingAuthData;

  /// Success message naming the verified channel.
  ///
  /// In hr, this message translates to:
  /// **'Vlasništvo je potvrđeno: {name}'**
  String ownershipOwnershipConfirmedWithName(String name);

  /// Message shown when a claim is received but not yet verified.
  ///
  /// In hr, this message translates to:
  /// **'Zahtjev je zaprimljen (status: {status}).'**
  String ownershipRequestReceivedWithStatus(String status);

  /// App bar title of the OAuth callback screen.
  ///
  /// In hr, this message translates to:
  /// **'Potvrda vlasništva'**
  String get ownershipCallbackTitle;

  /// Title of the dialog confirming ownership revocation.
  ///
  /// In hr, this message translates to:
  /// **'Otpustiti vlasništvo?'**
  String get ownershipRevokeDialogTitle;

  /// Body of the ownership revocation confirmation dialog.
  ///
  /// In hr, this message translates to:
  /// **'Odričeš se vlasništva nad kanalom „{name}”. Verifikacija i status isplate poništavaju se, a kanal postaje dostupan za novo preuzimanje. Možeš ga ponovno preuzeti bilo kada.'**
  String ownershipRevokeDialogBody(String name);

  /// Confirm button to revoke ownership.
  ///
  /// In hr, this message translates to:
  /// **'Otpusti'**
  String get ownershipRevokeAction;

  /// Snackbar confirming ownership was revoked.
  ///
  /// In hr, this message translates to:
  /// **'Vlasništvo je otpušteno.'**
  String get ownershipRevokedSnack;

  /// Section title listing channels the user has claimed.
  ///
  /// In hr, this message translates to:
  /// **'Preuzeti kanali'**
  String get ownershipClaimedChannelsTitle;

  /// Section title for payout wallets.
  ///
  /// In hr, this message translates to:
  /// **'Novčanici za isplatu'**
  String get ownershipPayoutWalletsTitle;

  /// Explanatory text describing what payout wallets are.
  ///
  /// In hr, this message translates to:
  /// **'Odredište na koje vam se isplaćuju prikupljena sredstva — vaš kripto-novčanik (0x, Gnosis). Kad zatražite isplatu, platforma izvrši prijenos na tu adresu.\n\nOvo NIJE adresa na koju stižu donacije: svaka kampanja ima zaseban Safe na koji uplate dolaze (vidljiv svima na Gnosisscanu); isplatu pokrećete iz upravljanja kampanjom.'**
  String get ownershipPayoutWalletsDesc;

  /// Empty-state text when the user has no claimed channels.
  ///
  /// In hr, this message translates to:
  /// **'Još nemaš nijedan preuzet kanal. Otvori kanal i odaberi „Preuzmi vlasništvo” da pokreneš verifikaciju.'**
  String get ownershipNoClaimsBody;

  /// Button to browse channels from the empty claims state.
  ///
  /// In hr, this message translates to:
  /// **'Pregledajte kanale'**
  String get ownershipBrowseChannels;

  /// Suffix tag shown on a claim that requires re-verification.
  ///
  /// In hr, this message translates to:
  /// **'treba ponovnu potvrdu'**
  String get ownershipNeedsReverifyTag;

  /// Tooltip for the per-channel options menu.
  ///
  /// In hr, this message translates to:
  /// **'Opcije'**
  String get ownershipOptionsTooltip;

  /// Menu item opening the channel's Pinka support campaigns.
  ///
  /// In hr, this message translates to:
  /// **'Kampanje (Zid podrške)'**
  String get ownershipCampaignsMenu;

  /// Menu item to revoke ownership of a channel.
  ///
  /// In hr, this message translates to:
  /// **'Otpusti vlasništvo'**
  String get ownershipRevokeMenu;

  /// Subtitle for a verified payout wallet.
  ///
  /// In hr, this message translates to:
  /// **'Odredište isplate · potvrđeno'**
  String get ownershipWalletDestVerified;

  /// Subtitle for a payout wallet.
  ///
  /// In hr, this message translates to:
  /// **'Odredište isplate'**
  String get ownershipWalletDest;

  /// Text field label for entering a payout wallet address.
  ///
  /// In hr, this message translates to:
  /// **'Adresa vašeg novčanika za isplatu (0x…)'**
  String get ownershipWalletAddressLabel;

  /// Helper text for the payout wallet address field.
  ///
  /// In hr, this message translates to:
  /// **'EVM adresa (Gnosis) na koju primate isplate.'**
  String get ownershipWalletAddressHelper;

  /// Button to register a new payout wallet.
  ///
  /// In hr, this message translates to:
  /// **'Dodajte novčanik'**
  String get ownershipAddWallet;

  /// Fallback app bar title while a campaign loads.
  ///
  /// In hr, this message translates to:
  /// **'Kampanja'**
  String get ownershipCampaignFallback;

  /// Campaign management tab: edit campaign details.
  ///
  /// In hr, this message translates to:
  /// **'Uredi'**
  String get ownershipTabEdit;

  /// Campaign management tab: assign episodes.
  ///
  /// In hr, this message translates to:
  /// **'Epizode'**
  String get ownershipTabEpisodes;

  /// Campaign management tab: statistics.
  ///
  /// In hr, this message translates to:
  /// **'Statistika'**
  String get ownershipTabStats;

  /// Campaign management tab: payouts.
  ///
  /// In hr, this message translates to:
  /// **'Isplata'**
  String get ownershipTabPayout;

  /// Shown when a campaign can't be loaded.
  ///
  /// In hr, this message translates to:
  /// **'Kampanja nije pronađena.'**
  String get ownershipCampaignNotFound;

  /// Snackbar confirming changes were saved.
  ///
  /// In hr, this message translates to:
  /// **'Spremljeno'**
  String get ownershipSaved;

  /// Snackbar shown when saving fails.
  ///
  /// In hr, this message translates to:
  /// **'Spremanje nije uspjelo.'**
  String get ownershipSaveFailed;

  /// Form field label: campaign title.
  ///
  /// In hr, this message translates to:
  /// **'Naslov'**
  String get ownershipFieldTitle;

  /// Form field label: campaign description.
  ///
  /// In hr, this message translates to:
  /// **'Opis'**
  String get ownershipFieldDescription;

  /// Form field label: funding goal in euros.
  ///
  /// In hr, this message translates to:
  /// **'Cilj (€)'**
  String get ownershipFieldGoal;

  /// Hint for the funding goal field.
  ///
  /// In hr, this message translates to:
  /// **'prazno = bez cilja'**
  String get ownershipFieldGoalHint;

  /// Form field label: minimum contribution amount in euros.
  ///
  /// In hr, this message translates to:
  /// **'Min. iznos (€)'**
  String get ownershipFieldMinAmount;

  /// Dropdown label: campaign state.
  ///
  /// In hr, this message translates to:
  /// **'Stanje'**
  String get ownershipFieldState;

  /// Dropdown label: campaign visibility.
  ///
  /// In hr, this message translates to:
  /// **'Vidljivost'**
  String get ownershipFieldVisibility;

  /// Note clarifying which fields aren't editable on this screen.
  ///
  /// In hr, this message translates to:
  /// **'Napomena: SEPA i on-chain podaci (IBAN, Safe adresa) te slug ne mijenjaju se ovdje.'**
  String get ownershipEditNote;

  /// Button to save campaign edits.
  ///
  /// In hr, this message translates to:
  /// **'Spremi promjene'**
  String get ownershipSaveChanges;

  /// Campaign state label: draft.
  ///
  /// In hr, this message translates to:
  /// **'Skica'**
  String get ownershipStateDraft;

  /// Campaign state label: active.
  ///
  /// In hr, this message translates to:
  /// **'Aktivna'**
  String get ownershipStateActive;

  /// Campaign state label: closed.
  ///
  /// In hr, this message translates to:
  /// **'Zatvorena'**
  String get ownershipStateClosed;

  /// Campaign state label: cancelled.
  ///
  /// In hr, this message translates to:
  /// **'Otkazana'**
  String get ownershipStateCancelled;

  /// Campaign state label: funded.
  ///
  /// In hr, this message translates to:
  /// **'Financirana'**
  String get ownershipStateFunded;

  /// Campaign visibility label: public.
  ///
  /// In hr, this message translates to:
  /// **'Javna'**
  String get ownershipVisPublic;

  /// Campaign visibility label: unlisted.
  ///
  /// In hr, this message translates to:
  /// **'Neuvrštena'**
  String get ownershipVisUnlisted;

  /// Campaign visibility label: private.
  ///
  /// In hr, this message translates to:
  /// **'Privatna'**
  String get ownershipVisPrivate;

  /// Summary of campaign supporters and contributions counts.
  ///
  /// In hr, this message translates to:
  /// **'{supporters, plural, one{{supporters} podržavatelj} few{{supporters} podržavatelja} other{{supporters} podržavatelja}} · {contributions, plural, one{{contributions} uplata} few{{contributions} uplate} other{{contributions} uplata}}'**
  String ownershipSupportersContributions(int supporters, int contributions);

  /// Section title for the public wall of contributions.
  ///
  /// In hr, this message translates to:
  /// **'Zid podrške'**
  String get ownershipSupportWall;

  /// Empty-state for the support wall.
  ///
  /// In hr, this message translates to:
  /// **'Još nema javnih doprinosa.'**
  String get ownershipNoPublicContributions;

  /// Validation error for an invalid payout amount.
  ///
  /// In hr, this message translates to:
  /// **'Unesi ispravan iznos.'**
  String get ownershipEnterValidAmount;

  /// Validation error when the requested amount is too high.
  ///
  /// In hr, this message translates to:
  /// **'Iznos premašuje raspoloživo.'**
  String get ownershipAmountExceedsAvailable;

  /// Validation error when no payout destination is provided.
  ///
  /// In hr, this message translates to:
  /// **'Unesi odredište (0x adresa ili IBAN).'**
  String get ownershipEnterDestination;

  /// Snackbar confirming a payout request was submitted.
  ///
  /// In hr, this message translates to:
  /// **'Zahtjev za isplatu poslan'**
  String get ownershipPayoutRequestSent;

  /// Generic error after a failed payout request.
  ///
  /// In hr, this message translates to:
  /// **'Zahtjev nije uspio. Pokušaj ponovno.'**
  String get ownershipRequestFailedRetry;

  /// Payout error: KYC verification required.
  ///
  /// In hr, this message translates to:
  /// **'Prije isplate potrebna je verifikacija eOsobnom (KYC).'**
  String get ownershipErrKycRequired;

  /// Payout error: invalid destination.
  ///
  /// In hr, this message translates to:
  /// **'Neispravno odredište (0x adresa ili IBAN).'**
  String get ownershipErrInvalidDestination;

  /// Payout error: invalid amount.
  ///
  /// In hr, this message translates to:
  /// **'Neispravan iznos.'**
  String get ownershipErrInvalidAmount;

  /// Payout error: not authorized.
  ///
  /// In hr, this message translates to:
  /// **'Nemate ovlasti za ovu kampanju.'**
  String get ownershipErrNotAuthorized;

  /// Payout error: generic failure.
  ///
  /// In hr, this message translates to:
  /// **'Zahtjev nije uspio.'**
  String get ownershipErrRequestFailed;

  /// Card explaining KYC is required to request a payout.
  ///
  /// In hr, this message translates to:
  /// **'Za isplatu je potrebna verifikacija eOsobnom (KYC). Dovršite je u odjeljku „Moji kanali”.'**
  String get ownershipPayoutNeedsKyc;

  /// Section title and button to request a payout.
  ///
  /// In hr, this message translates to:
  /// **'Zatražite isplatu'**
  String get ownershipRequestPayout;

  /// Text field label for the payout destination.
  ///
  /// In hr, this message translates to:
  /// **'Odredište (0x adresa ili IBAN)'**
  String get ownershipDestinationLabel;

  /// Text field label for the payout amount.
  ///
  /// In hr, this message translates to:
  /// **'Iznos (€)'**
  String get ownershipAmountLabel;

  /// Helper text showing the available payout balance.
  ///
  /// In hr, this message translates to:
  /// **'Raspoloživo: {amount} €'**
  String ownershipAvailableHelper(String amount);

  /// Section title for the list of past payouts.
  ///
  /// In hr, this message translates to:
  /// **'Povijest isplata'**
  String get ownershipPayoutHistory;

  /// Empty-state for the payout history.
  ///
  /// In hr, this message translates to:
  /// **'Još nema isplata.'**
  String get ownershipNoPayouts;

  /// Snackbar shown when toggling yield fails.
  ///
  /// In hr, this message translates to:
  /// **'Promjena nije uspjela.'**
  String get ownershipChangeFailed;

  /// Switch title to enable yield on idle funds.
  ///
  /// In hr, this message translates to:
  /// **'Oplođujte sredstva (Aave v3 · Gnosis)'**
  String get ownershipYieldTitle;

  /// Subtitle explaining the yield feature and its risks.
  ///
  /// In hr, this message translates to:
  /// **'Dok sredstva čekaju isplatu, nose prinos (~3,5 % APY, promjenjivo). Prinos pripada kampanji. DeFi rizik — glavnica nije zajamčena.'**
  String get ownershipYieldSubtitle;

  /// Key-value label: principal currently deposited in Aave.
  ///
  /// In hr, this message translates to:
  /// **'U oplodnji (Aave)'**
  String get ownershipYieldInPool;

  /// Key-value label: yield accrued so far.
  ///
  /// In hr, this message translates to:
  /// **'Akumulirani prinos'**
  String get ownershipYieldAccrued;

  /// Timestamp of the last yield sync.
  ///
  /// In hr, this message translates to:
  /// **'zadnja sinkronizacija: {time}'**
  String ownershipYieldLastSync(String time);

  /// Link to the yield-bearing token on Gnosisscan.
  ///
  /// In hr, this message translates to:
  /// **'aGnoEURe na Gnosisscanu'**
  String get ownershipYieldTokenLink;

  /// Payout summary row: total raised.
  ///
  /// In hr, this message translates to:
  /// **'Prikupljeno'**
  String get ownershipSummaryRaised;

  /// Payout summary row: accrued yield.
  ///
  /// In hr, this message translates to:
  /// **'Prinos (Aave)'**
  String get ownershipSummaryYield;

  /// Payout summary row / payout state: pending.
  ///
  /// In hr, this message translates to:
  /// **'U obradi'**
  String get ownershipSummaryPending;

  /// Payout summary row / payout state: paid out.
  ///
  /// In hr, this message translates to:
  /// **'Isplaćeno'**
  String get ownershipSummaryPaid;

  /// Payout summary row: available balance.
  ///
  /// In hr, this message translates to:
  /// **'Raspoloživo'**
  String get ownershipSummaryAvailable;

  /// Payout state label: requested.
  ///
  /// In hr, this message translates to:
  /// **'Zatraženo'**
  String get ownershipPayoutStateRequested;

  /// Payout state label: approved.
  ///
  /// In hr, this message translates to:
  /// **'Odobreno'**
  String get ownershipPayoutStateApproved;

  /// Payout state label: failed.
  ///
  /// In hr, this message translates to:
  /// **'Neuspjelo'**
  String get ownershipPayoutStateFailed;

  /// App bar title fallback for the channel campaigns screen.
  ///
  /// In hr, this message translates to:
  /// **'Kampanje'**
  String get ownershipCampaignsTitle;

  /// Prompt shown to signed-out users on the campaigns screen.
  ///
  /// In hr, this message translates to:
  /// **'Za upravljanje kampanjama prvo se prijavite.'**
  String get ownershipSignInToManageCampaigns;

  /// Shown when the user isn't a verified owner of the channel.
  ///
  /// In hr, this message translates to:
  /// **'Niste verificirani vlasnik ovog kanala.'**
  String get ownershipNotVerifiedOwner;

  /// Number of episodes assigned to a campaign.
  ///
  /// In hr, this message translates to:
  /// **'{count, plural, one{{count} epizoda} few{{count} epizode} other{{count} epizoda}}'**
  String ownershipEpisodesCount(int count);

  /// Empty-state title when a channel has no campaigns.
  ///
  /// In hr, this message translates to:
  /// **'Još nema kampanja za ovaj kanal.'**
  String get ownershipNoCampaignsTitle;

  /// Empty-state body explaining how campaigns are created.
  ///
  /// In hr, this message translates to:
  /// **'Kampanje se kreiraju na pinka.io (gdje se generira i Safe za isplatu). Nakon kreiranja povežite kampanju s kanalom kako biste je ovdje administrirali i dodijelili epizodama.'**
  String get ownershipNoCampaignsBody;

  /// Snackbar confirming the episode selection was saved.
  ///
  /// In hr, this message translates to:
  /// **'Epizode spremljene'**
  String get ownershipEpisodesSaved;

  /// Error when an episode is already assigned to a different campaign.
  ///
  /// In hr, this message translates to:
  /// **'Jedna od epizoda već je u drugoj kampanji.'**
  String get ownershipEpisodeTaken;

  /// Error after a failed episode save, prompting retry.
  ///
  /// In hr, this message translates to:
  /// **'Spremanje nije uspjelo. Pokušaj ponovno.'**
  String get ownershipSaveFailedRetry;

  /// Empty-state when a channel has no episodes to pick.
  ///
  /// In hr, this message translates to:
  /// **'Nema dostupnih epizoda za ovaj kanal.'**
  String get ownershipNoEpisodesAvailable;

  /// Count of currently selected episodes in the picker.
  ///
  /// In hr, this message translates to:
  /// **'Odabrano: {count, plural, one{{count} epizoda} few{{count} epizode} other{{count} epizoda}}'**
  String ownershipSelectedCount(int count);

  /// Naslov sekcije/ekrana sa zidom javnih doprinosa (pinka SDK).
  ///
  /// In hr, this message translates to:
  /// **'Zid podrške'**
  String get pinkaWallTitle;

  /// Gumb/naslov za podršku kampanji (pinka SDK).
  ///
  /// In hr, this message translates to:
  /// **'Podrži'**
  String get pinkaSupport;

  /// Prazno stanje kad subjekt (kanal/epizoda) nema aktivnu kampanju.
  ///
  /// In hr, this message translates to:
  /// **'Za ovaj sadržaj još nije pokrenuta kampanja podrške.'**
  String get pinkaNoCampaign;

  /// Prazno stanje zida podrške kad još nema doprinosa.
  ///
  /// In hr, this message translates to:
  /// **'Budi prvi koji podržava — tvoja poruka osvanut će ovdje.'**
  String get pinkaWallEmpty;

  /// Podnaslov ispod ukupnog iznosa kad kampanja nema cilj.
  ///
  /// In hr, this message translates to:
  /// **'prikupljeno'**
  String get pinkaRaisedLabel;

  /// Iznos cilja kampanje ispod prikupljenog (npr. 'od cilja 500 €').
  ///
  /// In hr, this message translates to:
  /// **'od cilja {amount} €'**
  String pinkaOfGoal(String amount);

  /// Prikupljeni iznos kampanje bez cilja (kompaktna kartica).
  ///
  /// In hr, this message translates to:
  /// **'Prikupljeno {amount} €'**
  String pinkaRaised(String amount);

  /// Prikupljeni iznos i cilj kampanje (kompaktna kartica).
  ///
  /// In hr, this message translates to:
  /// **'Prikupljeno {raised} € od {goal} €'**
  String pinkaRaisedOfGoal(String raised, String goal);

  /// Broj jedinstvenih podržavatelja kampanje.
  ///
  /// In hr, this message translates to:
  /// **'{count, plural, one{{count} podržavatelj} few{{count} podržavatelja} other{{count} podržavatelja}}'**
  String pinkaSupportersCount(int count);

  /// Ukupan broj uplata u kampanji.
  ///
  /// In hr, this message translates to:
  /// **'{count, plural, one{{count} uplata} few{{count} uplate} other{{count} uplata}}'**
  String pinkaPaymentsCount(int count);

  /// Naslov kartice za neovisnu provjeru stanja kampanje na blockchainu.
  ///
  /// In hr, this message translates to:
  /// **'Provjeri na lancu'**
  String get pinkaVerifyOnchainTitle;

  /// Objašnjenje transparentnosti uplata na on-chain Safe.
  ///
  /// In hr, this message translates to:
  /// **'Uplate stižu izravno na Safe kampanje (EURe na Gnosisu). Stanje može provjeriti bilo tko — neovisno o nama.'**
  String get pinkaVerifyOnchainBody;

  /// Živi EURe saldo campaign Safea, pročitan izravno s Gnosis lanca (razlikuje se od kumulativnog 'prikupljeno' jer vlasnik slobodno troši iz Safea).
  ///
  /// In hr, this message translates to:
  /// **'Trenutno na Safeu: {amount} €'**
  String pinkaOnchainBalance(String amount);

  /// Link na EURe saldo Safea u Gnosisscan exploreru.
  ///
  /// In hr, this message translates to:
  /// **'EURe saldo na Gnosisscanu'**
  String get pinkaEureBalanceOnGnosisscan;

  /// Link na povijest dolaznih transfera u Gnosisscan exploreru.
  ///
  /// In hr, this message translates to:
  /// **'Povijest priljeva (transferi)'**
  String get pinkaInflowHistory;

  /// Oznaka da su prikupljena sredstva deponirana na Aave radi prinosa.
  ///
  /// In hr, this message translates to:
  /// **'Sredstva trenutno rade na Aave v3 (Gnosis)'**
  String get pinkaFundsWorkingAave;

  /// Iznos sredstava trenutno deponiran na Aave.
  ///
  /// In hr, this message translates to:
  /// **'U Aaveu: {amount} €'**
  String pinkaInAaveLabel(String amount);

  /// Akumulirani prinos na deponirana sredstva (nastavak iza separatora).
  ///
  /// In hr, this message translates to:
  /// **'prinos: {amount} €'**
  String pinkaAaveYieldLabel(String amount);

  /// Objašnjenje zašto je EURe saldo na Safeu nizak dok su sredstva na Aaveu.
  ///
  /// In hr, this message translates to:
  /// **'Zato je EURe saldo na samom Safeu nizak — sredstva su deponirana radi prinosa i povlače se natrag pri isplati.'**
  String get pinkaAaveExplainer;

  /// Link na saldo Aave aGnoEURe tokena u Gnosisscan exploreru.
  ///
  /// In hr, this message translates to:
  /// **'aGnoEURe saldo na Gnosisscanu'**
  String get pinkaAgnoEureBalanceOnGnosisscan;

  /// Poruka kad je odabrani iznos manji od dopuštenog minimuma.
  ///
  /// In hr, this message translates to:
  /// **'Najmanji iznos je {amount} €'**
  String pinkaMinAmount(String amount);

  /// Greška pri kreiranju SEPA uplate.
  ///
  /// In hr, this message translates to:
  /// **'Uplatu nije bilo moguće pripremiti. Pokušaj ponovno.'**
  String get pinkaPaymentCreateFailed;

  /// Obavijest kad je on-chain uplata poslana, ali još nije potvrđena.
  ///
  /// In hr, this message translates to:
  /// **'Uplata je poslana — pojavit će se na zidu čim se potvrdi na lancu.'**
  String get pinkaPaymentSentPending;

  /// Greška pri slanju sredstava iz povezanog novčanika.
  ///
  /// In hr, this message translates to:
  /// **'Slanje iz novčanika nije uspjelo ili je otkazano.'**
  String get pinkaWalletSendFailed;

  /// Opisni tekst za on-chain način doprinosa.
  ///
  /// In hr, this message translates to:
  /// **'Pošalji EURe (Gnosis) izravno na lanac — transparentno i bez posrednika.'**
  String get pinkaOnchainBlurb;

  /// Opisni tekst za SEPA način doprinosa.
  ///
  /// In hr, this message translates to:
  /// **'Doniraj jednim skenom — SEPA, bez naknade. Sredstva idu izravno autoru.'**
  String get pinkaSepaBlurb;

  /// Hint u polju za unos vlastitog iznosa donacije.
  ///
  /// In hr, this message translates to:
  /// **'Ostalo'**
  String get pinkaCustomAmountHint;

  /// Predloženi iznos (placeholder + prefill na fokus) u polju za vlastiti iznos donacije; lokalizirani decimalni separator.
  ///
  /// In hr, this message translates to:
  /// **'19,91'**
  String get pinkaCustomAmountPlaceholder;

  /// Snackbar potvrda nakon kopiranja adrese campaign Safe-a iz verify kartice.
  ///
  /// In hr, this message translates to:
  /// **'Adresa Safe novčanika kopirana u međuspremnik.'**
  String get pinkaSafeAddressCopied;

  /// Tooltip copy gumba uz adresu campaign Safe-a u verify kartici.
  ///
  /// In hr, this message translates to:
  /// **'Kopiraj adresu Safe novčanika'**
  String get pinkaCopySafeAddress;

  /// Zaglavlje progress timelinea SEPA uplate (M od N koraka).
  ///
  /// In hr, this message translates to:
  /// **'Korak {current}/{total}'**
  String pinkaStepOf(int current, int total);

  /// Korak 1 SEPA timelinea — isti copy kao rail checkout (STEP_COPY); mijenjati u paru.
  ///
  /// In hr, this message translates to:
  /// **'Uplata iz tvoje banke'**
  String get pinkaStepPaymentTitle;

  /// No description provided for @pinkaStepPaymentCustodian.
  ///
  /// In hr, this message translates to:
  /// **'Skrbnik: tvoja banka'**
  String get pinkaStepPaymentCustodian;

  /// No description provided for @pinkaStepProcessingTitle.
  ///
  /// In hr, this message translates to:
  /// **'Zaprimljeno — obrada i provjera'**
  String get pinkaStepProcessingTitle;

  /// No description provided for @pinkaStepProcessingCustodian.
  ///
  /// In hr, this message translates to:
  /// **'Skrbnik: Monerium (regulirani izdavatelj e-novca)'**
  String get pinkaStepProcessingCustodian;

  /// No description provided for @pinkaStepMintedTitle.
  ///
  /// In hr, this message translates to:
  /// **'EURe iskovan'**
  String get pinkaStepMintedTitle;

  /// No description provided for @pinkaStepMintedCustodian.
  ///
  /// In hr, this message translates to:
  /// **'Na blockchainu (Gnosis)'**
  String get pinkaStepMintedCustodian;

  /// No description provided for @pinkaStepForwardingTitle.
  ///
  /// In hr, this message translates to:
  /// **'Prosljeđivanje primatelju'**
  String get pinkaStepForwardingTitle;

  /// No description provided for @pinkaStepForwardingCustodian.
  ///
  /// In hr, this message translates to:
  /// **'MPT relay'**
  String get pinkaStepForwardingCustodian;

  /// No description provided for @pinkaStepSettledTitle.
  ///
  /// In hr, this message translates to:
  /// **'Kod primatelja'**
  String get pinkaStepSettledTitle;

  /// No description provided for @pinkaStepSettledCustodian.
  ///
  /// In hr, this message translates to:
  /// **'Skrbnik: primatelj'**
  String get pinkaStepSettledCustodian;

  /// Poruka kad Monerium odbije SEPA uplatu (rail stage=rejected).
  ///
  /// In hr, this message translates to:
  /// **'Uplata je odbijena pri obradi — sredstva se vraćaju pošiljatelju.'**
  String get pinkaIntentRejected;

  /// Poruka kad SEPA intent istekne bez zaprimljene uplate (rail stage=expired).
  ///
  /// In hr, this message translates to:
  /// **'Vrijeme za uplatu je isteklo. Ako si uplatu ipak poslao, pojavit će se na zidu kad stigne.'**
  String get pinkaIntentExpired;

  /// Hint u polju za ime/nadimak donatora.
  ///
  /// In hr, this message translates to:
  /// **'Ime ili nadimak (neobavezno)'**
  String get pinkaNameHint;

  /// Hint u polju za poruku uz donaciju.
  ///
  /// In hr, this message translates to:
  /// **'Poruka uz podršku (neobavezno)'**
  String get pinkaMessageHint;

  /// Oznaka (labelText) polja za ime/nadimak donatora na obrascu podrške.
  ///
  /// In hr, this message translates to:
  /// **'Ime ili nadimak'**
  String get pinkaNameLabel;

  /// Pomoćni tekst ispod polja za ime — objašnjava gdje se ime pojavljuje.
  ///
  /// In hr, this message translates to:
  /// **'Ovako ćeš biti potpisan na zidu'**
  String get pinkaNameHelper;

  /// Oznaka (labelText) polja za poveznicu donatora.
  ///
  /// In hr, this message translates to:
  /// **'Poveznica (neobavezno)'**
  String get pinkaLinkLabel;

  /// Pomoćni tekst ispod polja za poveznicu.
  ///
  /// In hr, this message translates to:
  /// **'Tvoja stranica, projekt ili firma'**
  String get pinkaLinkHelper;

  /// Pogreška kad upisana poveznica nije valjan https URL.
  ///
  /// In hr, this message translates to:
  /// **'Provjeri poveznicu — mora počinjati s https://'**
  String get pinkaLinkInvalid;

  /// Oznaka (labelText) polja za poruku uz donaciju.
  ///
  /// In hr, this message translates to:
  /// **'Poruka (neobavezno)'**
  String get pinkaMessageLabel;

  /// Naslov iznad živog pregleda kartice na obrascu podrške.
  ///
  /// In hr, this message translates to:
  /// **'Ovako će izgledati tvoja kartica'**
  String get pinkaPreviewHeading;

  /// Prigušeni placeholder za ime u živom pregledu kartice dok polje nije ispunjeno.
  ///
  /// In hr, this message translates to:
  /// **'Tvoje ime ili nadimak'**
  String get pinkaPreviewNamePlaceholder;

  /// Prigušeni placeholder za poruku u živom pregledu kartice dok polje nije ispunjeno.
  ///
  /// In hr, this message translates to:
  /// **'Tvoja poruka'**
  String get pinkaPreviewMessagePlaceholder;

  /// Gumb u detaljnom sheetu kartice zida koji otvara poveznicu doprinosa.
  ///
  /// In hr, this message translates to:
  /// **'Otvori poveznicu'**
  String get pinkaWallOpenLink;

  /// Semantics oznaka/tooltip kartice na zidu podrške — tap otvara detaljni sheet.
  ///
  /// In hr, this message translates to:
  /// **'Prikaži cijelu poruku'**
  String get pinkaWallCardDetails;

  /// Oznaka checkboxa za anonimnu donaciju.
  ///
  /// In hr, this message translates to:
  /// **'Doniraj anonimno (ne prikazuj me na zidu podrške)'**
  String get pinkaAnonymousLabel;

  /// Stanje gumba dok se uplata priprema.
  ///
  /// In hr, this message translates to:
  /// **'Pripremam…'**
  String get pinkaPreparing;

  /// Glavni SEPA gumb s odabranim iznosom.
  ///
  /// In hr, this message translates to:
  /// **'Podrži s {amount} €'**
  String pinkaSupportWithAmount(String amount);

  /// Stanje gumba dok se povezuje novčanik.
  ///
  /// In hr, this message translates to:
  /// **'Povezujem novčanik…'**
  String get pinkaWalletConnecting;

  /// Stanje gumba dok se otvara novčanik za potpis transakcije.
  ///
  /// In hr, this message translates to:
  /// **'Otvaram novčanik…'**
  String get pinkaWalletOpening;

  /// Stanje gumba dok se transakcija potvrđuje na lancu.
  ///
  /// In hr, this message translates to:
  /// **'Potvrđujem na lancu…'**
  String get pinkaWalletConfirming;

  /// Gumb za plaćanje iz ugrađenog novčanika; {brand} je wordmark brenda.
  ///
  /// In hr, this message translates to:
  /// **'Plati {amount} € iz {brand} novčanika'**
  String pinkaPayFromDomovinaWallet(String amount, String brand);

  /// Razdjelnik između plaćanja iz ugrađenog novčanika i QR koda.
  ///
  /// In hr, this message translates to:
  /// **'ili skeniraj drugim novčanikom'**
  String get pinkaOrScanOtherWallet;

  /// Uputa ispod QR koda za on-chain doprinos.
  ///
  /// In hr, this message translates to:
  /// **'Skeniraj novčanikom (MetaMask / Monerium) i pošalji {amount} € u EURe.'**
  String pinkaScanWithWallet(String amount);

  /// Oznaka retka s adresom/imenom primatelja uplate.
  ///
  /// In hr, this message translates to:
  /// **'Primatelj'**
  String get pinkaRecipient;

  /// Oznaka retka s tokenom (npr. EURe · Monerium V2 · Gnosis).
  ///
  /// In hr, this message translates to:
  /// **'Token'**
  String get pinkaToken;

  /// Napomena o vremenu pojavljivanja on-chain donacije.
  ///
  /// In hr, this message translates to:
  /// **'Donacija se pojavi na zidu podrške kad stigne na lanac (~1–2 min).'**
  String get pinkaOnchainArrivalNote;

  /// Naslov SEPA QR ekrana.
  ///
  /// In hr, this message translates to:
  /// **'Skeniraj u svojoj bankovnoj aplikaciji'**
  String get pinkaScanInBankApp;

  /// Prikaz iznosa SEPA uplate iznad QR koda.
  ///
  /// In hr, this message translates to:
  /// **'Iznos: {amount} €'**
  String pinkaAmountLabel(String amount);

  /// Oznaka retka s opisom/pozivom na broj SEPA uplate.
  ///
  /// In hr, this message translates to:
  /// **'Opis plaćanja'**
  String get pinkaPaymentReference;

  /// Status dok se čeka potvrda SEPA uplate.
  ///
  /// In hr, this message translates to:
  /// **'Čekam potvrdu plaćanja…'**
  String get pinkaAwaitingPayment;

  /// Poruka zahvale nakon uspješne uplate. Bez emojija — iznad nje stoji Icons.check_circle.
  ///
  /// In hr, this message translates to:
  /// **'Hvala na podršci!'**
  String get pinkaThanksForSupport;

  /// Potvrda da je uplata zabilježena na lancu.
  ///
  /// In hr, this message translates to:
  /// **'Plaćanje je potvrđeno na lancu.'**
  String get pinkaPaymentConfirmedOnchain;

  /// Ispod zahvale kad je Monerium zaprimio SEPA uplatu (rail stage=received_processing), a EURe još nije izdan. Bez obećanja trajanja.
  ///
  /// In hr, this message translates to:
  /// **'Uplata je zaprimljena. Izdavanje EURe-a je u tijeku.'**
  String get pinkaSepaReceivedProcessing;

  /// Smirujuća napomena uz received_processing; nakon ~60 s u toj fazi se ističe. Namjerno „provjera", ne tehnički naziv.
  ///
  /// In hr, this message translates to:
  /// **'Kod prve uplate s novog računa provjera može potrajati. Ne moraš ništa raditi.'**
  String get pinkaSepaFirstPaymentReview;

  /// Ispod zahvale kad je EURe izdan, a prosljeđivanje kampanji traje (rail stage=minted/forwarding).
  ///
  /// In hr, this message translates to:
  /// **'EURe izdan, prosljeđuje se kampanji…'**
  String get pinkaSepaMintedForwarding;

  /// Razlog odbijanja SEPA uplate s raila (status.rejected_reason), ispod pinkaIntentRejected.
  ///
  /// In hr, this message translates to:
  /// **'Razlog: {reason}'**
  String pinkaIntentRejectedReason(String reason);

  /// Gumb na ekranu zahvale koji vraća obrazac za novu donaciju.
  ///
  /// In hr, this message translates to:
  /// **'Doniraj još jednom'**
  String get pinkaDonateAgain;

  /// SnackBar potvrda kopiranja vrijednosti (IBAN/adresa/opis).
  ///
  /// In hr, this message translates to:
  /// **'Kopirano: {label}'**
  String pinkaCopiedLabel(String label);

  /// Zamjenski naziv izvora kad link preview nema ime stranice.
  ///
  /// In hr, this message translates to:
  /// **'poveznica'**
  String get pinkaLink;

  /// Prikazano ime za anonimnog donatora na zidu podrške.
  ///
  /// In hr, this message translates to:
  /// **'Anoniman'**
  String get pinkaAnonymous;

  /// Naslov bloka članka (AI-obrađeni tekst epizode) i naslov lijevog stupca u paralelnom prikazu.
  ///
  /// In hr, this message translates to:
  /// **'Članak'**
  String get sectionArticle;

  /// Tooltip play-gumba uz sekciju članka — reproducira video/audio od navedenog vremena.
  ///
  /// In hr, this message translates to:
  /// **'Pusti od {timestamp}'**
  String sectionPlayFrom(String timestamp);

  /// Crvena oznaka na sekciji članka kad korisnik dođe s profila govornika (/p/…?p=slug), a osoba je među diariziranim govornicima epizode.
  ///
  /// In hr, this message translates to:
  /// **'{name} govori ovdje'**
  String sectionPersonSpeaksHere(String name);

  /// Crvena oznaka na sekciji članka kad korisnik dođe s profila osobe (/p/…?p=slug), a osoba se u epizodi samo spominje (nije diarizirani govornik).
  ///
  /// In hr, this message translates to:
  /// **'Ovdje se spominje: {name}'**
  String sectionPersonMentionedHere(String name);

  /// Tooltip gumba koji kopira dijeljivu poveznicu na sekciju s vremenskom oznakom.
  ///
  /// In hr, this message translates to:
  /// **'Kopiraj poveznicu'**
  String get sectionCopyLink;

  /// SnackBar potvrda nakon kopiranja poveznice na sekciju.
  ///
  /// In hr, this message translates to:
  /// **'Poveznica kopirana: {timestamp}'**
  String sectionLinkCopied(String timestamp);

  /// Naslov inline Magisterium bloka ispod pojedine sekcije članka.
  ///
  /// In hr, this message translates to:
  /// **'Teološka procjena'**
  String get sectionTheologicalAssessment;

  /// Broj citiranih izvora u Magisterium bloku (gumb za otvaranje/zatvaranje citata).
  ///
  /// In hr, this message translates to:
  /// **'{count, plural, one{{count} izvor} few{{count} izvora} other{{count} izvora}}'**
  String sectionSources(int count);

  /// Naslov sekcije sažetka epizode.
  ///
  /// In hr, this message translates to:
  /// **'Sažetak'**
  String get sectionSummary;

  /// Naslov sekcije s ključnim temama epizode.
  ///
  /// In hr, this message translates to:
  /// **'Ključne teme'**
  String get sectionKeyTopics;

  /// Naslov sekcije s popisom govornika epizode.
  ///
  /// In hr, this message translates to:
  /// **'Govornici'**
  String get sectionSpeakers;

  /// Naslov sekcije s ključnim zaključcima epizode.
  ///
  /// In hr, this message translates to:
  /// **'Ključni zaključci'**
  String get sectionKeyTakeaways;

  /// Naslov sekcije s poglavljima (outline) epizode.
  ///
  /// In hr, this message translates to:
  /// **'Poglavlja'**
  String get sectionChapters;

  /// Naslov grupe spomenutih osoba u sekciji entiteta.
  ///
  /// In hr, this message translates to:
  /// **'Osobe'**
  String get sectionPeople;

  /// Naslov grupe spomenutih mjesta u sekciji entiteta.
  ///
  /// In hr, this message translates to:
  /// **'Mjesta'**
  String get sectionPlaces;

  /// Naslov grupe spomenutih organizacija u sekciji entiteta.
  ///
  /// In hr, this message translates to:
  /// **'Organizacije'**
  String get sectionOrganizations;

  /// Naslov bočnog kazala (table of contents) u desktop prikazu članka.
  ///
  /// In hr, this message translates to:
  /// **'Sadržaj'**
  String get sectionContents;

  /// Relativna oznaka starosti epizode objavljene danas (badge svježine).
  ///
  /// In hr, this message translates to:
  /// **'danas'**
  String get sectionAgeToday;

  /// Relativna oznaka starosti epizode objavljene jučer (badge svježine).
  ///
  /// In hr, this message translates to:
  /// **'jučer'**
  String get sectionAgeYesterday;

  /// Relativna starost epizode u danima (badge svježine), za 2–6 dana.
  ///
  /// In hr, this message translates to:
  /// **'{count, plural, one{prije {count} dan} few{prije {count} dana} other{prije {count} dana}}'**
  String sectionAgeDays(int count);

  /// Relativna starost epizode u tjednima (kratki badge svježine).
  ///
  /// In hr, this message translates to:
  /// **'{count, plural, one{prije tjedan} few{prije {count} tj.} other{prije {count} tj.}}'**
  String sectionAgeWeeks(int count);

  /// Relativna starost epizode u mjesecima (kratki badge svježine).
  ///
  /// In hr, this message translates to:
  /// **'{count, plural, one{prije mjesec} few{prije {count} mj.} other{prije {count} mj.}}'**
  String sectionAgeMonths(int count);

  /// Relativna starost epizode u godinama (kratki badge svježine).
  ///
  /// In hr, this message translates to:
  /// **'{count, plural, one{prije godinu} few{prije {count} god.} other{prije {count} god.}}'**
  String sectionAgeYears(int count);

  /// Tooltip badgea svježine — točan datum objave epizode.
  ///
  /// In hr, this message translates to:
  /// **'Objavljeno: {date}'**
  String sectionPublishedOn(String date);

  /// Podnaslov ispod naslova Magisterium stupca u paralelnom desktop prikazu.
  ///
  /// In hr, this message translates to:
  /// **'Teološka analiza, sekciju po sekciju'**
  String get sectionTheologicalAnalysisSubtitle;

  /// Placeholder u Magisterium stupcu kad sekcija nema teološku analizu.
  ///
  /// In hr, this message translates to:
  /// **'Nema teološke analize za ovu sekciju.'**
  String get sectionNoTheologicalAnalysis;

  /// Oznaka na cover-art prikazu za audio-only epizode.
  ///
  /// In hr, this message translates to:
  /// **'Audio'**
  String get sectionAudio;

  /// Generic error when the backend/auth service is not configured or reachable.
  ///
  /// In hr, this message translates to:
  /// **'Usluga trenutno nije dostupna. Pokušaj ponovo malo poslije.'**
  String get serviceUnavailable;

  /// Snackbar confirmation after a successful sign-in.
  ///
  /// In hr, this message translates to:
  /// **'Prijavljen si kao {name}.'**
  String serviceSignedInAs(String name);

  /// Fallback noun used in place of a display name or email when neither is known.
  ///
  /// In hr, this message translates to:
  /// **'korisnik'**
  String get serviceGenericUser;

  /// Snackbar hint shown on native after opening an external OAuth browser.
  ///
  /// In hr, this message translates to:
  /// **'Nastavi prijavu u pregledniku…'**
  String get serviceContinueSignInBrowser;

  /// Generic fallback when sign-in throws an unexpected error.
  ///
  /// In hr, this message translates to:
  /// **'Došlo je do neočekivane pogreške pri prijavi. Pokušaj ponovo.'**
  String get serviceUnexpectedSignInError;

  /// Auth error: rate limit on email/request/SMS sending.
  ///
  /// In hr, this message translates to:
  /// **'Previše pokušaja — pričekaj minutu pa pokušaj ponovo.'**
  String get serviceAuthRateLimited;

  /// Auth error: invalid email address.
  ///
  /// In hr, this message translates to:
  /// **'E-mail adresa ne izgleda ispravno. Provjeri unos.'**
  String get serviceAuthEmailInvalid;

  /// Auth error: one-time code expired.
  ///
  /// In hr, this message translates to:
  /// **'Kod je istekao — zatraži novi.'**
  String get serviceAuthOtpExpired;

  /// Auth error: OTP sign-in disabled.
  ///
  /// In hr, this message translates to:
  /// **'Prijava kodom trenutno nije dostupna.'**
  String get serviceAuthOtpDisabled;

  /// Auth error: user banned.
  ///
  /// In hr, this message translates to:
  /// **'Ovaj je račun privremeno blokiran.'**
  String get serviceAuthUserBanned;

  /// Auth error: signup disabled.
  ///
  /// In hr, this message translates to:
  /// **'Otvaranje novih računa trenutno nije moguće.'**
  String get serviceAuthSignupDisabled;

  /// Auth error: provider disabled.
  ///
  /// In hr, this message translates to:
  /// **'Ova metoda prijave trenutno nije dostupna.'**
  String get serviceAuthProviderDisabled;

  /// Auth error: email not confirmed.
  ///
  /// In hr, this message translates to:
  /// **'E-mail adresa još nije potvrđena.'**
  String get serviceAuthEmailNotConfirmed;

  /// Auth error: retryable network/fetch failure.
  ///
  /// In hr, this message translates to:
  /// **'Nema veze s poslužiteljem. Provjeri internet pa pokušaj ponovo.'**
  String get serviceAuthNoServerConnection;

  /// Auth error: generic sign-in failure fallback.
  ///
  /// In hr, this message translates to:
  /// **'Prijava nije uspjela. Pokušaj ponovo.'**
  String get serviceAuthSignInFailed;

  /// Shown when a permanent account lacks an email required for passkey registration.
  ///
  /// In hr, this message translates to:
  /// **'Tvoj račun nema e-mail adresu pa passkey trenutno nije moguć.'**
  String get serviceAccountNoEmailPasskey;

  /// Success message after adding a passkey to an existing account.
  ///
  /// In hr, this message translates to:
  /// **'Passkey je dodan na tvoj račun.'**
  String get servicePasskeyAddedToAccount;

  /// Success message after creating a new account with a passkey.
  ///
  /// In hr, this message translates to:
  /// **'Passkey je kreiran.'**
  String get servicePasskeyCreated;

  /// Error when sending the magic-link/OTP email fails.
  ///
  /// In hr, this message translates to:
  /// **'Slanje e-maila nije uspjelo. Pokušaj ponovo.'**
  String get serviceEmailSendFailed;

  /// Success message after verifying an email code.
  ///
  /// In hr, this message translates to:
  /// **'Prijava je uspješna.'**
  String get serviceSignInSuccess;

  /// Error when an entered email code is wrong or expired.
  ///
  /// In hr, this message translates to:
  /// **'Kod nije ispravan ili je istekao — provjeri unos ili zatraži novi.'**
  String get serviceOtpInvalidOrExpired;

  /// Error when email and password sign-in is rejected.
  ///
  /// In hr, this message translates to:
  /// **'Pogrešan e-mail ili lozinka.'**
  String get servicePasswordInvalid;

  /// Generic error when code verification fails unexpectedly.
  ///
  /// In hr, this message translates to:
  /// **'Provjera koda nije uspjela.'**
  String get serviceOtpCheckFailed;

  /// Shown when the account-delete backend endpoint isn't deployed (404).
  ///
  /// In hr, this message translates to:
  /// **'Brisanje računa kroz aplikaciju još nije dostupno. Pošalji zahtjev na privacy@italk.hr pa ćemo ga izbrisati ručno.'**
  String get serviceAccountDeleteUnavailable;

  /// Error deleting account with HTTP status code.
  ///
  /// In hr, this message translates to:
  /// **'Brisanje računa nije uspjelo ({status}). Pokušaj ponovo.'**
  String serviceAccountDeleteFailedWithStatus(String status);

  /// Generic error deleting account.
  ///
  /// In hr, this message translates to:
  /// **'Brisanje računa nije uspjelo. Pokušaj ponovo.'**
  String get serviceAccountDeleteFailed;

  /// Confirmation after account deletion.
  ///
  /// In hr, this message translates to:
  /// **'Račun je trajno izbrisan.'**
  String get serviceAccountDeleted;

  /// Snackbar after signing out (anonymous session continues).
  ///
  /// In hr, this message translates to:
  /// **'Odjavljen si — nastavljaš kao gost.'**
  String get serviceSignedOutGuest;

  /// Title of the email-input dialog for sign-in.
  ///
  /// In hr, this message translates to:
  /// **'Tvoj e-mail'**
  String get serviceEmailDialogTitle;

  /// Body text of the email-input dialog for sign-in.
  ///
  /// In hr, this message translates to:
  /// **'Poslat ćemo ti link i šesteroznamenkasti kod za prijavu.'**
  String get serviceEmailDialogMessage;

  /// Placeholder example shown inside the email input field.
  ///
  /// In hr, this message translates to:
  /// **'ime@primjer.com'**
  String get serviceEmailDialogHint;

  /// Confirm button label on the email-input dialog.
  ///
  /// In hr, this message translates to:
  /// **'Pošalji'**
  String get serviceEmailDialogConfirm;

  /// Shown when a second passkey ceremony is started while one is running.
  ///
  /// In hr, this message translates to:
  /// **'Passkey zahtjev je već u tijeku — pričekaj da završi ili osvježi stranicu.'**
  String get servicePasskeyRequestInProgress;

  /// Error when passkey registration is cancelled by the user or times out.
  ///
  /// In hr, this message translates to:
  /// **'Registracija passkeyja je otkazana ili je istekla. Pokušaj ponovo.'**
  String get servicePasskeyRegisterCancelled;

  /// Error when a password manager intercepts the passkey registration ceremony.
  ///
  /// In hr, this message translates to:
  /// **'Upravitelj lozinki (npr. LastPass) blokira passkey. U njegovu prozoru odaberi „Use a different passkey” i izaberi iCloud/Apple Passwords — ili isključi LastPass za ovu stranicu.'**
  String get servicePasskeyPasswordManagerBlockRegister;

  /// Error when a passkey for the account already exists on the device.
  ///
  /// In hr, this message translates to:
  /// **'Na ovom uređaju već postoji passkey za ovaj račun.'**
  String get servicePasskeyAlreadyExists;

  /// Error when the app domain isn't associated for WebAuthn (assetlinks/AASA).
  ///
  /// In hr, this message translates to:
  /// **'Domena nije povezana s passkeyjem. Pokušaj ponovo malo poslije.'**
  String get servicePasskeyDomainNotAssociated;

  /// Error when the device lacks passkey support.
  ///
  /// In hr, this message translates to:
  /// **'Ovaj uređaj ne podržava passkey.'**
  String get servicePasskeyDeviceUnsupported;

  /// Generic fallback error for passkey registration failures.
  ///
  /// In hr, this message translates to:
  /// **'Passkey nije moguće kreirati na ovom uređaju.'**
  String get servicePasskeyCreateFailed;

  /// Error when passkey login finds no credential on the device.
  ///
  /// In hr, this message translates to:
  /// **'Na ovom uređaju nema spremljenog passkeyja.'**
  String get servicePasskeyNoneOnDevice;

  /// Error when passkey login is cancelled by the user or times out.
  ///
  /// In hr, this message translates to:
  /// **'Prijava passkeyjem je otkazana ili je istekla. Pokušaj ponovo.'**
  String get servicePasskeyLoginCancelled;

  /// Error when a password manager intercepts the passkey login ceremony.
  ///
  /// In hr, this message translates to:
  /// **'Upravitelj lozinki (npr. LastPass) blokira passkey. U njegovu prozoru odaberi „Use a different passkey” — ili isključi LastPass za ovu stranicu.'**
  String get servicePasskeyPasswordManagerBlockLogin;

  /// Generic fallback error for passkey login failures.
  ///
  /// In hr, this message translates to:
  /// **'Prijava passkeyjem nije uspjela.'**
  String get servicePasskeyLoginFailed;

  /// Shown when the passkey-list backend endpoint isn't deployed (404).
  ///
  /// In hr, this message translates to:
  /// **'Upravljanje passkeyjima još nije dostupno.'**
  String get servicePasskeyManageUnavailable;

  /// Error fetching the passkey list with HTTP status code.
  ///
  /// In hr, this message translates to:
  /// **'Dohvat passkeyja nije uspio ({status}).'**
  String servicePasskeyFetchFailedWithStatus(String status);

  /// Shown when the passkey-delete backend endpoint isn't deployed (404).
  ///
  /// In hr, this message translates to:
  /// **'Uklanjanje passkeyja još nije dostupno.'**
  String get servicePasskeyRemoveUnavailable;

  /// Error deleting a passkey with HTTP status code.
  ///
  /// In hr, this message translates to:
  /// **'Uklanjanje passkeyja nije uspjelo ({status}).'**
  String servicePasskeyRemoveFailedWithStatus(String status);

  /// Error when finalizing the passkey session bridge fails.
  ///
  /// In hr, this message translates to:
  /// **'Dovršetak prijave passkeyjem nije uspio.'**
  String get servicePasskeyFinishFailed;

  /// Error when the backend response is missing the action link / OTP needed to sign in.
  ///
  /// In hr, this message translates to:
  /// **'Poslužitelj nije vratio podatke za prijavu.'**
  String get serviceBackendNoSignInData;

  /// Error when the backend requires an email to start passkey registration.
  ///
  /// In hr, this message translates to:
  /// **'Unesi e-mail za otvaranje računa s passkeyjem.'**
  String get servicePasskeyEmailRequired;

  /// Error starting the passkey ceremony with HTTP status code.
  ///
  /// In hr, this message translates to:
  /// **'Priprema passkeyja nije uspjela ({status}).'**
  String servicePasskeyPrepareFailedWithStatus(String status);

  /// Error when passkey verification fails on the backend.
  ///
  /// In hr, this message translates to:
  /// **'Passkey nije verificiran. Pokušaj ponovo.'**
  String get servicePasskeyNotVerified;

  /// Error when the presented passkey credential is unknown.
  ///
  /// In hr, this message translates to:
  /// **'Ovaj passkey nije prepoznat — možda je vezan uz drugi račun.'**
  String get servicePasskeyUnknownCredential;

  /// Error when account creation collides with an existing email.
  ///
  /// In hr, this message translates to:
  /// **'Račun s tom e-mail adresom već postoji — prijavi se passkeyjem ili Googleom.'**
  String get servicePasskeyAccountExists;

  /// Error when the passkey challenge is missing or expired.
  ///
  /// In hr, this message translates to:
  /// **'Sesija je istekla. Pokušaj ponovo.'**
  String get serviceSessionExpired;

  /// Generic passkey finish error with HTTP status code.
  ///
  /// In hr, this message translates to:
  /// **'Dovršetak prijave passkeyjem nije uspio ({status}).'**
  String servicePasskeyFinishFailedWithStatus(String status);

  /// Error when the Certilia (e-Osobna) authentication is cancelled.
  ///
  /// In hr, this message translates to:
  /// **'Prijava e-Osobnom je otkazana.'**
  String get serviceCertiliaCancelled;

  /// Error when the Certilia server can't be reached.
  ///
  /// In hr, this message translates to:
  /// **'Certilia trenutno nije dostupna. Pokušaj ponovo malo poslije.'**
  String get serviceCertiliaServerUnavailable;

  /// Generic fallback error for Certilia authentication.
  ///
  /// In hr, this message translates to:
  /// **'Prijava e-Osobnom nije uspjela.'**
  String get serviceCertiliaFailed;

  /// Error when the Certilia id token is missing after authentication.
  ///
  /// In hr, this message translates to:
  /// **'Certilia nije vratila token. Pokušaj ponovo.'**
  String get serviceCertiliaMissingToken;

  /// Error when finalizing the Certilia session bridge fails.
  ///
  /// In hr, this message translates to:
  /// **'Dovršetak prijave e-Osobnom nije uspio.'**
  String get serviceCertiliaFinishFailed;

  /// Backend error: invalid Certilia token.
  ///
  /// In hr, this message translates to:
  /// **'Certilia token nije valjan. Pokušaj ponovo.'**
  String get serviceCertiliaInvalidToken;

  /// Backend error: missing OIB claim from Certilia.
  ///
  /// In hr, this message translates to:
  /// **'Certilia nije vratila OIB pa prijava nije moguća.'**
  String get serviceCertiliaNoOib;

  /// Generic Certilia bridge error with HTTP status code.
  ///
  /// In hr, this message translates to:
  /// **'Povezivanje s računom nije uspjelo ({status}).'**
  String serviceCertiliaLinkFailedWithStatus(String status);

  /// Validation error for the cross-device handoff code.
  ///
  /// In hr, this message translates to:
  /// **'Kod mora imati točno šest znamenki.'**
  String get serviceHandoffCodeSixDigits;

  /// Error when the handoff backend response is missing the action link.
  ///
  /// In hr, this message translates to:
  /// **'Poslužitelj nije vratio link za prijavu.'**
  String get serviceHandoffNoSignInLink;

  /// Error when the receiving device isn't authenticated during handoff.
  ///
  /// In hr, this message translates to:
  /// **'Ovaj uređaj nema aktivnu sesiju — osvježi stranicu pa pokušaj ponovo.'**
  String get serviceHandoffNoActiveSession;

  /// Error when the handoff code is invalid or expired.
  ///
  /// In hr, this message translates to:
  /// **'Kod ne postoji ili je istekao.'**
  String get serviceHandoffInvalidOrExpiredCode;

  /// Handoff error for an unexpected request method (HTTP 405).
  ///
  /// In hr, this message translates to:
  /// **'Pogreška u pozivu poslužitelja. Pokušaj ponovo.'**
  String get serviceHandoffRequestError;

  /// Generic handoff failure with HTTP status code.
  ///
  /// In hr, this message translates to:
  /// **'Prijenos nije uspio ({status}).'**
  String serviceHandoffTransferFailedWithStatus(String status);

  /// Error when the channel-claim backend doesn't return the Google consent URL.
  ///
  /// In hr, this message translates to:
  /// **'Poslužitelj nije vratio adresu za autorizaciju.'**
  String get serviceClaimNoAuthUrl;

  /// Channel-claim mismatch error when the account manages no channels at all.
  ///
  /// In hr, this message translates to:
  /// **'Prijavljeni Google račun nije vlasnik ovog kanala. Ovaj račun ne upravlja nijednim YouTube kanalom. Prijavi se Google računom koji je vlasnik kanala (a ne samo urednik).'**
  String get serviceClaimMismatchNoChannel;

  /// Channel-claim mismatch error naming the channel the account actually manages. The name is rendered in bold.
  ///
  /// In hr, this message translates to:
  /// **'Prijavljeni Google račun nije vlasnik ovog kanala. Ovim računom upravljaš kanalom: {name}. Prijavi se Google računom koji je vlasnik kanala (a ne samo urednik).'**
  String serviceClaimMismatchWithChannel(String name);

  /// Error when revoking a channel ownership claim fails.
  ///
  /// In hr, this message translates to:
  /// **'Odustajanje od vlasništva nije uspjelo.'**
  String get serviceClaimRevokeFailed;

  /// Channel-claim backend reason: channel_mismatch.
  ///
  /// In hr, this message translates to:
  /// **'Prijavljeni YouTube račun nije vlasnik ovog kanala.'**
  String get serviceClaimChannelMismatch;

  /// Channel-claim backend reason: no_channel.
  ///
  /// In hr, this message translates to:
  /// **'Na ovom Google računu nema YouTube kanala.'**
  String get serviceClaimNoChannel;

  /// Channel-claim backend reason: invalid_state.
  ///
  /// In hr, this message translates to:
  /// **'Autorizacija je istekla. Pokušaj ponovo.'**
  String get serviceClaimInvalidState;

  /// Channel-claim backend reason: already_claimed.
  ///
  /// In hr, this message translates to:
  /// **'Ovaj je kanal već preuzeo drugi korisnik.'**
  String get serviceClaimAlreadyClaimed;

  /// Channel-claim backend reason: not_signed_in.
  ///
  /// In hr, this message translates to:
  /// **'Za preuzimanje kanala moraš biti prijavljen.'**
  String get serviceClaimNotSignedIn;

  /// Channel-claim generic fallback error.
  ///
  /// In hr, this message translates to:
  /// **'Provjera vlasništva nije uspjela. Pokušaj ponovo.'**
  String get serviceClaimVerifyFailed;

  /// Safe payout error: not_eligible.
  ///
  /// In hr, this message translates to:
  /// **'Još ne ispunjavaš uvjete za isplatu (vlasništvo, potvrđen identitet i svježina potvrde).'**
  String get serviceSafeNotEligible;

  /// Safe payout error: kyc_required.
  ///
  /// In hr, this message translates to:
  /// **'Za isplatu najprije potvrdi identitet e-Osobnom (Certilia).'**
  String get serviceSafeKycRequired;

  /// Safe payout error: wallet_not_registered.
  ///
  /// In hr, this message translates to:
  /// **'Adresa novčanika nije registrirana na tvom računu.'**
  String get serviceSafeWalletNotRegistered;

  /// Safe payout error: no_safe.
  ///
  /// In hr, this message translates to:
  /// **'Za ovu epizodu još ne postoji novčanik.'**
  String get serviceSafeNoSafe;

  /// Safe payout error: safe_frozen.
  ///
  /// In hr, this message translates to:
  /// **'Novčanik epizode trenutno je zamrznut.'**
  String get serviceSafeFrozen;

  /// Safe payout error: reverify_needed.
  ///
  /// In hr, this message translates to:
  /// **'Vlasništvo treba ponovo potvrditi prije isplate.'**
  String get serviceSafeReverifyNeeded;

  /// Safe payout generic fallback error.
  ///
  /// In hr, this message translates to:
  /// **'Povezivanje s novčanikom nije uspjelo. Pokušaj ponovo.'**
  String get serviceSafeConnectFailed;

  /// Error when a registered wallet address fails format validation.
  ///
  /// In hr, this message translates to:
  /// **'Adresa novčanika nije ispravna (očekuje se 0x i 40 heksadekadskih znamenki).'**
  String get serviceWalletInvalidAddress;

  /// Error when an anonymous user tries to register a wallet.
  ///
  /// In hr, this message translates to:
  /// **'Za registraciju novčanika moraš biti prijavljen.'**
  String get serviceWalletNotSignedIn;

  /// Error when saving a wallet record fails.
  ///
  /// In hr, this message translates to:
  /// **'Spremanje novčanika nije uspjelo.'**
  String get serviceWalletSaveFailed;

  /// Error when deleting a wallet record fails.
  ///
  /// In hr, this message translates to:
  /// **'Brisanje novčanika nije uspjelo.'**
  String get serviceWalletRemoveFailed;

  /// Purchase error when the selected package can't be found in the store.
  ///
  /// In hr, this message translates to:
  /// **'Paket više nije dostupan. Pokušaj ponovo.'**
  String get servicePurchasePackageUnavailable;

  /// Purchase error when the entitlement isn't active after a successful purchase.
  ///
  /// In hr, this message translates to:
  /// **'Kupnja nije aktivirala pretplatu.'**
  String get servicePurchaseNotActivated;

  /// Generic purchase failure fallback.
  ///
  /// In hr, this message translates to:
  /// **'Kupnja nije uspjela. Pokušaj ponovo.'**
  String get servicePurchaseFailed;

  /// Restore error when no active entitlement is found.
  ///
  /// In hr, this message translates to:
  /// **'Nismo pronašli aktivnu pretplatu za vraćanje.'**
  String get serviceRestoreNoSubscription;

  /// Generic restore-purchases failure.
  ///
  /// In hr, this message translates to:
  /// **'Vraćanje kupnji nije uspjelo. Pokušaj ponovo.'**
  String get serviceRestoreFailed;

  /// Purchase error: purchaseNotAllowedError.
  ///
  /// In hr, this message translates to:
  /// **'Kupnja nije dopuštena na ovom uređaju.'**
  String get servicePurchaseNotAllowed;

  /// Purchase error: paymentPendingError.
  ///
  /// In hr, this message translates to:
  /// **'Plaćanje je u obradi — pretplata se aktivira čim bude potvrđeno.'**
  String get servicePurchasePending;

  /// Purchase error: productAlreadyPurchasedError.
  ///
  /// In hr, this message translates to:
  /// **'Već imaš ovu pretplatu. Pokušaj „Vrati kupnje”.'**
  String get servicePurchaseAlreadyOwned;

  /// Purchase error: networkError.
  ///
  /// In hr, this message translates to:
  /// **'Nema veze s trgovinom. Provjeri internet pa pokušaj ponovo.'**
  String get servicePurchaseNetworkError;

  /// Purchase error: storeProblemError.
  ///
  /// In hr, this message translates to:
  /// **'Trgovina trenutno ne odgovara. Pokušaj poslije.'**
  String get servicePurchaseStoreProblem;

  /// TV channel detail/list load error with raw error detail.
  ///
  /// In hr, this message translates to:
  /// **'Učitavanje kanala nije uspjelo:\n{details}'**
  String tvChannelLoadError(String details);

  /// Empty state shown on a TV channel screen with no episodes.
  ///
  /// In hr, this message translates to:
  /// **'U ovom kanalu još nema epizoda.'**
  String get tvChannelNoEpisodes;

  /// Episode count label (channel header and channel card).
  ///
  /// In hr, this message translates to:
  /// **'{count, plural, one{{count} epizoda} few{{count} epizode} other{{count} epizoda}}'**
  String tvEpisodeCountPlural(int count);

  /// Loading message on the TV blog-reader screen.
  ///
  /// In hr, this message translates to:
  /// **'Pripremam čitanje…'**
  String get tvReaderPreparing;

  /// Error state when an episode lacks the AI article required for the reader.
  ///
  /// In hr, this message translates to:
  /// **'Ova epizoda još nije AI-obrađena.\nPrikaz za čitanje zasad nije dostupan.'**
  String get tvReaderNotAiProcessed;

  /// Generic TV episode/reader load error with raw error detail.
  ///
  /// In hr, this message translates to:
  /// **'Greška pri učitavanju:\n{details}'**
  String tvLoadError(String details);

  /// Button that leaves the reader and opens the regular player view.
  ///
  /// In hr, this message translates to:
  /// **'Otvori klasični prikaz'**
  String get tvReaderOpenClassic;

  /// Reader progress indicator: current section of total.
  ///
  /// In hr, this message translates to:
  /// **'Odlomak {current} / {total}'**
  String tvReaderSectionOf(int current, int total);

  /// Reader picture-in-picture tally label when the video is playing.
  ///
  /// In hr, this message translates to:
  /// **'Uživo'**
  String get tvLive;

  /// Reader picture-in-picture tally label when the video is paused.
  ///
  /// In hr, this message translates to:
  /// **'Pauza'**
  String get tvPaused;

  /// Empty state in the reader's Magisterium side card.
  ///
  /// In hr, this message translates to:
  /// **'Za ovaj odlomak nema teološkog osvrta.'**
  String get tvReaderNoCommentary;

  /// Subtitle on the reader's Magisterium side card.
  ///
  /// In hr, this message translates to:
  /// **'Nauk Crkve za ovaj odlomak'**
  String get tvReaderChurchTeaching;

  /// Hint on the Magisterium card to open the full-screen commentary (OK = remote select button).
  ///
  /// In hr, this message translates to:
  /// **'OK — otvori cijeli osvrt'**
  String get tvReaderOpenFullCommentary;

  /// Radnja tipke OK u legendi daljinskog. Bez znaka tipke — tipku crta TvKeyHint.
  ///
  /// In hr, this message translates to:
  /// **'sviraj/pauza'**
  String get tvHintPlayPause;

  /// Radnja lijevo/desno na D-padu u čitaču (prethodni/sljedeći odlomak).
  ///
  /// In hr, this message translates to:
  /// **'odlomci'**
  String get tvHintSections;

  /// Radnja tipke BACK u čitaču — povratak na video.
  ///
  /// In hr, this message translates to:
  /// **'video'**
  String get tvHintVideo;

  /// Magisterium overlay heading for the assessment section.
  ///
  /// In hr, this message translates to:
  /// **'Procjena'**
  String get tvReaderHeadingAssessment;

  /// Magisterium overlay heading for the concerns section.
  ///
  /// In hr, this message translates to:
  /// **'Na što paziti'**
  String get tvReaderHeadingConcerns;

  /// Magisterium overlay heading for the enrichment/clarification section.
  ///
  /// In hr, this message translates to:
  /// **'Pojašnjenje'**
  String get tvReaderHeadingEnrichment;

  /// Magisterium overlay heading for the citations section.
  ///
  /// In hr, this message translates to:
  /// **'Citati iz Magisterija'**
  String get tvReaderHeadingCitations;

  /// Hint in the Magisterium overlay describing how to close it (remote buttons).
  ///
  /// In hr, this message translates to:
  /// **'BACK ili OK = zatvori'**
  String get tvReaderCloseHint;

  /// Toolbar button on the TV episode screen that opens the blog reader.
  ///
  /// In hr, this message translates to:
  /// **'Čitaj'**
  String get tvRead;

  /// Toolbar button label to enter fullscreen on the TV episode screen.
  ///
  /// In hr, this message translates to:
  /// **'Cijeli zaslon'**
  String get tvFullscreen;

  /// Toolbar button label to leave fullscreen on the TV episode screen.
  ///
  /// In hr, this message translates to:
  /// **'Izađi iz cijelog zaslona'**
  String get tvExitFullscreen;

  /// Loading message on the TV episode screen.
  ///
  /// In hr, this message translates to:
  /// **'Učitavam epizodu…'**
  String get tvLoadingEpisode;

  /// Error shown when a TV episode id cannot be found.
  ///
  /// In hr, this message translates to:
  /// **'Epizoda „{id}” nije pronađena.'**
  String tvEpisodeNotFound(String id);

  /// Buffer-ring hint while the player is being instantiated.
  ///
  /// In hr, this message translates to:
  /// **'Pokrećem media engine…'**
  String get tvBufferStartingEngine;

  /// Buffer-ring hint during initial buffering before the first frame.
  ///
  /// In hr, this message translates to:
  /// **'Učitavam video…'**
  String get tvBufferLoadingVideo;

  /// Buffer-ring hint during mid-playback re-buffering.
  ///
  /// In hr, this message translates to:
  /// **'Punjenje međuspremnika…'**
  String get tvBufferFilling;

  /// Radnja gore na D-padu u playeru — otvara čitač ili cijeli zaslon.
  ///
  /// In hr, this message translates to:
  /// **'Čitaj / Cijeli zaslon'**
  String get tvHintRead;

  /// Radnja tipke BACK / F u playeru na cijelom zaslonu.
  ///
  /// In hr, this message translates to:
  /// **'izađi'**
  String get tvHintExit;

  /// Header of the chapter side-rail on the TV episode screen (rendered uppercase).
  ///
  /// In hr, this message translates to:
  /// **'Poglavlja ({count})'**
  String tvChaptersWithCount(int count);

  /// App-bar search button label on the TV home screen.
  ///
  /// In hr, this message translates to:
  /// **'Pretraga'**
  String get tvSearch;

  /// TV home rail title for resume-watching items (rendered uppercase).
  ///
  /// In hr, this message translates to:
  /// **'Nastavi slušati'**
  String get tvRailContinueListening;

  /// TV home rail title for the newest episodes (rendered uppercase).
  ///
  /// In hr, this message translates to:
  /// **'Najnovije epizode'**
  String get tvRailLatestEpisodes;

  /// TV home channels section header with channel count (rendered uppercase).
  ///
  /// In hr, this message translates to:
  /// **'Kanali ({count})'**
  String tvChannelsWithCount(int count);

  /// Sort chip label that orders channels by episode count.
  ///
  /// In hr, this message translates to:
  /// **'Epizode'**
  String get tvSortEpisodes;

  /// Sort chip label that orders channels alphabetically.
  ///
  /// In hr, this message translates to:
  /// **'Abeceda'**
  String get tvSortAlpha;

  /// Sort chip label that shuffles the channel order.
  ///
  /// In hr, this message translates to:
  /// **'Nasumično'**
  String get tvSortShuffle;

  /// Cache-status line on the TV home screen during channel prefetch.
  ///
  /// In hr, this message translates to:
  /// **'Učitavam {loaded}/{total} kanala…'**
  String tvLoadingChannels(int loaded, int total);

  /// Progress label on the TV loading-tips carousel.
  ///
  /// In hr, this message translates to:
  /// **'Pripremam katalog…'**
  String get tvTipsPreparingCatalog;

  /// TV hero PLAY button label (rendered uppercase).
  ///
  /// In hr, this message translates to:
  /// **'Pokreni'**
  String get tvPlay;

  /// Naslov sekcije za odabir UI jezika na /account ekranu.
  ///
  /// In hr, this message translates to:
  /// **'Jezik'**
  String get authSectionLanguage;

  /// Broj epizoda u kojima osoba govori — statistika na profilu govornika (/p/:slug).
  ///
  /// In hr, this message translates to:
  /// **'{count, plural, one{{count} epizoda} few{{count} epizode} other{{count} epizoda}}'**
  String personEpisodesCount(int count);

  /// Naslov sekcije s raspodjelom epizoda po kanalima na profilu govornika.
  ///
  /// In hr, this message translates to:
  /// **'Gostuje na'**
  String get personAppearsOn;

  /// Naslov mjesečnog grafa aktivnosti na profilu govornika.
  ///
  /// In hr, this message translates to:
  /// **'Aktivnost kroz vrijeme'**
  String get personActivityOverTime;

  /// Naslov popisa epizoda na profilu govornika.
  ///
  /// In hr, this message translates to:
  /// **'Epizode'**
  String get personEpisodesHeading;

  /// Prazno stanje kad slug govornika ne postoji (404) ili dohvat ne uspije.
  ///
  /// In hr, this message translates to:
  /// **'Osobu nismo pronašli'**
  String get personNotFoundTitle;

  /// Objašnjenje praznog stanja na profilu osobe (ni govori ni spominje se).
  ///
  /// In hr, this message translates to:
  /// **'Ovu osobu još nemamo u bazi — ni kao govornika ni kao spomen u obrađenim epizodama.'**
  String get personNotFoundBody;

  /// Tooltip gumba za dijeljenje poveznice na profil govornika.
  ///
  /// In hr, this message translates to:
  /// **'Podijeli profil'**
  String get personShareTooltip;

  /// Potvrda nakon kopiranja poveznice na profil govornika u međuspremnik.
  ///
  /// In hr, this message translates to:
  /// **'Poveznica na profil kopirana'**
  String get personLinkCopied;

  /// Naslov sekcije s epizodama u kojima se osoba SPOMINJE (a ne govori).
  ///
  /// In hr, this message translates to:
  /// **'Spominje se u'**
  String get personMentionedIn;

  /// Broj epizoda u kojima se osoba spominje — statistika na profilu osobe (/p/:slug).
  ///
  /// In hr, this message translates to:
  /// **'{count, plural, one{{count} spomen} few{{count} spomena} other{{count} spomena}}'**
  String personMentionsCount(int count);

  /// Oznaka na kartici spomena kad znamo TOČAN trenutak — tap skače na tu sekundu. {time} je mm:ss ili h:mm:ss.
  ///
  /// In hr, this message translates to:
  /// **'spomen u {time}'**
  String personMentionAtTime(String time);

  /// Oznaka na kartici spomena kad trenutak nije razriješen — tap otvara epizodu od početka.
  ///
  /// In hr, this message translates to:
  /// **'spomen negdje u epizodi'**
  String get personMentionWholeEpisode;

  /// Naslov sekcije s raspodjelom SPOMENA po kanalima — za osobu koja nikad ne gostuje.
  ///
  /// In hr, this message translates to:
  /// **'Spominje se na'**
  String get personMentionedOn;

  /// Napomena na profilu osobe koja se samo spominje (nikad nije bila gost).
  ///
  /// In hr, this message translates to:
  /// **'Ova osoba nije gostovala u obrađenim epizodama — profil prati gdje se o njoj govori.'**
  String get personMentionOnlyNote;

  /// Snackbar na mobilnom webu (iOS) koji nudi preuzimanje native aplikacije iz App Storea.
  ///
  /// In hr, this message translates to:
  /// **'{app} ima i aplikaciju za iPhone.'**
  String appInstallBannerIos(String app);

  /// Snackbar na mobilnom webu (Android) koji nudi preuzimanje native aplikacije s Google Playa.
  ///
  /// In hr, this message translates to:
  /// **'{app} ima i aplikaciju za Android.'**
  String appInstallBannerAndroid(String app);

  /// Akcija na app-install snackbaru — otvara App Store / Google Play.
  ///
  /// In hr, this message translates to:
  /// **'Preuzmi'**
  String get appInstallBannerAction;

  /// One-liner iznad 120×120 zida kvadratića na stranici doniranja.
  ///
  /// In hr, this message translates to:
  /// **'Svaki kvadratić je jedna podrška — bliže središtu, veći doprinos.'**
  String get pinkaGridIntro;

  /// Uputa ispod zida kvadratića dok ništa nije pod pokazivačem.
  ///
  /// In hr, this message translates to:
  /// **'Dodirni slobodan kvadratić da odabereš iznos.'**
  String get pinkaGridTapHint;

  /// Naziv 1. (najjeftinijeg, rubnog) prstena zida kvadratića.
  ///
  /// In hr, this message translates to:
  /// **'Vanjski pojas'**
  String get pinkaGridZoneOuterBelt;

  /// Naziv 2. prstena zida kvadratića.
  ///
  /// In hr, this message translates to:
  /// **'Zaštitni prsten'**
  String get pinkaGridZoneDefenseRing;

  /// Naziv 3. prstena zida kvadratića.
  ///
  /// In hr, this message translates to:
  /// **'Središnji pojas'**
  String get pinkaGridZoneMidBelt;

  /// Naziv 4. prstena zida kvadratića.
  ///
  /// In hr, this message translates to:
  /// **'Visoka zona'**
  String get pinkaGridZoneHighZone;

  /// Naziv 5. prstena zida kvadratića.
  ///
  /// In hr, this message translates to:
  /// **'Zlatni krug'**
  String get pinkaGridZoneGoldenCircle;

  /// Naziv 6. prstena zida kvadratića.
  ///
  /// In hr, this message translates to:
  /// **'Poslovna zona'**
  String get pinkaGridZoneBusiness;

  /// Naziv 7. prstena zida kvadratića.
  ///
  /// In hr, this message translates to:
  /// **'Direktorska zona'**
  String get pinkaGridZoneExecutive;

  /// Naziv 8. prstena zida kvadratića.
  ///
  /// In hr, this message translates to:
  /// **'Prestiž'**
  String get pinkaGridZonePrestige;

  /// Naziv 9. prstena zida kvadratića.
  ///
  /// In hr, this message translates to:
  /// **'Elita'**
  String get pinkaGridZoneElite;

  /// Naziv 10. (središnjeg, najskupljeg) prstena zida kvadratića; u prikazu se verzalizira u kodu.
  ///
  /// In hr, this message translates to:
  /// **'Jezgra'**
  String get pinkaGridZoneCore;

  /// Labela zone s cijenom kvadratića (hover na desktopu).
  ///
  /// In hr, this message translates to:
  /// **'{name} · {price} €'**
  String pinkaGridZonePriceLabel(String name, String price);

  /// Potvrda (snackbar) nakon tapa na slobodan kvadratić: iznos u panelu za uplatu preuzet iz zone.
  ///
  /// In hr, this message translates to:
  /// **'{name} — iznos postavljen na {price} €.'**
  String pinkaGridAmountSet(String name, String price);

  /// Naslov bottom sheeta kad korisnik tapne zauzeti kvadratić (prikazuje se donator).
  ///
  /// In hr, this message translates to:
  /// **'Ovaj je kvadratić već zauzet'**
  String get pinkaGridTakenTitle;

  /// Uvodna rečenica iznad zida kad kampanja ima pravu mapu mjesta (server rezervira kvadratić).
  ///
  /// In hr, this message translates to:
  /// **'Odaberi svoj kvadratić — bliže središtu, veći doprinos. Mjesto ti se rezervira dok traje uplata.'**
  String get pinkaSlotIntro;

  /// Rezervni naziv zone kad backend pošalje ključ koji aplikacija još ne poznaje.
  ///
  /// In hr, this message translates to:
  /// **'Zona {index}'**
  String pinkaSlotZoneFallback(int index);

  /// Redak ispod zida kad je pokazivač nad kvadratićem u stanju „held”.
  ///
  /// In hr, this message translates to:
  /// **'Rezervirano — netko upravo plaća'**
  String get pinkaSlotStatusHeld;

  /// Redak ispod zida kad je pokazivač nad kvadratićem koji je organizator izuzeo iz ponude.
  ///
  /// In hr, this message translates to:
  /// **'Ovo mjesto nije u ponudi'**
  String get pinkaSlotStatusBlocked;

  /// Naslov bottom sheeta kad korisnik tapne rezervirani (još neplaćeni) kvadratić.
  ///
  /// In hr, this message translates to:
  /// **'Kvadratić je rezerviran'**
  String get pinkaSlotHeldTitle;

  /// Objašnjenje u bottom sheetu za rezervirani kvadratić.
  ///
  /// In hr, this message translates to:
  /// **'Netko ga upravo plaća. Ako uplata ne sjedne, kvadratić se vraća u ponudu — pokušaj kasnije ili odaberi drugi.'**
  String get pinkaSlotHeldBody;

  /// Zaključan iznos u panelu za uplatu kad je odabran kvadratić.
  ///
  /// In hr, this message translates to:
  /// **'Cijena mjesta: {price} €'**
  String pinkaSlotPriceLocked(String price);

  /// Napomena uz zaključan iznos: nadoplata je dopuštena, manjak nije.
  ///
  /// In hr, this message translates to:
  /// **'Možeš dati i više — manje od cijene mjesta ne.'**
  String get pinkaSlotTopUpHint;

  /// Oznaka polja za iznos kad je odabrano mjesto (umjesto preset čipova).
  ///
  /// In hr, this message translates to:
  /// **'Iznos'**
  String get pinkaSlotTopUpLabel;

  /// Gumb koji poništava odabir kvadratića i vraća obične iznose.
  ///
  /// In hr, this message translates to:
  /// **'Odustani'**
  String get pinkaSlotClear;

  /// Pogreška kad je upisani iznos ispod cijene odabranog kvadratića.
  ///
  /// In hr, this message translates to:
  /// **'Iznos ne smije biti manji od cijene mjesta ({price} €).'**
  String pinkaSlotBelowPrice(String price);

  /// Mjesto na zidu (kvadratić, sjedalo) traži račun; gost dobiva login_required.
  ///
  /// In hr, this message translates to:
  /// **'Za rezervaciju mjesta na zidu prijavi se. Običnu donaciju možeš poslati i bez prijave.'**
  String get pinkaSlotSignInRequired;

  /// Gostujuća donacija: backend vratio rate_limited (30 na sat po IP-u).
  ///
  /// In hr, this message translates to:
  /// **'Previše uplata s ove mreže u zadnjih sat vremena. Pokušaj malo kasnije ili se prijavi.'**
  String get pinkaGuestRateLimited;

  /// Pogreška kad server odbije rezervaciju jer je mjesto u međuvremenu zauzeto (409 slot_taken).
  ///
  /// In hr, this message translates to:
  /// **'Netko je bio brži — taj je kvadratić upravo zauzet. Odaberi drugi.'**
  String get pinkaSlotTakenError;

  /// Odbrojavanje rezervacije ispod SEPA QR-a.
  ///
  /// In hr, this message translates to:
  /// **'Mjesto ti je rezervirano još {time}.'**
  String pinkaSlotHoldCountdown(String time);

  /// Poruka nakon isteka holda: kasna uplata se i dalje kreditira (mark_contribution_paid prihvaća istekli doprinos).
  ///
  /// In hr, this message translates to:
  /// **'Rezervacija je istekla, ali uplata i dalje vrijedi — kad sjedne, dobivaš isti kvadratić ako je slobodan, inače najbliži u istoj ili skupljoj zoni.'**
  String get pinkaSlotHoldExpired;

  /// Mirna potvrda rezervacije mjesta dok je do isteka holda još puno vremena (ne prikazuje se sat).
  ///
  /// In hr, this message translates to:
  /// **'Mjesto ti je rezervirano.'**
  String get pinkaSlotHoldReserved;

  /// Smirujuća poruka ispod SEPA QR-a: SEPA transakcija smije zastati na provjeri kod banaka; backend obradi uplatu ako stigne unutar 24 h.
  ///
  /// In hr, this message translates to:
  /// **'Ako nalog zastane na provjeri kod tvoje ili primateljeve banke, ne brini — dovoljno je da uplata stigne unutar 24 sata i uredno ćemo je obraditi.'**
  String get pinkaSlotHoldReassure;

  /// Gumb na zidu koji otvara fullscreen odabir kvadratića sa zoomom.
  ///
  /// In hr, this message translates to:
  /// **'Povećaj'**
  String get pinkaSlotPickerOpen;

  /// Naslov fullscreen ekrana za odabir kvadratića.
  ///
  /// In hr, this message translates to:
  /// **'Odaberi mjesto'**
  String get pinkaSlotPickerTitle;

  /// Uputa na dnu fullscreen pickera: pan + pinch zoom, nišan u sredini bira ćeliju.
  ///
  /// In hr, this message translates to:
  /// **'Povlači i približi prstima; kvadratić pod nišanom je tvoj odabir.'**
  String get pinkaSlotPickerHint;

  /// Gumb koji potvrđuje odabrani slobodan kvadratić u fullscreen pickeru.
  ///
  /// In hr, this message translates to:
  /// **'Potvrdi mjesto · {price} €'**
  String pinkaSlotPickerConfirm(String price);

  /// Onemogućeni gumb u pickeru kad je kvadratić pod nišanom zauzet/rezerviran/izuzet.
  ///
  /// In hr, this message translates to:
  /// **'Mjesto je zauzeto'**
  String get pinkaSlotPickerTaken;

  /// Poruka/onemogućeni gumb u fullscreen pickeru kad je nišan iznad praznog platna izvan 120×120 mreže.
  ///
  /// In hr, this message translates to:
  /// **'Pomakni nišan na mrežu'**
  String get pinkaSlotPickerOffGrid;

  /// Naslov sekcije s postavkama reprodukcije na /account ekranu.
  ///
  /// In hr, this message translates to:
  /// **'Reprodukcija'**
  String get authSectionPlayback;

  /// Naslov prekidača koji određuje nastavlja li reprodukcija kad app ili tab ode u pozadinu.
  ///
  /// In hr, this message translates to:
  /// **'Reprodukcija u pozadini'**
  String get mediaBackgroundPlaybackTitle;

  /// Objašnjenje ispod prekidača za reprodukciju u pozadini.
  ///
  /// In hr, this message translates to:
  /// **'Nastavi slušati kad zaključaš zaslon ili prijeđeš u drugu aplikaciju.'**
  String get mediaBackgroundPlaybackSubtitle;

  /// Tooltip na kružnom prekidaču brzine reprodukcije u kontrolama playera.
  ///
  /// In hr, this message translates to:
  /// **'Brzina reprodukcije'**
  String get mediaPlaybackSpeed;

  /// Oznaka trenutne brzine reprodukcije (semantika/potvrda). Brzina je već formatirana po jeziku (hrvatski zarez: 1,5).
  ///
  /// In hr, this message translates to:
  /// **'Brzina: {rate}×'**
  String mediaPlaybackSpeedSet(String rate);

  /// Tooltip na gumbu slušalica u kontrolama playera dok je pozadinska reprodukcija uključena.
  ///
  /// In hr, this message translates to:
  /// **'Reprodukcija u pozadini je uključena'**
  String get mediaBackgroundPlaybackTooltipOn;

  /// Tooltip na gumbu slušalica u kontrolama playera dok je pozadinska reprodukcija isključena.
  ///
  /// In hr, this message translates to:
  /// **'Reprodukcija u pozadini je isključena'**
  String get mediaBackgroundPlaybackTooltipOff;

  /// Potvrda (SnackBar) nakon što korisnik uključi pozadinsku reprodukciju iz playera.
  ///
  /// In hr, this message translates to:
  /// **'Nastavit će svirati kad izađeš iz aplikacije'**
  String get mediaBackgroundPlaybackToastOn;

  /// Potvrda (SnackBar) nakon što korisnik isključi pozadinsku reprodukciju iz playera.
  ///
  /// In hr, this message translates to:
  /// **'Reprodukcija će stati kad izađeš iz aplikacije'**
  String get mediaBackgroundPlaybackToastOff;

  /// Tekst pilule koja nudi povratak na poziciju prije ručnog skoka po timelineu; {time} je vrijeme u obliku 1:12:03.
  ///
  /// In hr, this message translates to:
  /// **'Natrag na {time}'**
  String mediaSeekUndo(String time);

  /// Tooltip/semantika na piluli koja poništava ručni skok po timelineu.
  ///
  /// In hr, this message translates to:
  /// **'Poništi skok'**
  String get mediaSeekUndoTooltip;

  /// Eyebrow na kartici osobe kao virtualnog kanala (u UI-ju se prikazuje velikim slovima): oznaka, broj epizoda, ukupno trajanje. Pandan ključu homeChannelCardMeta.
  ///
  /// In hr, this message translates to:
  /// **'Osoba · {count} ep · {duration}'**
  String personCardMeta(int count, String duration);

  /// Deterministički podnaslov virtualnog kanala osobe kad se nastupi protežu kroz više godina. Rod je namjerno neutralan (glagol, ne imenica „gost/gošća“).
  ///
  /// In hr, this message translates to:
  /// **'Gostuje u {episodes, plural, one{{episodes} epizodi} few{{episodes} epizode} other{{episodes} epizoda}} na {channels, plural, one{{channels} kanalu} few{{channels} kanala} other{{channels} kanala}}, {fromYear}.–{toYear}.'**
  String personVirtualChannelSubtitle(
    int episodes,
    int channels,
    String fromYear,
    String toYear,
  );

  /// Varijanta podnaslova virtualnog kanala kad su svi nastupi unutar iste godine.
  ///
  /// In hr, this message translates to:
  /// **'Gostuje u {episodes, plural, one{{episodes} epizodi} few{{episodes} epizode} other{{episodes} epizoda}} na {channels, plural, one{{channels} kanalu} few{{channels} kanala} other{{channels} kanala}}, {year}.'**
  String personVirtualChannelSubtitleOneYear(
    int episodes,
    int channels,
    String year,
  );

  /// Naslov sekcije s glavnim epizodama (tier „primary“) u kanal-formi profila osobe. Ista vrijednost kao personEpisodesHeading, koji ostaje za današnji (ne-kanalski) prikaz profila.
  ///
  /// In hr, this message translates to:
  /// **'Epizode'**
  String get personSectionEpisodes;

  /// Naslov sekcije s epizodama u kojima osoba govori kratko (tier „cameo“) na profilu osobe.
  ///
  /// In hr, this message translates to:
  /// **'Kratki nastupi'**
  String get personSectionCameo;

  /// Jedna rečenica ispod naslova „Kratki nastupi“ koja objašnjava razliku prema glavnim epizodama.
  ///
  /// In hr, this message translates to:
  /// **'Epizode u kojima se javlja nakratko — dio šire rasprave, a ne glavni gost.'**
  String get personSectionCameoHint;

  /// Tooltip na neklikabilnom čipu izvornog kanala epizode kad kanal nije praćen (channelTracked == false).
  ///
  /// In hr, this message translates to:
  /// **'Ovaj kanal još ne pratimo, pa nema svoju stranicu.'**
  String get personSourceChannelUntracked;

  /// Akcija uz epizodu na profilu osobe — dojava da je govornik krivo pripisan.
  ///
  /// In hr, this message translates to:
  /// **'Prijavi grešku'**
  String get personReportError;

  /// Potvrda (SnackBar) nakon što korisnik prijavi krivo pripisanog govornika.
  ///
  /// In hr, this message translates to:
  /// **'Hvala na dojavi — provjerit ćemo ovu epizodu.'**
  String get personReportErrorThanks;

  /// Poruka na minimalnom profilu osobe koja je zatražila uklanjanje (opt-out); prikazuje se uz ime umjesto 404.
  ///
  /// In hr, this message translates to:
  /// **'Na zahtjev ove osobe više ne prikazujemo popis nastupa na ovom profilu. Epizode ostaju dostupne na svojim stranicama.'**
  String get personOptedOut;

  /// Gumb za praćenje osobe na profilu osobe (/p/:slug).
  ///
  /// In hr, this message translates to:
  /// **'Prati'**
  String get personFollow;

  /// Stanje gumba kad korisnik već prati osobu.
  ///
  /// In hr, this message translates to:
  /// **'Pratiš'**
  String get personFollowing;

  /// Gumb za praćenje kanala na stranici kanala (/c/:slug).
  ///
  /// In hr, this message translates to:
  /// **'Prati'**
  String get channelFollow;

  /// Stanje gumba kad korisnik već prati kanal.
  ///
  /// In hr, this message translates to:
  /// **'Pratiš'**
  String get channelFollowing;

  /// Filter čip na /channels: prikazuje i kanale i osobe.
  ///
  /// In hr, this message translates to:
  /// **'Sve'**
  String get channelsFilterAll;

  /// Filter čip na /channels: samo YouTube kanali.
  ///
  /// In hr, this message translates to:
  /// **'Kanali'**
  String get channelsFilterChannels;

  /// Filter čip na /channels: samo osobe (virtualni kanali).
  ///
  /// In hr, this message translates to:
  /// **'Osobe'**
  String get channelsFilterPersons;

  /// Naslov horizontalnog raila s osobama (virtualnim kanalima) na naslovnici.
  ///
  /// In hr, this message translates to:
  /// **'Osobe'**
  String get homePersonsRailTitle;

  /// Naslov horizontalnog raila s novim epizodama kanala i osoba koje korisnik prati.
  ///
  /// In hr, this message translates to:
  /// **'Novo od praćenih'**
  String get homeFollowedRailTitle;

  /// Naslov sekcije s pogođenim osobama iznad rezultata pretrage u command paletti.
  ///
  /// In hr, this message translates to:
  /// **'Osobe'**
  String get searchSectionPeople;

  /// Naslov lanea s osobama (virtualnim kanalima) na Android TV naslovnici.
  ///
  /// In hr, this message translates to:
  /// **'Osobe'**
  String get tvRailPersons;

  /// Oznaka feature-a — home chip, eyebrow raila, sekcija na /account. Namjerno NIJE „Izborni dan": to je ime mehanike (prozor ponoć–ponoć), a kao oznaka ne kaže ni što se bira ni zašto bi korisnika zanimalo.
  ///
  /// In hr, this message translates to:
  /// **'Tko ide sljedeći'**
  String get votingTitle;

  /// Naslov ekrana /glasanje. Upitnik samo ovdje — u zaglavlju je pitanje, na chipu i railu bi bio šum.
  ///
  /// In hr, this message translates to:
  /// **'Tko ide sljedeći?'**
  String get votingScreenTitle;

  /// Zaglavlje glasanja kad server još nije javio datum — jedino mjesto gdje „Izborni dan" stoji sam, u značenju prozora ponoć–ponoć.
  ///
  /// In hr, this message translates to:
  /// **'Izborni dan'**
  String get votingElectionDayPlain;

  /// Zaglavlje glasanja: današnji izborni dan (datum je već formatiran, npr. 8.8.2026.).
  ///
  /// In hr, this message translates to:
  /// **'Izborni dan · {date}'**
  String votingElectionDay(String date);

  /// Redni broj kola glasanja (kolo traje 14 dana).
  ///
  /// In hr, this message translates to:
  /// **'Kolo {number}'**
  String votingRoundLabel(int number);

  /// Koliko izbornih dana kolo još traje.
  ///
  /// In hr, this message translates to:
  /// **'{count, plural, one{još {count} dan} few{još {count} dana} other{još {count} dana}}'**
  String votingRoundDaysLeft(int count);

  /// Kolo završava danas — glas još ulazi u ovo kolo.
  ///
  /// In hr, this message translates to:
  /// **'posljednji dan kola'**
  String get votingRoundLastDay;

  /// Ukupan broj glasova u tekućem kolu (agregat, nikad pojedinačni glasovi).
  ///
  /// In hr, this message translates to:
  /// **'{count, plural, one{{count} glas u kolu} few{{count} glasa u kolu} other{{count} glasova u kolu}}'**
  String votingRoundVotes(int count);

  /// Broj različitih glasača u tekućem kolu.
  ///
  /// In hr, this message translates to:
  /// **'{count, plural, one{{count} glasač} few{{count} glasača} other{{count} glasača}}'**
  String votingRoundVoters(int count);

  /// Duljina niza uzastopnih izbornih dana u kojima je korisnik glasao.
  ///
  /// In hr, this message translates to:
  /// **'{count, plural, one{Niz {count} dan} few{Niz {count} dana} other{Niz {count} dana}}'**
  String votingStreakDays(int count);

  /// Prikaz kad je niz nula — poziv, ne nula.
  ///
  /// In hr, this message translates to:
  /// **'Još nemaš niz'**
  String get votingStreakNone;

  /// Tooltip iznad reda zastavica u zaglavlju glasanja.
  ///
  /// In hr, this message translates to:
  /// **'Zastavica sama spašava propušteni izborni dan. Možeš imati najviše dvije.'**
  String get votingFlagsTooltip;

  /// Koliko zastavica korisnik trenutno ima.
  ///
  /// In hr, this message translates to:
  /// **'{count, plural, one{{count} zastavica} few{{count} zastavice} other{{count} zastavica}}'**
  String votingFlagsLeft(int count);

  /// Zaglavlje za gosta / neverificiranog korisnika na /glasanje.
  ///
  /// In hr, this message translates to:
  /// **'Ljestvica je javna, glas nije.'**
  String get votingGuestTitle;

  /// Objašnjenje granice izbornog dana; ista rečenica vrijedi i za dijasporu.
  ///
  /// In hr, this message translates to:
  /// **'Izborni dan traje od ponoći do ponoći po hrvatskom vremenu.'**
  String get votingGuestBody;

  /// Zaglavlje kad je korisnik verificiran i danas još nije glasao.
  ///
  /// In hr, this message translates to:
  /// **'Imaš 1 glas. Potroši ga do ponoći.'**
  String get votingHaveVote;

  /// Podsjetnik što se gubi ako korisnik danas ne glasa.
  ///
  /// In hr, this message translates to:
  /// **'{count, plural, one{Tvoj niz je {count} dan — glasaj danas da ne pukne.} few{Tvoj niz je {count} dana — glasaj danas da ne pukne.} other{Tvoj niz je {count} dana — glasaj danas da ne pukne.}}'**
  String votingLossAversion(int count);

  /// Zaglavlje nakon što je korisnik potrošio današnji glas.
  ///
  /// In hr, this message translates to:
  /// **'Glas za danas je zabilježen.'**
  String get votingVotedToday;

  /// Kad korisnik ponovno dobiva glas.
  ///
  /// In hr, this message translates to:
  /// **'Vrati se sutra u 00:00 po hrvatskom vremenu.'**
  String get votingComeBackTomorrow;

  /// Oznaka na kartici kandidata za kojeg je današnji glas otišao.
  ///
  /// In hr, this message translates to:
  /// **'Tvoj glas danas'**
  String get votingYourVoteToday;

  /// Zaglavlje stanja „niz visi": zastavice ga danas još mogu obraniti.
  ///
  /// In hr, this message translates to:
  /// **'{count, plural, one{Zastavica brani tvoj niz — {count} dan.} few{Zastavica brani tvoj niz — {count} dana.} other{Zastavica brani tvoj niz — {count} dana.}}'**
  String votingAtRiskTitle(int count);

  /// Uputa uz stanje „niz visi" kad se nijedna zastavica ne troši.
  ///
  /// In hr, this message translates to:
  /// **'Glasaj danas i niz ide dalje.'**
  String get votingAtRiskBody;

  /// Koliko će zastavica izgorjeti ako korisnik danas glasa.
  ///
  /// In hr, this message translates to:
  /// **'{count, plural, one{Glasaš li danas, troši se {count} zastavica i niz ide dalje.} few{Glasaš li danas, troše se {count} zastavice i niz ide dalje.} other{Glasaš li danas, troši se {count} zastavica i niz ide dalje.}}'**
  String votingAtRiskBurn(int count);

  /// Jednokratna poruka kad niz pukne — bez prijekora.
  ///
  /// In hr, this message translates to:
  /// **'{count, plural, one{Niz je stao na {count} dan.} few{Niz je stao na {count} dana.} other{Niz je stao na {count} dana.}}'**
  String votingBrokenTitle(int count);

  /// Niz je pukao, ali broj dana prije pucanja nije poznat (server vraća prikazni niz 0).
  ///
  /// In hr, this message translates to:
  /// **'Niz je stao.'**
  String get votingBrokenTitleUnknown;

  /// Najduži niz ostaje zapisan i nakon pucanja.
  ///
  /// In hr, this message translates to:
  /// **'{count, plural, one{Najduži ostaje {count} dan.} few{Najduži ostaje {count} dana.} other{Najduži ostaje {count} dana.}}'**
  String votingBrokenLongest(int count);

  /// Gumb koji zatvara poruku o puknutom nizu i vraća na glasanje.
  ///
  /// In hr, this message translates to:
  /// **'Kreni ispočetka'**
  String get votingBrokenCta;

  /// Trajna traka na dnu /glasanje za neverificirane korisnike.
  ///
  /// In hr, this message translates to:
  /// **'Potvrdi se e-Osobnom i glasaj'**
  String get votingVerifyBarTitle;

  /// Podnaslov trajne trake za potvrdu identiteta.
  ///
  /// In hr, this message translates to:
  /// **'Jedna osoba, jedan glas svakih 24 sata.'**
  String get votingVerifyBarBody;

  /// Gumb koji pokreće potvrdu identiteta e-Osobnom (Certilia).
  ///
  /// In hr, this message translates to:
  /// **'Potvrdi se'**
  String get votingVerifyCta;

  /// Sort čip: neto rezultat silazno.
  ///
  /// In hr, this message translates to:
  /// **'Ljestvica'**
  String get votingSortLeaderboard;

  /// Sort čip: nasumično promiješani kandidati.
  ///
  /// In hr, this message translates to:
  /// **'Nasumično'**
  String get votingSortRandom;

  /// Sort čip: kandidati s najmanje glasova (rep ljestvice).
  ///
  /// In hr, this message translates to:
  /// **'Najmanje glasova'**
  String get votingSortLeastVotes;

  /// Placeholder u polju za pretragu kandidata.
  ///
  /// In hr, this message translates to:
  /// **'Traži kandidata…'**
  String get votingSearchHint;

  /// Čip koji miče filter po temi.
  ///
  /// In hr, this message translates to:
  /// **'Sve teme'**
  String get votingTagAll;

  /// Prazna ljestvica nakon filtriranja.
  ///
  /// In hr, this message translates to:
  /// **'Nema kandidata za ovaj odabir.'**
  String get votingEmpty;

  /// Akcija koja miče pretragu i filter po temi.
  ///
  /// In hr, this message translates to:
  /// **'Očisti filtre'**
  String get votingEmptyClear;

  /// Greška pri dohvatu ljestvice kola.
  ///
  /// In hr, this message translates to:
  /// **'Ljestvica se nije učitala.'**
  String get votingLoadFailed;

  /// Gumb za glas ZA na kartici kandidata (Icons.thumb_up_outlined).
  ///
  /// In hr, this message translates to:
  /// **'Glasaj za'**
  String get votingVoteUp;

  /// Gumb za glas PROTIV na kartici kandidata (Icons.thumb_down_outlined).
  ///
  /// In hr, this message translates to:
  /// **'Glasaj protiv'**
  String get votingVoteDown;

  /// Semantička oznaka neto rezultata (glasovi za minus glasovi protiv).
  ///
  /// In hr, this message translates to:
  /// **'Neto rezultat {value}'**
  String votingNetLabel(int value);

  /// Ukupan broj glasova na kandidatu u kolu.
  ///
  /// In hr, this message translates to:
  /// **'{count, plural, one{{count} glas} few{{count} glasa} other{{count} glasova}}'**
  String votingVotesCount(int count);

  /// Broj pretplatnika kanala u skraćenom zapisu (npr. 400 tis.).
  ///
  /// In hr, this message translates to:
  /// **'{value} pretplatnika'**
  String votingSubscribers(String value);

  /// Naziv retka u detalju kandidata.
  ///
  /// In hr, this message translates to:
  /// **'Pretplatnici'**
  String get votingSubscribersLabel;

  /// Naziv retka u detalju kandidata: procijenjen broj epizoda.
  ///
  /// In hr, this message translates to:
  /// **'Epizoda (procjena)'**
  String get votingEpisodesLabel;

  /// Naziv retka u detalju kandidata: voditelji podcasta.
  ///
  /// In hr, this message translates to:
  /// **'Voditelji'**
  String get votingHosts;

  /// Skraćeni zapis tisuća (npr. 400 tis.).
  ///
  /// In hr, this message translates to:
  /// **'{value} tis.'**
  String votingCountThousands(String value);

  /// Skraćeni zapis milijuna (npr. 1,2 mil.).
  ///
  /// In hr, this message translates to:
  /// **'{value} mil.'**
  String votingCountMillions(String value);

  /// Oznaka kandidata koji je pobijedio kolo.
  ///
  /// In hr, this message translates to:
  /// **'Pobjednik'**
  String get votingStatusWinner;

  /// Oznaka kandidata kojeg pipeline upravo obrađuje.
  ///
  /// In hr, this message translates to:
  /// **'U obradi'**
  String get votingStatusOnboarding;

  /// Oznaka kandidata koji je gotov i dostupan u aplikaciji.
  ///
  /// In hr, this message translates to:
  /// **'Već u aplikaciji'**
  String get votingStatusOnboarded;

  /// Oznaka kandidata koji je izašao iz igre.
  ///
  /// In hr, this message translates to:
  /// **'Povučen'**
  String get votingStatusWithdrawn;

  /// Naslov jednokratne privole prije prvog glasa.
  ///
  /// In hr, this message translates to:
  /// **'Ovo nije tajno glasovanje'**
  String get votingConsentTitle;

  /// Tekst privole iz plana §4.3 (GDPR čl. 9, posebne kategorije podataka).
  ///
  /// In hr, this message translates to:
  /// **'Tvoj je glas u bazi vezan uz potvrđeni identitet. Pojedinačne glasove nikad ne objavljujemo — javni su samo zbrojevi. Glas za kanal s političkim ili vjerskim predznakom može posredno otkriti tvoje uvjerenje, pa ti to kažemo prije prvog glasa.'**
  String get votingConsentBody;

  /// Gumb koji prihvaća privolu i nastavlja s glasom.
  ///
  /// In hr, this message translates to:
  /// **'Razumijem, glasaj'**
  String get votingConsentAccept;

  /// Tiho poravnanje stanja kad je glas već zabilježen (druga kartica, drugi uređaj).
  ///
  /// In hr, this message translates to:
  /// **'Glas za danas je već potrošen.'**
  String get votingAlreadyVoted;

  /// Potvrda korisnikove radnje nakon uspješnog glasa.
  ///
  /// In hr, this message translates to:
  /// **'Glas je zabilježen.'**
  String get votingVoteRecorded;

  /// Potvrda da su zastavice pokrile propuštene izborne dane.
  ///
  /// In hr, this message translates to:
  /// **'{count, plural, one{{count} zastavica spasila je tvoj niz.} few{{count} zastavice spasile su tvoj niz.} other{{count} zastavica spasilo je tvoj niz.}}'**
  String votingStreakSaved(int count);

  /// Nakon glasa koji je puknuo niz, a pritom pojeo zastavice (praznina veća od broja zastavica). Bez ove poruke zastavice nestanu bez objašnjenja.
  ///
  /// In hr, this message translates to:
  /// **'{count, plural, one{Niz je pukao — potrošena je {count} zastavica.} few{Niz je pukao — potrošene su {count} zastavice.} other{Niz je pukao — potrošeno je {count} zastavica.}}'**
  String votingStreakBrokeBurned(int count);

  /// Greška: korisnik nije verificiran.
  ///
  /// In hr, this message translates to:
  /// **'Za glasanje treba potvrda e-Osobnom.'**
  String get votingErrorNotVerified;

  /// Greška: kandidat je u međuvremenu povučen ili je pobijedio.
  ///
  /// In hr, this message translates to:
  /// **'Ovaj kandidat više nije u igri.'**
  String get votingErrorCandidateGone;

  /// Greška: kolo se zatvorilo dok je ekran bio otvoren.
  ///
  /// In hr, this message translates to:
  /// **'Kolo je u međuvremenu zatvoreno.'**
  String get votingErrorRoundClosed;

  /// Neočekivana greška pri glasanju.
  ///
  /// In hr, this message translates to:
  /// **'Glas nije zabilježen. Pokušaj ponovno.'**
  String get votingErrorGeneric;

  /// Tooltip chipa s nizom u zaglavlju početnog ekrana.
  ///
  /// In hr, this message translates to:
  /// **'Glasaj koji podcast ide sljedeći u obradu'**
  String get votingHomeChipTooltip;

  /// Značenje crvene točke na chipu: današnji glas još nije potrošen.
  ///
  /// In hr, this message translates to:
  /// **'Imaš neiskorišten glas.'**
  String get votingUnusedVote;

  /// Najduži niz uzastopnih izbornih dana na ekranu računa.
  ///
  /// In hr, this message translates to:
  /// **'{count, plural, one{Najduži niz {count} dan} few{Najduži niz {count} dana} other{Najduži niz {count} dana}}'**
  String votingLongestStreak(int count);

  /// Ukupan broj glasova koje je korisnik dosad potrošio.
  ///
  /// In hr, this message translates to:
  /// **'{count, plural, one{{count} glas ukupno} few{{count} glasa ukupno} other{{count} glasova ukupno}}'**
  String votingTotalVotes(int count);

  /// Naslov trajne trake na dnu popisa kanala.
  ///
  /// In hr, this message translates to:
  /// **'Nema tvog podcasta?'**
  String get votingChannelsBarTitle;

  /// Podnaslov trajne trake na dnu popisa kanala.
  ///
  /// In hr, this message translates to:
  /// **'Glasaj koji podcast ide sljedeći u obradu.'**
  String get votingChannelsBarBody;

  /// Gumb trajne trake koji vodi na ekran glasanja.
  ///
  /// In hr, this message translates to:
  /// **'Glasaj'**
  String get votingChannelsBarCta;

  /// Poveznica u zaglavlju home raila na puni popis kandidata.
  ///
  /// In hr, this message translates to:
  /// **'Svi kandidati'**
  String get votingRailSeeAll;

  /// Mjesto kandidata na ljestvici, ispod imena u home railu.
  ///
  /// In hr, this message translates to:
  /// **'{rank}. mjesto'**
  String votingRailRank(int rank);

  /// Naslov zadnje kartice u home railu — vodi na ekran glasanja.
  ///
  /// In hr, this message translates to:
  /// **'Glasaj koji ide sljedeći'**
  String get votingRailCtaTitle;

  /// Podnaslov zadnje kartice u home railu.
  ///
  /// In hr, this message translates to:
  /// **'Ljestvicu odlučuju građani potvrđeni e-Osobnom.'**
  String get votingRailCtaBody;

  /// Naslov kartice na /account za korisnika bez potvrde e-Osobnom.
  ///
  /// In hr, this message translates to:
  /// **'Glasaj koji podcast ide sljedeći'**
  String get votingAccountVerifyTitle;

  /// Tijelo kartice na /account za korisnika bez potvrde e-Osobnom.
  ///
  /// In hr, this message translates to:
  /// **'Potvrdi se e-Osobnom i dobivaš jedan glas svaki dan.'**
  String get votingAccountVerifyBody;

  /// Tooltip ikone u app baru epizode koja otvara sheet s e-knjigom.
  ///
  /// In hr, this message translates to:
  /// **'E-knjiga epizode'**
  String get ebookTooltip;

  /// Oznaka iznad naslova epizode u sheetu e-knjige; caps se radi u kodu (.toUpperCase()).
  ///
  /// In hr, this message translates to:
  /// **'E-knjiga'**
  String get ebookSheetTitle;

  /// Redak u sheetu: hrvatska verzija EPUB knjige.
  ///
  /// In hr, this message translates to:
  /// **'Hrvatsko izdanje'**
  String get ebookEditionHr;

  /// Redak u sheetu: engleska verzija EPUB knjige.
  ///
  /// In hr, this message translates to:
  /// **'Englesko izdanje'**
  String get ebookEditionEn;

  /// Podnaslov retka kad platforma zna podijeliti datoteku (mobitel).
  ///
  /// In hr, this message translates to:
  /// **'Šalje se kao datoteka — WhatsApp, e-pošta, Knjige.'**
  String get ebookShareHint;

  /// Podnaslov retka kad platforma ne zna dijeliti datoteke (desktop browser).
  ///
  /// In hr, this message translates to:
  /// **'Preuzima se na uređaj.'**
  String get ebookDownloadHint;

  /// Stanje retka dok se EPUB preuzima s CDN-a.
  ///
  /// In hr, this message translates to:
  /// **'Pripremam knjigu…'**
  String get ebookPreparing;

  /// Snackbar nakon preuzimanja knjige.
  ///
  /// In hr, this message translates to:
  /// **'Preuzeto: {file}'**
  String ebookDownloaded(String file);

  /// Snackbar kad preuzimanje ili dijeljenje knjige ne uspije.
  ///
  /// In hr, this message translates to:
  /// **'Knjigu nije bilo moguće dohvatiti. Pokušaj ponovno.'**
  String get ebookFailed;

  /// Zadnja stavka u sheetu — kopira izravni CDN URL knjige.
  ///
  /// In hr, this message translates to:
  /// **'Kopiraj poveznicu na knjigu'**
  String get ebookCopyLink;

  /// Snackbar potvrda kopiranja poveznice na knjigu.
  ///
  /// In hr, this message translates to:
  /// **'Poveznica na knjigu je kopirana'**
  String get ebookLinkCopied;

  /// Napomena na dnu sheeta e-knjige, ista tvrdnja kao kolofon u samoj knjizi.
  ///
  /// In hr, this message translates to:
  /// **'Izdanje je izvedeno iz epizode; prava na izgovoreni sadržaj ostaju izvornom kanalu.'**
  String get ebookRights;

  /// Naslov kartice u epizodi koja nudi e-knjigu.
  ///
  /// In hr, this message translates to:
  /// **'Ponesi epizodu sa sobom'**
  String get ebookCardTitle;

  /// Tijelo kartice koja nudi e-knjigu.
  ///
  /// In hr, this message translates to:
  /// **'Cijela epizoda kao e-knjiga: poglavlja, slike i poveznice natrag na snimku. Čita se u Knjigama, Play Books ili Kindleu.'**
  String get ebookCardBody;

  /// Gumb na kartici koji otvara sheet s e-knjigom.
  ///
  /// In hr, this message translates to:
  /// **'E-knjiga (EPUB)'**
  String get ebookCardAction;

  /// Naslov sekcije sa sponzorima ugrađenima u snimku (partneri koje je autor sam doveo). Ton zahvale, ne reklame.
  ///
  /// In hr, this message translates to:
  /// **'Uz podršku'**
  String get sponsorsInVideoTitle;

  /// Podnaslov sekcije sponzora epizode.
  ///
  /// In hr, this message translates to:
  /// **'Partneri koji su omogućili ovu epizodu. Hvala im što podržavaju autore.'**
  String get sponsorsInVideoIntro;

  /// Uloga sponzora (role = sponsor).
  ///
  /// In hr, this message translates to:
  /// **'Sponzor epizode'**
  String get sponsorsInVideoRoleSponsor;

  /// Uloga sponzora (role = partner).
  ///
  /// In hr, this message translates to:
  /// **'Partner podcasta'**
  String get sponsorsInVideoRolePartner;

  /// Kredit za garderobu voditelja (role = wardrobe).
  ///
  /// In hr, this message translates to:
  /// **'Garderoba'**
  String get sponsorsInVideoRoleWardrobe;

  /// Kredit za opremanje studija (role = studio).
  ///
  /// In hr, this message translates to:
  /// **'Opremanje studija'**
  String get sponsorsInVideoRoleStudio;

  /// Uloga sponzora koju aplikacija ne poznaje — generička oznaka.
  ///
  /// In hr, this message translates to:
  /// **'Podrška'**
  String get sponsorsInVideoRoleOther;

  /// Gumb koji skoči na poruku sponzora u snimci i pusti je.
  ///
  /// In hr, this message translates to:
  /// **'Poslušaj poruku sponzora'**
  String get sponsorsInVideoListen;

  /// Gumb koji skoči na sponzoriranu rubriku u snimci i pusti je.
  ///
  /// In hr, this message translates to:
  /// **'Poslušaj sponzoriranu rubriku'**
  String get sponsorsInVideoListenRubric;

  /// Poveznica koja skače na trenutak kad voditelj zahvaljuje sponzoru, bez automatskog zaustavljanja.
  ///
  /// In hr, this message translates to:
  /// **'Zahvala na {time}'**
  String sponsorsInVideoThanksAt(String time);

  /// Poveznica na autorovo poglavlje nazvano po sponzoru.
  ///
  /// In hr, this message translates to:
  /// **'Poglavlje na {time}'**
  String sponsorsInVideoChapterAt(String time);

  /// Generička poveznica na trenutak u snimci.
  ///
  /// In hr, this message translates to:
  /// **'Na {time}'**
  String sponsorsInVideoAt(String time);

  /// Poveznica na web stranicu sponzora (otvara vanjski preglednik).
  ///
  /// In hr, this message translates to:
  /// **'Web'**
  String get sponsorsInVideoWebsite;

  /// Proširi skraćen opis sponzora.
  ///
  /// In hr, this message translates to:
  /// **'više'**
  String get sponsorsInVideoMore;

  /// Skrati proširen opis sponzora.
  ///
  /// In hr, this message translates to:
  /// **'manje'**
  String get sponsorsInVideoLess;

  /// Kratka potvrda kad poruka sponzora pokrenuta gumbom „Poslušaj“ završi; reprodukcija se nastavlja.
  ///
  /// In hr, this message translates to:
  /// **'Poruka sponzora je završila'**
  String get sponsorsInVideoEnded;

  /// Kratka oznaka gumba za poruku sponzora u playeru, uz trajanje („Poslušaj · 0:45“).
  ///
  /// In hr, this message translates to:
  /// **'Poslušaj'**
  String get sponsorsInVideoListenShort;

  /// Kratka oznaka gumba za sponzoriranu rubriku u playeru, uz trajanje („Rubrika · 3:49“).
  ///
  /// In hr, this message translates to:
  /// **'Rubrika'**
  String get sponsorsInVideoRubricShort;

  /// Oznaka u sekciji članka u kojoj je poruka sponzora; ispod su gumbi s imenom sponzora.
  ///
  /// In hr, this message translates to:
  /// **'Poruka sponzora na {time}'**
  String sponsorsInVideoMessageAt(String time);

  /// Oznaka u sekciji članka u kojoj počinje sponzorirana rubrika.
  ///
  /// In hr, this message translates to:
  /// **'Sponzorirana rubrika na {time}'**
  String sponsorsInVideoRubricAt(String time);

  /// App bar title of the standalone YouTube watch screen (/yt/:id).
  ///
  /// In hr, this message translates to:
  /// **'YouTube video'**
  String get ytWatchTitle;

  /// Button on /yt/:id shown when domovina.ai already has an AI-processed episode for this video.
  ///
  /// In hr, this message translates to:
  /// **'Otvori obrađenu epizodu'**
  String get ytWatchOpenEpisode;

  /// Shown on /yt/:id when the id is not a valid 11-character YouTube video id.
  ///
  /// In hr, this message translates to:
  /// **'Neispravna YouTube poveznica.'**
  String get ytWatchInvalidId;

  /// Shown on web browsers (Safari, Firefox) that cannot embed YouTube under our cross-origin isolation.
  ///
  /// In hr, this message translates to:
  /// **'Ovaj preglednik ne može prikazati YouTube player unutar stranice, pa se video otvara na YouTubeu.'**
  String get ytWatchEmbedUnsupported;

  /// Heading of the in-episode transcript search on the episode screen.
  ///
  /// In hr, this message translates to:
  /// **'Pronađi u epizodi'**
  String get findInEpisodeTitle;

  /// Placeholder of the in-episode transcript search field.
  ///
  /// In hr, this message translates to:
  /// **'Riječ, ime ili fraza'**
  String get findInEpisodeHint;

  /// No description provided for @findInEpisodeClear.
  ///
  /// In hr, this message translates to:
  /// **'Obriši'**
  String get findInEpisodeClear;

  /// No description provided for @findInEpisodeNoHits.
  ///
  /// In hr, this message translates to:
  /// **'Nema pogodaka u ovoj epizodi.'**
  String get findInEpisodeNoHits;

  /// No description provided for @findInEpisodeError.
  ///
  /// In hr, this message translates to:
  /// **'Pretraga trenutno ne radi. Pokušaj ponovno malo kasnije.'**
  String get findInEpisodeError;

  /// Number of transcript moments matching the query.
  ///
  /// In hr, this message translates to:
  /// **'{count, plural, one{{count} trenutak} few{{count} trenutka} other{{count} trenutaka}}'**
  String findInEpisodeCount(int count);

  /// No description provided for @findInEpisodeCountPartial.
  ///
  /// In hr, this message translates to:
  /// **'Prikazano {shown} od {total} trenutaka'**
  String findInEpisodeCountPartial(int shown, int total);

  /// Subheading above hits that matched only through typo tolerance.
  ///
  /// In hr, this message translates to:
  /// **'Približni pogoci'**
  String get findInEpisodeApproximate;

  /// Label on a paid sponsored moment (DSA art. 26).
  ///
  /// In hr, this message translates to:
  /// **'Sponzorirano'**
  String get sponsoredLabel;

  /// Paid moment label with the paying brand.
  ///
  /// In hr, this message translates to:
  /// **'Sponzorirano · {brand}'**
  String sponsoredBy(String brand);

  /// Who paid for the sponsored moment.
  ///
  /// In hr, this message translates to:
  /// **'Plaća: {brand}'**
  String sponsoredPaidBy(String brand);

  /// Fallback label for the brand link.
  ///
  /// In hr, this message translates to:
  /// **'Web stranica'**
  String get sponsoredWebsite;

  /// Article mark for a paid moment.
  ///
  /// In hr, this message translates to:
  /// **'Sponzorirani trenutak na {time}'**
  String sponsoredAt(String time);

  /// Seek to the start of a sponsored moment.
  ///
  /// In hr, this message translates to:
  /// **'Poslušaj'**
  String get sponsoredListen;

  /// Strip badge while the paid moment plays.
  ///
  /// In hr, this message translates to:
  /// **'Upravo svira'**
  String get sponsoredNow;

  /// Channel screen button to the sponsor store.
  ///
  /// In hr, this message translates to:
  /// **'Oglašavanje'**
  String get sponsorStoreEntry;

  /// Sponsor store heading.
  ///
  /// In hr, this message translates to:
  /// **'Oglašavanje na kanalu {channel}'**
  String sponsorStoreTitle(String channel);

  /// Sponsor store intro.
  ///
  /// In hr, this message translates to:
  /// **'Izaberi trenutak u epizodi i tvoj brand bit će označen kao sponzor upravo tog dijela. Plaćaš jednom, SEPA uplatom, a oglas ide uživo čim uplata stigne.'**
  String get sponsorStoreIntro;

  /// Store empty state.
  ///
  /// In hr, this message translates to:
  /// **'Ovaj kanal trenutno nema ponudu sponzorskih trenutaka.'**
  String get sponsorStoreEmpty;

  /// Store load error.
  ///
  /// In hr, this message translates to:
  /// **'Ponudu nije moguće učitati.'**
  String get sponsorStoreLoadFailed;

  /// Free moments in an episode.
  ///
  /// In hr, this message translates to:
  /// **'{count, plural, one{{count} slobodan trenutak} few{{count} slobodna trenutka} other{{count} slobodnih trenutaka}}'**
  String sponsorStoreFreeCount(int count);

  /// Lowest gross price in an episode.
  ///
  /// In hr, this message translates to:
  /// **'od {price} €'**
  String sponsorStoreFromPrice(String price);

  /// Brand-safety filter heading.
  ///
  /// In hr, this message translates to:
  /// **'Ne prikazuj me uz…'**
  String get sponsorStoreAvoidTitle;

  /// Brand-safety filter hint.
  ///
  /// In hr, this message translates to:
  /// **'Sigurnost branda biraš ti. Oznake tema su gruba procjena, pa uz svaku epizodu vidiš i njezine stvarne teme.'**
  String get sponsorStoreAvoidHint;

  /// All episodes filtered out.
  ///
  /// In hr, this message translates to:
  /// **'Nijedna epizoda ne odgovara odabranom filtru.'**
  String get sponsorStoreAllFiltered;

  /// Episode topic label.
  ///
  /// In hr, this message translates to:
  /// **'Vjera'**
  String get sponsorTopicFaith;

  /// Episode topic label.
  ///
  /// In hr, this message translates to:
  /// **'Politika'**
  String get sponsorTopicPolitics;

  /// Episode topic label.
  ///
  /// In hr, this message translates to:
  /// **'Posao i tehnologija'**
  String get sponsorTopicBusiness;

  /// Episode map heading.
  ///
  /// In hr, this message translates to:
  /// **'Sponzorski trenuci'**
  String get sponsorMapTitle;

  /// Episode map intro.
  ///
  /// In hr, this message translates to:
  /// **'Svaki trenutak je dio epizode uz naslov sekcije članka koja u njemu počinje. Poslušaj ga prije kupnje.'**
  String get sponsorMapIntro;

  /// Heading above episode topics.
  ///
  /// In hr, this message translates to:
  /// **'Teme epizode'**
  String get sponsorMapTopics;

  /// Moment state.
  ///
  /// In hr, this message translates to:
  /// **'Slobodno'**
  String get sponsorStateFree;

  /// Moment state: held by an unpaid order.
  ///
  /// In hr, this message translates to:
  /// **'Netko upravo plaća'**
  String get sponsorStateHeld;

  /// Moment state.
  ///
  /// In hr, this message translates to:
  /// **'Zauzeto'**
  String get sponsorStateSold;

  /// Moment state with end date.
  ///
  /// In hr, this message translates to:
  /// **'Zauzeto do {date}'**
  String sponsorStateSoldUntil(String date);

  /// Moment state.
  ///
  /// In hr, this message translates to:
  /// **'Nije u ponudi'**
  String get sponsorStateBlocked;

  /// Price zone (contract key).
  ///
  /// In hr, this message translates to:
  /// **'Zatvaranje'**
  String get sponsorZoneZatvaranje;

  /// Price zone (contract key).
  ///
  /// In hr, this message translates to:
  /// **'Središnji dio'**
  String get sponsorZoneTijelo;

  /// Price zone (contract key).
  ///
  /// In hr, this message translates to:
  /// **'Otvaranje'**
  String get sponsorZoneOtvaranje;

  /// Gross price.
  ///
  /// In hr, this message translates to:
  /// **'{price} € s PDV-om'**
  String sponsorPriceGross(String price);

  /// How long a bought moment runs.
  ///
  /// In hr, this message translates to:
  /// **'{count, plural, one{uživo {count} dan nakon uplate} few{uživo {count} dana nakon uplate} other{uživo {count} dana nakon uplate}}'**
  String sponsorRunDays(int count);

  /// Pick a moment on the map.
  ///
  /// In hr, this message translates to:
  /// **'Izaberi'**
  String get sponsorPick;

  /// Timeline legend.
  ///
  /// In hr, this message translates to:
  /// **'Traka prikazuje cijelu epizodu.'**
  String get sponsorLegend;

  /// Checkout heading.
  ///
  /// In hr, this message translates to:
  /// **'Narudžba'**
  String get sponsorCheckoutTitle;

  /// Selected moment summary.
  ///
  /// In hr, this message translates to:
  /// **'Trenutak {range} · {zone}'**
  String sponsorCheckoutMoment(String range, String zone);

  /// Back to the map.
  ///
  /// In hr, this message translates to:
  /// **'Promijeni trenutak'**
  String get sponsorCheckoutChange;

  /// Creative form section.
  ///
  /// In hr, this message translates to:
  /// **'Oglas'**
  String get sponsorCreativeSection;

  /// Form field.
  ///
  /// In hr, this message translates to:
  /// **'Naziv branda'**
  String get sponsorFieldBrand;

  /// Form field help.
  ///
  /// In hr, this message translates to:
  /// **'Prikazuje se uz oznaku „Sponzorirano“ i ne može biti anoniman.'**
  String get sponsorFieldBrandHelp;

  /// Form field.
  ///
  /// In hr, this message translates to:
  /// **'Jedna rečenica (neobavezno)'**
  String get sponsorFieldTagline;

  /// Form field.
  ///
  /// In hr, this message translates to:
  /// **'Poveznica, https:// (neobavezno)'**
  String get sponsorFieldLink;

  /// Logo picker hint.
  ///
  /// In hr, this message translates to:
  /// **'Logo: PNG, JPG ili WebP, najviše 200 kB (neobavezno)'**
  String get sponsorFieldLogo;

  /// Logo picker button.
  ///
  /// In hr, this message translates to:
  /// **'Dodaj logo'**
  String get sponsorLogoPick;

  /// Remove logo button.
  ///
  /// In hr, this message translates to:
  /// **'Ukloni logo'**
  String get sponsorLogoRemove;

  /// Logo validation.
  ///
  /// In hr, this message translates to:
  /// **'Logo je veći od 200 kB.'**
  String get sponsorLogoTooBig;

  /// Logo validation.
  ///
  /// In hr, this message translates to:
  /// **'Logo mora biti PNG, JPG ili WebP.'**
  String get sponsorLogoBadType;

  /// Logo upload error.
  ///
  /// In hr, this message translates to:
  /// **'Logo nije učitan. Pokušaj ponovno ili nastavi bez njega.'**
  String get sponsorLogoUploadFailed;

  /// Company form section.
  ///
  /// In hr, this message translates to:
  /// **'Podaci za račun'**
  String get sponsorCompanySection;

  /// Form field.
  ///
  /// In hr, this message translates to:
  /// **'Naziv tvrtke'**
  String get sponsorFieldCompany;

  /// Form field.
  ///
  /// In hr, this message translates to:
  /// **'OIB (neobavezno)'**
  String get sponsorFieldOib;

  /// Form field.
  ///
  /// In hr, this message translates to:
  /// **'PDV ID (neobavezno)'**
  String get sponsorFieldVat;

  /// Form field.
  ///
  /// In hr, this message translates to:
  /// **'Ulica i kućni broj'**
  String get sponsorFieldStreet;

  /// Form field.
  ///
  /// In hr, this message translates to:
  /// **'Grad'**
  String get sponsorFieldCity;

  /// Form field.
  ///
  /// In hr, this message translates to:
  /// **'Poštanski broj'**
  String get sponsorFieldPostal;

  /// Form field.
  ///
  /// In hr, this message translates to:
  /// **'Država (HR, SI, DE…)'**
  String get sponsorFieldCountry;

  /// Form field.
  ///
  /// In hr, this message translates to:
  /// **'Adresa e-pošte za račun'**
  String get sponsorFieldEmail;

  /// Form field.
  ///
  /// In hr, this message translates to:
  /// **'Broj narudžbenice (neobavezno)'**
  String get sponsorFieldReference;

  /// Preview heading.
  ///
  /// In hr, this message translates to:
  /// **'Ovako će oglas izgledati'**
  String get sponsorPreviewTitle;

  /// Terms checkbox.
  ///
  /// In hr, this message translates to:
  /// **'Prihvaćam uvjete oglašavanja'**
  String get sponsorTermsAccept;

  /// Open terms dialog.
  ///
  /// In hr, this message translates to:
  /// **'Pročitaj uvjete'**
  String get sponsorTermsRead;

  /// Terms dialog title.
  ///
  /// In hr, this message translates to:
  /// **'Uvjeti oglašavanja'**
  String get sponsorTermsTitle;

  /// Advertising terms (formal register).
  ///
  /// In hr, this message translates to:
  /// **'Oglas se objavljuje automatski čim uplata stigne, bez prethodnog odobrenja, i traje onoliko dana koliko je navedeno uz trenutak.\n\nOglas je označen kao „Sponzorirano“ uz naziv Vašeg branda, sukladno članku 26. Uredbe (EU) 2022/2065.\n\nNije dopušten sadržaj koji je nezakonit, obmanjujući, uvredljiv ili diskriminirajući, kao ni oglašavanje duhanskih proizvoda, oružja, igara na sreću te lijekova na recept.\n\nVlasnik kanala može povući oglas koji krši ove uvjete. U tom slučaju, kao i kad uplata stigne nakon što je trenutak prodan drugome, iznos Vam vraćamo ručno.\n\nCijena uključuje PDV. Račun se izdaje automatski i šalje na adresu e-pošte navedenu u narudžbi.'**
  String get sponsorTermsBody;

  /// Validation.
  ///
  /// In hr, this message translates to:
  /// **'Obavezno polje'**
  String get sponsorErrorRequired;

  /// Validation.
  ///
  /// In hr, this message translates to:
  /// **'OIB nije ispravan'**
  String get sponsorErrorOib;

  /// Validation.
  ///
  /// In hr, this message translates to:
  /// **'PDV ID nije ispravan (npr. HR12345678903)'**
  String get sponsorErrorVat;

  /// Validation.
  ///
  /// In hr, this message translates to:
  /// **'Adresa e-pošte nije ispravna'**
  String get sponsorErrorEmail;

  /// Validation.
  ///
  /// In hr, this message translates to:
  /// **'Poveznica mora počinjati s https://'**
  String get sponsorErrorLink;

  /// Validation.
  ///
  /// In hr, this message translates to:
  /// **'Najviše {max} znakova'**
  String sponsorErrorTooLong(int max);

  /// Validation.
  ///
  /// In hr, this message translates to:
  /// **'Dvoslovna oznaka države, npr. HR'**
  String get sponsorErrorCountry;

  /// Validation.
  ///
  /// In hr, this message translates to:
  /// **'Za narudžbu je potrebno prihvatiti uvjete.'**
  String get sponsorErrorTerms;

  /// Checkout submit.
  ///
  /// In hr, this message translates to:
  /// **'Nastavi na plaćanje'**
  String get sponsorSubmit;

  /// 409 slot_taken.
  ///
  /// In hr, this message translates to:
  /// **'Netko je upravo uzeo taj trenutak. Karta je osvježena, izaberi drugi.'**
  String get sponsorSlotTaken;

  /// 409 too_many_holds.
  ///
  /// In hr, this message translates to:
  /// **'Već imaš tri neplaćene narudžbe. Plati jednu ili pričekaj da istekne.'**
  String get sponsorTooManyHolds;

  /// Sponzorski checkout traži račun; poruka kad prijava nije dovršena.
  ///
  /// In hr, this message translates to:
  /// **'Za narudžbu sponzorskog trenutka prijavi se. Upisani podaci ostaju u obrascu.'**
  String get sponsorSignInRequired;

  /// Naslov auth sheeta otvorenog iz sponzorskog checkouta.
  ///
  /// In hr, this message translates to:
  /// **'Prijavi se za narudžbu'**
  String get sponsorSignInHeadline;

  /// Podnaslov auth sheeta iz sponzorskog checkouta.
  ///
  /// In hr, this message translates to:
  /// **'Narudžba, račun i stanje plaćanja vezani su uz tvoj račun.'**
  String get sponsorSignInSubtitle;

  /// Checkout error.
  ///
  /// In hr, this message translates to:
  /// **'Narudžbu nije moguće kreirati. Pokušaj ponovno.'**
  String get sponsorCheckoutFailed;

  /// Server rejected a field.
  ///
  /// In hr, this message translates to:
  /// **'Provjeri polje „{field}“.'**
  String sponsorCheckoutFieldRejected(String field);

  /// Payment step heading.
  ///
  /// In hr, this message translates to:
  /// **'Plaćanje'**
  String get sponsorPayTitle;

  /// Memo must be copied verbatim.
  ///
  /// In hr, this message translates to:
  /// **'Opis plaćanja kopiraj doslovno, bez ijedne izmjene. Po njemu sparujemo uplatu s narudžbom. Ako ga knjigovodstvo skrati ili prepiše, uplata se neće spariti automatski.'**
  String get sponsorMemoVerbatim;

  /// Hold expiry.
  ///
  /// In hr, this message translates to:
  /// **'Trenutak je rezerviran za tebe do {time}.'**
  String sponsorHoldUntil(String time);

  /// Hold expired.
  ///
  /// In hr, this message translates to:
  /// **'Rezervacija je istekla. Ako uplata ipak stigne, a trenutak je još slobodan, dodjeljujemo ga automatski.'**
  String get sponsorHoldExpired;

  /// Waiting for payment.
  ///
  /// In hr, this message translates to:
  /// **'Čekamo uplatu. Stranica se sama osvježi kad stigne.'**
  String get sponsorWaitingPayment;

  /// Order status link hint.
  ///
  /// In hr, this message translates to:
  /// **'Spremi ovu poveznicu. Preko nje uvijek vidiš stanje narudžbe.'**
  String get sponsorOrderLinkHint;

  /// Confirmation heading.
  ///
  /// In hr, this message translates to:
  /// **'Uplata je stigla, oglas je uživo'**
  String get sponsorPaidTitle;

  /// Confirmation body. No final full stop: {date} already ends with one (6. 11. 2026.).
  ///
  /// In hr, this message translates to:
  /// **'Trenutak je tvoj do {date}'**
  String sponsorPaidUntil(String date);

  /// Underpaid order.
  ///
  /// In hr, this message translates to:
  /// **'Uplata je manja od cijene trenutka, pa trenutak nije dodijeljen. Javit ćemo ti se radi povrata ili doplate.'**
  String get sponsorUnderpaid;

  /// Paid but slot sold to someone else.
  ///
  /// In hr, this message translates to:
  /// **'Uplata je stigla nakon isteka rezervacije, a trenutak je u međuvremenu prodan. Iznos vraćamo ručno.'**
  String get sponsorSlotUnassigned;

  /// Creative withdrawn.
  ///
  /// In hr, this message translates to:
  /// **'Vlasnik kanala povukao je oglas. Iznos vraćamo ručno.'**
  String get sponsorHidden;

  /// Expired order.
  ///
  /// In hr, this message translates to:
  /// **'Narudžba je istekla bez uplate.'**
  String get sponsorOrderExpired;

  /// Failed order.
  ///
  /// In hr, this message translates to:
  /// **'Plaćanje nije uspjelo.'**
  String get sponsorOrderFailed;

  /// Invoice issued.
  ///
  /// In hr, this message translates to:
  /// **'Račun {number} poslan je na adresu e-pošte iz narudžbe.'**
  String sponsorInvoiceSent(String number);

  /// Invoice pending.
  ///
  /// In hr, this message translates to:
  /// **'Račun stiže e-poštom nakon obrade.'**
  String get sponsorInvoicePending;

  /// Stats placeholder until backend.
  ///
  /// In hr, this message translates to:
  /// **'Broj prikaza i klikova prikazat ćemo ovdje čim mjerenje bude uključeno.'**
  String get sponsorStatsPending;

  /// Open the episode at the moment.
  ///
  /// In hr, this message translates to:
  /// **'Pogledaj na epizodi'**
  String get sponsorViewOnEpisode;

  /// Unknown order id.
  ///
  /// In hr, this message translates to:
  /// **'Narudžba nije pronađena.'**
  String get sponsorOrderNotFound;

  /// Order status after the lease ended. No final full stop: {date} ends with one.
  ///
  /// In hr, this message translates to:
  /// **'Trenutak je bio uživo do {date}'**
  String sponsorLeaseEnded(String date);

  /// Leave-payment confirmation title.
  ///
  /// In hr, this message translates to:
  /// **'Napustiti plaćanje?'**
  String get sponsorLeavePayTitle;

  /// Leave-payment confirmation body.
  ///
  /// In hr, this message translates to:
  /// **'Trenutak ostaje rezerviran do isteka, ali QR kod i opis plaćanja više nećeš vidjeti. Stanje narudžbe ostaje na poveznici iz adresne trake.'**
  String get sponsorLeavePayBody;

  /// Confirm leaving the payment step.
  ///
  /// In hr, this message translates to:
  /// **'Napusti'**
  String get sponsorLeavePayConfirm;

  /// Naslov ekrana s postavkama push obavijesti.
  ///
  /// In hr, this message translates to:
  /// **'Obavijesti'**
  String get notificationsTitle;

  /// Uvod na ekranu Obavijesti.
  ///
  /// In hr, this message translates to:
  /// **'Javit ćemo ti kad stigne nova epizoda. Ti biraš o čemu.'**
  String get notificationsIntro;

  /// Gumb koji otvara sistemski dijalog za dozvolu.
  ///
  /// In hr, this message translates to:
  /// **'Uključi obavijesti'**
  String get notificationsEnable;

  /// Stanje kad je dozvola dana.
  ///
  /// In hr, this message translates to:
  /// **'Obavijesti su uključene'**
  String get notificationsEnabledStatus;

  /// Naslov kad je sistemska dozvola odbijena.
  ///
  /// In hr, this message translates to:
  /// **'Obavijesti su isključene u postavkama uređaja'**
  String get notificationsDeniedTitle;

  /// Objašnjenje uz odbijenu dozvolu.
  ///
  /// In hr, this message translates to:
  /// **'Uključi ih u postavkama, pa ćemo ti javljati nove epizode.'**
  String get notificationsDeniedBody;

  /// Gumb koji otvara sistemske postavke aplikacije.
  ///
  /// In hr, this message translates to:
  /// **'Otvori postavke'**
  String get notificationsOpenSettings;

  /// Prekidač za temu svih novih epizoda.
  ///
  /// In hr, this message translates to:
  /// **'Sve nove epizode'**
  String get notificationsAllTitle;

  /// Koliko obavijesti donosi „Sve nove epizode” (izmjereno 15. 10. 2026.).
  ///
  /// In hr, this message translates to:
  /// **'Otprilike jedna do četiri dnevno'**
  String get notificationsAllSubtitle;

  /// Naslov popisa kanala.
  ///
  /// In hr, this message translates to:
  /// **'Kanali'**
  String get notificationsChannelsSection;

  /// Podnaslov kanala dok je uključeno „Sve nove epizode”.
  ///
  /// In hr, this message translates to:
  /// **'Uključeno kroz Sve nove epizode'**
  String get notificationsCoveredByAll;

  /// Hint u polju za pretragu kanala.
  ///
  /// In hr, this message translates to:
  /// **'Traži kanal'**
  String get notificationsSearchHint;

  /// Informacija o tihim satima.
  ///
  /// In hr, this message translates to:
  /// **'Ne šaljemo obavijesti između 22 i 7 sati.'**
  String get notificationsQuietHours;

  /// Greška pri učitavanju popisa kanala.
  ///
  /// In hr, this message translates to:
  /// **'Popis kanala trenutno nije dostupan.'**
  String get notificationsChannelsError;

  /// Poruka kad ekran nije dostupan (web, TV).
  ///
  /// In hr, this message translates to:
  /// **'Obavijesti su dostupne u aplikaciji za iOS i Android.'**
  String get notificationsAppOnly;

  /// Podnaslov retka na računu kad su obavijesti uključene.
  ///
  /// In hr, this message translates to:
  /// **'Uključene'**
  String get notificationsAccountOn;

  /// Podnaslov retka na računu kad su obavijesti isključene.
  ///
  /// In hr, this message translates to:
  /// **'Isključene'**
  String get notificationsAccountOff;

  /// Tooltip zvonca kad je obavijest kanala uključena.
  ///
  /// In hr, this message translates to:
  /// **'Isključi obavijesti za ovaj kanal'**
  String get notificationsBellOn;

  /// Tooltip zvonca kad je obavijest kanala isključena.
  ///
  /// In hr, this message translates to:
  /// **'Javi mi za nove epizode ovog kanala'**
  String get notificationsBellOff;

  /// Oznaka uz praćeni kanal u popisu.
  ///
  /// In hr, this message translates to:
  /// **'Pratiš'**
  String get notificationsFollowingLabel;

  /// Oznaka na ekranu epizode kad je epizoda varijanta druge (isti izvorni video, drugi prolaz obrade), a pipeline nije dao redni broj.
  ///
  /// In hr, this message translates to:
  /// **'Varijanta'**
  String get episodeVariant;

  /// Oznaka na ekranu epizode kad je epizoda varijanta druge (isti izvorni video, drugi prolaz obrade); n je redni broj varijante iz info.json `_variant.n`. Iza nje može slijediti opis varijante s CDN-a.
  ///
  /// In hr, this message translates to:
  /// **'Varijanta {n}'**
  String episodeVariantNumbered(int n);

  /// Header of the list of highlighted moments (reels) in the player panel.
  ///
  /// In hr, this message translates to:
  /// **'Istaknuti trenuci'**
  String get reelsTitle;

  /// Tooltip/semantic label: open the vertical 9:16 clip of this moment.
  ///
  /// In hr, this message translates to:
  /// **'Pogledaj isječak'**
  String get reelsWatch;

  /// Short button label on a highlighted moment that has a vertical clip.
  ///
  /// In hr, this message translates to:
  /// **'Pogledaj'**
  String get reelsWatchShort;

  /// Tooltip on a highlighted moment row; tapping seeks the episode.
  ///
  /// In hr, this message translates to:
  /// **'Skoči na {time} u epizodi'**
  String reelsJumpTo(String time);

  /// Button in the clip viewer: close it and continue in the full episode at this moment.
  ///
  /// In hr, this message translates to:
  /// **'Pogledaj u cijeloj epizodi'**
  String get reelsWatchInEpisode;

  /// Shown in the clip viewer when the vertical clip fails to load.
  ///
  /// In hr, this message translates to:
  /// **'Isječak se trenutno ne može pustiti.'**
  String get reelsPlaybackError;

  /// Overline heading of the share sheet opened from the vertical clip viewer, above the moment title.
  ///
  /// In hr, this message translates to:
  /// **'Istaknuti trenutak'**
  String get reelsShareTitle;

  /// Share-sheet action: send the vertical clip as a video file through the system share sheet (WhatsApp, Messages…).
  ///
  /// In hr, this message translates to:
  /// **'Pošalji vertikalni video (9:16)'**
  String get reelsSendVideo;

  /// Same action as reelsSendVideo on platforms that cannot share files (desktop browser): the clip is downloaded.
  ///
  /// In hr, this message translates to:
  /// **'Preuzmi vertikalni video (9:16)'**
  String get reelsDownloadVideo;

  /// Subtitle hint under the send-video action listing typical destinations.
  ///
  /// In hr, this message translates to:
  /// **'WhatsApp, poruke, e-pošta'**
  String get reelsSendHint;

  /// Subtitle while the vertical clip file is being downloaded before it can be shared.
  ///
  /// In hr, this message translates to:
  /// **'Pripremam video…'**
  String get reelsPreparing;

  /// Share-sheet action: copy the direct link to the vertical clip file.
  ///
  /// In hr, this message translates to:
  /// **'Kopiraj vezu na video'**
  String get reelsCopyVideoLink;

  /// Snackbar after copying the direct link to the vertical clip.
  ///
  /// In hr, this message translates to:
  /// **'Veza na video kopirana'**
  String get reelsVideoLinkCopied;

  /// Snackbar after the clip was downloaded as a file because the platform cannot share files.
  ///
  /// In hr, this message translates to:
  /// **'Video je preuzet'**
  String get reelsVideoDownloaded;

  /// Snackbar when downloading or sharing the vertical clip failed.
  ///
  /// In hr, this message translates to:
  /// **'Video se nije uspio pripremiti. Pokušaj ponovno.'**
  String get reelsShareFailed;

  /// Share-sheet action: download the same moment cut from the episode as a 16:9 MP4 (cutter service).
  ///
  /// In hr, this message translates to:
  /// **'Preuzmi vodoravni isječak (16:9)'**
  String get reelsDownloadWide;

  /// Share-sheet action: copy a link to the 16:9 cutter clip of the same moment.
  ///
  /// In hr, this message translates to:
  /// **'Kopiraj vezu na vodoravni isječak (16:9)'**
  String get reelsCopyWideLink;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'hr'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'hr':
      return AppLocalizationsHr();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
