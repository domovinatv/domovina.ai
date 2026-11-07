# Slike na iOS webu: crne/prazne nakon povratka na ekran (7. 11. 2026.)

## Simptom

iOS Chrome / Safari / WhatsApp preglednik (iOS 18.7, WebKit): na ekranu
„Epizode dana” (`/dani/:datum`) i na naslovnici prvi prikaz slika je uredan,
ali nakon povratka na isti ekran thumbnailovi ostanu crni ili sivi s ikonom
(`Icons.ondemand_video` = konačna greška).

## Mjerenje

Dijagnostički build preko Tailscalea (`scripts/serve-debug-web.py`; skripta u
`web/index.html` šalje konzolu na `/__log`, aktivna samo na `localhost` i
`*.ts.net`):

| build | učitavanja dana | greške slika |
|---|---|---|
| `CachedNetworkImage` (default `HtmlImage`) | ~10 | 149, sve `ImageCodecException: Failed to create image from Image.decode` |
| `CachedNetworkImage` + `ImageRenderMethodForWeb.HttpGet` | ~15 | 434, ista greška |
| vlastiti `WebBitmapImage` (`createImageBitmap`) | 98 | 0 |

Prva greška se uvijek javila tek na PRVOM POVRATKU na već viđeni dan.
`webglcontextlost` se nije dogodio nijednom — nije gubitak GPU konteksta.

## Uzrok

Flutter web engine (3.47.3) na pregledniku bez `ImageDecoder` (WebKit) i URL
i bajtove dekodira kroz `<img>` (`HtmlImageElementCodec`/`HtmlBlobCodec`) pa
radi `MakeLazyImageFromTextureSourceWithInfo(img, naturalWidth, naturalHeight)`.
Pri ponovnom dekodiranju iste slike WebKit javi `naturalWidth == 0`, CanvasKit
vrati `null` → iznimka iz `createCkImageFromImageElement`. Engine ima
zaobilazak za 0×0 samo za Firefox. `HttpGet` ne pomaže jer engine i bajtove
pretvara u blob → `<img>`.

Usput: `<img>` put ignorira `memCacheWidth`, pa je ImageCache bio na
82/100 MB i slike su ispadale iz njega — zato je povratak uopće dekodirao
ponovno.

## Popravak

`lib/widgets/web_bitmap_image_web.dart`: `fetch` → `Blob` →
`createImageBitmap(blob, {resizeWidth})` → `ui_web.createImageFromImageBitmap`.
`ImageBitmap` nosi stvarne dimenzije i odmah je smanjen na širinu prikaza.
`CachedThumbnail` ga koristi na webu; native ostaje na `CachedNetworkImage`.

Uz to (sve platforme): greška više nije odmah konačna — varijanta dobiva jedan
ponovni pokušaj prije PNG-a, PNG dva — i svaka se greška logira s URL-om i
stanjem ImageCachea.

## Otvoreno

- Native iOS: korisnik je prijavio sličan simptom; ovaj popravak ga ne dira
  (nema `<img>`). Treba zasebno mjerenje.
- Chromium web na novom putu provjeren je samo kroz build, ne ručno.
