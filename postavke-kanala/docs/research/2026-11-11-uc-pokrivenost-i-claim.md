# UC pokrivenost kataloga i stanje `youtube-claim` u produkciji (S1, 11. 11. 2026.)

## Zaključak

- **182 od 186 kanala** u javnom katalogu ima `youtube_channel_id`; 180 različitih UC-ova.
  Jedan UC pokriva tri sluga (playliste). Ključ postavki po UC-u (odluka 7) drži.
- Od 4 kanala bez UC-a, dva ga imaju u registryju (`launched`, `subclub`), a katalog ga ne
  prenosi. Dva nemaju YouTube uopće (`dijalog` RSS, `x-1973380383166050304` X izvor).
- **U produkciji nema nijednog stvarnog vlasnika.** `youtube-claim` je deployan i env je
  postavljen, ali `domovina_ai.channel_claims` ima 5 redaka, svi sintetički (izmišljeni
  UC-ovi `UCppp…`, `UCzzz…`, `UCaaa…`), stvoreni 14. 10. 2026., 4 `revoked` i 1 `pending`,
  0 `verified`. **Vrata prije S2** (odluka 103).

## 1. Pokrivenost UC id-a

Naredba (javni API, paginacija `?cursor=` iz polja `next`, `limit` ≤ 100):

```bash
out=channels.jsonl; : > $out
url='https://domovina.ai/api/katalog/v1/channels?limit=100'; cur=''
while :; do
  r=$(curl -sf "$url${cur:+&cursor=$cur}")
  echo "$r" | jq -c '.items[]' >> $out
  cur=$(echo "$r" | jq -r '.next // empty')
  [ -z "$cur" ] && break
done
jq -s '{ukupno:length,
  tier1:map(select(.tier==1))|length, tier2:map(select(.tier==2))|length,
  s_uc:map(select(.youtube_channel_id!=null))|length,
  bez_uc:map(select(.youtube_channel_id==null))|length,
  bez_uc_slugovi:map(select(.youtube_channel_id==null)|"\(.slug) t\(.tier) n=\(.processed_count)"),
  razlicitih_uc:(map(select(.youtube_channel_id!=null).youtube_channel_id)|unique|length),
  uc_vise_slugova:(map(select(.youtube_channel_id!=null))|group_by(.youtube_channel_id)
    |map(select(length>1)|{uc:.[0].youtube_channel_id,slugovi:map(.slug)}))}' $out
```

Izlaz 11. 11. 2026.:

| mjera | broj |
|---|---|
| kanala ukupno | 186 (Tier 1: 52, Tier 2: 134) |
| s `youtube_channel_id` | 182 |
| bez `youtube_channel_id` | 4 |
| različitih UC-ova | 180 |
| UC s više slugova | 1: `UCuk9D5H9mx7birJ1-S22nyQ` → `na_kavi_sa_svetim_ignacijem`, `slijedi_svoj_poziv_1`, `slijedi_svoj_poziv_2` |

182 − 180 = 2 suvišna sluga, oba na tom jednom UC-u.

Kanali bez UC-a u katalogu (stanje iz registryja
`../fetch.domovina.tv/data/podcasts_registry.json`, `jq '.podcasts[]|select(.slug=="<slug>")'`):

| slug | tier | epizoda | izvor | UC u registryju |
|---|---|---|---|---|
| `launched` | 1 | 122 | `audio-direct` (beamly MP3), YouTube playlista | da, `youtube.channel_id` |
| `subclub` | 1 | 187 | `audio-direct` (beamly MP3), YouTube playlista | da, `youtube.channel_id` |
| `dijalog` | 1 | 55 | `audio-direct` (RSS, anchor.fm) | ne (`youtube.type: audio-only`) |
| `x-1973380383166050304` | 2 | 1 | X (Twitter) | ne |

Zašto katalog nema UC za `launched`/`subclub`: `katalog/src/ingest/resolve.ts` UC za Tier 1
uzima iz `info.json` `channel_id` epizoda i `index.json` (`youtube_channel_url`); audio-direct
epizode nemaju YouTube `channel_id`. Registry ga ima.

## 2. `youtube-claim` u produkciji

Sve naredbe su samo čitanje preko SSH-a (`docs` iz memorije `infra_ssh_dom001`):

```bash
SSH='ssh -i ~/.ssh/dom-001-oracle-ssh-key-2026-04-20.key ubuntu@89.168.100.120'
# env postoji? (ispisuje samo duljinu, nikad vrijednost)
$SSH 'FN=$(docker ps --format "{{.Names}}" | grep edge-functions | head -1);
  for k in YOUTUBE_CLAIM_GOOGLE_CLIENT_ID YOUTUBE_CLAIM_GOOGLE_CLIENT_SECRET YOUTUBE_CLAIM_REDIRECT_URI;
  do v=$(docker exec $FN printenv $k); echo "$k ${v:+postavljen}"; done;
  docker exec $FN ls /home/deno/functions'
# redci claimova (bez account_id)
$SSH 'DB=$(docker ps --format "{{.Names}}" | grep supabase-db | head -1);
  docker exec $DB psql -U postgres -c "select youtube_channel_id, channel_title, role, status,
  created_at::date, verified_at::date from domovina_ai.channel_claims order by created_at"'
# pozivi funkcije u logu (zadnjih 30 dana ili od restarta kontejnera)
$SSH 'FN=$(docker ps --format "{{.Names}}" | grep edge-functions | head -1);
  docker logs --since 720h $FN 2>&1 | grep -c "functions/youtube-claim"'
```

| provjera | nalaz |
|---|---|
| funkcija `youtube-claim` deployana | da (i `safe-owner-add`) |
| `YOUTUBE_CLAIM_GOOGLE_CLIENT_ID` / `_SECRET` / `_REDIRECT_URI` | sva tri postavljena; redirect je `https://domovina.ai/youtube-claim/callback` |
| client u zasebnom GCP projektu (D-bis) | da: broj projekta u client ID-u razlikuje se od login clienta (`GOTRUE_EXTERNAL_GOOGLE_CLIENT_ID`) |
| Google verifikacija `youtube.readonly` | **nije utvrđeno iz CLI-a**: projekt nije vidljiv računu u `gcloud projects list`; status consent screena se vidi samo u GCP konzoli |
| redci u `channel_claims` | 5, svi 14. 10. 2026., sintetički UC-ovi i naslovi (`p`, `z`, `A-chan`, `B-chan`, `Btest`): 4 `revoked`, 1 `pending`, **0 `verified`** |
| `oauth_states` | 1 redak, 14. 10. 2026. |
| pozivi u logu | 33 posluživanja `youtube-claim`; 2 × `token exchange failed 400 invalid_grant "Malformed auth code."` |

Tumačenje: tok je u produkciji probno pokrenut 14. 10. (testni podaci, callback s krivim
kodom), ali nijedan stvarni vlasnik nije prošao do kraja. Uzrok može biti neverificirana
aplikacija (u „Testing” načinu Google pušta samo upisane testne korisnike) ili samo izostanak
kampanje prema vlasnicima. To razlučuje korisnik u GCP konzoli.

Usput: `docs/channel-ownership-and-safe-payout-plan.md` §15 još kaže „Preostaje: PROD
deploy”; deploy je u međuvremenu napravljen. Dokument nije ovog lanca, pa ga S1 ne mijenja.

## Odluke

Vidi `postavke-kanala/docs/decisions.md`, odluke 100–104.
