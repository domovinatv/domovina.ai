# Odluke — postavke kanala

Svaka odluka ima broj, datum, razlog i, ako je pretpostavka, uvjet pod kojim se revidira.
Svaka sesija numerira od svog bloka iz [plan.md](plan.md) (S1 od 100, S2 od 200, …).
Odluka se ne briše: zamijeni je novom koja je poziva.

## S0 (2026-11-11, planiranje)

1. **Prekidači (20 ključeva, zadano `true`).** Ključevi su ugovor između svih potrošača i
   ne preimenuju se:

   | skupina | ključ | isključeno znači |
   |---|---|---|
   | glavni | `channel_enabled` | kanal povučen iz cijele domovina.ai; svi ostali se tretiraju kao isključeni |
   | prisutnost | `processing` | nove epizode se ne preuzimaju ni obrađuju |
   | prisutnost | `home_featured` | nema u heru, „Upravo stiglo”, railovima, „Danas u korpusu” |
   | prisutnost | `in_app_search` | nema u paleti pretrage (lokalno, Meili, semantika) |
   | prisutnost | `search_engines` | `noindex`, izostaje iz sitemapa |
   | prisutnost | `push_notifications` | nema push obavijesti za nove epizode |
   | medij | `cdn_playback` | nema reprodukcije s našeg CDN-a; samo službeni YouTube player |
   | medij | `share_clips` | nema isječaka po poglavlju, 9:16 rendera ni OG slika po trenutku |
   | medij | `ebook` | nema EPUB-a |
   | AI | `article_summary` | nema članka ni sažetka |
   | AI | `transcript_subtitles` | nema transkripta, titlova ni „Pronađi u epizodi” |
   | AI | `english_translation` | nema `/en` izdanja |
   | AI | `magisterium` | umjesto ocjene stoji „Vlasnik je isključio procjenu” |
   | AI | `highlights_reels` | nema istaknutih trenutaka |
   | AI | `persons_mentions` | epizode kanala ne ulaze u `/p/` profile i virtualne kanale |
   | AI | `news_portal` | epizode kanala ne koriste se za članke na portalu vijesti |
   | AI | `ai_assistants` | izostaje iz MCP-a i semantičkog korpusa |
   | novac | `donations` | nema zida podrške ni donacija |
   | novac | `paid_sponsor_moments` | nema izloga ni prodaje sponzorskih trenutaka |
   | novac | `sponsors_in_video` | nema sekcije „Uz podršku” |

   Razlog: inventura od 11. 11. 2026. (chat S0) nad funkcionalnostima opisanima u
   korijenskom `CLAUDE.md`. TV, Cast i analitika nisu prekidači (način isporuke, ne
   sadržaj). Revizija: nova funkcionalnost nad sadržajem kanala dobiva svoj ključ.
2. **Magisterium je prekidač** (odluka korisnika 11. 11. 2026.), ali se ne skriva tiho:
   na mjestu ocjene stoji „Vlasnik je isključio procjenu”.
3. **Pišu primarni vlasnik i suradnik** (odluka korisnika 11. 11. 2026.): `role in
   ('primary','collaborator')`, `status = 'verified'`, `verified_at` mlađi od 90 dana
   (pravilo D4 iz `docs/channel-ownership-and-safe-payout-plan.md`). Isto vrijedi za
   zahtjev za brisanje i njegovo otkazivanje.
4. **Kronološki log svake promjene** (zahtjev korisnika): `channel_settings_events`
   append-only (ključ, stara i nova vrijednost, račun, uloga, vrijeme, izvor `app` /
   `phone` / `system`). Vlasnik i suradnici kanala ga vide na ekranu, od najnovijeg.
5. **Trajno brisanje = potvrda u aplikaciji + telefonski poziv na +385 98 967 9022**
   (zahtjev korisnika). Tek nakon poziva operater (service_role) potvrđuje zahtjev, a
   skripta brisanja `channel-delete.sh` (nastaje u S9) briše R2 (uz purge obje `Vary: Origin` varijante), Meili,
   RAG, vijesti, push teme i katalog. Vlasnik može otkazati zahtjev dok poziv nije
   potvrđen. Nema dodatnog vremenskog odmaka: poziv je potvrda. Broj je javan (repo i
   aplikacija su javni).
6. **Tombstone u katalogu je trajan** (zahtjev korisnika): UC id, ime kanala, slugovi,
   vrijeme zahtjeva, vrijeme potvrde poziva, vrijeme brisanja. Ne briše se nikad; pipeline
   ga čita kao blokadu.
7. **Ključ postavki je UC id**, ne slug: slugovi iz playlista dijele isti UC
   (`katalog/migrations/0001_init.sql`), pa postavka vrijedi za sve. Kanali bez UC id-a
   nemaju vlasnika na ovoj platformi dok S1 ne izmjeri koliko ih je.
8. **Isključen AI prekidač u v1 sakriva postojeće i ne generira nove artefakte**; postojeće
   datoteke ostaju na R2 do trajnog brisanja kanala. Revizija: ako vlasnik zatraži brisanje
   jednog artefakta, uvodi se brisanje po ključu.
9. **Lanac živi u `postavke-kanala/`**, a kod u postojećim mjestima: `packages/podcast_core/`,
   `katalog/`, `web/_worker.js`, i u repoima `domovina-api`, `fetch.domovina.tv`,
   `domovina-rag`, `domovina-push`. Rad u drugom repou ide iz sesije u tom repou.
10. **Paralelni lanci** `katalog/` i `vijesti/`: ovaj lanac im ne mijenja dokumente; izmjene
    koda u `katalog/` idu samo kad katalog nema necommitanih izmjena, a migracija uzima
    prvi slobodan broj.
