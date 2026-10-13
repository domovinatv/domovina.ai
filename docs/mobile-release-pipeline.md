# Mobile Release Pipeline — App Store + Google Play

Kompletan pipeline za build i objavu DOMOVINA.ai mobilne aplikacije na
**App Store (TestFlight → Production)** i **Google Play (Internal → Production)**,
maksimalno automatiziran preko store API-ja. Brzi runbook s komandama je u
[`release-mobile.md`](release-mobile.md); ovaj dokument objašnjava arhitekturu,
tokove i zamke.

## Identifikatori

| Stavka | Vrijednost |
|---|---|
| Bundle / Application ID | `ai.domovina` |
| Apple Team | `6SCK58757K` (ITalk d.o.o.) |
| App Store app id | `6781716801` |
| ASC API key id / issuer | `25KYCN22QD` / `69a6de85-…` (.p8 u `~/.appstoreconnect/private_keys/`) |
| Android upload keystore | `android/upload-keystore.jks`, alias `upload` (gitignored) |
| Play service account | `play-publisher@domovina-production.iam.gserviceaccount.com` (JSON u `~/.config/play-publisher/`) |
| GCP projekt | `domovina-production` (androidpublisher API enabled) |

> Tajne (`.p8`, keystore, `key.properties`, SA JSON) **nikad** ne idu u repo.

## Tok cijelog releasea

```mermaid
flowchart TD
    V[pubspec version bump<br/>2.0.x+N] --> B{Build}
    B -->|flutter build appbundle| AAB[app-release.aab<br/>upload-key signed]
    B -->|xcodebuild archive+export<br/>API-key signing| IPA[DOMOVINA.ai.ipa<br/>distribution signed]
    AAB -->|play-upload.sh internal| PI[Play Internal track]
    IPA -->|altool --upload-app| TF[TestFlight]
    PI --> PT[Internal testeri]
    TF --> TFT[TestFlight testeri]
    PI -->|App content forme<br/>console-only| PROD_A[Play Production review]
    TF -->|App Privacy + submit| PROD_I[App Store review]
    PROD_A --> LIVEA[Live na Play Storeu]
    PROD_I --> LIVEI[Live na App Storeu]
```

## iOS: signing + upload (zašto NE `flutter build ipa`)

ITalk team nema certifikat u keychainu niti je Apple ID prijavljen u Xcode,
pa automatsko potpisivanje kroz `flutter build ipa` **pada na exportu**. Umjesto
toga vozimo `xcodebuild` direktno s **App Store Connect API key** autentikacijom
(`-allowProvisioningUpdates`), koji programatski kreira distribution cert +
App Store provisioning profil i registrira capabilitye.

```mermaid
sequenceDiagram
    participant CLI as flutter/xcodebuild
    participant ASC as App Store Connect API
    participant KC as Keychain / Profiles
    CLI->>CLI: flutter build ios --config-only --release (dart-defines)
    CLI->>ASC: xcodebuild archive -allowProvisioningUpdates -authKey…
    ASC-->>KC: kreira Apple Distribution cert + profil (ai.domovina)
    CLI->>CLI: xcodebuild -exportArchive (ExportOptions.plist, app-store-connect)
    CLI->>ASC: altool --upload-app --apiKey --apiIssuer
    ASC-->>CLI: UPLOAD SUCCEEDED → build u obradi → TestFlight
```

**Preduvjeti koji su jednom riješeni preko ASC REST API-ja** (`asc-token.rb` + curl):
registracija bundle ID-a `ai.domovina`, uključen `ASSOCIATED_DOMAINS` capability
(za `applinks:domovina.ai`), kreiran App Review kontakt, age rating 4+,
listing metadata, screenshotovi.

## Android: upload preko Play Developer API

```mermaid
sequenceDiagram
    participant CLI as play-upload.sh
    participant GA as Google OAuth
    participant PA as Play Developer API
    CLI->>GA: gcloud auth (SA JSON) → access token (androidpublisher scope)
    CLI->>PA: edits.insert → editId
    CLI->>PA: edits.bundles.upload (app-release.aab) → versionCode
    CLI->>PA: edits.tracks.update (internal, status=completed)
    CLI->>PA: edits.commit
    PA-->>CLI: AAB live na Internal tracku
```

