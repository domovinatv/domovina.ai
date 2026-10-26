# MVP sponzorskih trenutaka — zaključak frontenda

*7.10.2026. Plan: [`2026-10-06-mvp-sponzorski-trenuci-domovina-tv.md`](2026-10-06-mvp-sponzorski-trenuci-domovina-tv.md)
(§0, §1, §2.2, §3). Ugovor: `domovina-api/docs/sponzorski-trenuci-ugovor.md` v1.
Ništa nije deployano.*

## Gotovo

| Komad | Gdje |
|---|---|
| Izlog `/c/:slug/oglasi`: epizode, oznaka teme + stvarne teme, filtar „Ne prikazuj me uz…", broj slobodnih, cijena od, mini traka | `lib/screens/sponsor/sponsor_store_screen.dart` |
| Karta `/v/:id/sponzoriraj`: vremenska traka (slobodno / netko plaća / zauzeto do), naslov sekcije, zona, cijena, trajanje, „Poslušaj" (→ `/v/<id>/t/<start>`) | `lib/screens/sponsor/sponsor_episode_screen.dart`, `lib/widgets/sponsor_timeline_bar.dart` |
| Checkout: kreativa, logo (web), podaci tvrtke, pregled oglasa istim widgetom kao u playeru, kvačica + uvjeti (formalno „Vi") | `lib/screens/sponsor/sponsor_checkout_form.dart` |
| Plaćanje: isti SEPA blok kao zid podrške (izvučen u `PinkaSepaQr`), uputa „kopiraj doslovno", istek holda, poveznica na narudžbu `?narudzba=<id>` | `lib/pinka_sdk/src/widgets/pinka_sepa_qr.dart` |
| Stanje narudžbe: pending → plaćeno / manjak / nedodijeljeno / povučeno / isteklo, račun | `sponsor_order_status` u istom ekranu |
| 409 `slot_taken` → natrag na kartu sa svježim stanjem; `too_many_holds`, `invalid_sponsor:<polje>` → poruka uz polje | `PinkaClient.contributeSponsor` |
| Prikaz plaćenog trenutka (`SponsoredMoment`): oznaka preko videa (i u fullscreenu), traka u `VideoPanel`, traka u `_PlayerTab`, oznaka u sekciji članka po vremenu, zlatni pojas na seek baru, `rel="sponsored"` | `lib/models/sponsored_moment.dart`, `lib/widgets/sponsored_moment_widgets.dart`, `lib/services/sponsored_moments_controller.dart` |
| Rute u `app_router.dart` + OG u `web/_worker.js` + `scripts/test-social-tags.mjs` | |
| 95 ARB ključeva (HR template + EN) | `lib/l10n/` |

**Usput popravljeno:** `PinkaClient.contribute` je 409 tražio u `res.data`, a
`functions.invoke` za svaki ne-2xx baca `FunctionException`. Sudar oko
kvadratića na zidu podrške završavao je kao generička „uplata nije kreirana".
Sada obje grane idu kroz `_invokeContribute` i bacaju `PinkaSlotTaken`.

## Provjereno

- `flutter analyze` čist; `flutter test` zelen osim dva poznata iz
  `.nightly/test-baseline.txt`.
- Novi testovi: `sponsored_moment_contract_test.dart` (stvarni odgovori
  lokalnog backenda), `sponsored_moments_test.dart` (mjerenje, sidrenje, teme,
  tijelo narudžbe, mapiranje grešaka preko `MockClient`),
  `sponsored_moment_layout_test.dart` (320 i 360 dp, HR i EN, najdulji brand i
  rečenica).
- `test-social-tags.mjs` nad lokalnim workerom (Node harness s mockanim
  `ASSETS`): 185/185, uključujući obje nove rute.
- `flutter build web --release --wasm` prolazi.
- Pravi Chrome (Playwright, headed), `--wasm` build nad lokalnim Supabaseom:
  izlog i karta s 79 trenutaka; narudžba `pending` → simulirani `intent.paid`
  (`mark_contribution_paid` nad lokalnom bazom) → stranica sama prijeđe u
  „Uplata je stigla, oglas je uživo"; na `/v/WRE248YCIeI/t/33` oznaka preko
  videa, traka „Upravo svira", „Plaća: Testni Brand" u članku i log
  `impression WRE248YCIeI@33` jednom; na `/m/…` (390 px, put kojim ide i
  audio-only) traka ispod kontrola.

## Code review prije commita (10 nalaza, 9 popravljeno)

- Istek zakupa usred slušanja: kontroler ponovno filtrira po `live_until`
  uz poziciju (oznaka, traka, pojas i mjerenje nestaju).
- Back iz plaćanja pita (`PopScope` + dijalog); narudžba ide u adresnu traku
  (`?narudzba=`) čim se intent kreira.
- Unos forme preživi 409 i „Promijeni trenutak" (`SponsorCheckoutFormData`
  pripada ekranu).
