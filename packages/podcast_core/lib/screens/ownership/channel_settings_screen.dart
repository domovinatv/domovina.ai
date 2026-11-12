/// Postavke kanala za vlasnika (`/account/channels/:ucId/postavke`, lanac
/// `postavke-kanala/`, S4): glavni prekidač, 19 prekidača u četiri skupine,
/// kronološki log promjena i trajno brisanje (potvrda u aplikaciji + poziv).
///
/// Ugovor s backendom (domovina-api, shema `domovina_ai`):
///   - prekidač prikazuje SIROVU vrijednost (`public_channel_settings.settings`,
///     zadano `true`); siv je kad ga roditelj gasi (sirovo `true`, efektivno
///     `false`). Efektivno stanje dolazi iz viewa i iz odgovora
///     `set_channel_setting`; klijent ga ne preračunava.
///   - tap je optimističan: sirova vrijednost i red „Sprema se…” odmah, na
///     grešku povrat i SnackBar s porukom po kodu.
///   - pisanje traži claim mlađi od 90 dana; stariji vidi ekran samo za
///     čitanje (log se čita uz claim bilo koje starosti, odluka 205).
///   - otvoren zahtjev za brisanje čita se iz `channel_deletion_requests`,
///     pa stanje preživi ponovno otvaranje ekrana.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../l10n/app_localizations.dart';
import '../../models/channel_claim.dart';
import '../../router/nav.dart';
import '../../services/channel_settings_service.dart';
import '../../src/log.dart' show log;
import 'channel_ownership_screen.dart' show OwnershipCrumbs;

/// Broj za telefonsku potvrdu trajnog brisanja (odluka 5; javan).
const String kChannelDeletionPhoneDisplay = '+385 98 967 9022';
final Uri kChannelDeletionPhoneUri = Uri.parse('tel:+385989679022');

/// Ruta ekrana postavki za kanal [ucId].
String channelSettingsLocation(String ucId) =>
    '/account/channels/$ucId/postavke';

/// Naziv prekidača.
String channelSettingLabel(AppLocalizations l, String key) => switch (key) {
  'channel_enabled' => l.channelSettingsKeyChannelEnabled,
  'processing' => l.channelSettingsKeyProcessing,
  'home_featured' => l.channelSettingsKeyHomeFeatured,
  'in_app_search' => l.channelSettingsKeyInAppSearch,
  'search_engines' => l.channelSettingsKeySearchEngines,
  'push_notifications' => l.channelSettingsKeyPushNotifications,
  'cdn_playback' => l.channelSettingsKeyCdnPlayback,
  'share_clips' => l.channelSettingsKeyShareClips,
  'ebook' => l.channelSettingsKeyEbook,
  'article_summary' => l.channelSettingsKeyArticleSummary,
  'transcript_subtitles' => l.channelSettingsKeyTranscriptSubtitles,
  'english_translation' => l.channelSettingsKeyEnglishTranslation,
  'magisterium' => l.channelSettingsKeyMagisterium,
  'highlights_reels' => l.channelSettingsKeyHighlightsReels,
  'persons_mentions' => l.channelSettingsKeyPersonsMentions,
  'news_portal' => l.channelSettingsKeyNewsPortal,
  'ai_assistants' => l.channelSettingsKeyAiAssistants,
  'donations' => l.channelSettingsKeyDonations,
  'paid_sponsor_moments' => l.channelSettingsKeyPaidSponsorMoments,
  'sponsors_in_video' => l.channelSettingsKeySponsorsInVideo,
  _ => key,
};

