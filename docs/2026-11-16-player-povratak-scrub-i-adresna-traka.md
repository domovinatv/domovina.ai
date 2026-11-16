# Player: titl ispod, oblačić na seek baru, pametni povratak, `?autoplay`, adresna traka

16. 11. 2026., v2.0.239–v2.0.246. Pravila su u CLAUDE.md („Kontrole reprodukcije”);
ovdje su razlozi, pragovi i ono što je ostalo otvoreno.

## Što je napravljeno

| verzija | promjena | glavne datoteke |
|---|---|---|
| 2.0.239 | titl ispod playera svugdje osim mobitela u landscapeu i fullscreena; isti izgled kao overlay | `widgets/subtitle_caption.dart` (`subtitlesBelowPlayer`, `captionTextStyle`…) |
| 2.0.240–241 | oblačić s vremenom i punim imenom poglavlja iznad seek bara (hover + drag), seek na cijelu sekundu | `widgets/scrub_preview.dart`, `video_panel.dart`, `episode_video.dart`, `_ScrubSlider` u `episode_simple_screen.dart` |
| 2.0.242–243 | pametni povratak: sidro je mjesto gledanja, drži se kroz sve skokove | `services/seek_undo.dart`, `SeekUndoPill` |
| 2.0.244–245 | `?autoplay=0` i YouTube `?t=`; pilula „Natrag na X \| Nastavi odavde” | `router/url_params.dart`, `services/player_resume.dart` |
| 2.0.246 | adresna traka miruje dok je korisnik u njoj | `services/url_sync_web.dart` |

## Pametni povratak — pragovi

Svi u `services/seek_undo.dart`, birani bez mjerenja na korisnicima:

- prag skoka 2 s (ne ispod 1 s — pri 2,0× prirodni pomak je ~0,4 s po eventu);
- mjesto gledanja = ≥ 15 s neprekidne reprodukcije, ili pouzdano slijetanje (resume, URL `t`);
- pilula je „svježa” 8 s, zatim chip;
- ponuda nestaje: ručni skok unutar 10 s od sidra, prirodno dolaženje do sidra,
  2 min mirnog gledanja na novom mjestu, „Nastavi odavde”, ili sam povratak.

Odbačeno: `suppress()` na tap poglavlja (stara odluka D2) — upravo skakanje po
poglavljima je slučaj kad korisniku treba povratak.

Zamka (2.0.245): s `?autoplay=0` pauzirani player kasno javi seek na `t`, pa je
prvi event na 0 postao mjesto gledanja i iskočilo je „Natrag na 0:00”. Prvi event
na 0 se zato ne smatra pouzdanim.

## Adresna traka (2.0.246)

Browser nema događaj „fokus u adresnoj traci”. Klik u nju skida fokus sa
stranice, pa `replaceTimestampImpl` dok `document.hasFocus()` vraća false samo
pamti zadnji URL i upiše ga na `window` `focus`.

Cijena: isti signal daje i prelazak u drugu aplikaciju. Tko gleda video sa strane
i odmah klikne adresnu traku, kopira vrijeme od trenutka kad je napustio stranicu.
Razlikovati se ne može (`visibilityState` ostaje `visible` u oba slučaja).

## Otvoreno / neprovjereno

- 2.0.246 nije provjeren klikom u adresnu traku (automatizacija ne klikće
  omnibox) — čeka ručnu provjeru u Braveu/Chromeu, Safariju i Firefoxu.
- Nakon `?autoplay=0` mjesto iz linka nije mjesto gledanja dok se ne pusti;
  skok na poglavlje bez puštanja ne nudi povratak na `t`.
- Mobilna media_kit traka (mobilni fullscreen) nema oblačić.
- Uz „Uključi zvuk” (utišani autoplay) media_kit kontrole i oblačić su skriveni
  (od prije).
- `/v/:id/read` (non-TV fallback) i TV ekrani ne primaju `?autoplay`.
- Ništa nije isprobano na pravom mobitelu.
