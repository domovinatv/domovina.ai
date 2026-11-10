# Naslovnica: tri varijante layouta iza `?home=a|b|c` (plan, 10. 11. 2026.)

Status: **plan, ništa nije implementirano.** Skice: Claude Design canvas
„Naslovnica — opcije layouta” (privatan artifact, link u handoffu).

## Problem

Današnji redoslijed slivera u `packages/podcast_core/lib/screens/home/home_screen.dart`
(`CustomScrollView`, ~r. 478–712):

1. `HomeAppBar`, `_HomeHeader`
2. `HeroCarousel` (latch, `HeroSkeleton` iste visine)
3. `VotingRail` (skriven, `flags.voting == false`)
4. Nastavi slušati (`EpisodesRail`, `continueWatching`)
5. Novo od praćenih (`FollowedRail`)
6. Istaknute emisije (`HomeFeed.featuredShows`)
7. Najnovije (`HomeFeed.latestEpisodes`)
8. Upravo stiglo (`HomeFeed.freshlyArrived`, neobrađene)
9. U korpusu (`CatalogDayRail`)
10. Osobe (`PersonsRail`)
11. Tvoje spremljeno (`FavoritesRail`)
12. CTA svi kanali, `HomeFooter`

Semantički nered: **tri raila odgovaraju na isto pitanje „što je novo”** (7, 8,
9) i nisu jedan do drugog po smislu nego po povijesti dodavanja; **osobno je
razbijeno** (4–5 gore, 11 na dnu). Sve tri varijante zato grupiraju u tri zone:
**Za tebe / Novo / Otkrij**.

## Varijante

| | Desktop | Mobitel | Novi widgeti |
|---|---|---|---|
| **A · Tri police** | hero; zone s naslovom + podnaslovom; „Novo” = JEDAN rail s filtrom *Obrađeno / U obradi / Danas u korpusu*; Spremljeno kao kartica u „Za tebe”; kanali mali grid | isto, vertikalno; „Novo” kao lista s malim thumbom | filtar-rail „Novo”, zaglavlje zone |
| **B · Novine** | 2 stupca: lijevo hero + „Najnovije” kao gusta lista (naslov, kanal, trajanje, Magisterium/„U obradi”), desno 380 px bočna traka (Nastavi, Od praćenih, brojač „Danas u korpusu”); „Otkrij” ispod preko cijele širine | tabovi *Za tebe / Novo / Otkrij* na vrhu umjesto jednog scrolla | lista epizoda, bočna traka, tabovi |
| **C · Prvo ti** | ako postoji nedovršena epizoda: velika kartica „Nastavi” + 3 manja; hero sažet u red od 3 „Istaknuto danas”; „Novo” filtar počinje s *Od praćenih*; „Otkrij” = tri pločice (Emisije, Osobe, Kanali) | kartica Nastavi, rail istaknutog, lista Novo, pločice; donja navigacija (Početna, Traži, Spremljeno, Račun) | resume kartica, pločice, donja nav (samo skica — vidi otvoreno) |

Gost bez povijesti: zona „Za tebe” se skriva (A, B), C pada na hero kao danas.

Preporuka iz sesije: **A kao osnova + C-ova kartica „Nastavi” kad postoji
nedovršena epizoda.** Odluka čeka gledanje nad stvarnim podacima.

## Implementacijski ugovor

1. **Postojeća naslovnica ostaje bajt-za-bajt ista** za sve bez parametra.
   Jedina promjena u `home_screen.dart`: na mjestu `return CustomScrollView(...)`
   grananje `if (variant != null) return buildHomeVariant(variant, data, …)`.
2. Novi folder `packages/podcast_core/lib/screens/home/variants/`:
   `home_variant.dart` (enum + čitanje parametra), `home_variant_data.dart`
   (jedan objekt s već izračunatim `featuredPicks`, `allVids`,
   `continueWatching`, `freshlyArrived`, `channels`, `isMobile`, callbackovima),
   `home_variant_a.dart`, `_b.dart`, `_c.dart`.
3. **Nula novih mrežnih poziva** — varijante samo drugačije slažu podatke koje
   build već ima i reuseaju `EpisodesRail`, `EpisodeRailCard`, `FollowedRail`,
   `CatalogDayRail`, `PersonsRail`, `FavoritesRail`, `HeroCarousel`. Hero latch i
   `HeroSkeleton` visina vrijede i ovdje (`test/hero_slot_layout_test.dart`).
4. Parametar `?home=a|b|c` po uzoru na `services/person_channel_flag.dart`
   (`?vk=`): pamti se u localStorage da preživi navigaciju unutar aplikacije;
   `?home=0` briše. Nepoznata vrijednost = današnji layout.
5. Tekstovi zona (Za tebe / Novo / Otkrij, podnaslovi, filtri) su privremeno
   Dart konstante u `variants/` — **svjesna iznimka** od ARB pravila dok se ne
   izabere pobjednik; tada idu u `app_hr.arb`/`app_en.arb`. Bez emojija,
   registar „ti”.
6. Padding listi unutar scrollabla (pravilo iz CLAUDE.md), `CachedThumbnail` s
   `width`, `drillDown` za navigaciju — isti ugovori kao ostatak aplikacije.

## Provjera

- `flutter analyze` iz korijena, `cd packages/podcast_core && flutter test`.
- Test: bez parametra se gradi isti sliver popis kao prije (regresijska vrata).
- Lokalni web build, sve tri varijante na 390 px i 1440 px nad produkcijskim
  CDN-om (build web → lokalni server → preglednik).
- Deploy samo na izričit zahtjev; u produkciji parametar nikome ništa ne mijenja.

## Otvoreno

- Donja navigacija u C dira globalni chrome, ne samo naslovnicu — u prvom
  prolazu vjerojatno izostaviti ili ograničiti na `?home=c`.
- Filtar „U obradi” i „Danas u korpusu” u spojenom railu: prvi je
  `freshlyArrived` (listing), drugi `CatalogDayRail` (katalog, Worker + D1) —
  različiti izvori, pa filtar mijenja izvor, ne samo predikat.
- Analitika: `screen_view` se ne mijenja; ako treba usporedba varijanti, novi
  događaj povlači pravne dokumente (CLAUDE.md, „Vlastita analitika”).
