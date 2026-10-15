// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Croatian (`hr`).
class AppLocalizationsHr extends AppLocalizations {
  AppLocalizationsHr([String locale = 'hr']) : super(locale);

  @override
  String appTitle(String app) {
    return '$app';
  }

  @override
  String get updateAvailable => 'Dostupna je nova verzija';

  @override
  String get updateRefresh => 'Osvježi';

  @override
  String get commonCancel => 'Odustani';

  @override
  String get commonClose => 'Zatvori';

  @override
  String get commonBack => 'Natrag';

  @override
  String get commonSave => 'Spremi';

  @override
  String get commonConfirm => 'Potvrdi';

  @override
  String get commonDone => 'Gotovo';

  @override
  String get commonContinue => 'Nastavi';

  @override
  String get commonRetry => 'Pokušaj ponovno';

  @override
  String get commonSeeAll => 'Prikaži sve';

  @override
  String get commonUndo => 'Poništi';

  @override
  String get commonCopy => 'Kopiraj';

  @override
  String get commonShare => 'Podijeli';

  @override
  String get commonCopyLink => 'Kopiraj poveznicu';

  @override
  String get commonLinkCopied => 'Poveznica kopirana';

  @override
  String get commonOk => 'U redu';

  @override
  String get commonSignIn => 'Prijavi se';

  @override
  String get commonSignOut => 'Odjavi se';

  @override
  String get commonLoading => 'Učitavanje…';

  @override
  String get commonGoHome => 'Natrag na početnu';

  @override
  String get commonOpenSource => 'Otvori izvor';

  @override
  String get commonThanksForSupport => 'Hvala na podršci';

  @override
  String commonErrorWithDetails(String details) {
    return 'Greška: $details';
  }

  @override
  String get authAccountTitle => 'Moj račun';

  @override
  String get authAnonTitle => 'Još nisi prijavljen·a';

  @override
  String get authAnonSubtitle =>
      'Prijavi se kako bi upravljao svojim računom, pristupnim ključevima i podacima.';

  @override
  String authLearnAboutPlus(String plus) {
    return 'Saznaj više o $plus';
  }

  @override
  String get authSectionSubscription => 'Pretplata';

  @override
  String get authSectionSignInMethods => 'Prijavne metode';

  @override
  String get authSectionPasskeys => 'Pristupni ključevi';

  @override
  String get authSectionDevices => 'Uređaji';

  @override
  String get authSectionDangerZone => 'Opasna zona';

  @override
  String get authPlusThanks => 'Hvala što podržavaš hrvatsku arhivu.';

  @override
  String get supportThanksGeneric => 'Hvala ti na podršci.';

  @override
  String get authDetails => 'Detalji';

  @override
  String authBecomePlus(String plus) {
    return 'Postani $plus';
  }

  @override
  String get authPlusBenefits =>
      'Šira pretraga, bedž podupiratelja i podrška arhivi.';

  @override
  String get authUserFallback => 'Korisnik';

  @override
  String get authVerifiedIdentity => 'Provjereni identitet (eOsobna)';

  @override
  String get authNoLinkedMethods => 'Nema povezanih prijavnih metoda.';

  @override
  String get authProviderGoogle => 'Google račun';

  @override
  String get authProviderApple => 'Apple račun';

  @override
  String get authProviderEmail => 'Poveznica ili kôd na e-mail';

  @override
  String get authProviderPasskey => 'Pristupni ključ';

  @override
  String get authProviderCertilia => 'Hrvatska e-osobna (Certilia / NIAS)';

  @override
  String get authPasskeysSoon =>
      'Pregled i uklanjanje pristupnih ključeva stiže uskoro. Novi ključ možeš dodati već sada.';

  @override
  String get authNoPasskeys =>
      'Nemaš nijedan pristupni ključ. Pristupni ključ je najsigurniji i najbrži način prijave — bez lozinke, uz Face ID ili otisak prsta.';

  @override
  String get authPasskeyFetchFailed =>
      'Dohvaćanje pristupnih ključeva nije uspjelo.';

  @override
  String get authRemovePasskey => 'Ukloni pristupni ključ';

  @override
  String get authAddPasskeyHere => 'Dodaj pristupni ključ na ovom uređaju';

  @override
  String get authWherePasskeyStored => 'Gdje se sprema pristupni ključ?';

  @override
  String authPasskeyHintBody(String site, String steps) {
    return 'Preporučujemo Apple Passwords ili Google Password Manager — tako je pristupni ključ vezan uz Face ID ili otisak prsta i sinkroniziran na svim tvojim uređajima. Ako koristiš proširenje poput LastPassa ili 1Passworda, isključi ga za $site (ili ga ukloni kao zadani upravitelj ključeva) jer presreće prozor pristupnog ključa i ometa prijavu.\n\n$steps';
  }

  @override
  String get authPasskeyStepsApple =>
      'Postavke → Aplikacije → Lozinke → Opcije lozinki → „Automatski popunjavaj\" — odaberi Lozinke (iCloud).';

  @override
  String get authPasskeyStepsAndroid =>
      'Postavke → Lozinke i računi → Zadana usluga za pristupne ključeve → odaberi Google Password Manager.';

  @override
  String get authPasskeyStepsGeneric =>
      'U postavkama operativnog sustava odaberi sustavski upravitelj pristupnih ključeva (Apple Passwords ili Google Password Manager).';

  @override
  String authPasskeyAdded(String date) {
    return 'dodan $date';
  }

  @override
  String authPasskeyLastUsed(String date) {
    return 'zadnje korišten $date';
  }

  @override
  String get authPasskeyAddedToast => 'Pristupni ključ je dodan.';

  @override
  String get authPasskeyAddFailed => 'Pristupni ključ nije dodan.';

  @override
  String get authRemovePasskeyTitle => 'Ukloniti pristupni ključ?';

  @override
  String authRemovePasskeyBody(String name) {
    return '„$name\" više neće moći prijaviti ovaj račun. Ova je radnja trajna.';
  }

  @override
  String get authRemove => 'Ukloni';

  @override
  String get authPasskeyRemoved => 'Pristupni ključ je uklonjen.';

  @override
  String get authSwitchDevice => 'Prebaci na drugi uređaj';

  @override
  String get authDevicesSubtitle =>
      'Generiraj kôd i prijavi se na TV-u ili mobitelu';

  @override
  String get authSignOutSubtitle =>
      'Nastavi kao gost — podaci ostaju spremljeni na računu';

  @override
  String get authDeleteAccount => 'Izbriši račun';

  @override
  String get authDeleteAccountSubtitle =>
      'Trajno briše račun, favorite, napredak i sve povezane podatke.';

  @override
  String get authAccountDeleted => 'Račun je izbrisan.';

  @override
  String get authDeleteFailed => 'Brisanje nije uspjelo.';

  @override
  String get authSignOutTitle => 'Odjaviti se?';

  @override
  String get authSignOutBody =>
      'Tvoj napredak i favoriti ostaju spremljeni na računu — vraćaju se kad se ponovno prijaviš.';

  @override
  String get authDeleteConfirmTitle => 'Trajno izbrisati račun?';

  @override
  String get authDeleteConfirmWord => 'IZBRIŠI';

  @override
  String authDeleteConfirmBody(String word) {
    return 'Brišu se račun, favoriti, napredak gledanja, pristupni ključevi i sve povezane postavke. Ova je radnja nepovratna.\n\nZa potvrdu upiši $word:';
  }

  @override
  String get authDeletePermanently => 'Trajno izbriši';

  @override
  String get authErrLinkExpired =>
      'Poveznica za prijavu je istekla — zatraži novu.';

  @override
  String get authErrUserBanned => 'Ovaj je račun privremeno blokiran.';

  @override
  String get authErrSignupDisabled =>
      'Registracija novih računa trenutno nije moguća.';

  @override
  String get authErrAccessDenied => 'Prijava je odbijena ili otkazana.';

  @override
  String get authErrServerError =>
      'Greška na poslužitelju — pokušaj ponovo za minutu.';

  @override
  String get authErrGeneric => 'Prijava nije uspjela. Pokušaj ponovo.';

  @override
  String get authErrTimeout =>
      'Prijava traje predugo ili je prekinuta. Pokušaj ponovo.';

  @override
  String authSignedInAs(String name) {
    return 'Prijavljen si kao $name.';
  }

  @override
  String get authSigningIn => 'Prijava u tijeku…';

  @override
  String get authInviteTitle => 'Prihvati pozivnicu';

  @override
  String get authInviteProcessing => 'Obrađujemo pozivnicu…';

  @override
  String get authInviteError =>
      'Došlo je do pogreške ili je poveznica istekla.';

  @override
  String get authM3Toast =>
      'Spremljeno na ovaj uređaj. Sinkronizirati favorite na sve uređaje?';

  @override
  String get authSync => 'Sinkroniziraj';

  @override
  String get authTabSend => 'Pošalji';

  @override
  String get authTabReceive => 'Primi';

  @override
  String get authHandoffSignInFirst => 'Prvo se prijavi';

  @override
  String get authHandoffSignInFirstBody =>
      'Da bi prenio cijeli svoj napredak na drugi uređaj, prvo se prijavi na ovom — tada i drugi uređaj može pristupiti istom računu.';

  @override
  String get authHandoffSendTitle => 'Pošalji prijavu na drugi uređaj';

  @override
  String get authHandoffSendSheetSub =>
      'Za slanje prijave na drugi uređaj prvo se prijavi na ovom.';

  @override
  String authHandoffSendBody(String app) {
    return 'Otvori $app/handoff na drugom uređaju i unesi kôd ispod. Kôd vrijedi 5 minuta.';
  }

  @override
  String get authGenerateCode => 'Generiraj kôd';

  @override
  String get authNewCode => 'Novi kôd';

  @override
  String get authValid5Min => 'Vrijedi 5 minuta';

  @override
  String get authCodeCopied => 'Kôd je kopiran';

  @override
  String get authHandoffReceiveTitle => 'Imaš kôd s drugog uređaja?';

  @override
  String get authHandoffReceiveBody =>
      'Unesi šesteroznamenkasti kôd s drugog uređaja da ovdje preuzmeš njegov račun.';

  @override
  String get authReceiveSignIn => 'Preuzmi prijavu';

  @override
  String get authCode6Digits => 'Kôd mora imati 6 znamenki.';

  @override
  String get authOpeningSignIn => 'Otvaramo prijavu…';

  @override
  String get authOpeningSignInBody =>
      'Ako se otvori preglednik, potvrdi prijavu pa se vrati u aplikaciju.';

  @override
  String get authSuccess => 'Uspješno!';

  @override
  String get authSignInWithPasskey => 'Nastavi pristupnim ključem';

  @override
  String get authPasskeyTileSub =>
      'Face ID ili otisak — ako si ključ već dodao·la';

  @override
  String get authBadgeRecommended => 'Preporučeno';

  @override
  String get authBadgeLastUsed => 'Zadnji put';

  @override
  String get authSignInWithEid => 'Nastavi eOsobnom';

  @override
  String get authContinueWithGoogle => 'Nastavi s Googleom';

  @override
  String get authContinueWithApple => 'Nastavi s Apple računom';

  @override
  String get authEmailMagicLink => 'Nastavi e-mailom';

  @override
  String get authEmailTileSub => 'Pošaljemo ti poveznicu i kôd za prijavu';

  @override
  String get authEmailHint => 'ime@primjer.com';

  @override
  String get authSendCode => 'Pošalji kôd';

  @override
  String get authResendCode => 'Pošalji novi kôd';

  @override
  String authResendCodeIn(int seconds) {
    return 'Pošalji novi kôd ($seconds s)';
  }

  @override
  String get authChangeEmail => 'Promijeni e-mail';

  @override
  String get authEmailTitle => 'Prijava e-mailom';

  @override
  String get authCheckEmail => 'Provjeri e-mail';

  @override
  String get authEmailEntrySub =>
      'Pošaljemo ti poveznicu i šesteroznamenkasti kôd za prijavu — bez lozinke.';

  @override
  String get authUsePassword => 'Prijava lozinkom';

  @override
  String get authPasswordEntrySub => 'Za račune kojima je postavljena lozinka.';

  @override
  String get authPasswordHint => 'Lozinka';

  @override
  String authOtpSentTo(String email) {
    return 'Poslali smo poveznicu i kôd na $email. Upiši kôd — ili otvori poveznicu u e-mailu.';
  }

  @override
  String authHeadlineAccount(String app) {
    return 'Prijavi se na $app';
  }

  @override
  String get authHeadlineMoment3 => 'Spremi favorite u svoj račun';

  @override
  String get authHeadlineHandoff => 'Završi prijavu na ovom uređaju';

  @override
  String get authSubAccount =>
      'Bez lozinke. Prvom prijavom automatski nastaje tvoj račun.';

  @override
  String get authHeadlineGuest => 'Spremi napredak i favorite';

  @override
  String get authSubGuest =>
      'Slušaš kao gost — napredak i favoriti ostaju samo na ovom uređaju.';

  @override
  String get authGuestBarTitle => 'Slušaš kao gost';

  @override
  String get authGuestBarBody =>
      'Napredak, favoriti i postavke ostaju samo na ovom uređaju';

  @override
  String get authSubMoment3 =>
      'Da ti favoriti ostanu dostupni na svim uređajima.';

  @override
  String get authSubHandoff =>
      'Kôd je provjeren — odaberi kako želiš nastaviti.';

  @override
  String authPasskeyMissingNotice(String app) {
    return 'Na ovom uređaju još nema pristupnog ključa za $app. Prijavi se drugom metodom — ključ zatim dodaš u Moj račun.';
  }

  @override
  String get authInvalidEmail => 'Unesi ispravnu e-mail adresu.';

  @override
  String get authSendFailed => 'Slanje nije uspjelo.';

  @override
  String authNewCodeSentTo(String email) {
    return 'Novi kôd poslan na $email.';
  }

  @override
  String get authCodeInvalid => 'Kôd nije ispravan.';

  @override
  String get authSignInFailed => 'Prijava nije uspjela.';

  @override
  String get authYourEmail => 'tvoj e-mail';

  @override
  String authLinkCodeSent(String email) {
    return 'Poveznica i kôd poslani su na $email — provjeri sandučić.';
  }

  @override
  String get authLegalPrefix => 'Nastavkom prihvaćaš ';

  @override
  String get authLegalTerms => 'Uvjete korištenja';

  @override
  String get authLegalAnd => ' i ';

  @override
  String get authLegalPrivacy => 'Pravila privatnosti';

  @override
  String get authLegalSuffix => '.';

  @override
  String get authReassurance =>
      'Tvoj trenutačni napredak ostaje sačuvan i sigurno se povezuje s računom.';

  @override
  String get authOr => 'ili';

  @override
  String get channelClaimOwnership => 'Preuzmi vlasništvo';

  @override
  String get channelAudioOnly => 'Samo zvuk';

  @override
  String get channelInProcessing => 'U obradi';

  @override
  String get channelAllChannels => 'Svi kanali';

  @override
  String get channelSearchChannelsHint => 'Pretraži kanale…';

  @override
  String get channelClear => 'Očisti';

