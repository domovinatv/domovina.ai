/// Gumb „Prati" / „Pratiš" za kanal (`/c/:slug`) i osobu (`/p/:slug`).
///
/// Jedan widget za oba ekrana jer je ponašanje identično — razlikuju se samo
/// ključ u [FollowService] i copy (`channelFollow*` vs `personFollow*`).
///
/// Widget se **sam sakrije dok je [PersonChannelFlag] ugašen**: praćenje je
/// dio featurea virtualnih kanala (rail „Novo od praćenih" troši isti popis),
/// pa bez flaga oba ekrana izgledaju točno kao danas — isto pravilo koje već
/// slijede `PersonsRail` i kanal-forma u `person_screen.dart`.
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../router/nav.dart';
import '../services/follow_service.dart';
import '../services/person_channel_flag.dart';
import '../services/push_topics.dart';

class FollowButton extends StatefulWidget {
  /// Ključ u popisu praćenja — [personFollowKey] ili [channelFollowKey].
  final String followKey;

  /// Copy za stanje „ne pratim" (`l.personFollow` / `l.channelFollow`).
  final String followLabel;

  /// Copy za stanje „pratim" (`l.personFollowing` / `l.channelFollowing`).
  final String followingLabel;

  /// `Semantics(identifier:)` sidro za e2e (npr. `person-follow-button`).
  final String? semanticsIdentifier;

  const FollowButton({
    super.key,
    required this.followKey,
    required this.followLabel,
    required this.followingLabel,
    this.semanticsIdentifier,
  });

  @override
  State<FollowButton> createState() => _FollowButtonState();
}

class _FollowButtonState extends State<FollowButton> {
  bool _flagOn = false;
  bool _following = false;

  @override
  void initState() {
    super.initState();
    // Flag i popis se čitaju IZVAN build faze — `PersonChannelFlag.isOn` pri
    // prvom čitanju zove `notifyListeners()` sinkrono (`?vk=1` grana), što bi
    // iz build()-a srušilo frame.
    PersonChannelFlag.instance.addListener(_onFlagChanged);
    FollowService.instance.addListener(_onFollowsChanged);
    PushTopics.instance.addListener(_onPushChanged);
    unawaited(Future.microtask(_bootstrap));
  }

  Future<void> _bootstrap() async {
    await FollowService.instance.ensureLoaded();
    await PersonChannelFlag.instance.init();
    _onFollowsChanged();
    _onFlagChanged();
  }

  @override
  void didUpdateWidget(covariant FollowButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.followKey != widget.followKey) _onFollowsChanged();
  }

  @override
  void dispose() {
    PersonChannelFlag.instance.removeListener(_onFlagChanged);
    FollowService.instance.removeListener(_onFollowsChanged);
    PushTopics.instance.removeListener(_onPushChanged);
    super.dispose();
  }

  void _onFlagChanged() {
    final on = PersonChannelFlag.instance.isOn;
    if (!mounted || on == _flagOn) return;
    setState(() => _flagOn = on);
  }

  void _onFollowsChanged() {
    final following = FollowService.instance.isFollowingSync(widget.followKey);
    if (!mounted || following == _following) return;
    setState(() => _following = following);
  }

  void _onPushChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _toggle() async {
    await FollowService.instance.toggle(widget.followKey);
  }

  @override
  Widget build(BuildContext context) {
    if (!_flagOn) return const SizedBox.shrink();
    final theme = Theme.of(context);

    final child = _following
        ? FilledButton.tonalIcon(
            onPressed: _toggle,
            icon: const Icon(Icons.check, size: 18),
            label: Text(widget.followingLabel),
            style: FilledButton.styleFrom(
              visualDensity: VisualDensity.compact,
              textStyle: theme.textTheme.labelLarge,
            ),
          )
        : OutlinedButton.icon(
            onPressed: _toggle,
            icon: const Icon(Icons.add, size: 18),
            label: Text(widget.followLabel),
            style: OutlinedButton.styleFrom(
              visualDensity: VisualDensity.compact,
              textStyle: theme.textTheme.labelLarge,
            ),
          );

    final withBell = _bell(context) == null
        ? child
        : Row(mainAxisSize: MainAxisSize.min, children: [child, _bell(context)!]);

    final id = widget.semanticsIdentifier;
    if (id == null) return withBell;
    return Semantics(identifier: id, container: true, child: withBell);
  }

  /// Zvonce uz „Pratiš" na KANALU: obavijest o novim epizodama tog kanala.
  /// Samo dok korisnik prati i samo kad ljuska ima push. Tap iz isključenog
  /// stanja je prvi trenutak u kojem se smije otvoriti sistemski dijalog —
  /// i tada pretplati SAMO taj kanal (vidi `PushTopics._setTopic`).
  Widget? _bell(BuildContext context) {
    final push = PushTopics.instance;
    final channelId = channelIdFromFollowKey(widget.followKey);
    if (!push.available || channelId == null || !_following) return null;
    final l = AppLocalizations.of(context);
    final on = push.allEpisodes || push.isChannelOn(channelId);
    return IconButton(
      key: const ValueKey('follow-bell'),
      tooltip: on ? l.notificationsBellOn : l.notificationsBellOff,
      icon: Icon(on
          ? Icons.notifications_active
          : Icons.notifications_none_outlined),
      // Pod „Sve nove epizode" kanal se ne može isključiti zasebno — zvonce
      // tada vodi na ekran gdje je to objašnjeno.
      onPressed: push.allEpisodes
          ? () => drillDown(context, '/obavijesti')
          : () => push.setChannel(channelId, !on),
    );
  }
}
