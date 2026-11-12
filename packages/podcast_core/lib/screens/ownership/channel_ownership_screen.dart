/// Channel ownership UI — vlasnik preuzima kanal, verificira identitet,
/// registrira novčanik (odredište isplate). Tri ekrana (go_router rute):
///   - `ChannelOwnershipScreen`     (`/c/:channelId/claim`)    — per-kanal flow
///   - `YoutubeClaimCallbackScreen` (`/youtube-claim/callback`) — OAuth povratak
///   - `MyChannelsScreen`           (`/account/channels`)      — lista claimova
/// Vidi docs/channel-ownership-and-safe-payout-plan.md §5–§11.
library;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../brand/app_brand.dart';
import '../../l10n/app_localizations.dart';
import '../../src/log.dart' show log;
import '../../models/channel_claim.dart';
import '../../models/channel_detail.dart';
import '../../models/owner_wallet.dart';
import '../../models/payout_eligibility.dart';
import '../../services/auth_service.dart';
import '../../services/channel_ownership_service.dart';
import '../../services/data_service.dart';
import '../../services/locale_service.dart';
import '../../services/wallet_service.dart';
import '../../router/nav.dart';
import 'channel_settings_screen.dart' show channelSettingsLocation;

// ───────────────────────────────────────────────────────────────────────────
// Per-channel claim flow
// ───────────────────────────────────────────────────────────────────────────

// AppBar breadcrumb (Početna › … › current). In-app navigacija natrag —
// nuždan jer iOS PWA nema browser back. Zadnji čvor je "current" (ne-tappable).
class _Crumbs extends StatelessWidget {
  final List<(String, VoidCallback?)> items;
  const _Crumbs(this.items);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final row = <Widget>[];
    for (var i = 0; i < items.length; i++) {
      final (label, onTap) = items[i];
      final current = i == items.length - 1;
      final text = Text(
        label,
        maxLines: 1,
        softWrap: false,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.titleMedium?.copyWith(
          fontWeight: current ? FontWeight.w600 : FontWeight.w500,
          color: current ? theme.colorScheme.onSurface : muted,
        ),
      );
      row.add(
        onTap == null
            ? text
            : InkWell(
                onTap: onTap,
                borderRadius: BorderRadius.circular(6),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 2,
                  ),
                  child: text,
                ),
              ),
      );
      if (!current) row.add(Icon(Icons.chevron_right, size: 18, color: muted));
    }
    // Rubnih 16px je content padding UNUTAR scrolla (uz titleSpacing: 0 na
    // AppBaru) — inače se scrollabilni breadcrumb reže 16px od ruba ekrana.
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(mainAxisSize: MainAxisSize.min, children: row),
    );
  }
}

/// Isti breadcrumb za susjedne ekrane vlasnika (postavke kanala).
class OwnershipCrumbs extends StatelessWidget {
  final List<(String, VoidCallback?)> items;
  const OwnershipCrumbs(this.items, {super.key});

  @override
  Widget build(BuildContext context) => _Crumbs(items);
}

class ChannelOwnershipScreen extends StatefulWidget {
  /// Interni channel slug (kao `/c/:id`) — screen iz njega dohvati UC… ID.
  /// Alternativno (npr. iz "Moji kanali") otvori se direktno po [youtubeChannelId]
  /// (UC…), bez učitavanja channel.json — naziv se uzme iz claima.
  final String? channelId;
  final String? youtubeChannelId;
  const ChannelOwnershipScreen({
    super.key,
    this.channelId,
    this.youtubeChannelId,
  }) : assert(
         channelId != null || youtubeChannelId != null,
         'Treba channelId (slug) ili youtubeChannelId (UC…)',
       );

  @override
  State<ChannelOwnershipScreen> createState() => _ChannelOwnershipScreenState();
}

