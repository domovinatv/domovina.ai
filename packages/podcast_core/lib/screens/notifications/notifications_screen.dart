/// Ekran Obavijesti (`/obavijesti`) — korisnik bira na što je pretplaćen.
///
/// Gore je stanje sistemske dozvole, ispod „Sve nove epizode" i popis svih
/// kanala s prekidačem po kanalu. Dok je „Sve" uključeno, kanali su prikazani
/// uključeni i zaključani: tema se ne može izuzeti po kanalu, pa tko želi samo
/// neke kanale, prvo isključi „Sve".
///
/// Sistemski dijalog otvara SAMO tap (gumb ili prekidač) — nikad sam ekran.
/// Plan: `docs/plans/2026-10-15-push-nove-epizode.md` §4.3.
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../models/channel_index.dart';
import '../../push/push_transport.dart';
import '../../router/nav.dart';
import '../../services/channel_cache.dart';
import '../../services/follow_service.dart';
import '../../services/push_topics.dart';
import '../../src/log.dart' show log;
import '../../widgets/cached_thumbnail.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen>
    with WidgetsBindingObserver {
  final _push = PushTopics.instance;
  List<ChannelSummary>? _channels;
  bool _channelsFailed = false;
  String _query = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _push.addListener(_onChanged);
    FollowService.instance.addListener(_onChanged);
    unawaited(_push.refreshPermission());
    unawaited(FollowService.instance.ensureLoaded());
    unawaited(_loadChannels());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _push.removeListener(_onChanged);
    FollowService.instance.removeListener(_onChanged);
    super.dispose();
  }

  /// Korisnik se vraća iz sistemskih postavki — dozvola se možda promijenila.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_push.refreshPermission());
    }
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _loadChannels() async {
    try {
      final index = await channelCache.loadIndex();
      if (!mounted) return;
      setState(() {
        _channels = index.channels;
        _channelsFailed = false;
      });
    } catch (e) {
      log('notifications: channel index failed ($e)');
      if (mounted) setState(() => _channelsFailed = true);
    }
  }

  /// Praćeni i već uključeni kanali prvi, zatim abecedno.
  List<ChannelSummary> _sorted(List<ChannelSummary> channels) {
    final follows = FollowService.instance;
    final on = _push.channelIds;
    int rank(ChannelSummary c) =>
        (follows.isFollowingSync(channelFollowKey(c.id)) || on.contains(c.id))
            ? 0
            : 1;
    final q = _query.trim().toLowerCase();
    return channels
        .where((c) => q.isEmpty || c.name.toLowerCase().contains(q))
        .toList()
      ..sort((a, b) {
        final r = rank(a).compareTo(rank(b));
        return r != 0 ? r : a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      appBar: AppBar(
        backgroundColor: theme.colorScheme.surface,
        title: Text(l.notificationsTitle),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          tooltip: l.commonBack,
          onPressed: () => backUp(context),
        ),
      ),
      body: _push.available ? _body(theme, l) : _unavailable(theme, l),
    );
  }

  Widget _unavailable(ThemeData theme, AppLocalizations l) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.notifications_off_outlined,
                size: 40, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(height: 12),
            Text(l.notificationsAppOnly,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyLarge),
          ],
        ),
      ),
    );
  }

  Widget _body(ThemeData theme, AppLocalizations l) {
    final cs = theme.colorScheme;
    final denied = _push.permission == PushPermission.denied;
    final all = _push.allEpisodes;
    final channels = _channels;

    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640),
        child: ListView(
          padding: const EdgeInsets.symmetric(vertical: 16),
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Text(
                l.notificationsIntro,
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: cs.onSurfaceVariant),
              ),
            ),
            const SizedBox(height: 12),
            _statusCard(theme, l),
            const SizedBox(height: 8),
            SwitchListTile(
              key: const ValueKey('notifications-all'),
              contentPadding: const EdgeInsets.symmetric(horizontal: 20),
              secondary: Icon(Icons.new_releases_outlined, color: cs.primary),
              title: Text(l.notificationsAllTitle),
              subtitle: Text(l.notificationsAllSubtitle),
              value: all,
              onChanged: denied ? null : (v) => _push.setAllEpisodes(v),
            ),
            const Divider(height: 24),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text(
                l.notificationsChannelsSection,
                style: theme.textTheme.titleSmall,
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: TextField(
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.search),
                  hintText: l.notificationsSearchHint,
                  isDense: true,
                  border: const OutlineInputBorder(),
                ),
                onChanged: (v) => setState(() => _query = v),
              ),
            ),
            if (channels == null && !_channelsFailed)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              ),
            if (_channelsFailed)
              ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 20),
                title: Text(l.notificationsChannelsError),
                trailing: TextButton(
                  onPressed: () {
                    setState(() => _channelsFailed = false);
                    unawaited(_loadChannels());
                  },
                  child: Text(l.commonRetry),
                ),
              ),
            if (channels != null)
              for (final c in _sorted(channels))
                _channelTile(theme, l, c, all: all, denied: denied),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  Icon(Icons.bedtime_outlined,
                      size: 18, color: cs.onSurfaceVariant),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      l.notificationsQuietHours,
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: cs.onSurfaceVariant),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _statusCard(ThemeData theme, AppLocalizations l) {
    final cs = theme.colorScheme;
    final Widget content;
    if (_push.permission == PushPermission.denied) {
      content = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.notifications_off_outlined, color: cs.error),
              const SizedBox(width: 12),
              Expanded(
                child: Text(l.notificationsDeniedTitle,
                    style: theme.textTheme.titleSmall),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(l.notificationsDeniedBody,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: cs.onSurfaceVariant)),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            icon: const Icon(Icons.settings_outlined),
            label: Text(l.notificationsOpenSettings),
            onPressed: _push.openSystemSettings,
          ),
        ],
      );
    } else if (_push.enabled) {
      content = Row(
        children: [
          Icon(Icons.notifications_active_outlined, color: cs.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Text(l.notificationsEnabledStatus,
                style: theme.textTheme.titleSmall),
          ),
        ],
      );
    } else {
      content = Align(
        alignment: Alignment.centerLeft,
        child: FilledButton.icon(
          key: const ValueKey('notifications-enable'),
          icon: const Icon(Icons.notifications_outlined),
          label: Text(l.notificationsEnable),
          onPressed: () => _push.enable(),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.6)),
        ),
        child: content,
      ),
    );
  }

  Widget _channelTile(
    ThemeData theme,
    AppLocalizations l,
    ChannelSummary c, {
    required bool all,
    required bool denied,
  }) {
    final cs = theme.colorScheme;
    final following =
        FollowService.instance.isFollowingSync(channelFollowKey(c.id));
    final subtitle = all
        ? l.notificationsCoveredByAll
        : (following ? l.notificationsFollowingLabel : null);
    return SwitchListTile(
      key: ValueKey('notifications-channel-${c.id}'),
      contentPadding: const EdgeInsets.symmetric(horizontal: 20),
      secondary: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: SizedBox(
          width: 40,
          height: 40,
          child: c.avatarSquare != null
              ? CachedThumbnail(
                  url: c.avatarSquare!,
                  width: 40,
                  height: 40,
                  fit: BoxFit.cover,
                  errorFallbackBuilder: (_) =>
                      ColoredBox(color: cs.surfaceContainerHighest),
                )
              : ColoredBox(color: cs.surfaceContainerHighest),
        ),
      ),
      title: Text(c.name, maxLines: 2, overflow: TextOverflow.ellipsis),
      subtitle: subtitle == null
          ? null
          : Text(subtitle,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: cs.onSurfaceVariant)),
      value: all || _push.isChannelOn(c.id),
      onChanged:
          (denied || all) ? null : (v) => _push.setChannel(c.id, v),
    );
  }
}
