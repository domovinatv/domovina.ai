# Magisterium izvori — tekst odlomka i hrvatski (plan, 20.10.2026.)

## Stanje (izmjereno 19.–20.10.2026.)

- `article.magisterium.json`: svih 394 citata u 6 epizoda ima `cited_text: ''`.
  MCP hibrid (`fetch.domovina.tv/magisterium_mcp_assemble.js`) ga namjerno ostavlja
  praznim — MCP `chat` vraća samo `{document_title, document_author, document_reference}`.
- Lokalni sirovi odgovori (`/tmp/mag_hybrid/<job>.results/*.raw.txt`, 17 poslova)
  nose isto: naslov, autor, ref. **Backfill teksta iz njih nije moguć.**
- MCP `search` vraća `id: "1"` za svaki rezultat; `fetch` na taj id (ili URL)
  vraća `found: false`. Put „search → fetch → tekst" trenutno ne radi.
- magisterium.com nema HR sučelje (hreflang: en, es, pt, fr, it, de, uk, zh);
  `GET /api/documents/<uuid>/full-translations` za provjereni dokument je prazan.
  Interni `/api/documents/<uuid>/ref/<n>` vraća točan odlomak (TEI XML), ali traži
  prijavu i iza je Vercel checkpointa — nije za produkciju.

## Frontend (napravljeno, ovaj commit)

Izvori rašireni po defaultu; kartica bez praznog citata, čitljiva referenca
(`citationRefLabel`: „br. 74", „str. 65"); bez teksta tap ide izravno na izvor
(`openCitation`), uz oznaku „Magisterium.com · nije na hrvatskom".

## Sljedeće (pipeline, fetch repo)

1. **Tekst odlomka uz citat** — `cited_text` (izvornik). Opcije: (a) prijaviti
   Magisteriumu da MCP `fetch` ne razrješava `search` id-eve; (b) ograničen API
   poziv samo za dohvat odlomka — traži izričitu odluku (pravilo „MCP only").
   Sirovi MCP odgovor ubuduće spremati cijeli (JSON `references[]`), ne samo
   ručno složen `References:` tekst, i ne u `/tmp`.
2. **`cited_text_hr`** — prijevod odlomka u pipelineu (Gemini), tek kad 1. postoji.
   Frontend: sheet pokazuje HR prijevod + izvornik ispod.
3. **Službeni HR prijevodi** — registar naslov → vatican.va `/hr/` URL za
   enciklike i pobudnice; gumb „Pročitaj na hrvatskom" uz Magisterium link.