/// Jedna rečenica: što isključenje znači (odluka 1).
String channelSettingOffMeaning(AppLocalizations l, String key) =>
    switch (key) {
      'channel_enabled' => l.channelSettingsOffChannelEnabled,
      'processing' => l.channelSettingsOffProcessing,
      'home_featured' => l.channelSettingsOffHomeFeatured,
      'in_app_search' => l.channelSettingsOffInAppSearch,
      'search_engines' => l.channelSettingsOffSearchEngines,
      'push_notifications' => l.channelSettingsOffPushNotifications,
      'cdn_playback' => l.channelSettingsOffCdnPlayback,
      'share_clips' => l.channelSettingsOffShareClips,
      'ebook' => l.channelSettingsOffEbook,
      'article_summary' => l.channelSettingsOffArticleSummary,
      'transcript_subtitles' => l.channelSettingsOffTranscriptSubtitles,
      'english_translation' => l.channelSettingsOffEnglishTranslation,
      'magisterium' => l.channelSettingsOffMagisterium,
      'highlights_reels' => l.channelSettingsOffHighlightsReels,
      'persons_mentions' => l.channelSettingsOffPersonsMentions,
      'news_portal' => l.channelSettingsOffNewsPortal,
      'ai_assistants' => l.channelSettingsOffAiAssistants,
      'donations' => l.channelSettingsOffDonations,
      'paid_sponsor_moments' => l.channelSettingsOffPaidSponsorMoments,
      'sponsors_in_video' => l.channelSettingsOffSponsorsInVideo,
      _ => '',
    };

/// Poruka za kod greške backenda.
String channelSettingsErrorText(AppLocalizations l, String code) =>
    switch (code) {
      'login_required' => l.channelSettingsErrorLoginRequired,
      'not_owner' => l.channelSettingsErrorNotOwner,
      'unknown_key' => l.channelSettingsErrorUnknownKey,
      'channel_deleted' => l.channelSettingsErrorChannelDeleted,
      'confirm_name_mismatch' => l.channelSettingsErrorNameMismatch,
      'deletion_already_requested' => l.channelSettingsErrorAlreadyRequested,
      'no_open_request' => l.channelSettingsErrorNoOpenRequest,
      _ => l.channelSettingsErrorGeneric,
    };

/// Lokalni datum i vrijeme za log i stanje zahtjeva.
String channelSettingsWhen(BuildContext context, DateTime? t) {
  if (t == null) return '';
  final local = t.toLocal();
  final locale = Localizations.maybeLocaleOf(context)?.languageCode ?? 'hr';
  try {
    return DateFormat.yMMMd(locale).add_Hm().format(local);
  } catch (_) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${local.day}. ${local.month}. ${local.year}. '
        '${two(local.hour)}:${two(local.minute)}';
  }
}

class ChannelSettingsScreen extends StatefulWidget {
  const ChannelSettingsScreen({
    super.key,
    required this.youtubeChannelId,
    this.backend,
    this.launcher,
  });

  /// UC… id; ekran postoji samo za kanale s UC-om (odluka 7).
  final String youtubeChannelId;

  /// `null` = [ChannelSettingsBackend.instance]. Testovi daju lažnjak.
  final ChannelSettingsBackend? backend;

  /// Otvara `tel:` poveznicu; `null` = `url_launcher`.
  final Future<bool> Function(Uri uri)? launcher;

  @override
  State<ChannelSettingsScreen> createState() => _ChannelSettingsScreenState();
}

class _ChannelSettingsScreenState extends State<ChannelSettingsScreen> {
  static const int _logPage = 50;

  late final ChannelSettingsBackend _backend =
      widget.backend ?? ChannelSettingsBackend.instance;
  String get _uc => widget.youtubeChannelId;

  bool _loading = true;
  String? _userId;
  ChannelClaim? _claim;
  ChannelSettings _settings = ChannelSettings.defaults;
  bool _settingsFailed = false;

  List<ChannelSettingsEvent> _log = const [];
  final List<ChannelSettingsEvent> _pending = [];
  bool _logFailed = false;
  bool _logHasMore = false;
  bool _logLoadingMore = false;

  ChannelDeletionRequest? _deletion;
  bool _deletionBusy = false;
  final _confirmCtrl = TextEditingController();

