# Stilski vodič: vijest iz podcasta

Format `vijest` (S4) je kratka vijest napisana iz izjava jedne epizode
podcasta. Članak ne smije reći ništa što ne piše u trenucima epizode
(`vijesti.moments`) ili u njezinim metapodacima. Vodič je izvor za sistemsku
uputu generatora (`engine/write/prompt.ts`, `SYSTEM_PROMPT`) i za
determinističke provjere u `engine/verify/article.ts`.

**Usklađenost (odluka 415):** svako pravilo ima oznaku `V1`…`V14`; sistemska
uputa nosi iste oznake sa sažetkom pravila. Test „stil.md i sistemska uputa su
usklađeni” (`engine/write/write.test.ts`) pada kad: (a) oznaka postoji samo na
jednoj strani, (b) popis kategorija ovdje i `CATEGORIES` u kodu nisu isti,
(c) se ova datoteka promijeni, a `STIL_SHA256` u `prompt.ts` nije
osvježen. Uz (c) ide i novi `PROMPT_VERSION` generatora kad se mijenja
pravilo, ne samo tipfeler.

## Pravila

**V1. Treće lice, izvještajni ton.** Autor se ne pojavljuje u tekstu: bez
„mi”, „nas”, „naš”, „ja”, bez obraćanja čitatelju („ti”, „vi”).

**V2. Obrnuta piramida.** Najvažnija tvrdnja ide prva (naslov i lead), zatim
pojedinosti po važnosti, pozadina i manje važne izjave na kraju. Članak se
može rezati odozdo bez gubitka bitnog.

**V3. Naslov bez mamca.** Jedna izjavna rečenica do 110 znakova. Bez upitnika
i uskličnika, bez pitanja-mamaca („Je li ovo kraj…”), bez riječi „šokantno”,
„nevjerojatno”, „nećete vjerovati”, „evo zašto”, „otkriveno”. Velika slova
samo na početku i u vlastitim imenima. Bez navodnika.

**V4. Lead: tko, što, gdje, kada.** Prva jedna do dvije rečenice kažu tko
(ime govornika), što (glavna tvrdnja), gdje (u kojem podcastu: ime kanala) i
kada (datum objave epizode, npr. „6. studenoga 2026.”).

**V5. Citat je referenca, ne prijepis.** Doslovni citat ulazi u članak samo
kao blok `{"type":"quote","moment":N}` koji upućuje na trenutak `tN`. Tekst
citata generator NE piše: prikaz ga umeće iz `moments.quote`, uz ime govornika
i vrijeme u snimci. U odlomcima nema navodnika; prepričana izjava („kaže da
…”) ne ide u navodnike.

**V6. Svaka tvrdnja ima govornika.** Tvrdnja se pripisuje onome tko ju je
izrekao („kaže”, „smatra”, „prema riječima”). Članak ništa ne tvrdi u svoje
ime.

**V7. Samo iz ulaza.** Svako ime, broj, datum, funkcija i događaj mora biti u
trenucima ili metapodacima epizode. Funkcija ili titula govornika navodi se
samo ako piše u ulazu. Brojke se prepisuju točno kako su u ulazu.

**V8. Bez superlativa bez izvora.** Bez „najveći”, „povijesni”, „ključni”,
„revolucionarni” i sličnih pojačivača, osim kad ih izgovori govornik (tada su
njegova tvrdnja i pripisuju se njemu).

**V9. Bez mišljenja i vrednovanja.** Bez „hrabro”, „nažalost”, „srećom”,
„važno je istaknuti”, „jasno je da”, bez autorovih zaključaka i savjeta.

**V10. Duljina 300–500 riječi.** Broje se riječi leada, odlomaka i citata
kako se prikazuju; naslov ne ulazi. Izvan raspona članak se sprema, a provjera
ga označi za urednika (odluka 418).

**V11. Pravopis IHJJ.** Dijakritike (č, ć, š, ž, đ), hrvatski navodnici „…”
(samo u prikazu citata), datumi „6. studenoga 2026.”, „podcast” malim slovom.
Kratice titula s točkom („dr.”, „fra”, „don”) prema pravopisu.

**V12. Bez emojija i bez naglašavanja.** Bez emojija, bez riječi pisanih
velikim slovima radi naglaska, bez uskličnika.

**V13. Engleska epizoda.** Članak je na hrvatskom. Citat ostaje doslovno na
izvornom jeziku (blok-referenca, V5); prijevod se ne stavlja u navodnike ni
predstavlja kao citat, nego se izjava prepričava neizravnim govorom.

**V14. Jedna kategorija iz zatvorenog popisa.** Bira se prema temi glavne
tvrdnje, ne prema kanalu ni govorniku. Kad tema pripada dvjema kategorijama,
vrijedi ona koja je prva u popisu ispod.

## Kategorije

Zatvoren popis (odluka 416). Slug ide u `article_versions.category`.

| slug | naziv | što pokriva |
| --- | --- | --- |
| `politika` | Politika | vlada, sabor, stranke, izbori, zakoni, javne politike |
| `gospodarstvo` | Gospodarstvo | poduzeća, financije, rad, cijene, porezi, energetika |
| `vjera` | Vjera i Crkva | Crkva, vjernici, nauk, svećenici, redovnici, hodočašća |
| `zdravlje` | Zdravlje | bolesti, liječenje, zdravstveni sustav, prehrana |
| `obrazovanje` | Obrazovanje | škole, sveučilišta, odgoj, mladi u obrazovanju |
| `znanost-tehnologija` | Znanost i tehnologija | istraživanja, umjetna inteligencija, internet, tehnika |
| `kultura` | Kultura | knjige, film, glazba, baština, mediji |
| `sport` | Sport | sportaši, natjecanja, rekreacija |
| `svijet` | Svijet | događaji i odnosi izvan Hrvatske koji ne spadaju gore |
| `drustvo` | Društvo | obitelj, demografija, zajednica, sve ostalo |
