# Politika privatnosti — DOMOVINA.ai

> Analitika korištenja dodana 14. 10. 2026. (§1e, §2, §3).
>
> **NACRT za pravni pregled** — vidi [`README.md`](README.md). Ne objavljivati
> bez odobrenja pravnika/DPO-a. `‹…›` popuniti.

**Zadnja izmjena:** ‹datum› · **Voditelj obrade:** ‹naziv pravne osobe›, OIB ‹…›,
‹adresa› · **Kontakt:** `privacy@domovina.ai`

DOMOVINA.ai poštuje tvoju privatnost. Ova politika objašnjava koje osobne podatke
prikupljamo, zašto, na kojoj pravnoj osnovi, koliko ih čuvamo i koja su tvoja prava
prema Općoj uredbi o zaštiti podataka (GDPR) i hrvatskom Zakonu o provedbi OUZP-a.

## 1. Koje podatke prikupljamo

**a) Korištenje bez prijave (anonimno).** Tehnička sesija + napredak gledanja
(koju epizodu, gdje si stao). Ne znamo tko si.

**b) Prijava.** Ovisno o načinu prijave:
- **Google / Apple:** e-mail, ime, avatar (ono što provider podijeli).
- **E-mail (magic link):** tvoja e-mail adresa.
- **Passkey:** kriptografski ključ vezan uz uređaj (bez lozinke).

**c) Prijava e-Osobnom (Certilia / NIAS).** Kad se prijaviš hrvatskom
e-Osobnom, uz tvoju privolu na Certilia ekranu, primamo i pohranjujemo
**verificirani minimum**: **OIB, ime, prezime, datum rođenja i državu**.
> Namjerno **NE** prikupljamo tvoju **fotografiju**, podatke o ispravi, adresu,
> spol ni broj mobitela. Tvoj **OIB čuvamo enkriptirano**.

**d) Sadržaj.** Napredak gledanja, favoriti.

**e) Analitika korištenja.** Bilježimo kako se aplikacija koristi: pokretanje,
stranice i epizode koje otvaraš, trajanje sesije te prikaze i klikove na
sponzorske poruke. Uz to spremamo nasumični identifikator uređaja (aplikacija
ga stvara pri prvom pokretanju i čuva na uređaju ili u pregledniku),
identifikator sesije, vrstu uređaja i preglednika, verziju aplikacije, jezik,
veličinu zaslona i približnu lokaciju (država, regija, grad). Ako si prijavljen,
događaje povezujemo s tvojim računom. **IP adresu ne spremamo** i ne koristimo
alate trećih strana za praćenje.

## 2. Zašto i na kojoj osnovi (čl. 6 GDPR)

| Svrha | Pravna osnova |
|---|---|
| Pružanje usluge i tvoj račun | izvršenje ugovora (čl. 6(1)(b)) |
| Anonimni nastavak korištenja | legitimni interes (čl. 6(1)(f)) |
| Verifikacija identiteta e-Osobnom | tvoja **privola** (čl. 6(1)(a)) + nužnost za uslugu |
| Prijava e-mailom | izvršenje ugovora |
| Analitika korištenja | legitimni interes (čl. 6(1)(f)): mjerenje i poboljšanje usluge, bilježenje sponzorskih poruka |

Verificirani identitet koristimo da potvrdimo da si stvarna osoba i kao pripremu
za buduće regulirane funkcije (npr. novčanik). Privolu možeš povući (vidi §6).

## 3. Koliko dugo čuvamo

Podatke čuvamo **dok imaš račun**. Kad obrišeš račun, brišemo tvoje podatke,
uključujući KYC podatke iz e-Osobne — osim ako nas zakon obvezuje da nešto
zadržimo. ‹Ako uvedemo novčanik pod AML propisima, neke podatke ćemo morati
čuvati zakonski određeno razdoblje — ažurirat ćemo ovu politiku.›

Događaje analitike čuvamo **25 mjeseci**, pa se automatski brišu. Brisanje
računa ih ne briše samo po sebi; za brisanje događaja povezanih s tvojim
računom piši na `privacy@domovina.ai`.

## 4. Tko ima pristup / s kim dijelimo

Podatke obrađujemo na vlastitoj (self-hosted) infrastrukturi na poslužitelju u
EU (Oracle Cloud, Frankfurt). Koristimo i provjerene izvršitelje obrade: **Certilia/NIAS** (izvor eID identiteta),
**Resend** (slanje e-maila), **Google** (prijava), **Cloudflare** (hosting/CDN i prijenos događaja analitike), **Oracle Cloud** (poslužitelj).
Ne prodajemo tvoje podatke.

## 5. Sigurnost

OIB je enkriptiran u bazi; baza nije javno dostupna; sav promet ide preko HTTPS-a;
pristup je strogo ograničen. Vidi tehnički okvir mjera (interno).

## 6. Tvoja prava (čl. 15–22 GDPR)

Imaš pravo na: pristup, ispravak, **brisanje** ("pravo na zaborav"), ograničenje,
prenosivost i prigovor, te povlačenje privole u svakom trenutku. Zahtjev šalji na
`privacy@domovina.ai`; odgovaramo u roku **30 dana**.

Pritužbu možeš podnijeti i nadzornom tijelu: **Agencija za zaštitu osobnih
podataka (AZOP)**, Selska cesta 136, 10000 Zagreb, [azop.hr](https://azop.hr).

## 7. Promjene

Politiku možemo ažurirati; bitne promjene najavit ćemo u aplikaciji.

---

_Ovo je nacrt; konačan tekst potvrđuje pravnik/DPO prije objave._