## Što je automatizirano vs. console-only

```mermaid
flowchart LR
    subgraph API["✅ Automatizirano (store API)"]
        A1[Build + signing]
        A2[Upload na test track]
        A3[Store listing tekst]
        A4[Screenshotovi iPhone/iPad/phone]
        A5[Icon + feature graphic]
        A6[Contact details]
        A7[iOS age rating + review kontakt]
        A8[Bundle ID + capabilities + cert]
    end
    subgraph CON["❌ Console-only (pravne izjave)"]
        C1[App Privacy / Data safety]
        C2[Content rating IARC]
        C3[App access]
        C4[Ads / Target audience]
        C5[Financial features]
        C6[Privacy policy URL - Play]
    end
```

Store **API-ji ne izlažu** policy/compliance izjave (i Apple i Google ih drže
ručnima jer su pravne). Preporučeni odgovori su u [`release-mobile.md`](release-mobile.md).

## Interni testeri (dodano 13. 10. 2026.)

Oba storea imaju po jednu internu grupu koja se zove isto, **„DOMOVINA dev”**.
Dodavanje testera je polu-programsko, i to na različitim mjestima:

- **iOS (TestFlight interna grupa)**: interni tester MORA biti korisnik ASC tima.
  `POST /v1/betaTesters` u internu grupu (`81ae85bd-9194-4606-8fec-51ecfe377a4f`,
  `hasAccessToAllBuilds=true`) za e-mail koji još nije u timu Apple odbija s
  „Tester(s) cannot be assigned”. Redoslijed je zato:
  1. `POST /v1/userInvitations`: uloga `DEVELOPER`, `allAppsVisible:false`,
     `visibleApps=[6781716801]`, `provisioningAllowed:false` (najmanja ovlast).
     Pozivnica vrijedi 3 dana.
  2. Osoba prihvati e-mail od Applea.
  3. Tek tada ide `POST /v1/betaTesters` s relacijom `betaGroups` na internu grupu.

  Vanjski tester (bez pristupa timu) je druga putanja: vanjska grupa, za koju
  svaki build mora proći beta review.
  Napomena: u `curl` URL s `filter[...]` treba `-g`, inače curl uglate zagrade
  čita kao glob i vrati prazan odgovor.
- **Android (Play internal testing)**: `edits.testers` za internal track vodi
  SAMO `googleGroups`, a e-mail liste iz Consolea API ne vidi (`GET` vraća `{}`).
  Pojedinačni e-mail ide ručno: Play Console (developer račun **iTalk Ltd.**,
  `7441230488937961517`) → DOMOVINA.ai → Testing → Internal testing → Testers →
  lista „DOMOVINA dev” → dodaj e-mail → Save changes. Lista vrijedi za cijeli
  developer račun, ne samo za ovu aplikaciju. Tester se zatim mora prijaviti
  preko opt-in linka `https://play.google.com/apps/internaltest/4701741332883961120`.
  Za potpuno programski tok trebala bi Google Grupa vezana uz track (`googleGroups`).

## Screenshotovi

- **Izvor**: debug build na iOS Simulatoru (iPhone 16 Pro Max 6.9" = 1320×2868,
  PT-iPad13-181 = 2064×2752) i fizičkoj Motoroli edge 30 ultra (1080×2400) preko `adb`.
- **Display type enumi (ASC API)**: 6.9"/6.7" iPhone = `APP_IPHONE_67` (NE `APP_IPHONE_6_9`),
  iPad 13" = `APP_IPAD_PRO_3GEN_129`.
- **Upload**: `asc-upload-screenshot.rb` (reserve → PUT binary → commit s md5) za iOS;
  `edits.../phoneScreenshots` za Android.
