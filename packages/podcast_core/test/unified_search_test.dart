import 'package:flutter_test/flutter_test.dart';
import 'package:podcast_core/models/channel_detail.dart';
import 'package:podcast_core/services/meili_client.dart';
import 'package:podcast_core/services/search_service.dart';
import 'package:podcast_core/services/unified_search.dart';

/// Spajanje lokalnog, Meili i semantičkog sloja pretrage naslovnice.
///
/// Povod 13.10.2026.: „Nedjeljom u 2: Damir Sabol" (`pNSblshqEuU`) obrađen je
/// kao ad-hoc epizoda (kanal `_unlisted`), nema ga ni u jednom listingu ni u
/// `search.json`, pa ga lokalni sloj ne vidi. Meili ga ima na 1. mjestu.
void main() {
  MeiliHit meili(String id, String title,
          {String channel = '_unlisted', String snippet = ''}) =>
      MeiliHit(
        youtubeId: id,
        title: title.replaceAll('<em>', '').replaceAll('</em>', ''),
        channel: channel,
        uploadDate: '2026-09-14',
        sectionTitles: const [],
        deepLink: '',
        formattedTitle: title,
        formattedArticleSnippet: snippet,
      );

  SemanticResult sem(String id, double start, double score,
          {String channel = 'kanal', String? title}) =>
      SemanticResult(
        chunkId: '$id-$start',
        youtubeId: id,
        channel: channel,
        uploadDate: '2026-09-01',
        episodeTitle: title ?? 'Naslov $id',
        speakers: const [],
        startTs: start,
        endTs: start == 0 ? 0 : start + 30,
        text: 'tekst $id @ $start',
        score: score,
        deepLink: '',
      );

  LocalEpisodeMatch local(String id, String title, {bool titleMatch = true}) => (
        channelId: 'budi_frajer',
        channelName: 'Budi Frajer',
        video: ChannelVideo(id: id, title: title, date: '2026-10-01'),
        titleMatch: titleMatch,
        snippet: null,
      );

  String? names(String slug) =>
      {'budi_frajer': 'Budi Frajer', 'kanal': 'Kanal'}[slug];

  test('epizoda bez listinga (_unlisted) dolazi iz Meilija, bez imena kanala',
      () {
    final hits = mergeSearchResults(
      query: 'damir sabol',
      meili: [meili('pNSblshqEuU', 'Nedjeljom u 2: <em>Damir</em> <em>Sabol</em>')],
      semantic: [sem('xyz', 120, 0.6)],
      channelName: names,
    );
    expect(hits.first.youtubeId, 'pNSblshqEuU');
    expect(hits.first.tier, MatchTier.title);
    expect(hits.first.channelName, isNull, reason: '„_unlisted" se ne prikazuje');
    expect(hits.first.title.text, 'Nedjeljom u 2: Damir Sabol');
    expect(hits.first.title.ranges, [
      [15, 20],
      [21, 26],
    ]);
  });

  test('isti ID iz tri izvora = jedan red sa svim izvorima', () {
    final hits = mergeSearchResults(
      query: 'q',
      local: [local('a1', 'Propovijed fra Stjepana')],
      meili: [meili('a1', 'Propovijed <em>fra</em> Stjepana', channel: 'budi_frajer')],
      semantic: [sem('a1', 300, 0.5), sem('a1', 900, 0.7)],
      channelName: names,
    );
    expect(hits, hasLength(1));
    expect(hits.single.sources, {
      SearchSource.local,
      SearchSource.meili,
      SearchSource.semantic,
    });
    expect(hits.single.channelName, 'Budi Frajer');
    expect(hits.single.moments.map((m) => m.seconds), [300, 900],
        reason: 'trenuci poredani po vremenu');
  });

  test('pet chunkova iste epizode ne pojede listu — trenuci su pod-pogoci', () {
    final hits = mergeSearchResults(
      query: 'q',
      semantic: [
        for (var i = 0; i < 5; i++) sem('jedna', 100.0 + i * 200, 0.8 - i / 100),
        sem('druga', 60, 0.5),
      ],
      channelName: names,
    );
    expect(hits.map((h) => h.youtubeId), ['jedna', 'druga']);
    expect(hits.first.moments, hasLength(3), reason: 'najviše 3 trenutka');
    expect(hits.first.moments.first.seconds, 100,
        reason: 'najbolja tri po scoreu (100, 300, 500 s), poredana po vremenu');
  });

  test('susjedni chunkovi (< 30 s) su jedan trenutak', () {
    final hits = mergeSearchResults(
      query: 'q',
      semantic: [sem('e', 100, 0.9), sem('e', 110, 0.8), sem('e', 400, 0.7)],
      channelName: names,
    );
    expect(hits.single.moments.map((m) => m.seconds), [100, 400]);
  });

  test('rang: naslov na vrhu, ispod njega tekst i semantika isprepleteni', () {
    final hits = mergeSearchResults(
      query: 'sabol',
      local: [local('tekst', 'Nešto drugo', titleMatch: false)],
      meili: [meili('naslov', '<em>Sabol</em> u studiju', channel: 'kanal')],
      semantic: [sem('samo-sem', 30, 0.99), sem('naslov', 60, 0.2)],
      channelName: names,
    );
    expect(hits.first.youtubeId, 'naslov');
    expect(hits.first.tier, MatchTier.title);
    expect(hits.skip(1).map((h) => h.youtubeId).toSet(), {'tekst', 'samo-sem'},
        reason: 'prvo mjesto u dva izvora vrijedi jednako; nema razreda '
            '„tekst iznad semantike"');
  });

  // 14.10.2026.: „što je rekao papa o ratu u ukrajini" — semantika je na
  // 1. mjestu imala „Papa Franjo i patrijarh Kiril o ratu u Ukrajini", a u
  // listi ga nije bilo ni u prvih deset, jer je svih 12 Meilijevih pogodaka
  // (na „je", „o", „što") bilo u razredu „tekst" iznad semantike.
  test('pitanje: točan semantički pogodak ne tone ispod Meilijevih', () {
    final hits = mergeSearchResults(
      query: 'što je rekao papa o ratu u ukrajini',
      meili: [
        for (var i = 0; i < 12; i++)
          meili('m$i', 'Podcast #$i: <em>Je</em> li <em>o</em> tome',
              channel: 'kanal'),
      ],
      semantic: [sem('papa', 0, 0.69), sem('b', 120, 0.58)],
      channelName: names,
    );
    expect(hits.first.youtubeId, 'papa');
    expect(hits.map((h) => h.youtubeId).take(4), contains('b'));
  });

  test('kratki upit: semantika ima istu težinu kao full-text', () {
    final hits = mergeSearchResults(
      query: 'abortus',
      meili: [
        meili('m0', 'Svjedočanstvo', channel: 'kanal'),
        meili('m1', 'Drugo', channel: 'kanal'),
      ],
      semantic: [sem('s0', 0, 0.59), sem('s1', 60, 0.58)],
      channelName: names,
    );
    expect(hits.take(2).map((h) => h.youtubeId).toSet(), {'m0', 's0'});
  });

  test('epizoda koju nađu dva izvora ide iznad prvog mjesta jednog izvora',
      () {
    final hits = mergeSearchResults(
      query: 'tuga',
      meili: [
        meili('samo-meili', 'Prvo', channel: 'kanal'),
        meili('oba', 'Drugo', channel: 'kanal'),
      ],
      semantic: [sem('samo-sem', 0, 0.7), sem('oba', 30, 0.6)],
      channelName: names,
    );
    expect(hits.first.youtubeId, 'oba');
  });

  test('funkcijske riječi ne moraju biti istaknute za pogodak po naslovu', () {
    final hit = mergeSearchResults(
      query: 'marija i međugorje',
      meili: [
        meili('x', 'John Pridmore - <em>Marija</em> i <em>Međugorje</em>',
            channel: 'kanal'),
      ],
      channelName: names,
    ).single;
    expect(hit.tier, MatchTier.title);
  });

  test('epizoda samo iz semantike otvara se na najboljem trenutku', () {
    final hit = mergeSearchResults(
      query: 'q',
      semantic: [sem('s', 100, 0.4), sem('s', 700, 0.9)],
      channelName: names,
    ).single;
    expect(hit.openAt, 700);
    final titled = mergeSearchResults(
      query: 'naslov',
      meili: [meili('s', '<em>Naslov</em>')],
      semantic: [sem('s', 700, 0.9)],
      channelName: names,
    ).single;
    expect(titled.openAt, isNull, reason: 'pogodak u naslovu → od početka');
  });

  test('sažetak (bez vremena) nije trenutak, ali daje isječak', () {
    final hit = mergeSearchResults(
      query: 'q',
      semantic: [sem('z', 0, 0.6)],
      channelName: names,
    ).single;
    expect(hit.moments, isEmpty);
    expect(hit.snippet?.text, isNotEmpty);
  });

  test('djelomičan Meili pogodak (samo „Damir") nije pogodak po naslovu', () {
    final hits = mergeSearchResults(
      query: 'damir sabol',
      meili: [
        meili('pNSblshqEuU', 'Nedjeljom u 2: <em>Damir</em> <em>Sabol</em>'),
        meili('drugi', '<em>DAMIR</em> BILOGLAV – desnica', channel: 'kanal'),
      ],
      channelName: names,
    );
    expect(hits.map((h) => h.tier), [MatchTier.title, MatchTier.text]);
  });

  test('coversAllTokens prašta nastavke i dijakritike', () {
    final m = parseEmTags('Propovijed <em>fra</em> <em>Stjepana</em> Brčine');
    expect(coversAllTokens(m, ['fra', 'stjepan']), isTrue);
    expect(coversAllTokens(m, ['fra', 'brcina']), isFalse);
    expect(coversAllTokens(parseEmTags('<em>Nesbø</em>'), ['nesbo']), isTrue);
  });

  test('coversAllTokens: kratka istaknuta riječ ne pokriva dugi token', () {
    final m = parseEmTags('Učiteljstvo <em>o</em> <em>pornografiji</em>');
    expect(coversAllTokens(m, ['ovisnost', 'pornografiji']), isFalse);
  });

  test('coversAllTokens prašta tipfeler kao Meili', () {
    final m = parseEmTags('Marija i <em>Međugorje</em>');
    expect(coversAllTokens(m, ['megugorje']), isTrue);
    expect(coversAllTokens(parseEmTags('<em>Sato</em>'), ['sabol']), isFalse);
  });

  test('Meili bez isječka članka → pogođeni naslovi sekcija kao isječak', () {
    final h = MeiliHit(
      youtubeId: 'x',
      title: 'Posao i novac',
      channel: 'kanal',
      uploadDate: '',
      sectionTitles: const [],
      deepLink: '',
      formattedTitle: 'Posao i novac',
      formattedArticleSnippet: '',
      formattedSectionTitles: const ['Uvod', 'Priča <em>Damira</em> <em>Sabola</em>'],
    );
    final hit = mergeSearchResults(
            query: 'damir sabol', meili: [h], channelName: names)
        .single;
    expect(hit.tier, MatchTier.text);
    expect(hit.snippet!.text, 'Priča Damira Sabola');
    expect(hit.snippet!.ranges, [
      [6, 12],
      [13, 19],
    ]);
  });

  // Od 14.10.2026. Meili dokument je sekcija i `article_text` je u
  // displayedAttributes, pa crop stiže uvijek — i kad je pogodak bio u
  // naslovu. Takav crop (prve riječi sekcije) nije isječak pogotka.
  test('Meilijev crop bez pogotka ne postaje isječak', () {
    final h = MeiliHit(
      youtubeId: 'x',
      title: 'Damir Sabol',
      channel: 'kanal',
      uploadDate: '',
      sectionTitles: const [],
      deepLink: '',
      formattedTitle: '<em>Damir</em> <em>Sabol</em>',
      formattedArticleSnippet: 'Emisija je ušla u svoju 27. sezonu…',
      formattedSectionTitles: const ['Uvod'],
    );
    final hit = mergeSearchResults(
            query: 'damir sabol', meili: [h], channelName: names)
        .single;
    expect(hit.snippet, isNull);
  });

  test('parseEmTags', () {
    final m = parseEmTags('a <em>bc</em> d <em>e</em>');
    expect(m.text, 'a bc d e');
    expect(m.ranges, [
      [2, 4],
      [7, 8],
    ]);
  });
}
