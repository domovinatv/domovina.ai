# Fontovi jezgre (google_fonts iz assetsa)

`google_fonts` traži asset čije ime završava s `<Obitelj>-<Varijanta>.ttf` prije
nego ode na fonts.gstatic.com, pa ove datoteke idu s našeg hosta (web) ili iz
same aplikacije (native). Popis mora pratiti `AppTypography._usedVariants`.
Varijanta koje ovdje nema i dalje se dohvaća s mreže.

- **Playfair Display, Lora**: NEIZMIJENJENE datoteke s fonts.gstatic.com. OFL
  im navodi *Reserved Font Name*, pa bi srezana verzija morala nositi drugo ime.
- **Inter**: srezan na latinicu + latin-ext + interpunkciju, valute, strelice i
  ⌘⌥⌃⌫ (`pyftsubset`, raspon u `docs/2026-10-09-boot-splash.md` §8). Glif
  kojeg nema (ćirilica, grčki…) Flutter crta Noto fallbackom.

Licence: OFL-*.txt (registrirane u `LicenseRegistry`, `lib/theme/typography.dart`).
Web ih servira s `immutable`: novi sadržaj pod istim imenom ne stiže do
korisnika s cacheom, pa promjena fonta = novo ime datoteke.