  final Set<String> _saving = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _confirmCtrl.dispose();
    super.dispose();
  }

  bool get _expired => _claim?.needsReverify(DateTime.now()) ?? false;

  bool get _canWrite =>
      _claim != null &&
      _claim!.isVerified &&
      (_claim!.role == ClaimRole.primary ||
          _claim!.role == ClaimRole.collaborator) &&
      !_expired &&
      !_settings.tombstoned;

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _settingsFailed = false;
    });
    final uid = _backend.currentUserId;
    ChannelClaim? claim;
    if (uid != null) {
      try {
        claim = await _backend.myClaim(_uc);
      } catch (e) {
        log('channel settings claim: $e');
      }
    }
    if (!mounted) return;
    if (uid == null || claim == null || !claim.isVerified) {
      setState(() {
        _userId = uid;
        _claim = claim;
        _loading = false;
      });
      return;
    }

    final settingsF = _backend.fetchSettings(_uc);
    final deletionF = _backend.fetchOpenDeletionRequest(_uc);
    ChannelSettings? settings;
    ChannelDeletionRequest? deletion;
    try {
      settings = await settingsF;
    } on ChannelSettingsException catch (e) {
      log('channel settings load: $e');
    }
    try {
      deletion = await deletionF;
    } on ChannelSettingsException catch (e) {
      log('channel deletion load: $e');
    }
    if (!mounted) return;
    setState(() {
      _userId = uid;
      _claim = claim;
      _settings = settings ?? ChannelSettings.defaults;
      _settingsFailed = settings == null;
      _deletion = deletion;
    });
    await _reloadLog();
    if (mounted) setState(() => _loading = false);
  }

  static List<ChannelSettingsEvent> _newestFirst(
    Iterable<ChannelSettingsEvent> rows,
  ) => rows.toList()..sort((a, b) => (b.id ?? 0).compareTo(a.id ?? 0));

  Future<void> _reloadLog() async {
    try {
      final rows = await _backend.fetchLog(_uc, limit: _logPage);
      if (!mounted) return;
      setState(() {
        _log = _newestFirst(rows);
        _logHasMore = rows.length == _logPage;
        _logFailed = false;
      });
    } on ChannelSettingsException catch (e) {
      log('channel settings log: $e');
      if (!mounted) return;
      setState(() => _logFailed = true);
    }
  }

  Future<void> _loadOlder() async {
    final before = _log.isEmpty ? null : _log.last.id;
    if (before == null || _logLoadingMore) return;
    setState(() => _logLoadingMore = true);
    try {
      final rows = await _backend.fetchLog(
        _uc,
        limit: _logPage,
        before: before,
      );
      if (!mounted) return;
      setState(() {
        _log = _newestFirst([..._log, ...rows]);
        _logHasMore = rows.length == _logPage;
      });
    } on ChannelSettingsException catch (e) {
      log('channel settings log older: $e');
      if (mounted) _snack(channelSettingsErrorText(_l, e.code));
    } finally {
      if (mounted) setState(() => _logLoadingMore = false);
    }
  }

  AppLocalizations get _l => AppLocalizations.of(context);

  void _snack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _toggle(String key, bool value) async {
    if (!_canWrite || _saving.contains(key)) return;
    final old = _settings.rawValue(key);
    if (old == value) return;
    final pending = ChannelSettingsEvent.pendingSetting(
      key: key,
      oldValue: old,
      newValue: value,
      accountId: _userId,
      role: _claim?.role.name,
      at: DateTime.now(),
    );
    setState(() {
      _settings = _settings.withRaw(key, value);
      _pending.insert(0, pending);
      _saving.add(key);
    });
    try {
      final effective = await _backend.setSetting(_uc, key, value);
      if (!mounted) return;
      setState(() {
        _settings = _settings.withEffective(effective);
        _saving.remove(key);
      });
      await _reloadLog();
      if (!mounted) return;
      setState(() => _pending.remove(pending));
    } on ChannelSettingsException catch (e) {
      log('set_channel_setting $key=$value: $e');
      if (!mounted) return;
      setState(() {
        _settings = _settings.withRaw(key, old);
        _pending.remove(pending);
        _saving.remove(key);
      });
      _snack(channelSettingsErrorText(_l, e.code));
    }
  }

  bool _nameMatches(String? title) {
    final want = title?.trim() ?? '';
    return want.isNotEmpty && _confirmCtrl.text.trim() == want;
  }

  Future<void> _requestDeletion() async {
    final title = _claim?.channelTitle;
    if (!_canWrite || _deletionBusy || !_nameMatches(title)) return;
    final l = _l;
    setState(() => _deletionBusy = true);
    try {
      final id = await _backend.requestDeletion(_uc, _confirmCtrl.text.trim());
      ChannelDeletionRequest? req;
      try {
        req = await _backend.fetchOpenDeletionRequest(_uc);
      } on ChannelSettingsException catch (e) {
        log('channel deletion reload: $e');
      }
      if (!mounted) return;
      setState(() {
        _deletion =
            req ??
            ChannelDeletionRequest(
              id: id,
              youtubeChannelId: _uc,
              state: ChannelDeletionState.requested,
              channelTitle: title,
              requestedAt: DateTime.now(),
            );
        _confirmCtrl.clear();
      });
      _snack(l.channelSettingsDeleteRequestedSnack);
      await _reloadLog();
    } on ChannelSettingsException catch (e) {
      log('request_channel_deletion: $e');
      if (!mounted) return;
      _snack(channelSettingsErrorText(l, e.code));
      if (e.code == 'deletion_already_requested') await _reloadDeletion();
    } finally {
      if (mounted) setState(() => _deletionBusy = false);
    }
  }

  Future<void> _cancelDeletion() async {
    if (!_canWrite || _deletionBusy) return;
    final l = _l;
    setState(() => _deletionBusy = true);
    try {
      await _backend.cancelDeletion(_uc);
      if (!mounted) return;
      await _reloadDeletion(fallbackClosed: true);
      _snack(l.channelSettingsDeleteCancelledSnack);
      await _reloadLog();
    } on ChannelSettingsException catch (e) {
      log('cancel_channel_deletion: $e');
      if (!mounted) return;
      _snack(channelSettingsErrorText(l, e.code));
      await _reloadDeletion();
    } finally {
      if (mounted) setState(() => _deletionBusy = false);
    }
  }

  Future<void> _reloadDeletion({bool fallbackClosed = false}) async {
    try {
      final req = await _backend.fetchOpenDeletionRequest(_uc);
      if (mounted) setState(() => _deletion = req);
    } on ChannelSettingsException catch (e) {
      log('channel deletion reload: $e');
      if (mounted && fallbackClosed) setState(() => _deletion = null);
    }
  }

  Future<void> _callPhone() async {
    final launch =
        widget.launcher ??
        (Uri u) => launchUrl(u, mode: LaunchMode.externalApplication);
    try {
      await launch(kChannelDeletionPhoneUri);
    } catch (e) {
      log('tel launch: $e');
    }
  }

  // ── UI ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final title = _claim?.channelTitle ?? l.ownershipChannelFallback;
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: OwnershipCrumbs([
          (l.ownershipCrumbHome, () => context.go('/')),
          (l.ownershipMyChannels, () => context.go('/account/channels')),
          (title, () => context.go('/account/channels/$_uc')),
          (l.channelSettingsTitle, null),
        ]),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : LayoutBuilder(
              builder: (context, c) {
                // Sadržaj najviše 720 px, ali scroll ide do ruba ekrana:
                // razmak je padding LISTE, ne omotač oko nje.
                final side = math.max(0.0, (c.maxWidth - 720) / 2);
                return RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: EdgeInsets.fromLTRB(side, 16, side, 32),
                    children: _body(context, l),
                  ),
                );
              },
            ),
    );
  }

  List<Widget> _body(BuildContext context, AppLocalizations l) {
    final theme = Theme.of(context);
    if (_userId == null) return [_info(theme, l.channelSettingsSignIn)];
    final claim = _claim;
    if (claim == null || !claim.isVerified) {
      return [_info(theme, l.channelSettingsNotOwner)];
    }
    if (_settingsFailed) {
      return [
        _info(theme, l.channelSettingsLoadFailed),
        Center(
          child: OutlinedButton(onPressed: _load, child: Text(l.commonRetry)),
        ),
      ];
    }
    return [
      _pad(Text(claim.channelTitle ?? _uc, style: theme.textTheme.titleLarge)),
      _pad(Text(_uc, style: theme.textTheme.bodySmall)),
      const SizedBox(height: 12),
      if (_settings.tombstoned)
        _banner(theme, l.channelSettingsTombstoned)
      else if (_expired)
        _banner(
          theme,
          l.channelSettingsReverifyBody,
          action: FilledButton.icon(
            key: const ValueKey('channel-settings-reverify'),
            onPressed: () => drillDown(context, '/account/channels/$_uc'),
            icon: const Icon(Icons.verified_user_outlined),
            label: Text(l.channelSettingsReverifyAction),
          ),
        ),
      _switch(context, l, kChannelEnabledKey),
      for (final (group, heading) in [
        (ChannelSettingGroup.presence, l.channelSettingsGroupPresence),
        (ChannelSettingGroup.media, l.channelSettingsGroupMedia),
        (ChannelSettingGroup.ai, l.channelSettingsGroupAi),
        (ChannelSettingGroup.money, l.channelSettingsGroupMoney),
      ]) ...[
        const SizedBox(height: 8),
        _heading(theme, heading),
        for (final key in channelSettingKeysOf(group)) _switch(context, l, key),
      ],
      const SizedBox(height: 16),
      const Divider(),
      _heading(theme, l.channelSettingsLogTitle),
      ..._logSection(context, l),
      const SizedBox(height: 16),
      const Divider(),
      _deletionSection(context, l),
    ];
  }

  Widget _pad(Widget child) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16),
    child: child,
  );

  Widget _heading(ThemeData theme, String text) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
    child: Text(
      text,
      style: theme.textTheme.titleMedium?.copyWith(
        color: theme.colorScheme.primary,
      ),
    ),
  );

  Widget _info(ThemeData theme, String msg) => Padding(
    padding: const EdgeInsets.all(32),
    child: Text(
      msg,
      textAlign: TextAlign.center,
      style: theme.textTheme.bodyMedium?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
      ),
    ),
  );

  Widget _banner(ThemeData theme, String text, {Widget? action}) => Card(
    margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
    color: theme.colorScheme.surfaceContainerHighest,
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(text),
          if (action != null) ...[const SizedBox(height: 12), action],
        ],
      ),
    ),
  );

  Widget _switch(BuildContext context, AppLocalizations l, String key) {
    final theme = Theme.of(context);
    final isMaster = key == kChannelEnabledKey;
    String? blocked;
    if (!isMaster && !_settings.rawValue(kChannelEnabledKey)) {
      blocked = l.channelSettingsBlockedByMaster;
    } else if (!isMaster && _settings.isOverridden(key)) {
      final parent = _settings.blockingParent(key);
      blocked = parent == null
          ? l.channelSettingsBlockedGeneric
          : l.channelSettingsBlockedByParent(channelSettingLabel(l, parent));
    }
    final enabled = _canWrite && blocked == null && !_saving.contains(key);
    final muted = theme.colorScheme.onSurfaceVariant;
    return SwitchListTile(
      key: ValueKey('channel-setting-$key'),
      value: _settings.rawValue(key),
      onChanged: enabled ? (v) => _toggle(key, v) : null,
      title: Text(
        channelSettingLabel(l, key),
        style: isMaster
            ? theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)
            : null,
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(channelSettingOffMeaning(l, key)),
          if (key == 'cdn_playback')
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                l.channelSettingsCdnPlaybackNote,
                style: theme.textTheme.bodySmall?.copyWith(color: muted),
              ),
            ),
          if (blocked != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.info_outline, size: 16, color: muted),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      blocked,
                      key: ValueKey('channel-setting-blocked-$key'),
                      style: theme.textTheme.bodySmall?.copyWith(color: muted),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  // ── log ─────────────────────────────────────────────────────────────────

  List<Widget> _logSection(BuildContext context, AppLocalizations l) {
    final theme = Theme.of(context);
    final rows = [..._pending, ..._log];
    return [
      if (_logFailed && _log.isEmpty)
        _pad(Text(l.channelSettingsLogLoadFailed))
      else if (rows.isEmpty)
        _pad(
          Text(
            l.channelSettingsLogEmpty,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      for (final ev in rows) _logTile(context, l, ev),
      if (_logHasMore)
        Align(
          alignment: Alignment.centerLeft,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: TextButton(
              key: const ValueKey('channel-settings-log-older'),
              onPressed: _logLoadingMore ? null : _loadOlder,
              child: Text(l.channelSettingsLogLoadOlder),
            ),
          ),
        ),
    ];
  }

  Widget _logTile(
    BuildContext context,
    AppLocalizations l,
    ChannelSettingsEvent ev,
  ) {
    final theme = Theme.of(context);
    final key = ev.pending
        ? ValueKey('channel-settings-log-pending-${ev.key}')
        : ValueKey('channel-settings-log-${ev.id}');
    return ListTile(
      key: key,
      dense: true,
      leading: ev.pending
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Icon(_eventIcon(ev), color: theme.colorScheme.onSurfaceVariant),
      title: Text(_eventTitle(l, ev)),
      subtitle: Text(
        ev.pending
            ? l.channelSettingsLogSaving
            : l.channelSettingsLogMeta(
                _who(l, ev),
                channelSettingsWhen(context, ev.createdAt),
              ),
      ),
    );
  }

  static IconData _eventIcon(ChannelSettingsEvent ev) => switch (ev.kind) {
    ChannelSettingsEventKind.setting =>
      ev.newValue == false
          ? Icons.toggle_off_outlined
          : Icons.toggle_on_outlined,
    ChannelSettingsEventKind.deletionRequested => Icons.delete_outline,
    ChannelSettingsEventKind.deletionCancelled => Icons.undo,
    ChannelSettingsEventKind.deletionPhoneConfirmed => Icons.phone_outlined,
    ChannelSettingsEventKind.deletionExecuted => Icons.delete_forever_outlined,
    ChannelSettingsEventKind.unknown => Icons.history,
  };

  String _eventTitle(AppLocalizations l, ChannelSettingsEvent ev) {
    String v(bool? b) =>
        b == false ? l.channelSettingsValueOff : l.channelSettingsValueOn;
    return switch (ev.kind) {
      ChannelSettingsEventKind.setting => l.channelSettingsLogSettingChange(
        channelSettingLabel(l, ev.key ?? ''),
        v(ev.newValue),
        v(ev.oldValue),
      ),
      ChannelSettingsEventKind.deletionRequested =>
        l.channelSettingsLogDeletionRequested,
      ChannelSettingsEventKind.deletionCancelled =>
        l.channelSettingsLogDeletionCancelled,
      ChannelSettingsEventKind.deletionPhoneConfirmed =>
        l.channelSettingsLogDeletionPhoneConfirmed,
      ChannelSettingsEventKind.deletionExecuted =>
        l.channelSettingsLogDeletionExecuted,
      ChannelSettingsEventKind.unknown => l.channelSettingsLogUnknown,
    };
  }

  String _who(AppLocalizations l, ChannelSettingsEvent ev) {
    final base = switch (ev.source) {
      'phone' => l.channelSettingsRoleOperator,
      'system' => l.channelSettingsRoleSystem,
      _ =>
        ev.role == 'collaborator'
            ? l.channelSettingsRoleCollaborator
            : l.channelSettingsRoleOwner,
    };
    final mine =
        ev.source == 'app' && ev.accountId != null && ev.accountId == _userId;
    return mine ? l.channelSettingsWhoYou(base) : base;
  }

  // ── trajno brisanje ─────────────────────────────────────────────────────

  Widget _deletionSection(BuildContext context, AppLocalizations l) {
    final theme = Theme.of(context);
    final req = _deletion;
    final title = _claim?.channelTitle?.trim();
    final hasTitle = title != null && title.isNotEmpty;
    final children = <Widget>[
      Text(
        l.channelSettingsDeleteTitle,
        style: theme.textTheme.titleMedium?.copyWith(
          color: theme.colorScheme.error,
        ),
      ),
      const SizedBox(height: 8),
      Text(l.channelSettingsDeleteBody),
      const SizedBox(height: 12),
    ];

    if (req != null && req.isOpen) {
      if (req.state == ChannelDeletionState.phoneConfirmed) {
        children.add(
          Text(
            l.channelSettingsDeletePhoneConfirmed(
              channelSettingsWhen(context, req.phoneConfirmedAt),
            ),
            key: const ValueKey('channel-settings-deletion-confirmed'),
          ),
        );
      } else {
        children.addAll([
          Text(
            l.channelSettingsDeleteRequestedAt(
              channelSettingsWhen(context, req.requestedAt),
            ),
            key: const ValueKey('channel-settings-deletion-requested'),
          ),
          const SizedBox(height: 4),
          Text(
            l.channelSettingsDeleteCallToFinish,
            style: theme.textTheme.bodyLarge?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          _phoneLink(),
          if (_canWrite) ...[
            const SizedBox(height: 8),
            OutlinedButton(
              key: const ValueKey('channel-settings-cancel-deletion'),
              onPressed: _deletionBusy ? null : _cancelDeletion,
              child: Text(l.channelSettingsDeleteCancelAction),
            ),
          ],
        ]);
      }
    } else if (_canWrite) {
      if (!hasTitle) {
        children.addAll([
          Text(l.channelSettingsDeleteNoTitle),
          const SizedBox(height: 8),
          _phoneLink(),
        ]);
      } else {
        children.addAll([
          TextField(
            key: const ValueKey('channel-settings-delete-name'),
            controller: _confirmCtrl,
            autocorrect: false,
            enableSuggestions: false,
            decoration: InputDecoration(
              labelText: l.channelSettingsDeleteConfirmLabel(title),
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          ValueListenableBuilder<TextEditingValue>(
            valueListenable: _confirmCtrl,
            builder: (context, value, child) => FilledButton.icon(
              key: const ValueKey('channel-settings-delete-button'),
              style: FilledButton.styleFrom(
                backgroundColor: theme.colorScheme.error,
                foregroundColor: theme.colorScheme.onError,
              ),
              onPressed: !_deletionBusy && _nameMatches(title)
                  ? _requestDeletion
                  : null,
              icon: const Icon(Icons.delete_forever_outlined),
              label: Text(l.channelSettingsDeleteAction),
            ),
          ),
        ]);
      }
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      ),
    );
  }

  Widget _phoneLink() => TextButton.icon(
    key: const ValueKey('channel-settings-phone-link'),
    onPressed: _callPhone,
    icon: const Icon(Icons.phone_outlined),
    label: const Text(kChannelDeletionPhoneDisplay),
  );
}

/// Traka na vlasnikovom ekranu kampanja kad su donacije efektivno
/// isključene. Backend uplate ionako odbija; ovo je samo informacija.
class ChannelDonationsOffBanner extends StatelessWidget {
  const ChannelDonationsOffBanner({
    super.key,
    required this.youtubeChannelId,
    required this.settings,
  });

  final String youtubeChannelId;
  final ChannelSettings settings;

  @override
  Widget build(BuildContext context) {
    if (settings.effectiveValue('donations')) return const SizedBox.shrink();
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Card(
      key: const ValueKey('channel-donations-off-banner'),
      color: theme.colorScheme.surfaceContainerHighest,
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline, color: theme.colorScheme.primary),
                const SizedBox(width: 12),
                Expanded(child: Text(l.channelSettingsDonationsOffBanner)),
              ],
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () => drillDown(
                  context,
                  channelSettingsLocation(youtubeChannelId),
                ),
                child: Text(l.channelSettingsOpenAction),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