class _ChannelOwnershipScreenState extends State<ChannelOwnershipScreen> {
  ChannelDetail? _channel;
  ChannelClaim? _claim;
  String? _ucId;
  bool _loading = true;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      ChannelDetail? channel;
      String? ucId = widget.youtubeChannelId;
      if (widget.channelId != null) {
        channel = await ChannelService.loadChannel(widget.channelId!);
        ucId = channel.youtubeChannelId;
      }
      final claim = ucId == null
          ? null
          : await ChannelOwnershipService.instance.myClaimFor(ucId);
      if (!mounted) return;
      setState(() {
        _channel = channel;
        _ucId = ucId;
        _claim = claim;
        _loading = false;
      });
    } catch (e) {
      log('ownership load failed: $e');
      if (!mounted) return;
      setState(() {
        _error = appStrings.ownershipLoadChannelFailed;
        _loading = false;
      });
    }
  }

  Future<void> _startClaim() async {
    final ucId = _ucId;
    if (ucId == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final authUrl = await ChannelOwnershipService.instance.startClaim(ucId);
      final uri = Uri.parse(authUrl);
      // Web: redirect u istom tabu (callback dođe na /youtube-claim/callback).
      // Native: vanjski browser → ai.domovina:// deep link natrag.
      await launchUrl(
        uri,
        mode: kIsWeb
            ? LaunchMode.platformDefault
            : LaunchMode.externalApplication,
        webOnlyWindowName: kIsWeb ? '_self' : null,
      );
    } on ChannelOwnershipFailure catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message);
    } catch (e) {
      log('startClaim launch failed: $e');
      if (!mounted) return;
      setState(() => _error = appStrings.ownershipOpenAuthFailed);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: _Crumbs([
          (l.ownershipCrumbHome, () => context.go('/')),
          if (widget.channelId != null)
            (
              _channel?.name ?? l.ownershipChannelFallback,
              () => context.go('/c/${widget.channelId!.replaceAll('_', '-')}'),
            )
          else
            (l.ownershipMyChannels, () => context.go('/account/channels')),
          (l.ownershipCrumbOwnership, null),
        ]),
      ),
      body: AnimatedBuilder(
        animation: AuthService.instance,
        builder: (context, _) {
          if (_loading) {
            return const Center(child: CircularProgressIndicator());
          }
          return ListView(
            padding: const EdgeInsets.all(16),
            children: _buildBody(context),
          );
        },
      ),
    );
  }

  List<Widget> _buildBody(BuildContext context) {
    final l = AppLocalizations.of(context);
    final auth = AuthService.instance;
    final ucId = _ucId;
    final title = _channel?.name ?? _claim?.channelTitle ?? ucId;

    if (!auth.isSignedIn) {
      return [_infoCard(context, l.ownershipSignInToClaim)];
    }
    if (ucId == null) {
      return [
        _infoCard(
          context,
          _error ??
              (widget.channelId != null
                  ? l.ownershipNoYoutubeId
                  : l.ownershipChannelNotFound),
        ),
      ];
    }

    final eligibility = PayoutEligibility.evaluate(
      claim: _claim,
      isKycVerified: auth.currentUser?.isVerified ?? false,
      now: DateTime.now(),
    );

    return [
      Text(title ?? ucId, style: Theme.of(context).textTheme.titleLarge),
      const SizedBox(height: 4),
      Text(ucId, style: Theme.of(context).textTheme.bodySmall),
      // Postavke kanala (lanac postavke-kanala, S4): samo za potvrđen claim.
      if (_claim?.isVerified == true) ...[
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            key: const ValueKey('ownership-channel-settings'),
            onPressed: () => drillDown(context, channelSettingsLocation(ucId)),
            icon: const Icon(Icons.tune),
            label: Text(l.channelSettingsTitle),
          ),
        ),
      ],
      const SizedBox(height: 24),
      if (_error != null) ...[
        _errorBanner(context, _error!),
        const SizedBox(height: 16),
      ],
      _stepOwnership(context, eligibility),
      const SizedBox(height: 12),
      _stepKyc(context, eligibility),
      const SizedBox(height: 12),
      _stepWalletAndSafe(context, eligibility),
      if (widget.channelId != null && _claim?.isVerified != true) ...[
        const SizedBox(height: 20),
        _inviteOwnerCard(context, title ?? ucId),
      ],
    ];
  }

  // Poziv vlasniku kanala preko WhatsAppa (za korisnika koji nije vlasnik, ali
  // ga poznaje). wa.me/?text=… otvara WhatsApp s prefilanom porukom i pušta
  // korisnika da odabere primatelja (ne treba broj).
  Widget _inviteOwnerCard(BuildContext context, String channelTitle) {
    final l = AppLocalizations.of(context);
    final slugDashed = widget.channelId!.replaceAll('_', '-');
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l.ownershipNotOwnerTitle,
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 4),
            Text(l.ownershipNotOwnerBody(AppBrand.config.appName)),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () => _inviteOwnerWhatsApp(channelTitle, slugDashed),
              icon: const Icon(Icons.chat_outlined),
              label: Text(l.ownershipInviteOwnerWhatsApp),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _inviteOwnerWhatsApp(
    String channelTitle,
    String slugDashed,
  ) async {
    final link = AppBrand.config.shareUrl('/c/$slugDashed');
    final msg = appStrings.ownershipInviteMessage(
        channelTitle, link, AppBrand.config.appName);
    final uri = Uri.parse('https://wa.me/?text=${Uri.encodeComponent(msg)}');
    await launchUrl(
      uri,
      mode: kIsWeb
          ? LaunchMode.platformDefault
          : LaunchMode.externalApplication,
    );
  }

  // Step 1 — vlasništvo (YouTube OAuth).
  Widget _stepOwnership(BuildContext context, PayoutEligibility e) {
    final l = AppLocalizations.of(context);
    final claim = _claim;
    final reverify = e.block == EligibilityBlock.reverifyNeeded;
    final done = claim?.isVerified == true && !reverify;
    return _stepCard(
      context,
      index: 1,
      done: done,
      title: l.ownershipStepConfirmTitle,
      subtitle: reverify
          ? l.ownershipReverifySubtitle
          : claim?.isVerified == true
          ? l.ownershipOwnershipVerifiedSubtitle
          : l.ownershipSignInYoutubeSubtitle,
      note: done ? null : l.ownershipOwnershipNote,
      action: done
          ? null
          : FilledButton.icon(
              onPressed: _busy ? null : _startClaim,
              icon: const Icon(Icons.smart_display_outlined),
              label: Text(
                reverify ? l.ownershipReverifyAction : l.ownershipLoginYoutube,
              ),
            ),
    );
  }

  // Step 2 — KYC (Certilia eOsobna).
  Widget _stepKyc(BuildContext context, PayoutEligibility e) {
    final l = AppLocalizations.of(context);
    final auth = AuthService.instance;
    final locked = _claim?.isVerified != true;
    final done = auth.currentUser?.isVerified ?? false;
    return _stepCard(
      context,
      index: 2,
      done: done,
      locked: locked,
      title: l.ownershipStepVerifyIdentityTitle,
      subtitle: done
          ? l.ownershipIdentityVerifiedSubtitle
          : l.ownershipConnectEosobnaSubtitle,
      action: (locked || done)
          ? null
          : OutlinedButton.icon(
              onPressed: _busy ? null : () => _runKyc(context),
              icon: const Icon(Icons.badge_outlined),
              label: Text(l.ownershipVerifyWithEosobna),
            ),
    );
  }

  // Step 3 — wallet (odredište isplate).
  Widget _stepWalletAndSafe(BuildContext context, PayoutEligibility e) {
    final l = AppLocalizations.of(context);
    final locked = !e.isEligible;
    return _stepCard(
      context,
      index: 3,
      done: false,
      locked: locked,
      title: l.ownershipStepConnectWalletTitle,
      subtitle: locked
          ? l.ownershipWalletLockedSubtitle
          : l.ownershipWalletSubtitle,
      action: locked
          ? null
          : FilledButton.icon(
              onPressed: _busy ? null : () => drillDown(context, '/account/channels'),
              icon: const Icon(Icons.account_balance_wallet_outlined),
              label: Text(l.ownershipManageWallet),
            ),
    );
  }

  Future<void> _runKyc(BuildContext context) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      // AuthService spremi anon UUID + pokrene Certilia flow; app_metadata
      // .kyc_verified stigne preko onAuthStateChange.
      final result = await AuthService.instance.signInWithCertilia(context);
      if (mounted && result.status == AuthFlowStatus.failure) {
        setState(() => _error = result.message);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ── shared step UI ────────────────────────────────────────────────────────
  Widget _stepCard(
    BuildContext context, {
    required int index,
    required bool done,
    bool locked = false,
    required String title,
    required String subtitle,
    Widget? action,
    String? note,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final Color circleColor = done
        ? Colors.green
        : locked
        ? scheme.outlineVariant
        : scheme.primary;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(
              radius: 16,
              backgroundColor: circleColor,
              child: done
                  ? const Icon(Icons.check, size: 18, color: Colors.white)
                  : Text('$index', style: const TextStyle(color: Colors.white)),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 4),
                  Text(subtitle, style: Theme.of(context).textTheme.bodyMedium),
                  if (note != null) ...[
                    const SizedBox(height: 10),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.info_outline,
                          size: 16,
                          color: scheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            note,
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(color: scheme.onSurfaceVariant),
                          ),
                        ),
                      ],
                    ),
                  ],
                  if (action != null) ...[const SizedBox(height: 12), action],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _infoCard(BuildContext context, String text) => Card(
    child: Padding(padding: const EdgeInsets.all(16), child: Text(text)),
  );

  Widget _errorBanner(BuildContext context, String text) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.errorContainer,
      borderRadius: BorderRadius.circular(8),
    ),
    child: Text(
      text,
      style: TextStyle(color: Theme.of(context).colorScheme.onErrorContainer),
    ),
  );
}

