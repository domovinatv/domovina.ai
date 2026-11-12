import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../../models/channel_claim.dart';
import '../../../pinka_sdk/pinka_sdk.dart';
import '../../../services/auth_service.dart';
import '../../../services/channel_ownership_service.dart';
import '../../../services/channel_settings_service.dart';
import '../../../router/nav.dart';
import '../channel_settings_screen.dart' show ChannelDonationsOffBanner;

/// Lista Pinka kampanja ankeriranih na verificirani kanal (UC… id). Ulaz iz
/// "Moji kanali". Faza A: pregled + ulaz u upravljanje (bez in-app kreiranja).
class ChannelCampaignsScreen extends StatefulWidget {
  final String youtubeChannelId; // UC…

  /// Postavke kanala (traka „donacije isključene”); `null` =
  /// [ChannelSettingsBackend.instance].
  final ChannelSettingsBackend? settingsBackend;

  const ChannelCampaignsScreen({
    super.key,
    required this.youtubeChannelId,
    this.settingsBackend,
  });

  @override
  State<ChannelCampaignsScreen> createState() => _ChannelCampaignsScreenState();
}

class _ChannelCampaignsScreenState extends State<ChannelCampaignsScreen> {
  bool _loading = true;
  ChannelClaim? _claim;
  List<PinkaOwnerCampaign> _campaigns = const [];
  ChannelSettings? _settings;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final claim =
        await ChannelOwnershipService.instance.myClaimFor(widget.youtubeChannelId);
    final campaigns = (claim?.isVerified ?? false)
        ? await PinkaAdminClient.instance
            .listCampaignsForChannel(widget.youtubeChannelId)
        : const <PinkaOwnerCampaign>[];
    // Postavke kanala: samo informacija (backend uplate ionako odbija), pa
    // greška ne ruši ekran.
    ChannelSettings? settings;
    if (claim?.isVerified ?? false) {
      try {
        settings = await (widget.settingsBackend ??
                ChannelSettingsBackend.instance)
            .fetchSettings(widget.youtubeChannelId);
      } on ChannelSettingsException {
        settings = null;
      }
    }
    if (!mounted) return;
    setState(() {
      _claim = claim;
      _campaigns = campaigns;
      _settings = settings;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(_claim?.channelTitle ?? l.ownershipCampaignsTitle),
      ),
      body: AnimatedBuilder(
        animation: AuthService.instance,
        builder: (context, _) {
          if (!AuthService.instance.isSignedIn) {
            return _info(theme, l.ownershipSignInToManageCampaigns);
          }
          if (_loading) {
            return const Center(child: CircularProgressIndicator());
          }
          if (!(_claim?.isVerified ?? false)) {
            return _info(theme, l.ownershipNotVerifiedOwner);
          }
          return RefreshIndicator(
            onRefresh: _load,
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (_settings != null)
                  ChannelDonationsOffBanner(
                    youtubeChannelId: widget.youtubeChannelId,
                    settings: _settings!,
                  ),
                if (_campaigns.isEmpty)
                  _empty(l, theme)
                else
                  ..._campaigns.map((c) => _campaignTile(l, theme, c)),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _campaignTile(AppLocalizations l, ThemeData theme, PinkaOwnerCampaign c) {
    final raised = (c.totalRaisedCents / 100);
    final raisedStr = raised == raised.truncateToDouble()
        ? raised.toStringAsFixed(0)
        : raised.toStringAsFixed(2);
    return Card(
      child: ListTile(
        leading: Icon(
          c.state == 'active'
              ? Icons.campaign
              : c.state == 'draft'
                  ? Icons.edit_note
                  : Icons.flag,
          color: c.state == 'active' ? theme.colorScheme.tertiary : null,
        ),
        title: Text(c.title, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text(
          '${_stateLabel(l, c.state)} · ${_visLabel(l, c.visibility)} · '
          '$raisedStr € · ${l.ownershipEpisodesCount(c.episodeRefs.length)}',
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => drillDown(
          context,
          '/account/channels/${widget.youtubeChannelId}/campaigns/${c.id}',
        ),
      ),
    );
  }

  Widget _empty(AppLocalizations l, ThemeData theme) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l.ownershipNoCampaignsTitle,
                style: theme.textTheme.titleSmall),
            const SizedBox(height: 6),
            Text(
              l.ownershipNoCampaignsBody,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }

  Widget _info(ThemeData theme, String msg) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Text(msg,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
      ),
    );
  }

  static String _stateLabel(AppLocalizations l, String s) => switch (s) {
        'draft' => l.ownershipStateDraft,
        'active' => l.ownershipStateActive,
        'funded' => l.ownershipStateFunded,
        'closed' => l.ownershipStateClosed,
        'cancelled' => l.ownershipStateCancelled,
        _ => s,
      };

  static String _visLabel(AppLocalizations l, String v) => switch (v) {
        'public' => l.ownershipVisPublic,
        'unlisted' => l.ownershipVisUnlisted,
        'private' => l.ownershipVisPrivate,
        _ => v,
      };
}