- **Kurirani setovi**: `store-assets/{ios-iphone,ios-ipad,android,play-graphics}/`.
- **Clean status bar**: iOS `simctl status_bar override`, Android systemui demo mode.
- **PII**: izbjegavati login/account ekrane koji otkrivaju email; koristiti logged-out stanje.

## Zamke (naučeno)

```mermaid
flowchart TD
    G1[Simulator build ostavi x86_64<br/>u objective_c.framework] -->|altool 409<br/>Unsupported Architectures| F1[flutter clean prije release archive]
    G2[ai.domovina 'not available' 409] -->|već registriran pod ITalk| F2[GET bundleIds/&lt;id&gt; potvrdi vlasništvo]
    G3[whatsNew ne može na prvoj verziji] --> F3[izostavi za v1, koristi samo za update]
    G4[hr-HR nije Play locale] --> F4[koristi 'hr']
    G5[APP_IPHONE_6_9 nevažeći enum] --> F5[koristi APP_IPHONE_67]
    G6[build number mora rasti] --> F6[bump prije svakog uploada -75,76,…-]
    G7[universal link otvara Safari u simulatoru] --> F7[deep-nav screenshot radi samo na Androidu -adb-]
```

- **iOS rebuild uvijek**: `flutter clean` → `--config-only` → `xcodebuild archive` →
  `-exportArchive` → `altool`. Ne miješati sa simulator buildovima bez clean-a.
- **Build number**: TestFlight i Play odbijaju ponovljeni `versionCode`/build; uvijek bump.
- **App supports iPad** (`TARGETED_DEVICE_FAMILY = "1,2"`) → iPad screenshotovi su
  **obavezni** za App Store; Android tablet je opcionalan.

## Skripte

| Skripta | Što radi |
|---|---|
| `scripts/build-mobile-release.sh [android\|ios\|all]` | release AAB/IPA s dart-defines iz `.env`; iOS ide kroz `flutter clean` → `--config-only` → `xcodebuild archive`/`-exportArchive` s ASC API key (ne `flutter build ipa`) |
| `scripts/play-upload.sh [internal\|production]` | upload AAB na Play track (SA auth); release name čita iz pubspec-a |
| `scripts/testflight-upload.sh` | upload IPA na TestFlight (`altool` + ASC API key) |
| `scripts/play-promote.sh <vc> [track] [notes-hr]` | promocija VEĆ uploadanog versionCodea na production (bez re-uploada; re-upload istog vc-a pada) |
| `scripts/asc-submit.rb <build> --notes-hr "…" [--notes-en "…"] [--submit]` | iOS pandan: VALID TestFlight build → App Store review (dolje opisan flow). Bez `--submit` samo ispiše plan |

## Production promocija (programski — radi otkad su console forme jednom ispunjene)

- **Android**: `./scripts/play-promote.sh 96 production "Novosti: …"` — edits.insert →
  tracks.update(production, postojeći versionCode, releaseNotes `hr`) → commit.
  Google review krene automatski.
- **iOS** (ASC REST, sve preko `asc-token.rb` JWT-a):
  1. `POST /v1/appStoreVersions` (`versionString`, rel. app) → `PREPARE_FOR_SUBMISSION`
     (lokalizacije se naslijede s prethodne verzije).
  2. `PATCH /v1/appStoreVersionLocalizations/<locId>` s `whatsNew` (obavezno za update).
  3. Pričekaj `processingState=VALID` builda, pa
     `PATCH /v1/appStoreVersions/<id>/relationships/build`.
  4. `POST /v1/reviewSubmissions` (platform IOS) → `POST /v1/reviewSubmissionItems`
     (rel. appStoreVersion) → `PATCH reviewSubmissions submitted=true` → `WAITING_FOR_REVIEW`.
  - `ITSAppUsesNonExemptEncryption=false` u Info.plist → nema export-compliance prompta.
| `scripts/asc-token.rb` | mint ASC API JWT (ES256) |
| `scripts/asc-upload-screenshot.rb <locId> <displayType> <png>` | upload iOS screenshota |