// ───────────────────────────────────────────────────────────────────────────
// OAuth callback — /youtube-claim/callback?code&state
// ───────────────────────────────────────────────────────────────────────────

class YoutubeClaimCallbackScreen extends StatefulWidget {
  final String? code;
  final String? state;
  const YoutubeClaimCallbackScreen({super.key, this.code, this.state});

  @override
  State<YoutubeClaimCallbackScreen> createState() =>
      _YoutubeClaimCallbackScreenState();
}

class _YoutubeClaimCallbackScreenState
    extends State<YoutubeClaimCallbackScreen> {
  // Null dok traje provjera — build tada prikaže lokalizirani
  // "Provjeravamo vlasništvo…" preko contexta (reagira na promjenu jezika).
  String? _message;
  String? _boldTerm;
  bool _done = false;
  bool _ok = false;

  @override
  void initState() {
    super.initState();
    _complete();
  }

  Future<void> _complete() async {
    final code = widget.code;
    final state = widget.state;
    if (code == null || state == null) {
      setState(() {
        _message = appStrings.ownershipMissingAuthData;
        _done = true;
      });
      return;
    }
    try {
      final claim = await ChannelOwnershipService.instance.completeClaim(
        code: code,
        state: state,
      );
      if (!mounted) return;
      setState(() {
        _ok = claim.isVerified;
        _message = claim.isVerified
            ? appStrings.ownershipOwnershipConfirmedWithName(
                claim.channelTitle ?? claim.youtubeChannelId,
              )
            : appStrings.ownershipRequestReceivedWithStatus(claim.status.name);
        _done = true;
      });
    } on ChannelOwnershipFailure catch (e) {
      if (!mounted) return;
      setState(() {
        _message = e.message;
        _boldTerm = e.boldTerm;
        _done = true;
      });
    }
  }

  // Poruka s opcionalno boldanim pojmom (npr. naziv kanala).
  Widget _messageWidget(BuildContext context) {
    final message =
        _message ?? AppLocalizations.of(context).ownershipCheckingOwnership;
    final term = _boldTerm;
    final base = Theme.of(context).textTheme.bodyMedium;
    if (term == null || !message.contains(term)) {
      return Text(message, textAlign: TextAlign.center, style: base);
    }
    final i = message.indexOf(term);
    return Text.rich(
      TextSpan(
        style: base,
        children: [
          TextSpan(text: message.substring(0, i)),
          TextSpan(
            text: term,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          TextSpan(text: message.substring(i + term.length)),
        ],
      ),
      textAlign: TextAlign.center,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l.ownershipCallbackTitle)),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!_done)
                const CircularProgressIndicator()
              else
                Icon(
                  _ok ? Icons.verified : Icons.error_outline,
                  size: 48,
                  color: _ok
                      ? Colors.green
                      : Theme.of(context).colorScheme.error,
                ),
              const SizedBox(height: 16),
              _messageWidget(context),
              if (_done) ...[
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: () => back(context,
                      fallback: '/account/channels'),
                  child: Text(l.ownershipMyChannels),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ───────────────────────────────────────────────────────────────────────────
// Moji kanali + novčanik — /account/channels
// ───────────────────────────────────────────────────────────────────────────

class MyChannelsScreen extends StatefulWidget {
  const MyChannelsScreen({super.key});

  @override
  State<MyChannelsScreen> createState() => _MyChannelsScreenState();
}

class _MyChannelsScreenState extends State<MyChannelsScreen> {
  List<ChannelClaim> _claims = const [];
  List<OwnerWallet> _wallets = const [];
  bool _loading = true;
  final _walletCtrl = TextEditingController();
  String? _walletError;
  bool _walletBusy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _walletCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final claims = await ChannelOwnershipService.instance.myClaims();
    final wallets = await WalletService.instance.myWallets();
    if (!mounted) return;
    setState(() {
      _claims = claims;
      _wallets = wallets;
      _loading = false;
    });
  }

  Future<void> _addWallet() async {
    setState(() {
      _walletBusy = true;
      _walletError = null;
    });
    try {
      await WalletService.instance.register(_walletCtrl.text);
      _walletCtrl.clear();
      await _load();
    } on WalletFailure catch (e) {
      if (!mounted) return;
      setState(() => _walletError = e.message);
    } finally {
      if (mounted) setState(() => _walletBusy = false);
    }
  }

  Future<void> _reverify(ChannelClaim claim) async {
    try {
      await ChannelOwnershipService.instance.reverify(claim.id);
      await _load();
    } on ChannelOwnershipFailure catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _confirmRevoke(ChannelClaim c) async {
    final l = AppLocalizations.of(context);
    final name = c.channelTitle ?? c.youtubeChannelId;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.ownershipRevokeDialogTitle),
        content: Text(l.ownershipRevokeDialogBody(name)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l.commonCancel),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l.ownershipRevokeAction),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ChannelOwnershipService.instance.revokeClaim(c.id);
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l.ownershipRevokedSnack)));
    } on ChannelOwnershipFailure catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: _Crumbs([
          (l.ownershipCrumbHome, () => context.go('/')),
          (l.ownershipMyChannels, null),
        ]),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Text(
                    l.ownershipClaimedChannelsTitle,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  if (_claims.isEmpty)
                    _emptyClaims(context)
                  else
                    ..._claims.map((c) => _claimTile(context, c)),
                  const SizedBox(height: 24),
                  Text(
                    l.ownershipPayoutWalletsTitle,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    l.ownershipPayoutWalletsDesc,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 10),
                  ..._wallets.map((w) => _walletTile(context, w)),
                  const SizedBox(height: 12),
                  _addWalletForm(context),
                ],
              ),
            ),
    );
  }

  Widget _emptyClaims(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l.ownershipNoClaimsBody),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: () => context.go('/'),
          icon: const Icon(Icons.podcasts),
          label: Text(l.ownershipBrowseChannels),
        ),
      ],
    );
  }

  Widget _claimTile(BuildContext context, ChannelClaim c) {
    final l = AppLocalizations.of(context);
    final needsReverify = c.needsReverify(DateTime.now());
    return Card(
      child: ListTile(
        leading: Icon(
          c.isVerified ? Icons.verified : Icons.hourglass_empty,
          color: c.isVerified ? Colors.green : null,
        ),
        title: Text(c.channelTitle ?? c.youtubeChannelId),
        subtitle: Text(
          '${c.status.name} · ${c.role.name}'
          '${needsReverify ? ' · ${l.ownershipNeedsReverifyTag}' : ''}',
        ),
        trailing: PopupMenuButton<String>(
          tooltip: l.ownershipOptionsTooltip,
          onSelected: (v) {
            if (v == 'campaigns') {
              drillDown(context,
                  '/account/channels/${c.youtubeChannelId}/campaigns');
            }
            if (v == 'settings') {
              drillDown(context, channelSettingsLocation(c.youtubeChannelId));
            }
            if (v == 'reverify') _reverify(c);
            if (v == 'revoke') _confirmRevoke(c);
          },
          itemBuilder: (_) => [
            // Postavke kanala — samo za verificirane kanale (S4).
            if (c.isVerified)
              PopupMenuItem(
                value: 'settings',
                child: Text(l.channelSettingsTitle),
              ),
            // Pinka "Zid podrške" kampanje — samo za verificirane kanale.
            if (c.isVerified)
              PopupMenuItem(
                value: 'campaigns',
                child: Text(l.ownershipCampaignsMenu),
              ),
            if (needsReverify)
              PopupMenuItem(
                value: 'reverify',
                child: Text(l.ownershipReverifyAction),
              ),
            PopupMenuItem(
              value: 'revoke',
              child: Text(l.ownershipRevokeMenu),
            ),
          ],
        ),
        // Otvori per-kanal verifikacijski/upravljački ekran (po UC… ID-u).
        onTap: () =>
            drillDown(context, '/account/channels/${c.youtubeChannelId}'),
      ),
    );
  }

  Widget _walletTile(BuildContext context, OwnerWallet w) {
    final l = AppLocalizations.of(context);
    return Card(
      child: ListTile(
        leading: const Icon(Icons.account_balance_wallet_outlined),
        title: Text(_shortAddr(w.address)),
        subtitle: Text(
          w.isVerified
              ? l.ownershipWalletDestVerified
              : l.ownershipWalletDest,
        ),
        trailing: IconButton(
          icon: const Icon(Icons.delete_outline),
          onPressed: () async {
            await WalletService.instance.remove(w.id);
            await _load();
          },
        ),
      ),
    );
  }

  Widget _addWalletForm(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _walletCtrl,
              decoration: InputDecoration(
                labelText: l.ownershipWalletAddressLabel,
                helperText: l.ownershipWalletAddressHelper,
                helperMaxLines: 2,
                errorText: _walletError,
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: _walletBusy ? null : _addWallet,
              child: Text(l.ownershipAddWallet),
            ),
          ],
        ),
      ),
    );
  }

  String _shortAddr(String a) =>
      a.length > 12 ? '${a.substring(0, 6)}…${a.substring(a.length - 4)}' : a;
}
