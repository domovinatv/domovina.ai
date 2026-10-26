import '../brand/app_brand.dart';

/// Verzija aplikacije — prikazuje se u footeru naslovnice.
///
/// Konstantu mehanički bumpa `scripts/deploy.sh` (sed na ovu datoteku); ne
/// mijenjati ručno. Izdvojeno iz `main.dart` da bi servisi i ekrani mogli
/// uvoziti logger bez vučenja cijelog grafa aplikacije (priprema za
/// `podcast_core` paket, vidi docs/podcasterium_analysis_report.md).
const String appVersion = '2.0.197';

/// Console logger s verzijom — koristi za debug u release web buildovima
/// gdje su stack traceovi minificirani. Vidi CLAUDE.md, odjeljak Logging.
void log(String msg) =>
    // ignore: avoid_print
    print('[${AppBrand.config.logPrefix} v$appVersion] $msg');
