import 'package:flutter_test/flutter_test.dart';
import 'package:podcast_core/services/episode_playback_session.dart';

/// Ugovor dijeljenja: ekrani istog videa (TV epizoda i čitač iznad nje u
/// stogu) dobivaju ISTU sesiju, a player se gasi tek sa zadnjim ekranom.
/// Bez toga su na TV-u svirala dva playera istovremeno.
void main() {
  test('isti video = ista sesija dok je drži barem jedan ekran', () {
    final a = EpisodePlaybackSession.acquire('vid1', surface: 'tv');
    final b = EpisodePlaybackSession.acquire('vid1', surface: 'tv');
    expect(identical(a, b), isTrue);

    b.release();
    expect(EpisodePlaybackSession.liveFor('vid1'), same(a));

    a.release();
    expect(EpisodePlaybackSession.liveFor('vid1'), isNull);
  });

  test('nakon zadnjeg release-a acquire daje novu sesiju', () {
    final a = EpisodePlaybackSession.acquire('vid2', surface: 'tv');
    a.release();
    final b = EpisodePlaybackSession.acquire('vid2', surface: 'tv');
    expect(identical(a, b), isFalse);
    b.release();
  });

  test('različiti videi ne dijele sesiju', () {
    final a = EpisodePlaybackSession.acquire('vid3', surface: 'tv');
    final b = EpisodePlaybackSession.acquire('vid4', surface: 'tv');
    expect(identical(a, b), isFalse);
    a.release();
    b.release();
  });
}