- Oznaka preko videa je iznad `UnmuteOverlay` i niže u fullscreenu (ne
  preklapa `_SpeakerBadge`).
- Potvrda razlikuje „uživo" od „zakup je istekao" (`isLiveAt`).
- Polling: nakon `paid` čeka broj računa (≤ 10 min); nepostojeća narudžba
  staje nakon 3 prazna odgovora.
- Rasponi za seek bar računaju se jednom (painter uspoređuje identitet).
- Traka izloga ne baca na širini 0 i ne izlazi preko desnog ruba.
- Greška u tijelu kao String se parsira.
- **Nije mijenjano:** kampanja je u klijentu fiksna (`SponsorCampaign`).
  Svjesno za MVP (ugovor O1, jedna kampanja); druga kampanja ili kanal
  traže ili release ili RPC „kampanja za kanal" u ugovoru v2.

## Nije provjereno / stubano

| Što | Zašto | Kad se mijenja |
|---|---|---|
| Forma → `pinka-contribute` → SEPA panel u pregledniku | Lokalni edge runtime nema `PINKA_INTENTS_URL`, pa bi intent otišao na **produkcijski** `mpt.domovina.ai`. Nije poslano. Panel je isti widget kao na zidu podrške; mapiranje grešaka je pokriveno testom. | backend postavi lokalni stub raila |
| Mjerenje se ne sprema | Ugovor v1 nema tablicu ni RPC za događaje. Detekcija radi i logira (`LogSponsoredMomentSink`); potvrda kaže „brojke čim mjerenje bude uključeno". | ugovor v2: insert-only zapis + čitanje po narudžbi |
| Teme epizode (vjera / politika / posao) | Ugovor nema kategoriju; `SponsorTopic` je eksplicitan popis korijena nad `topics` iz listinga. Uz oznaku se uvijek vide i stvarne teme. | kolona u bazi (ugovor v2), fajl se briše |
| Upload loga | Lokalni Storage je zaustavljen; na nativeu nema pickera (web-only `<input type=file>`, bez novog paketa zbog `--wasm`). | |
| Tekst uvjeta | Nacrt, nije pravno pregledan (plan §5 P4). | pravnik |

## Čeka backend (`domovina-api`)

1. **Sponzorska kampanja curi u zid podrške.** Na epizodi `domovina_tv`
   traka na dnu piše „Sponzorski trenuci — DOMOVINA TV · Prikupljeno 370 € ·
   5 podržavatelja · Podrži": `active_campaign_for_subject` vraća sponzorsku
   kampanju preko `campaign_subjects`. To krši ugovor O2 („ne smije ući u zid
   podrške ni u statistiku donacija"). Popravak je u RPC-u (isključiti
   kampanje s `timeline` kartom ili `unlisted`), ne u klijentu. **Blokira
   go-live.**
   **Reproducirano na produkciji 26.10.2026.** (v2.0.200,
   `https://domovina.ai/v/WRE248YCIeI/t/1475`, gost): traka piše „Sponzorski
   trenuci — DOMOVINA TV · Prikupljeno 0 € · 0 podržavatelja · Podrži”. Vidi
   ga dakle svaki posjetitelj epizoda `domovina_tv`, ne samo lokalna baza.
2. Lokalno: `enable_anonymous_sign_ins` je isključen u `config.toml`, pa
   checkout lokalno nema sesiju (`401 not_authenticated`). E2E je išao s
   testnim korisnikom.
3. Lokalno: `PINKA_INTENTS_URL` za stub raila (gore).
4. Mjerenje i kategorija epizode (gore).

## Čeka tebe

- Deploy (samo s `main`), nakon što backend migracije i popravak 1 budu u
  produkciji. Prije toga `/c/domovina-tv/oglasi` u produkciji prikazuje
  „Ponudu nije moguće učitati".
- Pravni tekst uvjeta i oznake (P4), cjenik i `run_days` (P5).
- Lokalna baza nosi testnu narudžbu `ed7342b5…` („Testni Brand",
  `WRE248YCIeI@33`, plaćena simulacijom) i testnog korisnika
  `sponsor-e2e-*@example.test`. Ne smetaju ničemu u produkciji; obriši ih
  kad backend sesija završi testiranje.

## Reprodukcija

```bash
flutter test test/sponsored_moment_contract_test.dart test/sponsored_moments_test.dart test/sponsored_moment_layout_test.dart
node scripts/test-social-tags.mjs http://localhost:8788   # worker lokalno (vidi gore) ili produkcija nakon deploya
```

## Gašenje anonimnih prijava — audit frontenda (8.10.2026., implementirano, nedeployano)