  @override
  String channelChannelsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count kanala',
      few: '$count kanala',
      one: '$count kanal',
    );
    return '$_temp0';
  }

  @override
  String channelResultsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count rezultata',
      few: '$count rezultata',
      one: '$count rezultat',
    );
    return '$_temp0';
  }

  @override
  String get channelNoChannels => 'Nema kanala.';

  @override
  String channelNoChannelsForQuery(String query) {
    return 'Nema kanala za „$query”.';
  }

  @override
  String get channelSortChannels => 'Sortiraj kanale';

  @override
  String get channelShuffle => 'Promiješaj';

  @override
  String get channelKeywordSearch => 'Pretraga po riječima';

  @override
  String get channelKeywordSearchHint =>
      'Traži po riječima (otporno na pogreške)…';

  @override
  String channelSearchUnavailable(String url) {
    return 'Meilisearch nije dostupan na $url. Pokreni Docker kontejner i napuni indeks (repozitorij domovina-rag).';
  }

  @override
  String get channelSearching => 'Tražim…';

  @override
  String channelResultsInMs(int count, int ms) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count rezultata u $ms ms · otporno na pogreške',
      few: '$count rezultata u $ms ms · otporno na pogreške',
      one: '$count rezultat u $ms ms · otporno na pogreške',
    );
    return '$_temp0';
  }

  @override
  String get channelSearchPrompt => 'Upiši pojam za trenutnu pretragu epizoda.';

  @override
  String get channelAll => 'Svi';

  @override
  String get channelSearchStart => 'Pretraga po riječima — počni tipkati.';

  @override
  String channelNoResultsForQuery(String query) {
    return 'Nema rezultata za „$query”.';
  }

  @override
  String channelTriggerGenericHeadline(String plus) {
    return 'Postani $plus';
  }

  @override
  String get channelTriggerGenericSubtitle =>
      'Podrži hrvatsku arhivu i otključaj sve pogodnosti.';

  @override
  String get channelTriggerGenericSubtitleNeutral =>
      'Otključaj sve Plus pogodnosti.';

  @override
  String get channelTriggerSearchHeadline => 'Šira pretraga';

  @override
  String get channelTriggerSearchSubtitle =>
      'Do 30 rezultata pretrage umjesto 12.';

  @override
  String get channelTriggerBadgeHeadline => 'Postani podupiratelj arhive';

  @override
  String get channelTriggerBadgeSubtitle =>
      'Bedž podupiratelja na tvom računu.';

  @override
  String get channelPlanAnnual => 'Godišnje';

  @override
  String get channelPlanPerYear => '/ god.';

  @override
  String get channelPlanSaveBadge => '~33 % povoljnije';

  @override
  String get channelPlanMonthly => 'Mjesečno';

  @override
  String get channelPlanPerMonth => '/ mj.';

  @override
  String get channelPlanLifetime => 'Zauvijek';

  @override
  String get channelPlanOneTime => 'jednokratno';

  @override
  String channelTrialThen(int days, String price) {
    return '$days dana besplatno, zatim $price';
  }

  @override
  String get channelPlanFounderBadge => 'Osnivač';

  @override
  String get channelBenefitSearch =>
      'Šira pretraga — do 30 rezultata umjesto 12';

  @override
  String get channelBenefitBadge => 'Bedž podupiratelja na tvom računu';

  @override
  String get channelBenefitSupport => 'Podržavaš razvoj i troškove arhive';

  @override
  String get plusRoadmapTitle => 'U planu';

  @override
  String get plusRoadmapDisclaimer =>
      'Ovo su smjerovi razvoja, a ne dio onoga što danas kupuješ. Bez rokova — ako i kad stignu, bit će uključeni u Plus bez doplate.';

  @override
  String get plusRoadmapOffline =>
      'Preuzimanje epizoda za slušanje bez interneta';

  @override
  String get plusRoadmapExport => 'Izvoz transkripata i sažetaka';

  @override
  String get channelSignInToContinue => 'Prijavi se za nastavak';

  @override
  String get channelSubscriptionTiedToAccount =>
      'Pretplata se veže uz tvoj račun kako bi radila na svim uređajima.';

  @override
  String channelWelcomeToPlus(String plus) {
    return 'Dobro došao u $plus! Hvala na podršci.';
  }

  @override
  String get channelPurchaseUnavailableDevice =>
      'Kupnja nije dostupna na ovom uređaju.';

  @override
  String get channelPurchaseFailed => 'Kupnja nije uspjela. Pokušaj ponovno.';

  @override
  String get channelSubscriptionRestored => 'Pretplata je vraćena.';

  @override
  String get channelNoPurchaseToRestore => 'Nismo pronašli kupnju za vraćanje.';

  @override
  String get channelWebBillingSoon =>
      'Web naplata stiže uskoro. Zasad se pretplati u mobilnoj aplikaciji.';

  @override
  String get channelSignInFirst => 'Najprije se prijavi';

  @override
  String get channelRestorePurchases => 'Vrati kupnje';

  @override
  String get channelManageSubscription => 'Upravljaj pretplatom';

  @override
  String get channelCheckoutNote =>
      'Naplatu vodi sigurni RevenueCat / Stripe checkout. Konačna cijena prikazuje se na stranici za naplatu.';

  @override
  String get channelPricesIndicative =>
      'Cijene su okvirne; konačna cijena prikazuje se u trgovini.';

  @override
  String channelAlreadyPlus(String plus) {
    return 'Već imaš $plus';
  }

  @override
  String get channelThanksSupportingArchive =>
      'Hvala na podršci hrvatskoj arhivi.';

  @override
  String get channelLegalAutoRenew =>
      'Pretplata se automatski obnavlja dok je ne otkažeš. Otkazati je možeš bilo kada u postavkama trgovine. Doživotni paket jednokratna je kupnja.';

  @override
  String get channelLegalAutoRenewSubscriptionsOnly =>
      'Pretplata se automatski obnavlja dok je ne otkažeš. Otkazati je možeš bilo kada u postavkama trgovine.';

  @override
  String get channelTalkToFounder => 'Razgovaraj s osnivačem';

  @override
  String get channelCannotFetchSlots => 'Ne možemo dohvatiti termine.';

  @override
  String get channelNoSlotsThreeWeeks =>
      'Trenutačno nema slobodnih termina u sljedeća tri tjedna.';

  @override
  String get channelPickDay => 'Odaberi dan';

  @override
  String get channelAvailableSlots => 'Slobodni termini';

  @override
  String get channelFullName => 'Ime i prezime';

  @override
  String get channelEnterName => 'Upiši svoje ime';

  @override
  String get channelEmail => 'E-mail';

  @override
  String get channelEnterEmail => 'Upiši e-mail';

  @override
  String get channelInvalidEmail => 'Neispravan e-mail';

  @override
  String get channelTopicOptional => 'Tema razgovora (neobavezno)';

  @override
  String get channelConfirmSlot => 'Potvrdi termin';

  @override
  String get channelNetworkError => 'Pogreška u mreži. Pokušaj ponovno.';

  @override
  String get channelSlotConfirmed => 'Termin potvrđen!';

  @override
  String channelDayAtTime(String day, String time) {
    return '$day u $time';
  }

  @override
  String channelInviteSentTo(String email) {
    return 'Pozivnicu i Google Meet poveznicu poslali smo na $email.';
  }

  @override
  String get channelOpenGoogleMeet => 'Otvori Google Meet';

  @override
  String channelFounderCallTitle(String brand) {
    return 'Budi dio priče $brand';
  }

  @override
  String get channelFounderCallSubtitle =>
      '15 min Google Meeta · osobno s osnivačem · pomozi oblikovati platformu';

  @override
  String get channelChange => 'Promijeni';

  @override
  String episodeNotFoundDetailed(String id) {
    return 'Epizoda „$id” nije pronađena na CDN-u.\n\nProvjerite je li identifikator ispravan i jesu li datoteke postavljene.';
  }

  @override
  String episodeNotFound(String id) {
    return 'Epizoda „$id” nije pronađena.';
  }

  @override
  String episodeLoadError(String details) {
    return 'Greška pri učitavanju:\n$details';
  }

  @override
  String get episodeLoading => 'Učitavanje epizode';

  @override
  String episodeLinkCopied(String label) {
    return 'Link kopiran ($label)';
  }

  @override
  String get episodeWholeEpisode => 'cijela epizoda';

  @override
  String get clipShareTitle => 'Poglavlje kao isječak';

  @override
  String get clipTooltip => 'Preuzmi ili podijeli poglavlje';

  @override
  String get clipDownload => 'Preuzmi poglavlje';

  @override
  String clipDownloadSubtitle(int size, int minutes) {
    return 'MP4 · ~$size MB · $minutes min';
  }

  @override
  String get clipCopyLink => 'Kopiraj vezu na isječak';

  @override
  String get clipCopyLinkSubtitle => 'Za slanje u poruci ili chatu';

  @override
  String get clipLinkCopied => 'Veza na isječak kopirana';

  @override
  String get clipHint => 'Prvi se put isječak priprema nekoliko sekundi.';

  @override
  String get episodeOpenOnYouTube => 'Otvori na YouTubeu';

  @override
  String get episodeOpenOnX => 'Otvori na 𝕏';

  @override
  String get episodeCopyMomentLink => 'Kopiraj link na ovaj trenutak';

  @override
  String get episodeVideo => 'Video';

  @override
  String get episodeLanguageLabel => 'Jezik:';

  @override
  String get episodeContents => 'Sadržaj';

  @override
  String get episodeArticle => 'Članak';

  @override
  String get episodeListen => 'Slušaj epizodu';

  @override
  String get episodeWatchOnYouTube => 'Gledaj na YouTubeu';

  @override
  String get episodeStageQueuedBadge => 'U redu čekanja';

  @override
  String get episodeStageFetchedBadge => 'Preuzimamo';

  @override
  String get episodeStageMediaReadyBadge => 'Prepisujemo';

  @override
  String get episodeStageTranscribedBadge => 'Pišemo članak';

  @override
  String get episodeStageQueuedHeadline => 'Epizoda još nije preuzeta';

  @override
  String get episodeStageFetchedHeadline => 'Preuzimamo zvuk i sliku';

  @override
  String get episodeStageMediaReadyHeadline => 'Radimo prijepis govora';

  @override
  String get episodeStageTranscribedHeadline => 'Pišemo sažetak i članak';

  @override
  String get episodeStagePublishedHeadline => 'Epizoda je obrađena';

  @override
  String get episodeStageQueuedBody =>
      'Znamo za nju iz kanala, ali datoteke još nisu kod nas — preuzimanje nije uspjelo ili tek slijedi. Do tada je pogledaj izravno s izvora.';

  @override
  String get episodeStageFetchedBody =>
      'Naslov, opis i sličica su kod nas; zvuk i slika još nisu. Reprodukcija kod nas zato još ne radi — pogledaj epizodu s izvora dok je ne prenesemo.';

  @override
  String get episodeStageMediaReadyBodyVideo =>
      'Video možeš gledati odmah. Prijepis, sažetak, poglavlja, članak i teološka analiza stižu čim ih obrada pripremi.';

  @override
  String get episodeStageMediaReadyBodyAudio =>
      'Zvuk možeš slušati odmah. Prijepis, sažetak, poglavlja, članak i teološka analiza stižu čim ih obrada pripremi.';

  @override
  String get episodeStageTranscribedBody =>
      'Prijepis je gotov. Sažetak, poglavlja, članak i teološka analiza stižu čim ih obrada pripremi.';

  @override
  String get episodeStagePublishedBody => 'Sav sadržaj je spreman.';

  @override
  String get episodeStepFetch => 'Preuzeta epizoda';

  @override
  String get episodeStepMedia => 'Zvuk i slika';

  @override
  String get episodeStepTranscript => 'Prijepis govora';

  @override
  String get episodeStepSummary => 'Sažetak';

  @override
  String get episodeStepArticle => 'Članak';

  @override
  String get episodeStepMagisterium => 'Teološka analiza';

  @override
  String get episodeStatusStepsTitle => 'Napredak obrade';

  @override
  String get episodeWatchHere => 'Gledaj ovdje';

  @override
  String get episodeWatchInApp => 'Gledaj u aplikaciji';

  @override
  String get episodeWatchOurPlayer => 'Gledaj epizodu';

  @override
  String get episodeEmbedBlocked =>
      'Vlasnik je za ovu epizodu isključio ugrađeni player, pa se otvara na YouTubeu.';

  @override
  String episodeStatusNotOnCdn(String id) {
    return 'Epizoda „$id” nije pronađena na CDN-u.';
  }

  @override
  String get episodeYouTubeUntilProcessed =>
      'Gledaj s YouTubea dok epizodu ne obradimo.';

  @override
  String get episodeMediaUnavailable =>
      'Medijski zapis nije dostupan za ovu epizodu.';

  @override
  String get episodeNoChapters => 'Nema poglavlja za ovu epizodu.';

  @override
  String get episodeKeyTopics => 'Ključne teme';

  @override
  String get episodeKeyTakeaways => 'Ključne točke';

  @override
  String get episodeSpeakers => 'Govornici';

  @override
  String get episodeTabPlayer => 'Reprodukcija';

  @override
  String get episodeTabChapters => 'Poglavlja';

  @override
  String get episodeTabInfo => 'Info';

  @override
  String get episodeMetadata => 'Metapodaci';

  @override
  String get episodeMetaChannel => 'Kanal';

  @override
  String get episodeMetaModelSummary => 'Model (sažetak)';

  @override
  String get episodeMetaModelArticle => 'Model (članak)';

  @override
  String get episodeMetaModelTheology => 'Model (teologija)';

  @override
  String get episodeMetaGenerated => 'Generirano';

  @override
  String get episodeMetaLanguage => 'Jezik';

  @override
  String get episodeMetaContentType => 'Tip sadržaja';

  @override
  String get episodeMetaSentiment => 'Sentiment';

  @override
  String get episodeMetaDate => 'Datum';

  @override
  String get episodeMetaDuration => 'Trajanje';

  @override
  String homeChannelCardMeta(int count, String duration) {
    return 'Kanal · $count ep · $duration';
  }

  @override
  String homeChannelMagisteriumTooltip(String label) {
    return '$label\nProcjena usklađenosti s katoličkim naukom (0–100).';
  }

  @override
  String get homeFooterAbout => 'O projektu';

  @override
  String homeFooterAboutText(String app) {
    return '$app uz pomoć umjetne inteligencije transkribira, sažima i analizira hrvatske katoličke podcaste. Agent Magisterium AI ocjenjuje usklađenost s katoličkim naukom.';
  }

  @override
  String homeFooterAboutTextGeneric(String app) {
    return '$app uz pomoć umjetne inteligencije transkribira podcaste, dijeli ih na poglavlja i od njih piše članke koje možeš čitati, s govornicima i pretragom po smislu.';
  }

  @override
  String get homeFooterLinks => 'Poveznice';

  @override
  String get homeFooterSuggestEpisode => 'Predloži epizodu';

  @override
  String homeFooterEpisodeSuggestionSubject(String app) {
    return '$app — prijedlog epizode';
  }

  @override
  String get homeFooterContact => 'Kontakt';

  @override
  String get homeFooterPrivacy => 'Privatnost';

  @override
  String get homeFooterTerms => 'Uvjeti korištenja';

  @override
  String get homeFooterStats => 'Statistika';

  @override
  String homeFooterStatChannels(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'kanala',
      few: 'kanala',
      one: 'kanal',
    );
    return '$_temp0';
  }

  @override
  String homeFooterStatEpisodes(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'epizoda',
      few: 'epizode',
      one: 'epizoda',
    );
    return '$_temp0';
  }

  @override
  String homeFooterStatHours(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'sati obrađeno',
      few: 'sata obrađena',
      one: 'sat obrađen',
    );
    return '$_temp0';
  }

  @override
  String get homeFooterStatAvgScore => 'prosječna Magisterium ocjena';

  @override
  String get homeFooterSoon => 'Uskoro';

  @override
  String homeFooterCopyright(int year, String app) {
    return '© $year $app';
  }

  @override
  String get homeFooterMadeIn => 'Stvoreno u Hrvatskoj';

  @override
  String get homeSearchPlaceholderFull => 'Pretraži kanale i epizode';

  @override
  String get homeSearchTooltip => 'Pretraži';

  @override
  String get homeSortNewest => 'Najnoviji';

  @override
  String get homeSortMostEpisodes => 'Najviše epizoda';

  @override
  String get homeSortMagisterium => 'Magisterium ocjena';

  @override
  String get homeSortAlphabetical => 'Abecedno';

  @override
  String get homeSortCustom => 'Moj redoslijed';

  @override
  String get homeReasonShortHiQualityRecent => 'Najbolji izbor';

  @override
  String get homeReasonShortHiQuality => 'Visoka Magisterium ocjena';

  @override
  String get homeReasonShortAnyMagisterium => 'AI-obrađeno';

  @override
  String get homeReasonShortNewest => 'Najnovije';

  @override
  String homeHeroRotationTooltip(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          'Svaki dan biramo $count najboljih epizoda — automatski se izmjenjuju.',
      few:
          'Svaki dan biramo $count najbolje epizode — automatski se izmjenjuju.',
      one: 'Svaki dan biramo najbolju epizodu — automatski se izmjenjuju.',
    );
    return '$_temp0';
  }

  @override
  String get homeHeroRotationBadge => 'U rotaciji';

  @override
  String get homeHeroEyebrow => 'Istaknuto';

  @override
  String get homeHeroListen => 'Slušaj';

  @override
  String get homeHeroWhyButton => 'Zašto?';

  @override
  String get homeWhyDialogTitle => 'Kriteriji za isticanje';

  @override
  String get homeWhyAlgorithmHeading => 'Kako algoritam bira';

  @override
  String get homeWhyDialogExplainer =>
      'Istaknuta se epizoda mijenja svaki dan u ponoć — algoritam izdvaja pet najboljih kandidata iz aktivnog razreda i bira jednoga prema danu u godini. Tijekom dana izbor ostaje isti (deterministički).';

  @override
  String get homeWhyGotIt => 'Razumijem';

  @override
  String get homeReasonHeadlineHiQualityRecent =>
      'Visoka ocjena, svježa epizoda';

  @override
  String get homeReasonHeadlineHiQuality => 'Visoka Magisterium ocjena';

  @override
  String get homeReasonHeadlineAnyMagisterium => 'AI-obrađena epizoda';

  @override
  String get homeReasonHeadlineNewest => 'Najnovija epizoda';

  @override
  String get homeWhyFactChannel => 'Kanal';

  @override
  String get homeWhyFactScore => 'Magisterium ocjena';

  @override
  String get homeWhyFactPublished => 'Objavljeno';

  @override
  String get homeWhyFactAiProcessing => 'AI obrada';

  @override
  String get homeWhyFactAiYes =>
      'Da (transkript, sažetak i Magisterium analiza)';

  @override
  String get homeWhyFactAiYesGeneric => 'Da (transkript, članak i poglavlja)';

  @override
  String get homeWhyFactAiNo => 'Ne';

  @override
  String get homeWhyFactWeight => 'Algoritamska težina';

  @override
  String homeWhyFactWeightValue(String weight) {
    return '$weight (ocjena × 0,6 + svježina × 0,4)';
  }

  @override
  String get homeWhyFactPool => 'Skupina kandidata';

  @override
  String homeWhyFactPoolValue(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count epizoda u istom razredu',
      few: '$count epizode u istom razredu',
      one: '$count epizoda u istom razredu',
    );
    return '$_temp0';
  }

  @override
  String get homeTier1Title => '1. Najbolji izbor';

  @override
  String get homeTier1Desc =>
      'AI obrada + ocjena ≥ 70 + objavljeno u zadnjih 14 dana. Poredano po (ocjena × 0,6 + svježina × 0,4). Pet najboljih ulazi u dnevnu rotaciju.';

  @override
  String get homeTier2Title => '2. Visoka ocjena';

  @override
  String get homeTier2Desc =>
      'AI obrada + ocjena ≥ 70 (bilo koji datum). Poredano po ocjeni.';

  @override
  String get homeTier3Title => '3. AI-obrađeno';

  @override
  String get homeTier3Desc =>
      'Bilo koja epizoda s AI obradom. Poredano po datumu.';

  @override
  String get homeTier4Title => '4. Najnovije';

  @override
  String get homeTier4Desc => 'Pričuva — najnovija epizoda bez ikakve obrade.';

  @override
  String get homeAgoToday => 'danas';

  @override
  String get homeAgoYesterday => 'jučer';

  @override
  String homeAgoDays(int days) {
    String _temp0 = intl.Intl.pluralLogic(
      days,
      locale: localeName,
      other: 'prije $days dana',
      few: 'prije $days dana',
      one: 'prije $days dan',
    );
    return '$_temp0';
  }

  @override
  String homeAgoWeeks(int weeks) {
    String _temp0 = intl.Intl.pluralLogic(
      weeks,
      locale: localeName,
      other: 'prije $weeks tjedana',
      few: 'prije $weeks tjedna',
      one: 'prije $weeks tjedan',
    );
    return '$_temp0';
  }

  @override
  String homeAgoMonths(int months) {
    String _temp0 = intl.Intl.pluralLogic(
      months,
      locale: localeName,
      other: 'prije $months mjeseci',
      few: 'prije $months mjeseca',
      one: 'prije $months mjesec',
    );
    return '$_temp0';
  }

  @override
  String homeAgoYears(int years) {
    String _temp0 = intl.Intl.pluralLogic(
      years,
      locale: localeName,
      other: 'prije $years godina',
      few: 'prije $years godine',
      one: 'prije $years godinu',
    );
    return '$_temp0';
  }

  @override
  String get homeComingSoonSnack => 'Ova značajka uskoro stiže';

  @override
  String homeChannelsLoadError(String error) {
    return 'Pogreška pri učitavanju kanala:\n$error';
  }

  @override
  String get homeRailContinue => 'Nastavi slušati';

  @override
  String get homeRailLatest => 'Najnovije epizode';

  @override
  String get homeRailFeaturedShows => 'Istaknuti podcasti';

  @override
  String get homeRailFavorites => 'Tvoje spremljeno';

  @override
  String get favoritesTitle => 'Spremljene epizode';

  @override
  String favoritesCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count epizoda',
      few: '$count epizode',
      one: '$count epizoda',
    );
    return '$_temp0';
  }

  @override
  String get favoritesEmptyTitle => 'Još nemaš spremljenih epizoda';

  @override
  String get favoritesEmptyBody =>
      'Dodirni srce na epizodi i naći ćeš je ovdje — najnovije prvo.';

  @override
  String get favoritesBrowse => 'Istraži epizode';

  @override
  String get favoritesSaved => 'Spremljeno';

  @override
  String get favoritesRemoved => 'Uklonjeno iz spremljenih';

  @override
  String get favoritesAccountSubtitle => 'Cijeli popis, najnovije prvo';

  @override
  String get authSectionLibrary => 'Moja knjižnica';

  @override
  String get homeRailFreshlyArrived => 'Upravo stiglo';

  @override
  String get homeStatusProcessing => 'U obradi';

  @override
  String get homeChannelsEyebrow => 'Kanali';

  @override
  String get homeAllChannelsTitle => 'Svi kanali';

  @override
  String homeAllChannelsSubtitle(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Pretraži i pregledaj svih $count kanala',
      few: 'Pretraži i pregledaj svih $count kanala',
      one: 'Pretraži i pregledaj $count kanal',
    );
    return '$_temp0';
  }

  @override
  String homeLoadingChannels(int loaded, int total) {
    return 'Učitavam $loaded/$total kanala…';
  }

  @override
  String get homeSearchBarrierLabel => 'Zatvori pretragu';

  @override
  String get homeSearchHint => 'Pretraži kanale, epizode i sadržaj…';

  @override
  String get homeSearchClear => 'Obriši upit';

  @override
  String homeSearchNoResults(String query) {
    return 'Nema rezultata za „$query”';
  }

  @override
  String get homeSearchSearching => 'Pretražujem…';

  @override
  String get homeSearchSectionChannels => 'Kanali';

  @override
  String get homeSearchSectionEpisodes => 'Epizode';

  @override
  String get homeSearchEmptyTitle => 'Počni tipkati za pretragu';

  @override
  String get homeSearchEmptySubtitle =>
      'Pretražuje kanale, epizode i sam sadržaj razgovora';

  @override
  String get homeSearchKeyboardHint => '↑ ↓ kroz popis · ↵ za odabir';

  @override
  String homeSearchChannelMeta(int count, String duration) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count epizoda · $duration',
      few: '$count epizode · $duration',
      one: '$count epizoda · $duration',
    );
    return '$_temp0';
  }

  @override
  String get homeSearchOpenById => 'Otvori po YouTube ID-u';

  @override
  String get homeSearchShowAll => 'Prikaži sve rezultate';

  @override
  String homeSearchJumpTo(String time) {
    return 'Pusti od $time';
  }

  @override
  String get homeSearchIdHint => 'npr. H-p2Hl6x7I0';

  @override
  String legalLastUpdated(String date) {
    return 'Zadnje ažurirano: $date';
  }

  @override
  String get legalPrivacyPushTitle => 'Push obavijesti';

  @override
  String get legalPrivacyPushBody =>
      'Ako u aplikaciji za iOS ili Android uključite obavijesti, javljamo Vam kad stigne nova epizoda — sve nove ili samo s kanala koje izaberete na ekranu Obavijesti. Za dostavu koristimo Google Firebase Cloud Messaging: uređaj dobiva registracijski token i pretplaćuje se na teme koje ste izabrali (npr. „sve nove epizode” ili pojedini kanal). Token i popis tema ne spremamo uz Vaš račun; izbor tema čuva se samo na Vašem uređaju, a pretplate drži Google kao izvršitelj obrade.\n\nObavijesti šaljemo na temelju Vaše privole (čl. 6. st. 1. t. a) GDPR-a), koju dajete uključivanjem obavijesti i sistemskom dozvolom. Možete je povući u svakom trenutku na ekranu Obavijesti ili u postavkama uređaja. Između 22 i 7 sati obavijesti ne šaljemo.';

  @override
  String get legalContactTitle => 'Kontakt';

  @override
  String get legalPrivacyTitle => 'Politika privatnosti';

  @override
  String legalPrivacyIntro(String app) {
    return '$app aplikacija je koja transkribira, sažima i analizira hrvatske katoličke podcaste pomoću umjetne inteligencije.';
  }

  @override
  String legalPrivacyIntroGeneric(String app) {
    return '$app je aplikacija koja uz pomoć umjetne inteligencije transkribira podcaste, dijeli ih na poglavlja i od njih piše članke za čitanje.';
  }

  @override
  String get legalPrivacyDataTitle => 'Koje podatke prikupljamo';

  @override
  String legalPrivacyDataBody(String email) {
    return 'ITalk d.o.o. za informacijske tehnologije, kao voditelj obrade, prikuplja i obrađuje vaše podatke u skladu s Općom uredbom o zaštiti podataka (GDPR).\n\nKada se prijavite (putem Certilia IDP sustava, Googlea, Applea ili e-pošte), prikupljamo osnovne identifikacijske podatke (e-mail adresu, ime i prezime, te OIB ukoliko se prijavljujete putem e-Građani/Certilia sustava) isključivo u svrhu pružanja usluge. Vaš napredak slušanja, omiljene oznake i glasovanja pohranjuju se kako bi se sinkronizirali među uređajima.\n\nZa obradu \"Plus\" pretplata koristimo vanjske izvršitelje (Apple, Google, RevenueCat) te ne pohranjujemo niti imamo pristup podacima vaših bankovnih kartica. Primjenjujemo najviše tehničke i organizacijske mjere sigurnosti (enkripcija u prijenosu i pohrani).\n\nKao korisnik, imate pravo na pristup, ispravak, ograničenje obrade, prijenos i brisanje svojih podataka (svoj račun možete trajno obrisati u aplikaciji u svakom trenutku). Za sva pitanja o privatnosti ili ostvarivanje prava obratite se na $email. U slučaju sumnje na povredu podataka, imate pravo podnijeti pritužbu Agenciji za zaštitu osobnih podataka (AZOP).';
  }

  @override
  String get legalPrivacyAnalyticsTitle => 'Analitika korištenja';

  @override
  String legalPrivacyAnalyticsBody(String email) {
    return 'Kako bismo razumjeli kako se aplikacija koristi i mogli je poboljšavati, bilježimo događaje korištenja: pokretanje aplikacije, stranice i epizode koje otvarate, reprodukciju (pokretanje, pauzu, premotavanje, brzinu i koliko ste epizode odslušali), upite koje upišete u pretragu i što iz rezultata otvorite, trajanje sesije te prikaze i klikove na sponzorske poruke. Uz svaki događaj spremamo nasumični identifikator uređaja (aplikacija ga stvara pri prvom pokretanju i čuva u pohrani preglednika ili uređaja), identifikator sesije, vrstu uređaja i preglednika, verziju aplikacije, jezik, veličinu zaslona te približnu lokaciju (država, regija i grad), koju određuje Cloudflare. Ako ste prijavljeni, događaje povezujemo i s identifikatorom Vašeg računa. IP adresu ne spremamo.\n\nPodatke obrađujemo na temelju legitimnog interesa (čl. 6. st. 1. t. f) GDPR-a): mjerimo i poboljšavamo uslugu, uključujući pretragu, i bilježimo prikazivanje sponzorskih poruka. Ne koristimo alate trećih strana za praćenje (poput Google Analyticsa). Podatke pohranjujemo na vlastitom poslužitelju u Europskoj uniji (Frankfurt), a Cloudflare ih kao izvršitelj obrade prenosi do njega. Ne prodajemo ih i ne dijelimo s trećim stranama radi oglašavanja. Čuvamo ih 25 mjeseci. Identifikator uređaja možete ukloniti brisanjem podataka aplikacije ili pohrane preglednika. Za brisanje događaja povezanih s Vašim računom obratite se na $email.';
  }

  @override
  String legalPrivacyContactBody(String email) {
    return 'Aplikacijom upravlja ITalk d.o.o. za informacijske tehnologije, IX. Južna obala 20, 10000 Zagreb, OIB: 54872935051. Za pitanja u vezi s privatnošću obratite se Matiji Stepaniću na $email.';
  }

  @override
  String get legalTermsTitle => 'Uvjeti korištenja';

  @override
  String legalTermsIntro(String app) {
    return 'Korištenjem aplikacije $app prihvaćate ove Uvjete korištenja.';
  }

  @override
  String get legalTermsContentTitle => 'Sadržaj';

  @override
  String get legalTermsContentBody =>
      'Svi audio i video materijali preuzimaju se iz javnih i slobodno dostupnih izvora. Aplikacija se pruža \"kakva jest\" (as-is) i bez ikakvih jamstava u pogledu neprekidne dostupnosti. ITalk d.o.o. ne odgovara za izravnu ili neizravnu štetu nastalu korištenjem aplikacije, a ukupna odgovornost ograničena je na iznos pretplate u zadnja 3 mjeseca. Pretplata na \"Plus\" opciju obnavlja se sukladno uvjetima vanjskih pružatelja (Apple/Google) te povrat sredstava reguliraju njihova pravila. Na ove uvjete primjenjuje se pravo Republike Hrvatske, a za sporove je nadležan sud u Zagrebu.';

  @override
  String get legalTermsAiTitle => 'AI analiza';

  @override
  String get legalTermsAiBody =>
      'Magisterium AI ocjene i sažetci strojno su generirani i mogu sadržavati pogreške. Ne predstavljaju službeno stajalište Katoličke Crkve.';

  @override
  String get legalTermsAiBodyGeneric =>
      'Članci, sažeci, poglavlja i oznake govornika generiraju se automatski uz pomoć umjetne inteligencije (AI) i mogu sadržavati pogreške ili netočnosti (halucinacije). Korisnik AI značajke koristi na vlastitu odgovornost, a ITalk d.o.o. ne odgovara za točnost i pravne posljedice tako generiranog sadržaja.';

  @override
  String legalTermsContactBody(String email) {
    return 'Aplikacijom upravlja ITalk d.o.o. za informacijske tehnologije, IX. Južna obala 20, 10000 Zagreb, OIB: 54872935051. Za upite kontaktirajte Matiju Stepanića na $email.';
  }

  @override
  String get magisteriumScoreActivelyPromotes =>
      'Aktivno promiče katolički nauk';

  @override
  String get magisteriumScoreMostlyAligned => 'Uglavnom usklađeno';

  @override
  String get magisteriumScorePartiallyAligned => 'Djelomično usklađeno';

  @override
  String get magisteriumScoreDeviates => 'Odstupanje od nauka';

  @override
  String get magisteriumScoreContradicts => 'Proturječi nauku';

  @override
  String get magisteriumAlignmentSubtitle =>
      'Usklađenost s katoličkim naukom i Svetim pismom';

  @override
  String magisteriumTheologicalConcerns(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count teoloških zabrinutosti',
      few: '$count teološke zabrinutosti',
      one: '$count teološka zabrinutost',
    );
    return '$_temp0';
  }

  @override
  String get magisteriumArticleHeaderTitle =>
      'Magisterium AI — Teološka analiza';

  @override
  String get magisteriumArticleHeaderSubtitle =>
      'Kronološki pregled usklađenosti s katoličkim naukom';

  @override
  String magisteriumAnalysisGeneratedBy(String model, String date) {
    return 'Analiza generirana modelom $model • $date';
  }

  @override
  String magisteriumSourcesFromChurchDocs(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count izvora iz crkvenih dokumenata',
      few: '$count izvora iz crkvenih dokumenata',
      one: '$count izvor iz crkvenih dokumenata',
    );
    return '$_temp0';
  }

  @override
  String get magisteriumTabEvaluation => 'Evaluacija';

  @override
  String get magisteriumTabPrompt => 'Prompt';

  @override
  String get magisteriumFullHeaderTitle =>
      'Magisterium AI — Teološka evaluacija';

  @override
  String magisteriumModelCitations(String model, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count citata',
      few: '$count citata',
      one: '$count citat',
    );
    return '$model  •  $_temp0';
  }

  @override
  String get magisteriumSourcesTitle => 'Izvori';

  @override
  String magisteriumCitationsFromChurchDocs(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count citata iz crkvenih dokumenata',
      few: '$count citata iz crkvenih dokumenata',
      one: '$count citat iz crkvenih dokumenata',
    );
    return '$_temp0';
  }

  @override
  String get magisteriumScoreCaption => 'Magisterium ocjena';

  @override
  String get magisteriumOpenOnMagisterium => 'Otvori na Magisterium.com';

  @override
  String get mediaYouTubeHigherQuality => 'YouTube player (viša kvaliteta)';

  @override
  String get mediaSubtitlesOff => 'Isključi titlove (C)';

  @override
  String get mediaSubtitlesOn => 'Titlovi (C)';

  @override
  String get mediaBoostVolume => 'Uključi zvuk';

  @override
  String get mediaMute => 'Isključi zvuk (M)';

  @override
  String get mediaPause => 'Pauziraj';

  @override
  String get mediaPlay => 'Reproduciraj';

  @override
  String get mediaChapters => 'Poglavlja';

  @override
  String get mediaYouTubeQualityHint =>
      'YouTube player — kvalitetu biraš u postavkama playera';

  @override
  String mediaNativePlayerLabel(String brand) {
    return '$brand player';
  }

  @override
  String get mediaLanguageSelection => 'Odabir jezika prikaza';

  @override
  String get mediaTranslationDisclaimer =>
      'Prijevod je doslovan, bez AI halucinacija.';

  @override
  String get mediaSwitchToCroatian => 'Prebaci na hrvatski';

  @override
  String get mediaSwitchToEnglish => 'Prebaci na engleski';

  @override
  String get mediaRemoveFavorite => 'Ukloni iz favorita';

  @override
  String get mediaAddFavorite => 'Dodaj u favorite';

  @override
  String mediaResumingFrom(String time) {
    return 'Nastavljam od $time';
  }

  @override
  String get mediaSwitchToLightTheme => 'Prebaci na svijetlu temu';

  @override
  String get mediaSwitchToDarkTheme => 'Prebaci na tamnu temu';

  @override
  String get mediaViewSimple => 'Jednostavno';

  @override
  String get mediaViewDetailed => 'Detaljno';

  @override
  String get mediaViewSimpleTooltip =>
      'Prebaci na jednostavni prikaz — veliki player i poglavlja, bez članka (idealno za slušanje u autu)';

  @override
  String get mediaViewDetailedTooltip =>
      'Prebaci na detaljni prikaz — članak, Magisterium ocjena i poglavlja uz video';

  @override
  String get mediaViewDetailedTooltipGeneric =>
      'Prebaci na detaljni prikaz — članak i poglavlja uz video';

  @override
  String get mediaUserFallback => 'Korisnik';

  @override
  String mediaViaProvider(String provider) {
    return 'preko $provider';
  }

  @override
  String get mediaVerifiedIdentity => 'Verificiran identitet';

  @override
  String get mediaMyAccount => 'Moj račun';

  @override
  String get mediaMyChannels => 'Moji kanali';

  @override
  String get mediaSwitchDevice => 'Prebaci na drugi uređaj';

  @override
  String mediaMinAmount(String amount) {
    return 'Najmanji iznos je $amount €';
  }

  @override
  String get mediaPaymentCreateFailed =>
      'Stvaranje uplate nije uspjelo. Pokušaj ponovno.';

  @override
  String get mediaSupportEpisode => 'Podrži ovu epizodu';

  @override
  String get mediaSupportBlurb =>
      'Doniraj jednim skenom — SEPA, bez naknade. Sredstva idu izravno autoru, transparentno na lancu.';

  @override
  String mediaRaisedProgress(String raised, String goal, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '# podržavatelja',
      few: '# podržavatelja',
      one: '# podržavatelj',
    );
    return 'Prikupljeno $raised € od $goal € · $_temp0';
  }

  @override
  String get mediaPreparing => 'Pripremam…';

  @override
  String mediaSupportWithAmount(String amount) {
    return 'Podrži s $amount €';
  }

  @override
  String get mediaScanInBankApp => 'Skeniraj u svojoj bankovnoj aplikaciji';

  @override
  String mediaAmountValue(String amount) {
    return 'Iznos: $amount €';
  }

  @override
  String get mediaRecipient => 'Primatelj';

  @override
  String get mediaPaymentReference => 'Opis plaćanja';

  @override
  String get mediaAwaitingPayment => 'Čekam potvrdu plaćanja…';

  @override
  String get mediaPaymentConfirmedOnChain => 'Plaćanje je potvrđeno na lancu.';

  @override
  String mediaCopiedLabel(String label) {
    return 'Kopirano: $label';
  }

  @override
  String get mediaOtherAmount => 'Ostalo';

  @override
  String get ownershipCrumbHome => 'Početna';

  @override
  String get ownershipCrumbOwnership => 'Vlasništvo';

  @override
  String get ownershipChannelFallback => 'Kanal';

  @override
  String get ownershipMyChannels => 'Moji kanali';

  @override
  String get ownershipLoadChannelFailed => 'Učitavanje kanala nije uspjelo.';

  @override
  String get ownershipOpenAuthFailed => 'Otvaranje autorizacije nije uspjelo.';

  @override
  String get ownershipSignInToClaim => 'Za preuzimanje kanala prvo se prijavi.';

  @override
  String get ownershipNoYoutubeId =>
      'Ovaj kanal još nema povezan YouTube identifikator pa preuzimanje trenutno nije moguće.';

  @override
  String get ownershipChannelNotFound => 'Kanal nije pronađen.';

  @override
  String get ownershipNotOwnerTitle => 'Niste vlasnik kanala?';

  @override
  String ownershipNotOwnerBody(String app) {
    return 'Ako poznajete vlasnika, pošaljite mu poruku da preuzme vlasništvo i verificira se na $app.';
  }

  @override
  String get ownershipInviteOwnerWhatsApp => 'Pozovite vlasnika (WhatsApp)';

  @override
  String ownershipInviteMessage(String channelTitle, String link, String app) {
    return 'Pozdrav! Vaš YouTube kanal „$channelTitle” nalazi se na $app. Možete besplatno preuzeti vlasništvo te upravljati svojim sadržajem i isplatama — verificirajte se kao vlasnik kanala ovdje: $link';
  }

  @override
  String get ownershipStepConfirmTitle => 'Potvrdi vlasništvo';

  @override
  String get ownershipReverifySubtitle =>
      'Vlasništvo je starije od 90 dana — potvrdite ga ponovno.';

  @override
  String get ownershipOwnershipVerifiedSubtitle =>
      'Vlasništvo je potvrđeno putem YouTube računa.';

  @override
  String get ownershipSignInYoutubeSubtitle =>
      'Prijavi se YouTube računom koji je vlasnik ovog kanala.';

  @override
  String get ownershipOwnershipNote =>
      'Vlasništvo može preuzeti samo Google račun koji je vlasnik kanala. Uređivači i menadžeri dodani u YouTube postavkama (Channel permissions) to ne mogu — YouTube ih ne prikazuje kao vlasnike. Ako kanal pripada Brand računu, prijavite se Google računom koji njime upravlja.';

  @override
  String get ownershipReverifyAction => 'Ponovite potvrdu';

  @override
  String get ownershipLoginYoutube => 'Prijava putem YouTubea';

  @override
  String get ownershipStepVerifyIdentityTitle => 'Verificiraj identitet';

  @override
  String get ownershipIdentityVerifiedSubtitle =>
      'Identitet je verificiran (eOsobna).';

  @override
  String get ownershipConnectEosobnaSubtitle =>
      'Poveži eOsobnu (Certilia) — nužno prije isplate.';

  @override
  String get ownershipVerifyWithEosobna => 'Verificiraj eOsobnom';

  @override
  String get ownershipStepConnectWalletTitle => 'Poveži novčanik';

  @override
  String get ownershipWalletLockedSubtitle =>
      'Dostupno nakon potvrde vlasništva i verifikacije identiteta.';

  @override
  String get ownershipWalletSubtitle =>
      'Registrirajte adresu novčanika za isplatu (odredište).';

  @override
  String get ownershipManageWallet => 'Upravljajte novčanikom';

  @override
  String get ownershipCheckingOwnership => 'Provjeravamo vlasništvo…';

  @override
  String get ownershipMissingAuthData => 'Nedostaju podaci autorizacije.';

  @override
  String ownershipOwnershipConfirmedWithName(String name) {
    return 'Vlasništvo je potvrđeno: $name';
  }

  @override
  String ownershipRequestReceivedWithStatus(String status) {
    return 'Zahtjev je zaprimljen (status: $status).';
  }

  @override
  String get ownershipCallbackTitle => 'Potvrda vlasništva';

  @override
  String get ownershipRevokeDialogTitle => 'Otpustiti vlasništvo?';

  @override
  String ownershipRevokeDialogBody(String name) {
    return 'Odričeš se vlasništva nad kanalom „$name”. Verifikacija i status isplate poništavaju se, a kanal postaje dostupan za novo preuzimanje. Možeš ga ponovno preuzeti bilo kada.';
  }

  @override
  String get ownershipRevokeAction => 'Otpusti';

  @override
  String get ownershipRevokedSnack => 'Vlasništvo je otpušteno.';

  @override
  String get ownershipClaimedChannelsTitle => 'Preuzeti kanali';

  @override
  String get ownershipPayoutWalletsTitle => 'Novčanici za isplatu';

  @override
  String get ownershipPayoutWalletsDesc =>
      'Odredište na koje vam se isplaćuju prikupljena sredstva — vaš kripto-novčanik (0x, Gnosis). Kad zatražite isplatu, platforma izvrši prijenos na tu adresu.\n\nOvo NIJE adresa na koju stižu donacije: svaka kampanja ima zaseban Safe na koji uplate dolaze (vidljiv svima na Gnosisscanu); isplatu pokrećete iz upravljanja kampanjom.';

  @override
  String get ownershipNoClaimsBody =>
      'Još nemaš nijedan preuzet kanal. Otvori kanal i odaberi „Preuzmi vlasništvo” da pokreneš verifikaciju.';

  @override
  String get ownershipBrowseChannels => 'Pregledajte kanale';

  @override
  String get ownershipNeedsReverifyTag => 'treba ponovnu potvrdu';

  @override
  String get ownershipOptionsTooltip => 'Opcije';

  @override
  String get ownershipCampaignsMenu => 'Kampanje (Zid podrške)';

  @override
  String get ownershipRevokeMenu => 'Otpusti vlasništvo';

  @override
  String get ownershipWalletDestVerified => 'Odredište isplate · potvrđeno';

  @override
  String get ownershipWalletDest => 'Odredište isplate';

  @override
  String get ownershipWalletAddressLabel =>
      'Adresa vašeg novčanika za isplatu (0x…)';

  @override
  String get ownershipWalletAddressHelper =>
      'EVM adresa (Gnosis) na koju primate isplate.';

  @override
  String get ownershipAddWallet => 'Dodajte novčanik';

  @override
  String get ownershipCampaignFallback => 'Kampanja';

  @override
  String get ownershipTabEdit => 'Uredi';

  @override
  String get ownershipTabEpisodes => 'Epizode';

  @override
  String get ownershipTabStats => 'Statistika';

  @override
  String get ownershipTabPayout => 'Isplata';

  @override
  String get ownershipCampaignNotFound => 'Kampanja nije pronađena.';

  @override
  String get ownershipSaved => 'Spremljeno';

  @override
  String get ownershipSaveFailed => 'Spremanje nije uspjelo.';

  @override
  String get ownershipFieldTitle => 'Naslov';

  @override
  String get ownershipFieldDescription => 'Opis';

  @override
  String get ownershipFieldGoal => 'Cilj (€)';

  @override
  String get ownershipFieldGoalHint => 'prazno = bez cilja';

  @override
  String get ownershipFieldMinAmount => 'Min. iznos (€)';

  @override
  String get ownershipFieldState => 'Stanje';

  @override
  String get ownershipFieldVisibility => 'Vidljivost';

  @override
  String get ownershipEditNote =>
      'Napomena: SEPA i on-chain podaci (IBAN, Safe adresa) te slug ne mijenjaju se ovdje.';

  @override
  String get ownershipSaveChanges => 'Spremi promjene';

  @override
  String get ownershipStateDraft => 'Skica';

  @override
  String get ownershipStateActive => 'Aktivna';

  @override
  String get ownershipStateClosed => 'Zatvorena';

  @override
  String get ownershipStateCancelled => 'Otkazana';

  @override
  String get ownershipStateFunded => 'Financirana';

  @override
  String get ownershipVisPublic => 'Javna';

  @override
  String get ownershipVisUnlisted => 'Neuvrštena';

  @override
  String get ownershipVisPrivate => 'Privatna';

  @override
  String ownershipSupportersContributions(int supporters, int contributions) {
    String _temp0 = intl.Intl.pluralLogic(
      supporters,
      locale: localeName,
      other: '$supporters podržavatelja',
      few: '$supporters podržavatelja',
      one: '$supporters podržavatelj',
    );
    String _temp1 = intl.Intl.pluralLogic(
      contributions,
      locale: localeName,
      other: '$contributions uplata',
      few: '$contributions uplate',
      one: '$contributions uplata',
    );
    return '$_temp0 · $_temp1';
  }

  @override
  String get ownershipSupportWall => 'Zid podrške';

  @override
  String get ownershipNoPublicContributions => 'Još nema javnih doprinosa.';

  @override
  String get ownershipEnterValidAmount => 'Unesi ispravan iznos.';

  @override
  String get ownershipAmountExceedsAvailable => 'Iznos premašuje raspoloživo.';

  @override
  String get ownershipEnterDestination =>
      'Unesi odredište (0x adresa ili IBAN).';

  @override
  String get ownershipPayoutRequestSent => 'Zahtjev za isplatu poslan';

  @override
  String get ownershipRequestFailedRetry =>
      'Zahtjev nije uspio. Pokušaj ponovno.';

  @override
  String get ownershipErrKycRequired =>
      'Prije isplate potrebna je verifikacija eOsobnom (KYC).';

  @override
  String get ownershipErrInvalidDestination =>
      'Neispravno odredište (0x adresa ili IBAN).';

  @override
  String get ownershipErrInvalidAmount => 'Neispravan iznos.';

  @override
  String get ownershipErrNotAuthorized => 'Nemate ovlasti za ovu kampanju.';

  @override
  String get ownershipErrRequestFailed => 'Zahtjev nije uspio.';

  @override
  String get ownershipPayoutNeedsKyc =>
      'Za isplatu je potrebna verifikacija eOsobnom (KYC). Dovršite je u odjeljku „Moji kanali”.';

  @override
  String get ownershipRequestPayout => 'Zatražite isplatu';

  @override
  String get ownershipDestinationLabel => 'Odredište (0x adresa ili IBAN)';

  @override
  String get ownershipAmountLabel => 'Iznos (€)';

  @override
  String ownershipAvailableHelper(String amount) {
    return 'Raspoloživo: $amount €';
  }

  @override
  String get ownershipPayoutHistory => 'Povijest isplata';

  @override
  String get ownershipNoPayouts => 'Još nema isplata.';

  @override
  String get ownershipChangeFailed => 'Promjena nije uspjela.';

  @override
  String get ownershipYieldTitle => 'Oplođujte sredstva (Aave v3 · Gnosis)';

  @override
  String get ownershipYieldSubtitle =>
      'Dok sredstva čekaju isplatu, nose prinos (~3,5 % APY, promjenjivo). Prinos pripada kampanji. DeFi rizik — glavnica nije zajamčena.';

  @override
  String get ownershipYieldInPool => 'U oplodnji (Aave)';

  @override
  String get ownershipYieldAccrued => 'Akumulirani prinos';

  @override
  String ownershipYieldLastSync(String time) {
    return 'zadnja sinkronizacija: $time';
  }

  @override
  String get ownershipYieldTokenLink => 'aGnoEURe na Gnosisscanu';

  @override
  String get ownershipSummaryRaised => 'Prikupljeno';

  @override
  String get ownershipSummaryYield => 'Prinos (Aave)';

  @override
  String get ownershipSummaryPending => 'U obradi';

  @override
  String get ownershipSummaryPaid => 'Isplaćeno';

  @override
  String get ownershipSummaryAvailable => 'Raspoloživo';

  @override
  String get ownershipPayoutStateRequested => 'Zatraženo';

  @override
  String get ownershipPayoutStateApproved => 'Odobreno';

  @override
  String get ownershipPayoutStateFailed => 'Neuspjelo';

  @override
  String get ownershipCampaignsTitle => 'Kampanje';

  @override
  String get ownershipSignInToManageCampaigns =>
      'Za upravljanje kampanjama prvo se prijavite.';

  @override
  String get ownershipNotVerifiedOwner =>
      'Niste verificirani vlasnik ovog kanala.';

  @override
  String ownershipEpisodesCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count epizoda',
      few: '$count epizode',
      one: '$count epizoda',
    );
    return '$_temp0';
  }

  @override
  String get ownershipNoCampaignsTitle => 'Još nema kampanja za ovaj kanal.';

  @override
  String get ownershipNoCampaignsBody =>
      'Kampanje se kreiraju na pinka.io (gdje se generira i Safe za isplatu). Nakon kreiranja povežite kampanju s kanalom kako biste je ovdje administrirali i dodijelili epizodama.';

  @override
  String get ownershipEpisodesSaved => 'Epizode spremljene';

  @override
  String get ownershipEpisodeTaken =>
      'Jedna od epizoda već je u drugoj kampanji.';

  @override
  String get ownershipSaveFailedRetry =>
      'Spremanje nije uspjelo. Pokušaj ponovno.';

  @override
  String get ownershipNoEpisodesAvailable =>
      'Nema dostupnih epizoda za ovaj kanal.';

  @override
  String ownershipSelectedCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count epizoda',
      few: '$count epizode',
      one: '$count epizoda',
    );
    return 'Odabrano: $_temp0';
  }

  @override
  String get pinkaWallTitle => 'Zid podrške';

  @override
  String get pinkaSupport => 'Podrži';

  @override
  String get pinkaNoCampaign =>
      'Za ovaj sadržaj još nije pokrenuta kampanja podrške.';

  @override
  String get pinkaWallEmpty =>
      'Budi prvi koji podržava — tvoja poruka osvanut će ovdje.';

  @override
  String get pinkaRaisedLabel => 'prikupljeno';

  @override
  String pinkaOfGoal(String amount) {
    return 'od cilja $amount €';
  }

  @override
  String pinkaRaised(String amount) {
    return 'Prikupljeno $amount €';
  }

  @override
  String pinkaRaisedOfGoal(String raised, String goal) {
    return 'Prikupljeno $raised € od $goal €';
  }

  @override
  String pinkaSupportersCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count podržavatelja',
      few: '$count podržavatelja',
      one: '$count podržavatelj',
    );
    return '$_temp0';
  }

  @override
  String pinkaPaymentsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count uplata',
      few: '$count uplate',
      one: '$count uplata',
    );
    return '$_temp0';
  }

  @override
  String get pinkaVerifyOnchainTitle => 'Provjeri na lancu';

  @override
  String get pinkaVerifyOnchainBody =>
      'Uplate stižu izravno na Safe kampanje (EURe na Gnosisu). Stanje može provjeriti bilo tko — neovisno o nama.';

  @override
  String pinkaOnchainBalance(String amount) {
    return 'Trenutno na Safeu: $amount €';
  }

  @override
  String get pinkaEureBalanceOnGnosisscan => 'EURe saldo na Gnosisscanu';

  @override
  String get pinkaInflowHistory => 'Povijest priljeva (transferi)';

  @override
  String get pinkaFundsWorkingAave =>
      'Sredstva trenutno rade na Aave v3 (Gnosis)';

  @override
  String pinkaInAaveLabel(String amount) {
    return 'U Aaveu: $amount €';
  }

  @override
  String pinkaAaveYieldLabel(String amount) {
    return 'prinos: $amount €';
  }

  @override
  String get pinkaAaveExplainer =>
      'Zato je EURe saldo na samom Safeu nizak — sredstva su deponirana radi prinosa i povlače se natrag pri isplati.';

  @override
  String get pinkaAgnoEureBalanceOnGnosisscan =>
      'aGnoEURe saldo na Gnosisscanu';

  @override
  String pinkaMinAmount(String amount) {
    return 'Najmanji iznos je $amount €';
  }

  @override
  String get pinkaPaymentCreateFailed =>
      'Uplatu nije bilo moguće pripremiti. Pokušaj ponovno.';

  @override
  String get pinkaPaymentSentPending =>
      'Uplata je poslana — pojavit će se na zidu čim se potvrdi na lancu.';

  @override
  String get pinkaWalletSendFailed =>
      'Slanje iz novčanika nije uspjelo ili je otkazano.';

  @override
  String get pinkaOnchainBlurb =>
      'Pošalji EURe (Gnosis) izravno na lanac — transparentno i bez posrednika.';

  @override
  String get pinkaSepaBlurb =>
      'Doniraj jednim skenom — SEPA, bez naknade. Sredstva idu izravno autoru.';

  @override
  String get pinkaCustomAmountHint => 'Ostalo';

  @override
  String get pinkaCustomAmountPlaceholder => '19,91';

  @override
  String get pinkaSafeAddressCopied =>
      'Adresa Safe novčanika kopirana u međuspremnik.';

  @override
  String get pinkaCopySafeAddress => 'Kopiraj adresu Safe novčanika';

  @override
  String pinkaStepOf(int current, int total) {
    return 'Korak $current/$total';
  }

  @override
  String get pinkaStepPaymentTitle => 'Uplata iz tvoje banke';

  @override
  String get pinkaStepPaymentCustodian => 'Skrbnik: tvoja banka';

  @override
  String get pinkaStepProcessingTitle => 'Zaprimljeno — obrada i provjera';

  @override
  String get pinkaStepProcessingCustodian =>
      'Skrbnik: Monerium (regulirani izdavatelj e-novca)';

  @override
  String get pinkaStepMintedTitle => 'EURe iskovan';

  @override
  String get pinkaStepMintedCustodian => 'Na blockchainu (Gnosis)';

  @override
  String get pinkaStepForwardingTitle => 'Prosljeđivanje primatelju';

  @override
  String get pinkaStepForwardingCustodian => 'MPT relay';

  @override
  String get pinkaStepSettledTitle => 'Kod primatelja';

  @override
  String get pinkaStepSettledCustodian => 'Skrbnik: primatelj';

  @override
  String get pinkaIntentRejected =>
      'Uplata je odbijena pri obradi — sredstva se vraćaju pošiljatelju.';

  @override
  String get pinkaIntentExpired =>
      'Vrijeme za uplatu je isteklo. Ako si uplatu ipak poslao, pojavit će se na zidu kad stigne.';

  @override
  String get pinkaNameHint => 'Ime ili nadimak (neobavezno)';

  @override
  String get pinkaMessageHint => 'Poruka uz podršku (neobavezno)';

  @override
  String get pinkaNameLabel => 'Ime ili nadimak';

  @override
  String get pinkaNameHelper => 'Ovako ćeš biti potpisan na zidu';

  @override
  String get pinkaLinkLabel => 'Poveznica (neobavezno)';

  @override
  String get pinkaLinkHelper => 'Tvoja stranica, projekt ili firma';

  @override
  String get pinkaLinkInvalid =>
      'Provjeri poveznicu — mora počinjati s https://';

  @override
  String get pinkaMessageLabel => 'Poruka (neobavezno)';

  @override
  String get pinkaPreviewHeading => 'Ovako će izgledati tvoja kartica';

  @override
  String get pinkaPreviewNamePlaceholder => 'Tvoje ime ili nadimak';

  @override
  String get pinkaPreviewMessagePlaceholder => 'Tvoja poruka';

  @override
  String get pinkaWallOpenLink => 'Otvori poveznicu';

  @override
  String get pinkaWallCardDetails => 'Prikaži cijelu poruku';

  @override
  String get pinkaAnonymousLabel =>
      'Doniraj anonimno (ne prikazuj me na zidu podrške)';

  @override
  String get pinkaPreparing => 'Pripremam…';

  @override
  String pinkaSupportWithAmount(String amount) {
    return 'Podrži s $amount €';
  }

  @override
  String get pinkaWalletConnecting => 'Povezujem novčanik…';

  @override
  String get pinkaWalletOpening => 'Otvaram novčanik…';

  @override
  String get pinkaWalletConfirming => 'Potvrđujem na lancu…';

  @override
  String pinkaPayFromDomovinaWallet(String amount, String brand) {
    return 'Plati $amount € iz $brand novčanika';
  }

  @override
  String get pinkaOrScanOtherWallet => 'ili skeniraj drugim novčanikom';

  @override
  String pinkaScanWithWallet(String amount) {
    return 'Skeniraj novčanikom (MetaMask / Monerium) i pošalji $amount € u EURe.';
  }

  @override
  String get pinkaRecipient => 'Primatelj';

  @override
  String get pinkaToken => 'Token';

  @override
  String get pinkaOnchainArrivalNote =>
      'Donacija se pojavi na zidu podrške kad stigne na lanac (~1–2 min).';

  @override
  String get pinkaScanInBankApp => 'Skeniraj u svojoj bankovnoj aplikaciji';

  @override
  String pinkaAmountLabel(String amount) {
    return 'Iznos: $amount €';
  }

  @override
  String get pinkaPaymentReference => 'Opis plaćanja';

  @override
  String get pinkaAwaitingPayment => 'Čekam potvrdu plaćanja…';

  @override
  String get pinkaThanksForSupport => 'Hvala na podršci!';

  @override
  String get pinkaPaymentConfirmedOnchain => 'Plaćanje je potvrđeno na lancu.';

  @override
  String get pinkaSepaReceivedProcessing =>
      'Uplata je zaprimljena. Izdavanje EURe-a je u tijeku.';

  @override
  String get pinkaSepaFirstPaymentReview =>
      'Kod prve uplate s novog računa provjera može potrajati. Ne moraš ništa raditi.';

  @override
  String get pinkaSepaMintedForwarding =>
      'EURe izdan, prosljeđuje se kampanji…';

  @override
  String pinkaIntentRejectedReason(String reason) {
    return 'Razlog: $reason';
  }

  @override
  String get pinkaDonateAgain => 'Doniraj još jednom';

  @override
  String pinkaCopiedLabel(String label) {
    return 'Kopirano: $label';
  }

  @override
  String get pinkaLink => 'poveznica';

  @override
  String get pinkaAnonymous => 'Anoniman';

  @override
  String get sectionArticle => 'Članak';

  @override
  String sectionPlayFrom(String timestamp) {
    return 'Pusti od $timestamp';
  }

  @override
  String sectionPersonSpeaksHere(String name) {
    return '$name govori ovdje';
  }

  @override
  String sectionPersonMentionedHere(String name) {
    return 'Ovdje se spominje: $name';
  }

  @override
  String get sectionCopyLink => 'Kopiraj poveznicu';

  @override
  String sectionLinkCopied(String timestamp) {
    return 'Poveznica kopirana: $timestamp';
  }

  @override
  String get sectionTheologicalAssessment => 'Teološka procjena';

  @override
  String sectionSources(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count izvora',
      few: '$count izvora',
      one: '$count izvor',
    );
    return '$_temp0';
  }

  @override
  String get sectionSummary => 'Sažetak';

  @override
  String get sectionKeyTopics => 'Ključne teme';

  @override
  String get sectionSpeakers => 'Govornici';

  @override
  String get sectionKeyTakeaways => 'Ključni zaključci';

  @override
  String get sectionChapters => 'Poglavlja';

  @override
  String get sectionPeople => 'Osobe';

  @override
  String get sectionPlaces => 'Mjesta';

  @override
  String get sectionOrganizations => 'Organizacije';

  @override
  String get sectionContents => 'Sadržaj';

  @override
  String get sectionAgeToday => 'danas';

  @override
  String get sectionAgeYesterday => 'jučer';

  @override
  String sectionAgeDays(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'prije $count dana',
      few: 'prije $count dana',
      one: 'prije $count dan',
    );
    return '$_temp0';
  }

  @override
  String sectionAgeWeeks(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'prije $count tj.',
      few: 'prije $count tj.',
      one: 'prije tjedan',
    );
    return '$_temp0';
  }

  @override
  String sectionAgeMonths(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'prije $count mj.',
      few: 'prije $count mj.',
      one: 'prije mjesec',
    );
    return '$_temp0';
  }

  @override
  String sectionAgeYears(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'prije $count god.',
      few: 'prije $count god.',
      one: 'prije godinu',
    );
    return '$_temp0';
  }

  @override
  String sectionPublishedOn(String date) {
    return 'Objavljeno: $date';
  }

  @override
  String get sectionTheologicalAnalysisSubtitle =>
      'Teološka analiza, sekciju po sekciju';

  @override
  String get sectionNoTheologicalAnalysis =>
      'Nema teološke analize za ovu sekciju.';

  @override
  String get sectionAudio => 'Audio';

  @override
  String get serviceUnavailable =>
      'Usluga trenutno nije dostupna. Pokušaj ponovo malo poslije.';

  @override
  String serviceSignedInAs(String name) {
    return 'Prijavljen si kao $name.';
  }

  @override
  String get serviceGenericUser => 'korisnik';

  @override
  String get serviceContinueSignInBrowser => 'Nastavi prijavu u pregledniku…';

  @override
  String get serviceUnexpectedSignInError =>
      'Došlo je do neočekivane pogreške pri prijavi. Pokušaj ponovo.';

  @override
  String get serviceAuthRateLimited =>
      'Previše pokušaja — pričekaj minutu pa pokušaj ponovo.';

  @override
  String get serviceAuthEmailInvalid =>
      'E-mail adresa ne izgleda ispravno. Provjeri unos.';

  @override
  String get serviceAuthOtpExpired => 'Kod je istekao — zatraži novi.';

  @override
  String get serviceAuthOtpDisabled => 'Prijava kodom trenutno nije dostupna.';

  @override
  String get serviceAuthUserBanned => 'Ovaj je račun privremeno blokiran.';

  @override
  String get serviceAuthSignupDisabled =>
      'Otvaranje novih računa trenutno nije moguće.';

  @override
  String get serviceAuthProviderDisabled =>
      'Ova metoda prijave trenutno nije dostupna.';

  @override
  String get serviceAuthEmailNotConfirmed =>
      'E-mail adresa još nije potvrđena.';

  @override
  String get serviceAuthNoServerConnection =>
      'Nema veze s poslužiteljem. Provjeri internet pa pokušaj ponovo.';

  @override
  String get serviceAuthSignInFailed => 'Prijava nije uspjela. Pokušaj ponovo.';

  @override
  String get serviceAccountNoEmailPasskey =>
      'Tvoj račun nema e-mail adresu pa passkey trenutno nije moguć.';

  @override
  String get servicePasskeyAddedToAccount => 'Passkey je dodan na tvoj račun.';

  @override
  String get servicePasskeyCreated => 'Passkey je kreiran.';

  @override
  String get serviceEmailSendFailed =>
      'Slanje e-maila nije uspjelo. Pokušaj ponovo.';

  @override
  String get serviceSignInSuccess => 'Prijava je uspješna.';

  @override
  String get serviceOtpInvalidOrExpired =>
      'Kod nije ispravan ili je istekao — provjeri unos ili zatraži novi.';

  @override
  String get servicePasswordInvalid => 'Pogrešan e-mail ili lozinka.';

  @override
  String get serviceOtpCheckFailed => 'Provjera koda nije uspjela.';

  @override
  String get serviceAccountDeleteUnavailable =>
      'Brisanje računa kroz aplikaciju još nije dostupno. Pošalji zahtjev na privacy@italk.hr pa ćemo ga izbrisati ručno.';

  @override
  String serviceAccountDeleteFailedWithStatus(String status) {
    return 'Brisanje računa nije uspjelo ($status). Pokušaj ponovo.';
  }

  @override
  String get serviceAccountDeleteFailed =>
      'Brisanje računa nije uspjelo. Pokušaj ponovo.';

  @override
  String get serviceAccountDeleted => 'Račun je trajno izbrisan.';

  @override
  String get serviceSignedOutGuest => 'Odjavljen si — nastavljaš kao gost.';

  @override
  String get serviceEmailDialogTitle => 'Tvoj e-mail';

  @override
  String get serviceEmailDialogMessage =>
      'Poslat ćemo ti link i šesteroznamenkasti kod za prijavu.';

  @override
  String get serviceEmailDialogHint => 'ime@primjer.com';

  @override
  String get serviceEmailDialogConfirm => 'Pošalji';

  @override
  String get servicePasskeyRequestInProgress =>
      'Passkey zahtjev je već u tijeku — pričekaj da završi ili osvježi stranicu.';

  @override
  String get servicePasskeyRegisterCancelled =>
      'Registracija passkeyja je otkazana ili je istekla. Pokušaj ponovo.';

  @override
  String get servicePasskeyPasswordManagerBlockRegister =>
      'Upravitelj lozinki (npr. LastPass) blokira passkey. U njegovu prozoru odaberi „Use a different passkey” i izaberi iCloud/Apple Passwords — ili isključi LastPass za ovu stranicu.';

  @override
  String get servicePasskeyAlreadyExists =>
      'Na ovom uređaju već postoji passkey za ovaj račun.';

  @override
  String get servicePasskeyDomainNotAssociated =>
      'Domena nije povezana s passkeyjem. Pokušaj ponovo malo poslije.';

  @override
  String get servicePasskeyDeviceUnsupported =>
      'Ovaj uređaj ne podržava passkey.';

  @override
  String get servicePasskeyCreateFailed =>
      'Passkey nije moguće kreirati na ovom uređaju.';

  @override
  String get servicePasskeyNoneOnDevice =>
      'Na ovom uređaju nema spremljenog passkeyja.';

  @override
  String get servicePasskeyLoginCancelled =>
      'Prijava passkeyjem je otkazana ili je istekla. Pokušaj ponovo.';

  @override
  String get servicePasskeyPasswordManagerBlockLogin =>
      'Upravitelj lozinki (npr. LastPass) blokira passkey. U njegovu prozoru odaberi „Use a different passkey” — ili isključi LastPass za ovu stranicu.';

  @override
  String get servicePasskeyLoginFailed => 'Prijava passkeyjem nije uspjela.';

  @override
  String get servicePasskeyManageUnavailable =>
      'Upravljanje passkeyjima još nije dostupno.';

  @override
  String servicePasskeyFetchFailedWithStatus(String status) {
    return 'Dohvat passkeyja nije uspio ($status).';
  }

  @override
  String get servicePasskeyRemoveUnavailable =>
      'Uklanjanje passkeyja još nije dostupno.';

  @override
  String servicePasskeyRemoveFailedWithStatus(String status) {
    return 'Uklanjanje passkeyja nije uspjelo ($status).';
  }

  @override
  String get servicePasskeyFinishFailed =>
      'Dovršetak prijave passkeyjem nije uspio.';

  @override
  String get serviceBackendNoSignInData =>
      'Poslužitelj nije vratio podatke za prijavu.';

  @override
  String get servicePasskeyEmailRequired =>
      'Unesi e-mail za otvaranje računa s passkeyjem.';

  @override
  String servicePasskeyPrepareFailedWithStatus(String status) {
    return 'Priprema passkeyja nije uspjela ($status).';
  }

  @override
  String get servicePasskeyNotVerified =>
      'Passkey nije verificiran. Pokušaj ponovo.';

  @override
  String get servicePasskeyUnknownCredential =>
      'Ovaj passkey nije prepoznat — možda je vezan uz drugi račun.';

  @override
  String get servicePasskeyAccountExists =>
      'Račun s tom e-mail adresom već postoji — prijavi se passkeyjem ili Googleom.';

  @override
  String get serviceSessionExpired => 'Sesija je istekla. Pokušaj ponovo.';

  @override
  String servicePasskeyFinishFailedWithStatus(String status) {
    return 'Dovršetak prijave passkeyjem nije uspio ($status).';
  }

  @override
  String get serviceCertiliaCancelled => 'Prijava e-Osobnom je otkazana.';

  @override
  String get serviceCertiliaServerUnavailable =>
      'Certilia trenutno nije dostupna. Pokušaj ponovo malo poslije.';

  @override
  String get serviceCertiliaFailed => 'Prijava e-Osobnom nije uspjela.';

  @override
  String get serviceCertiliaMissingToken =>
      'Certilia nije vratila token. Pokušaj ponovo.';

  @override
  String get serviceCertiliaFinishFailed =>
      'Dovršetak prijave e-Osobnom nije uspio.';

  @override
  String get serviceCertiliaInvalidToken =>
      'Certilia token nije valjan. Pokušaj ponovo.';

  @override
  String get serviceCertiliaNoOib =>
      'Certilia nije vratila OIB pa prijava nije moguća.';

  @override
  String serviceCertiliaLinkFailedWithStatus(String status) {
    return 'Povezivanje s računom nije uspjelo ($status).';
  }

  @override
  String get serviceHandoffCodeSixDigits =>
      'Kod mora imati točno šest znamenki.';

  @override
  String get serviceHandoffNoSignInLink =>
      'Poslužitelj nije vratio link za prijavu.';

  @override
  String get serviceHandoffNoActiveSession =>
      'Ovaj uređaj nema aktivnu sesiju — osvježi stranicu pa pokušaj ponovo.';

  @override
  String get serviceHandoffInvalidOrExpiredCode =>
      'Kod ne postoji ili je istekao.';

  @override
  String get serviceHandoffRequestError =>
      'Pogreška u pozivu poslužitelja. Pokušaj ponovo.';

  @override
  String serviceHandoffTransferFailedWithStatus(String status) {
    return 'Prijenos nije uspio ($status).';
  }

  @override
  String get serviceClaimNoAuthUrl =>
      'Poslužitelj nije vratio adresu za autorizaciju.';

  @override
  String get serviceClaimMismatchNoChannel =>
      'Prijavljeni Google račun nije vlasnik ovog kanala. Ovaj račun ne upravlja nijednim YouTube kanalom. Prijavi se Google računom koji je vlasnik kanala (a ne samo urednik).';

  @override
  String serviceClaimMismatchWithChannel(String name) {
    return 'Prijavljeni Google račun nije vlasnik ovog kanala. Ovim računom upravljaš kanalom: $name. Prijavi se Google računom koji je vlasnik kanala (a ne samo urednik).';
  }

  @override
  String get serviceClaimRevokeFailed =>
      'Odustajanje od vlasništva nije uspjelo.';

  @override
  String get serviceClaimChannelMismatch =>
      'Prijavljeni YouTube račun nije vlasnik ovog kanala.';

  @override
  String get serviceClaimNoChannel =>
      'Na ovom Google računu nema YouTube kanala.';

  @override
  String get serviceClaimInvalidState =>
      'Autorizacija je istekla. Pokušaj ponovo.';

  @override
  String get serviceClaimAlreadyClaimed =>
      'Ovaj je kanal već preuzeo drugi korisnik.';

  @override
  String get serviceClaimNotSignedIn =>
      'Za preuzimanje kanala moraš biti prijavljen.';

  @override
  String get serviceClaimVerifyFailed =>
      'Provjera vlasništva nije uspjela. Pokušaj ponovo.';

  @override
  String get serviceSafeNotEligible =>
      'Još ne ispunjavaš uvjete za isplatu (vlasništvo, potvrđen identitet i svježina potvrde).';

  @override
  String get serviceSafeKycRequired =>
      'Za isplatu najprije potvrdi identitet e-Osobnom (Certilia).';

  @override
  String get serviceSafeWalletNotRegistered =>
      'Adresa novčanika nije registrirana na tvom računu.';

  @override
  String get serviceSafeNoSafe => 'Za ovu epizodu još ne postoji novčanik.';

  @override
  String get serviceSafeFrozen => 'Novčanik epizode trenutno je zamrznut.';

  @override
  String get serviceSafeReverifyNeeded =>
      'Vlasništvo treba ponovo potvrditi prije isplate.';

  @override
  String get serviceSafeConnectFailed =>
      'Povezivanje s novčanikom nije uspjelo. Pokušaj ponovo.';

  @override
  String get serviceWalletInvalidAddress =>
      'Adresa novčanika nije ispravna (očekuje se 0x i 40 heksadekadskih znamenki).';

  @override
  String get serviceWalletNotSignedIn =>
      'Za registraciju novčanika moraš biti prijavljen.';

  @override
  String get serviceWalletSaveFailed => 'Spremanje novčanika nije uspjelo.';

  @override
  String get serviceWalletRemoveFailed => 'Brisanje novčanika nije uspjelo.';

  @override
  String get servicePurchasePackageUnavailable =>
      'Paket više nije dostupan. Pokušaj ponovo.';

  @override
  String get servicePurchaseNotActivated => 'Kupnja nije aktivirala pretplatu.';

  @override
  String get servicePurchaseFailed => 'Kupnja nije uspjela. Pokušaj ponovo.';

  @override
  String get serviceRestoreNoSubscription =>
      'Nismo pronašli aktivnu pretplatu za vraćanje.';

  @override
  String get serviceRestoreFailed =>
      'Vraćanje kupnji nije uspjelo. Pokušaj ponovo.';

  @override
  String get servicePurchaseNotAllowed =>
      'Kupnja nije dopuštena na ovom uređaju.';

  @override
  String get servicePurchasePending =>
      'Plaćanje je u obradi — pretplata se aktivira čim bude potvrđeno.';

  @override
  String get servicePurchaseAlreadyOwned =>
      'Već imaš ovu pretplatu. Pokušaj „Vrati kupnje”.';

  @override
  String get servicePurchaseNetworkError =>
      'Nema veze s trgovinom. Provjeri internet pa pokušaj ponovo.';

  @override
  String get servicePurchaseStoreProblem =>
      'Trgovina trenutno ne odgovara. Pokušaj poslije.';

  @override
  String tvChannelLoadError(String details) {
    return 'Učitavanje kanala nije uspjelo:\n$details';
  }

  @override
  String get tvChannelNoEpisodes => 'U ovom kanalu još nema epizoda.';

  @override
  String tvEpisodeCountPlural(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count epizoda',
      few: '$count epizode',
      one: '$count epizoda',
    );
    return '$_temp0';
  }

  @override
  String get tvReaderPreparing => 'Pripremam čitanje…';

  @override
  String get tvReaderNotAiProcessed =>
      'Ova epizoda još nije AI-obrađena.\nPrikaz za čitanje zasad nije dostupan.';

  @override
  String tvLoadError(String details) {
    return 'Greška pri učitavanju:\n$details';
  }

  @override
  String get tvReaderOpenClassic => 'Otvori klasični prikaz';

  @override
  String tvReaderSectionOf(int current, int total) {
    return 'Odlomak $current / $total';
  }

  @override
  String get tvLive => 'Uživo';

  @override
  String get tvPaused => 'Pauza';

  @override
  String get tvReaderNoCommentary => 'Za ovaj odlomak nema teološkog osvrta.';

  @override
  String get tvReaderChurchTeaching => 'Nauk Crkve za ovaj odlomak';

  @override
  String get tvReaderOpenFullCommentary => 'OK — otvori cijeli osvrt';

  @override
  String get tvHintPlayPause => 'sviraj/pauza';

  @override
  String get tvHintSections => 'odlomci';

  @override
  String get tvHintVideo => 'video';

  @override
  String get tvReaderHeadingAssessment => 'Procjena';

  @override
  String get tvReaderHeadingConcerns => 'Na što paziti';

  @override
  String get tvReaderHeadingEnrichment => 'Pojašnjenje';

  @override
  String get tvReaderHeadingCitations => 'Citati iz Magisterija';

  @override
  String get tvReaderCloseHint => 'BACK ili OK = zatvori';

  @override
  String get tvRead => 'Čitaj';

  @override
  String get tvFullscreen => 'Cijeli zaslon';

  @override
  String get tvExitFullscreen => 'Izađi iz cijelog zaslona';

  @override
  String get tvLoadingEpisode => 'Učitavam epizodu…';

  @override
  String tvEpisodeNotFound(String id) {
    return 'Epizoda „$id” nije pronađena.';
  }

  @override
  String get tvBufferStartingEngine => 'Pokrećem media engine…';

  @override
  String get tvBufferLoadingVideo => 'Učitavam video…';

  @override
  String get tvBufferFilling => 'Punjenje međuspremnika…';

  @override
  String get tvHintRead => 'Čitaj / Cijeli zaslon';

  @override
  String get tvHintExit => 'izađi';

  @override
  String tvChaptersWithCount(int count) {
    return 'Poglavlja ($count)';
  }

  @override
  String get tvSearch => 'Pretraga';

  @override
  String get tvRailContinueListening => 'Nastavi slušati';

  @override
  String get tvRailLatestEpisodes => 'Najnovije epizode';

  @override
  String tvChannelsWithCount(int count) {
    return 'Kanali ($count)';
  }

  @override
  String get tvSortEpisodes => 'Epizode';

  @override
  String get tvSortAlpha => 'Abeceda';

  @override
  String get tvSortShuffle => 'Nasumično';

  @override
  String tvLoadingChannels(int loaded, int total) {
    return 'Učitavam $loaded/$total kanala…';
  }

  @override
  String get tvTipsPreparingCatalog => 'Pripremam katalog…';

  @override
  String get tvPlay => 'Pokreni';

  @override
  String get authSectionLanguage => 'Jezik';

  @override
  String personEpisodesCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count epizoda',
      few: '$count epizode',
      one: '$count epizoda',
    );
    return '$_temp0';
  }

  @override
  String get personAppearsOn => 'Gostuje na';

  @override
  String get personActivityOverTime => 'Aktivnost kroz vrijeme';

  @override
  String get personEpisodesHeading => 'Epizode';

  @override
  String get personNotFoundTitle => 'Osobu nismo pronašli';

  @override
  String get personNotFoundBody =>
      'Ovu osobu još nemamo u bazi — ni kao govornika ni kao spomen u obrađenim epizodama.';

  @override
  String get personShareTooltip => 'Podijeli profil';

  @override
  String get personLinkCopied => 'Poveznica na profil kopirana';

  @override
  String get personMentionedIn => 'Spominje se u';

  @override
  String personMentionsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count spomena',
      few: '$count spomena',
      one: '$count spomen',
    );
    return '$_temp0';
  }

  @override
  String personMentionAtTime(String time) {
    return 'spomen u $time';
  }

  @override
  String get personMentionWholeEpisode => 'spomen negdje u epizodi';

  @override
  String get personMentionedOn => 'Spominje se na';

  @override
  String get personMentionOnlyNote =>
      'Ova osoba nije gostovala u obrađenim epizodama — profil prati gdje se o njoj govori.';

  @override
  String appInstallBannerIos(String app) {
    return '$app ima i aplikaciju za iPhone.';
  }

  @override
  String appInstallBannerAndroid(String app) {
    return '$app ima i aplikaciju za Android.';
  }

  @override
  String get appInstallBannerAction => 'Preuzmi';

  @override
  String get pinkaGridIntro =>
      'Svaki kvadratić je jedna podrška — bliže središtu, veći doprinos.';

  @override
  String get pinkaGridTapHint =>
      'Dodirni slobodan kvadratić da odabereš iznos.';

  @override
  String get pinkaGridZoneOuterBelt => 'Vanjski pojas';

  @override
  String get pinkaGridZoneDefenseRing => 'Zaštitni prsten';

  @override
  String get pinkaGridZoneMidBelt => 'Središnji pojas';

  @override
  String get pinkaGridZoneHighZone => 'Visoka zona';

  @override
  String get pinkaGridZoneGoldenCircle => 'Zlatni krug';

  @override
  String get pinkaGridZoneBusiness => 'Poslovna zona';

  @override
  String get pinkaGridZoneExecutive => 'Direktorska zona';

  @override
  String get pinkaGridZonePrestige => 'Prestiž';

  @override
  String get pinkaGridZoneElite => 'Elita';

  @override
  String get pinkaGridZoneCore => 'Jezgra';

  @override
  String pinkaGridZonePriceLabel(String name, String price) {
    return '$name · $price €';
  }

  @override
  String pinkaGridAmountSet(String name, String price) {
    return '$name — iznos postavljen na $price €.';
  }

  @override
  String get pinkaGridTakenTitle => 'Ovaj je kvadratić već zauzet';

  @override
  String get pinkaSlotIntro =>
      'Odaberi svoj kvadratić — bliže središtu, veći doprinos. Mjesto ti se rezervira dok traje uplata.';

  @override
  String pinkaSlotZoneFallback(int index) {
    return 'Zona $index';
  }

  @override
  String get pinkaSlotStatusHeld => 'Rezervirano — netko upravo plaća';

  @override
  String get pinkaSlotStatusBlocked => 'Ovo mjesto nije u ponudi';

  @override
  String get pinkaSlotHeldTitle => 'Kvadratić je rezerviran';

  @override
  String get pinkaSlotHeldBody =>
      'Netko ga upravo plaća. Ako uplata ne sjedne, kvadratić se vraća u ponudu — pokušaj kasnije ili odaberi drugi.';

  @override
  String pinkaSlotPriceLocked(String price) {
    return 'Cijena mjesta: $price €';
  }

  @override
  String get pinkaSlotTopUpHint =>
      'Možeš dati i više — manje od cijene mjesta ne.';

  @override
  String get pinkaSlotTopUpLabel => 'Iznos';

  @override
  String get pinkaSlotClear => 'Odustani';

  @override
  String pinkaSlotBelowPrice(String price) {
    return 'Iznos ne smije biti manji od cijene mjesta ($price €).';
  }

  @override
  String get pinkaSlotSignInRequired =>
      'Za rezervaciju mjesta na zidu prijavi se. Običnu donaciju možeš poslati i bez prijave.';

  @override
  String get pinkaGuestRateLimited =>
      'Previše uplata s ove mreže u zadnjih sat vremena. Pokušaj malo kasnije ili se prijavi.';

  @override
  String get pinkaSlotTakenError =>
      'Netko je bio brži — taj je kvadratić upravo zauzet. Odaberi drugi.';

  @override
  String pinkaSlotHoldCountdown(String time) {
    return 'Mjesto ti je rezervirano još $time.';
  }

  @override
  String get pinkaSlotHoldExpired =>
      'Rezervacija je istekla, ali uplata i dalje vrijedi — kad sjedne, dobivaš isti kvadratić ako je slobodan, inače najbliži u istoj ili skupljoj zoni.';

  @override
  String get pinkaSlotHoldReserved => 'Mjesto ti je rezervirano.';

  @override
  String get pinkaSlotHoldReassure =>
      'Ako nalog zastane na provjeri kod tvoje ili primateljeve banke, ne brini — dovoljno je da uplata stigne unutar 24 sata i uredno ćemo je obraditi.';

  @override
  String get pinkaSlotPickerOpen => 'Povećaj';

  @override
  String get pinkaSlotPickerTitle => 'Odaberi mjesto';

  @override
  String get pinkaSlotPickerHint =>
      'Povlači i približi prstima; kvadratić pod nišanom je tvoj odabir.';

  @override
  String pinkaSlotPickerConfirm(String price) {
    return 'Potvrdi mjesto · $price €';
  }

  @override
  String get pinkaSlotPickerTaken => 'Mjesto je zauzeto';

  @override
  String get pinkaSlotPickerOffGrid => 'Pomakni nišan na mrežu';

  @override
  String get authSectionPlayback => 'Reprodukcija';

  @override
  String get mediaBackgroundPlaybackTitle => 'Reprodukcija u pozadini';

  @override
  String get mediaBackgroundPlaybackSubtitle =>
      'Nastavi slušati kad zaključaš zaslon ili prijeđeš u drugu aplikaciju.';

  @override
  String get mediaPlaybackSpeed => 'Brzina reprodukcije';

  @override
  String mediaPlaybackSpeedSet(String rate) {
    return 'Brzina: $rate×';
  }

  @override
  String get mediaBackgroundPlaybackTooltipOn =>
      'Reprodukcija u pozadini je uključena';

  @override
  String get mediaBackgroundPlaybackTooltipOff =>
      'Reprodukcija u pozadini je isključena';

  @override
  String get mediaBackgroundPlaybackToastOn =>
      'Nastavit će svirati kad izađeš iz aplikacije';

  @override
  String get mediaBackgroundPlaybackToastOff =>
      'Reprodukcija će stati kad izađeš iz aplikacije';

  @override
  String mediaSeekUndo(String time) {
    return 'Natrag na $time';
  }

  @override
  String get mediaSeekUndoTooltip => 'Poništi skok';

  @override
  String personCardMeta(int count, String duration) {
    return 'Osoba · $count ep · $duration';
  }

  @override
  String personVirtualChannelSubtitle(
    int episodes,
    int channels,
    String fromYear,
    String toYear,
  ) {
    String _temp0 = intl.Intl.pluralLogic(
      episodes,
      locale: localeName,
      other: '$episodes epizoda',
      few: '$episodes epizode',
      one: '$episodes epizodi',
    );
    String _temp1 = intl.Intl.pluralLogic(
      channels,
      locale: localeName,
      other: '$channels kanala',
      few: '$channels kanala',
      one: '$channels kanalu',
    );
    return 'Gostuje u $_temp0 na $_temp1, $fromYear.–$toYear.';
  }

  @override
  String personVirtualChannelSubtitleOneYear(
    int episodes,
    int channels,
    String year,
  ) {
    String _temp0 = intl.Intl.pluralLogic(
      episodes,
      locale: localeName,
      other: '$episodes epizoda',
      few: '$episodes epizode',
      one: '$episodes epizodi',
    );
    String _temp1 = intl.Intl.pluralLogic(
      channels,
      locale: localeName,
      other: '$channels kanala',
      few: '$channels kanala',
      one: '$channels kanalu',
    );
    return 'Gostuje u $_temp0 na $_temp1, $year.';
  }

  @override
  String get personSectionEpisodes => 'Epizode';

  @override
  String get personSectionCameo => 'Kratki nastupi';

  @override
  String get personSectionCameoHint =>
      'Epizode u kojima se javlja nakratko — dio šire rasprave, a ne glavni gost.';

  @override
  String get personSourceChannelUntracked =>
      'Ovaj kanal još ne pratimo, pa nema svoju stranicu.';

  @override
  String get personReportError => 'Prijavi grešku';

  @override
  String get personReportErrorThanks =>
      'Hvala na dojavi — provjerit ćemo ovu epizodu.';

  @override
  String get personOptedOut =>
      'Na zahtjev ove osobe više ne prikazujemo popis nastupa na ovom profilu. Epizode ostaju dostupne na svojim stranicama.';

  @override
  String get personFollow => 'Prati';

  @override
  String get personFollowing => 'Pratiš';

  @override
  String get channelFollow => 'Prati';

  @override
  String get channelFollowing => 'Pratiš';

  @override
  String get channelsFilterAll => 'Sve';

  @override
  String get channelsFilterChannels => 'Kanali';

  @override
  String get channelsFilterPersons => 'Osobe';

  @override
  String get homePersonsRailTitle => 'Osobe';

  @override
  String get homeFollowedRailTitle => 'Novo od praćenih';

  @override
  String get searchSectionPeople => 'Osobe';

  @override
  String get tvRailPersons => 'Osobe';

  @override
  String get votingTitle => 'Tko ide sljedeći';

  @override
  String get votingScreenTitle => 'Tko ide sljedeći?';

  @override
  String get votingElectionDayPlain => 'Izborni dan';

  @override
  String votingElectionDay(String date) {
    return 'Izborni dan · $date';
  }

  @override
  String votingRoundLabel(int number) {
    return 'Kolo $number';
  }

  @override
  String votingRoundDaysLeft(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'još $count dana',
      few: 'još $count dana',
      one: 'još $count dan',
    );
    return '$_temp0';
  }

  @override
  String get votingRoundLastDay => 'posljednji dan kola';

  @override
  String votingRoundVotes(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count glasova u kolu',
      few: '$count glasa u kolu',
      one: '$count glas u kolu',
    );
    return '$_temp0';
  }

  @override
  String votingRoundVoters(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count glasača',
      few: '$count glasača',
      one: '$count glasač',
    );
    return '$_temp0';
  }

  @override
  String votingStreakDays(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Niz $count dana',
      few: 'Niz $count dana',
      one: 'Niz $count dan',
    );
    return '$_temp0';
  }

  @override
  String get votingStreakNone => 'Još nemaš niz';

  @override
  String get votingFlagsTooltip =>
      'Zastavica sama spašava propušteni izborni dan. Možeš imati najviše dvije.';

  @override
  String votingFlagsLeft(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count zastavica',
      few: '$count zastavice',
      one: '$count zastavica',
    );
    return '$_temp0';
  }

  @override
  String get votingGuestTitle => 'Ljestvica je javna, glas nije.';

  @override
  String get votingGuestBody =>
      'Izborni dan traje od ponoći do ponoći po hrvatskom vremenu.';

  @override
  String get votingHaveVote => 'Imaš 1 glas. Potroši ga do ponoći.';

  @override
  String votingLossAversion(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Tvoj niz je $count dana — glasaj danas da ne pukne.',
      few: 'Tvoj niz je $count dana — glasaj danas da ne pukne.',
      one: 'Tvoj niz je $count dan — glasaj danas da ne pukne.',
    );
    return '$_temp0';
  }

  @override
  String get votingVotedToday => 'Glas za danas je zabilježen.';

  @override
  String get votingComeBackTomorrow =>
      'Vrati se sutra u 00:00 po hrvatskom vremenu.';

  @override
  String get votingYourVoteToday => 'Tvoj glas danas';

  @override
  String votingAtRiskTitle(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Zastavica brani tvoj niz — $count dana.',
      few: 'Zastavica brani tvoj niz — $count dana.',
      one: 'Zastavica brani tvoj niz — $count dan.',
    );
    return '$_temp0';
  }

  @override
  String get votingAtRiskBody => 'Glasaj danas i niz ide dalje.';

  @override
  String votingAtRiskBurn(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Glasaš li danas, troši se $count zastavica i niz ide dalje.',
      few: 'Glasaš li danas, troše se $count zastavice i niz ide dalje.',
      one: 'Glasaš li danas, troši se $count zastavica i niz ide dalje.',
    );
    return '$_temp0';
  }

  @override
  String votingBrokenTitle(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Niz je stao na $count dana.',
      few: 'Niz je stao na $count dana.',
      one: 'Niz je stao na $count dan.',
    );
    return '$_temp0';
  }

  @override
  String get votingBrokenTitleUnknown => 'Niz je stao.';

  @override
  String votingBrokenLongest(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Najduži ostaje $count dana.',
      few: 'Najduži ostaje $count dana.',
      one: 'Najduži ostaje $count dan.',
    );
    return '$_temp0';
  }

  @override
  String get votingBrokenCta => 'Kreni ispočetka';

  @override
  String get votingVerifyBarTitle => 'Potvrdi se e-Osobnom i glasaj';

  @override
  String get votingVerifyBarBody => 'Jedna osoba, jedan glas svakih 24 sata.';

  @override
  String get votingVerifyCta => 'Potvrdi se';

  @override
  String get votingSortLeaderboard => 'Ljestvica';

  @override
  String get votingSortRandom => 'Nasumično';

  @override
  String get votingSortLeastVotes => 'Najmanje glasova';

  @override
  String get votingSearchHint => 'Traži kandidata…';

  @override
  String get votingTagAll => 'Sve teme';

  @override
  String get votingEmpty => 'Nema kandidata za ovaj odabir.';

  @override
  String get votingEmptyClear => 'Očisti filtre';

  @override
  String get votingLoadFailed => 'Ljestvica se nije učitala.';

  @override
  String get votingVoteUp => 'Glasaj za';

  @override
  String get votingVoteDown => 'Glasaj protiv';

  @override
  String votingNetLabel(int value) {
    return 'Neto rezultat $value';
  }

  @override
  String votingVotesCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count glasova',
      few: '$count glasa',
      one: '$count glas',
    );
    return '$_temp0';
  }

  @override
  String votingSubscribers(String value) {
    return '$value pretplatnika';
  }

  @override
  String get votingSubscribersLabel => 'Pretplatnici';

  @override
  String get votingEpisodesLabel => 'Epizoda (procjena)';

  @override
  String get votingHosts => 'Voditelji';

  @override
  String votingCountThousands(String value) {
    return '$value tis.';
  }

  @override
  String votingCountMillions(String value) {
    return '$value mil.';
  }

  @override
  String get votingStatusWinner => 'Pobjednik';

  @override
  String get votingStatusOnboarding => 'U obradi';

  @override
  String get votingStatusOnboarded => 'Već u aplikaciji';

  @override
  String get votingStatusWithdrawn => 'Povučen';

  @override
  String get votingConsentTitle => 'Ovo nije tajno glasovanje';

  @override
  String get votingConsentBody =>
      'Tvoj je glas u bazi vezan uz potvrđeni identitet. Pojedinačne glasove nikad ne objavljujemo — javni su samo zbrojevi. Glas za kanal s političkim ili vjerskim predznakom može posredno otkriti tvoje uvjerenje, pa ti to kažemo prije prvog glasa.';

  @override
  String get votingConsentAccept => 'Razumijem, glasaj';

  @override
  String get votingAlreadyVoted => 'Glas za danas je već potrošen.';

  @override
  String get votingVoteRecorded => 'Glas je zabilježen.';

  @override
  String votingStreakSaved(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count zastavica spasilo je tvoj niz.',
      few: '$count zastavice spasile su tvoj niz.',
      one: '$count zastavica spasila je tvoj niz.',
    );
    return '$_temp0';
  }

  @override
  String votingStreakBrokeBurned(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Niz je pukao — potrošeno je $count zastavica.',
      few: 'Niz je pukao — potrošene su $count zastavice.',
      one: 'Niz je pukao — potrošena je $count zastavica.',
    );
    return '$_temp0';
  }

  @override
  String get votingErrorNotVerified => 'Za glasanje treba potvrda e-Osobnom.';

  @override
  String get votingErrorCandidateGone => 'Ovaj kandidat više nije u igri.';

  @override
  String get votingErrorRoundClosed => 'Kolo je u međuvremenu zatvoreno.';

  @override
  String get votingErrorGeneric => 'Glas nije zabilježen. Pokušaj ponovno.';

  @override
  String get votingHomeChipTooltip =>
      'Glasaj koji podcast ide sljedeći u obradu';

  @override
  String get votingUnusedVote => 'Imaš neiskorišten glas.';

  @override
  String votingLongestStreak(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Najduži niz $count dana',
      few: 'Najduži niz $count dana',
      one: 'Najduži niz $count dan',
    );
    return '$_temp0';
  }

  @override
  String votingTotalVotes(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count glasova ukupno',
      few: '$count glasa ukupno',
      one: '$count glas ukupno',
    );
    return '$_temp0';
  }

  @override
  String get votingChannelsBarTitle => 'Nema tvog podcasta?';

  @override
  String get votingChannelsBarBody =>
      'Glasaj koji podcast ide sljedeći u obradu.';

  @override
  String get votingChannelsBarCta => 'Glasaj';

  @override
  String get votingRailSeeAll => 'Svi kandidati';

  @override
  String votingRailRank(int rank) {
    return '$rank. mjesto';
  }

  @override
  String get votingRailCtaTitle => 'Glasaj koji ide sljedeći';

  @override
  String get votingRailCtaBody =>
      'Ljestvicu odlučuju građani potvrđeni e-Osobnom.';

  @override
  String get votingAccountVerifyTitle => 'Glasaj koji podcast ide sljedeći';

  @override
  String get votingAccountVerifyBody =>
      'Potvrdi se e-Osobnom i dobivaš jedan glas svaki dan.';

  @override
  String get ebookTooltip => 'E-knjiga epizode';

  @override
  String get ebookSheetTitle => 'E-knjiga';

  @override
  String get ebookEditionHr => 'Hrvatsko izdanje';

  @override
  String get ebookEditionEn => 'Englesko izdanje';

  @override
  String get ebookShareHint =>
      'Šalje se kao datoteka — WhatsApp, e-pošta, Knjige.';

  @override
  String get ebookDownloadHint => 'Preuzima se na uređaj.';

  @override
  String get ebookPreparing => 'Pripremam knjigu…';

  @override
  String ebookDownloaded(String file) {
    return 'Preuzeto: $file';
  }

  @override
  String get ebookFailed =>
      'Knjigu nije bilo moguće dohvatiti. Pokušaj ponovno.';

  @override
  String get ebookCopyLink => 'Kopiraj poveznicu na knjigu';

  @override
  String get ebookLinkCopied => 'Poveznica na knjigu je kopirana';

  @override
  String get ebookRights =>
      'Izdanje je izvedeno iz epizode; prava na izgovoreni sadržaj ostaju izvornom kanalu.';

  @override
  String get ebookCardTitle => 'Ponesi epizodu sa sobom';

  @override
  String get ebookCardBody =>
      'Cijela epizoda kao e-knjiga: poglavlja, slike i poveznice natrag na snimku. Čita se u Knjigama, Play Books ili Kindleu.';

  @override
  String get ebookCardAction => 'E-knjiga (EPUB)';

  @override
  String get sponsorsInVideoTitle => 'Uz podršku';

  @override
  String get sponsorsInVideoIntro =>
      'Partneri koji su omogućili ovu epizodu. Hvala im što podržavaju autore.';

  @override
  String get sponsorsInVideoRoleSponsor => 'Sponzor epizode';

  @override
  String get sponsorsInVideoRolePartner => 'Partner podcasta';

  @override
  String get sponsorsInVideoRoleWardrobe => 'Garderoba';

  @override
  String get sponsorsInVideoRoleStudio => 'Opremanje studija';

  @override
  String get sponsorsInVideoRoleOther => 'Podrška';

  @override
  String get sponsorsInVideoListen => 'Poslušaj poruku sponzora';

  @override
  String get sponsorsInVideoListenRubric => 'Poslušaj sponzoriranu rubriku';

  @override
  String sponsorsInVideoThanksAt(String time) {
    return 'Zahvala na $time';
  }

  @override
  String sponsorsInVideoChapterAt(String time) {
    return 'Poglavlje na $time';
  }

  @override
  String sponsorsInVideoAt(String time) {
    return 'Na $time';
  }

  @override
  String get sponsorsInVideoWebsite => 'Web';

  @override
  String get sponsorsInVideoMore => 'više';

  @override
  String get sponsorsInVideoLess => 'manje';

  @override
  String get sponsorsInVideoEnded => 'Poruka sponzora je završila';

  @override
  String get sponsorsInVideoListenShort => 'Poslušaj';

  @override
  String get sponsorsInVideoRubricShort => 'Rubrika';

  @override
  String sponsorsInVideoMessageAt(String time) {
    return 'Poruka sponzora na $time';
  }

  @override
  String sponsorsInVideoRubricAt(String time) {
    return 'Sponzorirana rubrika na $time';
  }

  @override
  String get ytWatchTitle => 'YouTube video';

  @override
  String get ytWatchOpenEpisode => 'Otvori obrađenu epizodu';

  @override
  String get ytWatchInvalidId => 'Neispravna YouTube poveznica.';

  @override
  String get ytWatchEmbedUnsupported =>
      'Ovaj preglednik ne može prikazati YouTube player unutar stranice, pa se video otvara na YouTubeu.';

  @override
  String get findInEpisodeTitle => 'Pronađi u epizodi';

  @override
  String get findInEpisodeHint => 'Riječ, ime ili fraza';

  @override
  String get findInEpisodeClear => 'Obriši';

  @override
  String get findInEpisodeNoHits => 'Nema pogodaka u ovoj epizodi.';

  @override
  String get findInEpisodeError =>
      'Pretraga trenutno ne radi. Pokušaj ponovno malo kasnije.';

  @override
  String findInEpisodeCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count trenutaka',
      few: '$count trenutka',
      one: '$count trenutak',
    );
    return '$_temp0';
  }

  @override
  String findInEpisodeCountPartial(int shown, int total) {
    return 'Prikazano $shown od $total trenutaka';
  }

  @override
  String get findInEpisodeApproximate => 'Približni pogoci';

  @override
  String get sponsoredLabel => 'Sponzorirano';

  @override
  String sponsoredBy(String brand) {
    return 'Sponzorirano · $brand';
  }

  @override
  String sponsoredPaidBy(String brand) {
    return 'Plaća: $brand';
  }

  @override
  String get sponsoredWebsite => 'Web stranica';

  @override
  String sponsoredAt(String time) {
    return 'Sponzorirani trenutak na $time';
  }

  @override
  String get sponsoredListen => 'Poslušaj';

  @override
  String get sponsoredNow => 'Upravo svira';

  @override
  String get sponsorStoreEntry => 'Oglašavanje';

  @override
  String sponsorStoreTitle(String channel) {
    return 'Oglašavanje na kanalu $channel';
  }

  @override
  String get sponsorStoreIntro =>
      'Izaberi trenutak u epizodi i tvoj brand bit će označen kao sponzor upravo tog dijela. Plaćaš jednom, SEPA uplatom, a oglas ide uživo čim uplata stigne.';

  @override
  String get sponsorStoreEmpty =>
      'Ovaj kanal trenutno nema ponudu sponzorskih trenutaka.';

  @override
  String get sponsorStoreLoadFailed => 'Ponudu nije moguće učitati.';

  @override
  String sponsorStoreFreeCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count slobodnih trenutaka',
      few: '$count slobodna trenutka',
      one: '$count slobodan trenutak',
    );
    return '$_temp0';
  }

  @override
  String sponsorStoreFromPrice(String price) {
    return 'od $price €';
  }

  @override
  String get sponsorStoreAvoidTitle => 'Ne prikazuj me uz…';

  @override
  String get sponsorStoreAvoidHint =>
      'Sigurnost branda biraš ti. Oznake tema su gruba procjena, pa uz svaku epizodu vidiš i njezine stvarne teme.';

  @override
  String get sponsorStoreAllFiltered =>
      'Nijedna epizoda ne odgovara odabranom filtru.';

  @override
  String get sponsorTopicFaith => 'Vjera';

  @override
  String get sponsorTopicPolitics => 'Politika';

  @override
  String get sponsorTopicBusiness => 'Posao i tehnologija';

  @override
  String get sponsorMapTitle => 'Sponzorski trenuci';

  @override
  String get sponsorMapIntro =>
      'Svaki trenutak je dio epizode uz naslov sekcije članka koja u njemu počinje. Poslušaj ga prije kupnje.';

  @override
  String get sponsorMapTopics => 'Teme epizode';

  @override
  String get sponsorStateFree => 'Slobodno';

  @override
  String get sponsorStateHeld => 'Netko upravo plaća';

  @override
  String get sponsorStateSold => 'Zauzeto';

  @override
  String sponsorStateSoldUntil(String date) {
    return 'Zauzeto do $date';
  }

  @override
  String get sponsorStateBlocked => 'Nije u ponudi';

  @override
  String get sponsorZoneZatvaranje => 'Zatvaranje';

  @override
  String get sponsorZoneTijelo => 'Središnji dio';

  @override
  String get sponsorZoneOtvaranje => 'Otvaranje';

  @override
  String sponsorPriceGross(String price) {
    return '$price € s PDV-om';
  }

  @override
  String sponsorRunDays(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'uživo $count dana nakon uplate',
      few: 'uživo $count dana nakon uplate',
      one: 'uživo $count dan nakon uplate',
    );
    return '$_temp0';
  }

  @override
  String get sponsorPick => 'Izaberi';

  @override
  String get sponsorLegend => 'Traka prikazuje cijelu epizodu.';

  @override
  String get sponsorCheckoutTitle => 'Narudžba';

  @override
  String sponsorCheckoutMoment(String range, String zone) {
    return 'Trenutak $range · $zone';
  }

  @override
  String get sponsorCheckoutChange => 'Promijeni trenutak';

  @override
  String get sponsorCreativeSection => 'Oglas';

  @override
  String get sponsorFieldBrand => 'Naziv branda';

  @override
  String get sponsorFieldBrandHelp =>
      'Prikazuje se uz oznaku „Sponzorirano“ i ne može biti anoniman.';

  @override
  String get sponsorFieldTagline => 'Jedna rečenica (neobavezno)';

  @override
  String get sponsorFieldLink => 'Poveznica, https:// (neobavezno)';

  @override
  String get sponsorFieldLogo =>
      'Logo: PNG, JPG ili WebP, najviše 200 kB (neobavezno)';

  @override
  String get sponsorLogoPick => 'Dodaj logo';

  @override
  String get sponsorLogoRemove => 'Ukloni logo';

  @override
  String get sponsorLogoTooBig => 'Logo je veći od 200 kB.';

  @override
  String get sponsorLogoBadType => 'Logo mora biti PNG, JPG ili WebP.';

  @override
  String get sponsorLogoUploadFailed =>
      'Logo nije učitan. Pokušaj ponovno ili nastavi bez njega.';

  @override
  String get sponsorCompanySection => 'Podaci za račun';

  @override
  String get sponsorFieldCompany => 'Naziv tvrtke';

  @override
  String get sponsorFieldOib => 'OIB (neobavezno)';

  @override
  String get sponsorFieldVat => 'PDV ID (neobavezno)';

  @override
  String get sponsorFieldStreet => 'Ulica i kućni broj';

  @override
  String get sponsorFieldCity => 'Grad';

  @override
  String get sponsorFieldPostal => 'Poštanski broj';

  @override
  String get sponsorFieldCountry => 'Država (HR, SI, DE…)';

  @override
  String get sponsorFieldEmail => 'Adresa e-pošte za račun';

  @override
  String get sponsorFieldReference => 'Broj narudžbenice (neobavezno)';

  @override
  String get sponsorPreviewTitle => 'Ovako će oglas izgledati';

  @override
  String get sponsorTermsAccept => 'Prihvaćam uvjete oglašavanja';

  @override
  String get sponsorTermsRead => 'Pročitaj uvjete';

  @override
  String get sponsorTermsTitle => 'Uvjeti oglašavanja';

  @override
  String get sponsorTermsBody =>
      'Oglas se objavljuje automatski čim uplata stigne, bez prethodnog odobrenja, i traje onoliko dana koliko je navedeno uz trenutak.\n\nOglas je označen kao „Sponzorirano“ uz naziv Vašeg branda, sukladno članku 26. Uredbe (EU) 2022/2065.\n\nNije dopušten sadržaj koji je nezakonit, obmanjujući, uvredljiv ili diskriminirajući, kao ni oglašavanje duhanskih proizvoda, oružja, igara na sreću te lijekova na recept.\n\nVlasnik kanala može povući oglas koji krši ove uvjete. U tom slučaju, kao i kad uplata stigne nakon što je trenutak prodan drugome, iznos Vam vraćamo ručno.\n\nCijena uključuje PDV. Račun se izdaje automatski i šalje na adresu e-pošte navedenu u narudžbi.';

  @override
  String get sponsorErrorRequired => 'Obavezno polje';

  @override
  String get sponsorErrorOib => 'OIB nije ispravan';

  @override
  String get sponsorErrorVat => 'PDV ID nije ispravan (npr. HR12345678903)';

  @override
  String get sponsorErrorEmail => 'Adresa e-pošte nije ispravna';

  @override
  String get sponsorErrorLink => 'Poveznica mora počinjati s https://';

  @override
  String sponsorErrorTooLong(int max) {
    return 'Najviše $max znakova';
  }

  @override
  String get sponsorErrorCountry => 'Dvoslovna oznaka države, npr. HR';

  @override
  String get sponsorErrorTerms => 'Za narudžbu je potrebno prihvatiti uvjete.';

  @override
  String get sponsorSubmit => 'Nastavi na plaćanje';

  @override
  String get sponsorSlotTaken =>
      'Netko je upravo uzeo taj trenutak. Karta je osvježena, izaberi drugi.';

  @override
  String get sponsorTooManyHolds =>
      'Već imaš tri neplaćene narudžbe. Plati jednu ili pričekaj da istekne.';

  @override
  String get sponsorSignInRequired =>
      'Za narudžbu sponzorskog trenutka prijavi se. Upisani podaci ostaju u obrascu.';

  @override
  String get sponsorSignInHeadline => 'Prijavi se za narudžbu';

  @override
  String get sponsorSignInSubtitle =>
      'Narudžba, račun i stanje plaćanja vezani su uz tvoj račun.';

  @override
  String get sponsorCheckoutFailed =>
      'Narudžbu nije moguće kreirati. Pokušaj ponovno.';

  @override
  String sponsorCheckoutFieldRejected(String field) {
    return 'Provjeri polje „$field“.';
  }

  @override
  String get sponsorPayTitle => 'Plaćanje';

  @override
  String get sponsorMemoVerbatim =>
      'Opis plaćanja kopiraj doslovno, bez ijedne izmjene. Po njemu sparujemo uplatu s narudžbom. Ako ga knjigovodstvo skrati ili prepiše, uplata se neće spariti automatski.';

  @override
  String sponsorHoldUntil(String time) {
    return 'Trenutak je rezerviran za tebe do $time.';
  }

  @override
  String get sponsorHoldExpired =>
      'Rezervacija je istekla. Ako uplata ipak stigne, a trenutak je još slobodan, dodjeljujemo ga automatski.';

  @override
  String get sponsorWaitingPayment =>
      'Čekamo uplatu. Stranica se sama osvježi kad stigne.';

  @override
  String get sponsorOrderLinkHint =>
      'Spremi ovu poveznicu. Preko nje uvijek vidiš stanje narudžbe.';

  @override
  String get sponsorPaidTitle => 'Uplata je stigla, oglas je uživo';

  @override
  String sponsorPaidUntil(String date) {
    return 'Trenutak je tvoj do $date';
  }

  @override
  String get sponsorUnderpaid =>
      'Uplata je manja od cijene trenutka, pa trenutak nije dodijeljen. Javit ćemo ti se radi povrata ili doplate.';

  @override
  String get sponsorSlotUnassigned =>
      'Uplata je stigla nakon isteka rezervacije, a trenutak je u međuvremenu prodan. Iznos vraćamo ručno.';

  @override
  String get sponsorHidden =>
      'Vlasnik kanala povukao je oglas. Iznos vraćamo ručno.';

  @override
  String get sponsorOrderExpired => 'Narudžba je istekla bez uplate.';

  @override
  String get sponsorOrderFailed => 'Plaćanje nije uspjelo.';

  @override
  String sponsorInvoiceSent(String number) {
    return 'Račun $number poslan je na adresu e-pošte iz narudžbe.';
  }

  @override
  String get sponsorInvoicePending => 'Račun stiže e-poštom nakon obrade.';

  @override
  String get sponsorStatsPending =>
      'Broj prikaza i klikova prikazat ćemo ovdje čim mjerenje bude uključeno.';

  @override
  String get sponsorViewOnEpisode => 'Pogledaj na epizodi';

  @override
  String get sponsorOrderNotFound => 'Narudžba nije pronađena.';

  @override
  String sponsorLeaseEnded(String date) {
    return 'Trenutak je bio uživo do $date';
  }

  @override
  String get sponsorLeavePayTitle => 'Napustiti plaćanje?';

  @override
  String get sponsorLeavePayBody =>
      'Trenutak ostaje rezerviran do isteka, ali QR kod i opis plaćanja više nećeš vidjeti. Stanje narudžbe ostaje na poveznici iz adresne trake.';

  @override
  String get sponsorLeavePayConfirm => 'Napusti';

  @override
  String get notificationsTitle => 'Obavijesti';

  @override
  String get notificationsIntro =>
      'Javit ćemo ti kad stigne nova epizoda. Ti biraš o čemu.';

  @override
  String get notificationsEnable => 'Uključi obavijesti';

  @override
  String get notificationsEnabledStatus => 'Obavijesti su uključene';

  @override
  String get notificationsDeniedTitle =>
      'Obavijesti su isključene u postavkama uređaja';

  @override
  String get notificationsDeniedBody =>
      'Uključi ih u postavkama, pa ćemo ti javljati nove epizode.';

  @override
  String get notificationsOpenSettings => 'Otvori postavke';

  @override
  String get notificationsAllTitle => 'Sve nove epizode';

  @override
  String get notificationsAllSubtitle => 'Otprilike jedna do četiri dnevno';

  @override
  String get notificationsChannelsSection => 'Kanali';

  @override
  String get notificationsCoveredByAll => 'Uključeno kroz Sve nove epizode';

  @override
  String get notificationsSearchHint => 'Traži kanal';

  @override
  String get notificationsQuietHours =>
      'Ne šaljemo obavijesti između 22 i 7 sati.';

  @override
  String get notificationsChannelsError =>
      'Popis kanala trenutno nije dostupan.';

  @override
  String get notificationsAppOnly =>
      'Obavijesti su dostupne u aplikaciji za iOS i Android.';

  @override
  String get notificationsAccountOn => 'Uključene';

  @override
  String get notificationsAccountOff => 'Isključene';

  @override
  String get notificationsBellOn => 'Isključi obavijesti za ovaj kanal';

  @override
  String get notificationsBellOff => 'Javi mi za nove epizode ovog kanala';

  @override
  String get notificationsFollowingLabel => 'Pratiš';

  @override
  String get episodeVariant => 'Varijanta';

  @override
  String episodeVariantNumbered(int n) {
    return 'Varijanta $n';
  }
}
