import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:podcast_core/l10n/app_localizations.dart';
import 'package:podcast_core/services/ebook_service.dart';
import 'package:podcast_core/theme/app_theme.dart';
import 'package:podcast_core/widgets/ebook_sheet.dart';

/// Kontrakt: **e-knjiga se nudi samo kad je izmjerena.**
///
/// Probe ([EbookService.probe]) je asinkron, pa kartica i ikona u app baru
/// kroz prvi frame uvijek dobiju praznu dostupnost. Da se tada iscrtaju,
/// korisnik bi na svakoj epizodi vidio ponudu koja za većinu njih vodi na 404
/// — ista greška zbog koje `EpisodeStatus.fromPipeline` ne smije tvrditi fazu
/// iz izostanka zastavice.
Widget _host(Widget child) => MaterialApp(
      theme: AppTheme.light(),
      locale: const Locale('hr'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: SingleChildScrollView(child: child)),
    );

const _hr = EbookEdition(
  isEn: false,
  url: 'https://cdn.domovina.ai/data/abc/book.epub',
  bytes: 2638696,
);

void main() {
  testWidgets('bez izmjerene knjige kartica ne zauzima ništa', (tester) async {
    await tester.pumpWidget(
      _host(
        const EbookCard(
          availability: EbookAvailability.none,
          title: 'Nedjeljom u 2: Damir Sabol',
          preferEn: false,
        ),
      ),
    );
    expect(find.byType(FilledButton), findsNothing);
    expect(tester.getSize(find.byType(EbookCard)), Size.zero);
  });

  testWidgets('s knjigom kartica ponudi EPUB', (tester) async {
    await tester.pumpWidget(
      _host(
        const EbookCard(
          availability: EbookAvailability(hr: _hr),
          title: 'Nedjeljom u 2: Damir Sabol',
          preferEn: false,
        ),
      ),
    );
    expect(find.text('Ponesi epizodu sa sobom'), findsOneWidget);
    expect(find.text('E-knjiga (EPUB)'), findsOneWidget);
  });

  // Jezik e-knjige je jezik SADRŽAJA: `/v/<id>/en` uz hrvatsko sučelje je
  // nudio hrvatsku karticu i „Kopiraj poveznicu na knjigu".
  testWidgets('engleski sadržaj uz hrvatsko sučelje: kartica i sheet na engleskom',
      (tester) async {
    const en = EbookEdition(
      isEn: true,
      url: 'https://cdn.domovina.ai/data/abc/book.en.epub',
      bytes: 2638696,
    );
    await tester.pumpWidget(
      _host(
        const EbookCard(
          availability: EbookAvailability(hr: _hr, en: en),
          title: 'Episode',
          preferEn: true,
        ),
      ),
    );
    expect(find.text('Take the episode with you'), findsOneWidget);
    expect(find.text('Ponesi epizodu sa sobom'), findsNothing);

    expect(find.text('Ebook (EPUB)'), findsOneWidget);
    // Sheet (traži GoRouter zbog closeOnRouteChange) čita iste tekstove.
    expect(ebookStrings(true).ebookCopyLink, 'Copy link to the book');
    expect(ebookStrings(false).ebookCopyLink, 'Kopiraj poveznicu na knjigu');
  });

  testWidgets('ikona u app baru se pojavi tek s knjigom', (tester) async {
    await tester.pumpWidget(
      _host(
        const EbookAction(
          availability: EbookAvailability.none,
          title: 'Epizoda',
          preferEn: false,
        ),
      ),
    );
    expect(find.byType(IconButton), findsNothing);

    await tester.pumpWidget(
      _host(
        const EbookAction(
          availability: EbookAvailability(hr: _hr),
          title: 'Epizoda',
          preferEn: false,
        ),
      ),
    );
    expect(find.byIcon(Icons.auto_stories_outlined), findsOneWidget);
  });
}
