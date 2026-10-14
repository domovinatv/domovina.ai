# Usklađenost sa zaštitom osobnih podataka (GDPR / AZOP)

Ovaj direktorij je **jedinstveni izvor istine** za usklađenost DOMOVINA.ai sustava
s Uredbom (EU) 2016/679 (**GDPR / OUZP**) i hrvatskim **Zakonom o provedbi Opće
uredbe o zaštiti podataka** (NN 42/2018).

> ## ⚠️ Pravni disclaimer
> Ovi dokumenti su **nacrt / radni okvir** koji su napisali inženjeri, **nisu
> pravni savjet**. Prije nego što se objave (Politika privatnosti) ili koriste
> za bilo kakvu komunikaciju s **AZOP-om** (Agencija za zaštitu osobnih podataka),
> **mora ih pregledati i odobriti kvalificirani pravnik / službenik za zaštitu
> podataka (DPO)**. Sadrže pretpostavke koje treba potvrditi za stvarni pravni
> subjekt (voditelj obrade), poslovni model i obradu.

## Dokumenti

| Dokument | Svrha |
|---|---|
| [`data-protection.md`](data-protection.md) | MASTER: ROPA (evidencija obrade), pravna osnova, DPIA, TOMs, prava ispitanika, postupak povrede, sub-procesori |
| [`privacy-policy-hr.md`](privacy-policy-hr.md) | Korisnička **Politika privatnosti** (HR) — nacrt za objavu |
| [`kyc-strategy-and-extensibility.md`](kyc-strategy-and-extensibility.md) | **Širina KYC-a**: spektar opsega, AML/wallet, AZOP/DPIA trigeri, backward-kompatibilan model proširenja, decision log |

## Što je tehnički već implementirano (i gdje)

- **Minimizacija** podataka (čl. 5): Certilia eID sprema samo OIB + ime + prezime + datum rođenja + država. Bez fotografije (čl. 9), bez podataka o ispravi.
- **Enkripcija** OIB-a (čl. 32): `pgcrypto` u `public.identity_verifications` (migracija `…_identity_verifications.sql`); ključ u `KYC_ENCRYPTION_KEY` env-u, ne u bazi.
- **Pristup** (čl. 32): RLS service-role-only; OIB ne izlazi klijentu (samo `my_identity_status()` siguran subset).
- **Pravo na zaborav** (čl. 17): `on delete cascade` na `auth.users` → brisanje računa briše KYC + sve povezane podatke.
- **Audit** (čl. 5(2) odgovornost): `public.activity_events` append-only.

## Održavanje

Ažuriraj ove dokumente pri **svakoj** promjeni: koje podatke skupljamo, gdje ih
spremamo, koji sub-procesori, rokovi čuvanja, nove obrade (npr. self-custody
wallet / AML). Vidi tehnički vodič: [`../authentication-setup-guide.md`](../authentication-setup-guide.md).

_Zadnje ažurirano: 2026-10-14 (analitika korištenja, regija poslužitelja)._
