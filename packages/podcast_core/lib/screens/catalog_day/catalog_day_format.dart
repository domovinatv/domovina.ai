import 'package:flutter/widgets.dart';
import 'package:intl/intl.dart';

import '../../l10n/app_localizations.dart';
import '../../models/catalog_day.dart';

// Datumi za rail „Danas u korpusu” i ekran `/dani/:datum`.
//
// Nazivi mjeseci dolaze iz `intl` `DateFormat` za jezik SUČELJA (hr:
// „6. studenoga 2026.”, en: „November 6, 2026”), a ne iz ručnih tablica kao u
// `founder_booking.dart`. Podaci o datumima za jezike aplikacije učitavaju se
// s `GlobalMaterialLocalizations` (dio `AppLocalizations.localizationsDelegates`).
// Ako ih ipak nema (izoliran test bez delegata), pada se na brojčani oblik
// „6. 11. 2026.”, koji je ispravan hrvatski i čitljiv na engleskom.

/// Dan, mjesec i godina: „6. studenoga 2026.”.
String catalogDayLongLabel(BuildContext context, DateTime date) => _format(
  context,
  date,
  (locale) => DateFormat.yMMMMd(locale),
  '${date.day}. ${date.month}. ${date.year}.',
);

/// Dan i mjesec: „3. studenoga”.
String catalogDayShortLabel(BuildContext context, DateTime date) => _format(
  context,
  date,
  (locale) => DateFormat.MMMMd(locale),
  '${date.day}. ${date.month}.',
);

/// Naslov raila prema udaljenosti dana od [today]: „Danas u korpusu”,
/// „Jučer u korpusu” ili „U korpusu · 3. studenoga”.
String catalogDayRailEyebrow(
  BuildContext context,
  AppLocalizations l,
  DateTime date,
  DateTime today,
) {
  if (date == today) return l.homeRailCatalogToday;
  if (date == shiftCatalogDate(today, -1)) return l.homeRailCatalogYesterday;
  return l.homeRailCatalogOnDate(catalogDayShortLabel(context, date));
}

String _format(
  BuildContext context,
  DateTime date,
  DateFormat Function(String locale) pattern,
  String fallback,
) {
  final locale = Localizations.maybeLocaleOf(context)?.languageCode ?? 'hr';
  try {
    return pattern(locale).format(date);
  } catch (_) {
    return fallback;
  }
}