Backend je u `domovina-api` `6d6947e` (ugovor v2 §9, zaključak §7) prešao na
gostujuću donaciju: klijent **nigdje** ne smije zvati `signInAnonymously`, a
sponzorski checkout, logo i svaka rezervacija mjesta traže pravi račun
(`401 login_required`). Stanje frontenda:

| Mora se mijenjati | Danas | Promjena |
|---|---|---|
| `lib/main.dart` (start) | anonimna prijava pri pokretanju | maknuti; bez sesije = gost |
| `AuthService.signOut` | nakon odjave nova anonimna sesija | odjava ostavi gosta bez sesije |
| `AuthService.deleteAccount` | isto | isto |
| `PinkaClient.ensureSession` | anonimna prijava prije donacije / previewa / checkouta | gost donira bez sesije; checkout traži račun |
| `PinkaContributePanel` s mjestom (grid, sjedalo) | generička greška | `login_required` → postojeći `onSignInRequested` |
| `SponsorEpisodeScreen` | `ensureSession` pa checkout | prijava prije forme / na `login_required` |

**Već kompatibilno:** `AuthService.isAnonymous` vraća `true` i bez korisnika
(`?? true`), pa gost traka, paywall, handoff i favoriti nudge rade isto.
`watch_progress`, favoriti, novčanik i ownership već provjeravaju
`user == null` i padaju na lokalno. Postojeće anonimne sesije rade do gašenja u
GoTrueu, a zatim istekom postaju gost bez rušenja.

**Redoslijed je ugovor:** ovaj frontend NE smije u produkciju prije koraka 1
backendovog redoslijeda (migracije + `pinka-contribute` s gostujućom granom) —
stari produkcijski backend donaciju bez sesije odbija.

**Turnstile — otvorena odluka.** Ugovor traži token za gostujuću donaciju
(backend ga provodi tek kad je postavljen `TURNSTILE_SECRET_KEY`). Zamke:

- Web: Turnstile crta iframe s `challenges.cloudflare.com`, a naš
  `COEP: credentialless` odbija svaki tuđi iframe bez atributa `credentialless`
  postavljenog prije `src` — radi u Chromeu/Edgeu, **ne u Safariju ni Firefoxu**
  (isti mehanizam kao YouTube embed, CLAUDE.md „COEP zabranjuje SVAKI tuđi iframe").
- iOS/Android: Turnstile nema nativni SDK; samo WebView.

**Odluka (8.10.2026.): bez Turnstilea.** Frontend ne šalje token,
`TURNSTILE_SECRET_KEY` na backendu MORA ostati nepostavljen (inače svaka
gostujuća donacija dobije `403 captcha_failed`). Limit 30 / sat / IP štiti
donaciju bez mjesta, a mjesta (P9) već traže račun.

### Implementacija (8.10.2026.)

- `signInAnonymously` maknut iz `main.dart`, `AuthService.signOut`,
  `AuthService.deleteAccount`; `PinkaClient.ensureSession` je obrisan
  (`contribute`, `contributeSponsor`, `linkPreview` idu bez njega).
- `PinkaClient._invokeContribute`: `login_required` → `PinkaLoginRequired`
  (i za donaciju i za sponzora); `rate_limited` ostaje `PinkaFailure` s kodom.
- `PinkaContributePanel`: `login_required` → poruka
  `pinkaSlotSignInRequired` + gumb „Prijavi se" (`onSignInRequested`), u SEPA
  i on-chain grani; `rate_limited` → `pinkaGuestRateLimited`.
- `SponsorEpisodeScreen`: odabir trenutka traži prijavu prije forme
  (`_pick`); `_submit` ponovno provjeri račun i obradi `login_required` bez
  gubitka `_formData`. Nakon web OAuth redirecta korisnik se vraća na kartu i
  ponovno bira trenutak (odabir se ne pamti preko redirecta).
- Testovi: `test/no_anonymous_sign_in_test.dart` (tripwire, provjereno da
  pada), `sponsored_moments_test.dart` (gost bez sesije šalje samo
  `pinka-contribute` s `Bearer <anon>`, `login_required`, `rate_limited`),
  `pinka_contribute_panel_test.dart` (gumb prijave na `login_required`).

**Nije provjereno**: lokalni e2e protiv backenda `6d6947e` (gost donacija bez
sesije, gost s kvadratićem → 401, sponzorski checkout s prijavom).

## Review nakon produkcije (8.10.2026.)

Nalazi i redoslijed popravaka: [`../2026-10-08-review-sponzorski-trenuci-frontend.md`](../2026-10-08-review-sponzorski-trenuci-frontend.md).
Backend: `domovina-api/docs/review-2026-10-08-sponzorski-trenuci.md`.
