# Deklaracije za store: App Store „App Privacy” i Google Play „Data safety”

Obje forme su **console-only**: store API-ji ih ne izlažu, pa ih upisuje čovjek
(`docs/mobile-release-pipeline.md`). Ovaj dokument je izvor odgovora. Mijenja
se zajedno s Obradom E u [`data-protection.md`](data-protection.md) i s
politikom privatnosti (`legalPrivacyAnalytics*`), kad god se mijenjaju
događaji analitike.

_Stanje: 15. 10. 2026., v2.0.188. Upisano u konzole: ‹datum, tko›._

Nacrt kao i ostatak direktorija (vidi [`README.md`](README.md)). Redovi
označeni ‹provjeriti› ne dolaze iz analitike nego iz drugih obrada.

## Iz čega dolaze odgovori

| Događaj / polje (`domovina-analytics/docs/ugovor.md`) | Apple kategorija | Google kategorija |
|---|---|---|
| `device_id` (nasumičan, trajan) | Identifiers → Device ID | Device or other IDs |
| `user_id` (prijavljeni; `identify`, `sign_out`) | Identifiers → User ID | Personal info → User IDs |
| `screen_view`, `session_start`, `heartbeat`, `app_background`, `playback_*`, `episode_find` (skokovi) | Usage Data → Product Interaction | App activity → App interactions |
| `search.q`, `episode_find.q` (tekst upita) | Search History | App activity → In-app search history |
| `sponsored_*` (prikaz i klik na sponzorsku poruku) | Usage Data → Advertising Data | App activity → App interactions |
| `push_*` (pitanje za dozvolu, ishod, tema uključena/isključena, tap na obavijest) | Usage Data → Product Interaction | App activity → App interactions |
| država/regija/grad (Cloudflare iz IP-a; IP se ne sprema) | Location → Coarse Location | Location → Approximate location |
| vrsta uređaja, OS, preglednik, veličina zaslona, verzija aplikacije | (nije zasebna kategorija; dio Product Interaction) | (nije zasebna kategorija) |

## App Store Connect → App Privacy

Za svaki tip podatka iz tablice:

- **Linked to the user's identity:** **Da.** Događaji prijavljenog korisnika
  nose `user_id`, a gostovi trajan `device_id`.
- **Used for tracking:** **Ne.** Podaci se ne spajaju s podacima drugih
  tvrtki i ne dijele se s brokerima. Zato ne treba ni ATT prompt.
- **Purposes:** **Analytics** za sve. Coarse Location i Advertising Data uz to
  i **Developer's Advertising or Marketing** jer se njima mjeri prikaz
  plaćenih sponzorskih poruka ‹provjeriti s pravnikom; ako se mjerenje ne
  koristi za naplatu, ostaje samo Analytics›.

**Push obavijesti (Obrada F, od 15. 10. 2026.):** FCM token je
Identifiers → Device ID, svrha **App Functionality**, Linked: Ne (ne vežemo ga
uz račun i ne spremamo ga). Apple pitanje „Used for tracking" ostaje Ne.

Ostalo iz drugih obrada ‹provjeriti›: Contact Info → Email Address (račun,
App Functionality); Contact Info → Name (Certilia KYC, App Functionality);
Purchases → Purchase History (RevenueCat pretplate, App Functionality).

## Google Play Console → Data safety

- **Does your app collect or share any of the required user data types?** Da.
- **Is all of the user data collected by your app encrypted in transit?** Da (HTTPS).
- **Do you provide a way for users to request that their data is deleted?**
  Da: brisanje računa u aplikaciji; događaje analitike briše se na zahtjev na
  e-mail iz politike privatnosti (Obrada E).

Za svaki tip iz tablice:

- **Collected:** Da. **Shared:** Ne. Cloudflare i Oracle Cloud su izvršitelji
  obrade (service providers), što Google ne računa kao dijeljenje.
- **Processed ephemerally:** Ne.
- **Required or optional:** Required. Korisnik analitiku ne može isključiti.
- **Purpose:** Analytics. Za Approximate location i App interactions uz
  sponzorske poruke i **Advertising or marketing** ‹isto kao kod Applea›.

**Push obavijesti (Obrada F):** Device or other IDs (FCM token) —
Collected: Da, Shared: Ne (Google je izvršitelj), Optional (korisnik ih
uključuje sam), Purpose: **App functionality**.

Ostalo iz drugih obrada ‹provjeriti›: Personal info → Email address, Name
(račun, KYC; App functionality, Account management); Financial info →
Purchase history (pretplate).
