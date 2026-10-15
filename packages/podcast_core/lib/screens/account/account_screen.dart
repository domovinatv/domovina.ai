/// Moj račun — account management ekran (/account).
///
/// Sekcije: profil (ime/e-mail/KYC), povezane prijavne metode, passkeyji
/// (lista + uklanjanje + dodavanje), uređaji (handoff), odjava s potvrdom,
/// te opasna zona s trajnim brisanjem računa (App Store Guideline 5.1.1(v) —
/// app koji nudi kreiranje računa MORA nuditi i brisanje u appu).
///
/// Passkey list/delete i account-delete backend grane su specificirane u
/// docs/backend-prompts/10-account-management.md; dok ne postoje, UI
/// degradira graceful (PasskeyFailure.unsupported / 404 poruke).
library;

import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../l10n/app_localizations.dart';
import '../../brand/app_brand.dart';
import '../../src/log.dart' show log;
import '../../src/app.dart' show rootScaffoldMessengerKey;
import '../../onboarding/ui/auth_sheet.dart';
import '../../services/push_topics.dart';
import '../../services/auth_service.dart';
import '../../services/background_playback.dart';
import '../../services/entitlement_service.dart';
import '../../services/episode_language.dart';
import '../../services/favorites_service.dart';
import '../../services/locale_service.dart';
import '../../services/passkey_service.dart';
import '../../services/voting_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/plus_badge.dart';
import '../subscribe/paywall_screen.dart';
import '../subscribe/upgrade_trigger.dart';
import '../voting/widgets/streak_flags.dart';
import '../../router/nav.dart';

class AccountScreen extends StatefulWidget {
  const AccountScreen({super.key});

  @override
  State<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends State<AccountScreen> {
  List<PasskeyInfo>? _passkeys;
  bool _passkeysLoading = true;
  bool _passkeysUnsupported = false;
  String? _passkeysError;
  bool _deleting = false;

  /// Stanje glasanja je zatraženo — bez ovoga bi svaka promjena auth stanja
  /// ispalila novi RPC.
  bool _votingZatrazeno = false;

  @override
  void initState() {
    super.initState();
    AuthService.instance.addListener(_onAuthChange);
    if (AppBrand.config.flags.passkeys) _loadPasskeys();
    _mozdaUcitajGlasanje();
  }

  @override
  void dispose() {
    AuthService.instance.removeListener(_onAuthChange);
    super.dispose();
  }

  void _onAuthChange() {
    if (!mounted) return;
    _mozdaUcitajGlasanje();
    setState(() {});
  }

  /// Niz/zastavice za karticu „Izborni dan" — samo za verificirane, jer samo
  /// oni uopće imaju niz.
  ///
  /// `refresh(withLeaderboard: false)`, ne `ensureLoaded()`: ovaj ekran ne
  /// prikazuje ljestvicu pa nema razloga vući 181 kandidata. Microtask jer
  /// `refresh` na pogodak lokalnog cachea notifira sinkrono.
  void _mozdaUcitajGlasanje() {
    if (!AppBrand.config.flags.voting) return;
    if (_votingZatrazeno) return;
    if (!(AuthService.instance.currentUser?.isVerified ?? false)) return;
    _votingZatrazeno = true;
    // Namjerno bez `unawaited` — `unawaited` je u ovom fajlu dvoznačan
    // (paywall_screen ‖ favorites_service), a metoda je sinkrona pa
    // `unawaited_futures` lint ionako ne pali.
    Future.microtask(
      () => VotingService.instance.refresh(withLeaderboard: false),
    );
  }

  Future<void> _loadPasskeys() async {
    if (!AuthService.instance.isSignedIn) {
      setState(() => _passkeysLoading = false);
      return;
    }
    setState(() {
      _passkeysLoading = true;
      _passkeysError = null;
    });
    try {
      final list = await PasskeyService.instance.listPasskeys();
      if (!mounted) return;
      setState(() {
        _passkeys = list;
        _passkeysLoading = false;
      });
    } on PasskeyFailure catch (e) {
      if (!mounted) return;
      setState(() {
        _passkeysLoading = false;
        _passkeysUnsupported = e.unsupported;
        _passkeysError = e.unsupported ? null : e.message;
      });
    } catch (e) {
      log('AccountScreen._loadPasskeys: $e');
      if (!mounted) return;
      setState(() {
        _passkeysLoading = false;
        _passkeysError = AppLocalizations.of(context).authPasskeyFetchFailed;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l = AppLocalizations.of(context);
    final auth = AuthService.instance;

    return Scaffold(
      backgroundColor: theme.colorScheme.surfaceContainerLow,
      appBar: AppBar(
        title: Text(l.authAccountTitle),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            backUp(context);
          },
        ),
      ),
      body: auth.isSignedIn ? _signedInBody(theme) : _anonymousBody(theme),
    );
  }

  // ── anonymous state ──────────────────────────────────────────────────────

  Widget _anonymousBody(ThemeData theme) {
    final l = AppLocalizations.of(context);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 380),
        // Scrollable jer sadržaj s postavkama više ne stane na niske ekrane
        // (landscape mobitel); dok stane, Center ga i dalje drži po sredini.
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.person_outline,
                  size: 56, color: theme.colorScheme.primary),
              const SizedBox(height: 16),
              Text(
                l.authAnonTitle,
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                l.authAnonSubtitle,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                icon: const Icon(Icons.login),
                label: Text(l.commonSignIn),
                onPressed: () => showAuthSheet(context),
              ),
              const SizedBox(height: 8),
              TextButton.icon(
                icon: const Icon(Icons.workspace_premium_outlined),
                label: Text(l.authLearnAboutPlus(AppBrand.config.plusDisplayName)),
                onPressed: () => openPaywall(context, UpgradeTrigger.generic),
              ),
              const SizedBox(height: 28),
              // Favoriti su offline-first (localStorage) pa i gost ima svoju
              // policu — prijava ih samo sinkronizira preko uređaja.
              SizedBox(
                width: double.infinity,
                child: _sectionLabel(theme, l.authSectionLibrary),
              ),
              _favoritesCard(theme),
              const SizedBox(height: 16),
              // Postavka je lokalna (uređaj/preglednik) i ne ovisi o prijavi —
              // isti prekidač kao u _signedInBody.
              SizedBox(
                width: double.infinity,
                child: _sectionLabel(theme, l.authSectionPlayback),
              ),
              _backgroundPlaybackCard(theme),
              const SizedBox(height: 16),
              if (PushTopics.instance.available) ...[
                _notificationsCard(theme),
                const SizedBox(height: 16),
              ],
              _languageCard(theme),
            ],
          ),
        ),
      ),
    );
  }

  // ── signed-in state ──────────────────────────────────────────────────────

  Widget _signedInBody(ThemeData theme) {
    final l = AppLocalizations.of(context);
    final user = AuthService.instance.currentUser!;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _profileCard(theme, user),
              const SizedBox(height: 16),
              _sectionLabel(theme, l.authSectionSubscription),
              _plusCard(theme),
              const SizedBox(height: 16),
              // „Izborni dan" — sekcija stoji SVIMA. Verificirani vidi svoj
              // niz, ostali poziv na potvrdu e-Osobnom: ovo je ekran na kojem
              // korisnik prijavljen Googleom ionako sjedi kad gleda načine
              // prijave, pa je najbliži trenutak da dozna da glasanje postoji.
              // (Do 25.8.2026. je kartica bila skrivena neverificiranima —
              // vidi _VotingDiscoverChip u home_app_bar.dart.)
              if (AppBrand.config.flags.voting) ...[
                _sectionLabel(theme, l.votingTitle),
                _votingCard(theme),
                const SizedBox(height: 16),
              ],
              _sectionLabel(theme, l.authSectionLibrary),
              _favoritesCard(theme),
              const SizedBox(height: 16),
              _sectionLabel(theme, l.authSectionSignInMethods),
              _identitiesCard(theme),
              const SizedBox(height: 16),
              if (AppBrand.config.flags.passkeys) ...[
                _sectionLabel(theme, l.authSectionPasskeys),
                _passkeysCard(theme),
                const SizedBox(height: 16),
              ],
              _sectionLabel(theme, l.authSectionDevices),
              _devicesCard(theme),
              const SizedBox(height: 16),
              _sectionLabel(theme, l.authSectionPlayback),
              _backgroundPlaybackCard(theme),
              const SizedBox(height: 16),
              if (PushTopics.instance.available) ...[
                _sectionLabel(theme, l.notificationsTitle),
                _notificationsCard(theme),
                const SizedBox(height: 16),
              ],
              _sectionLabel(theme, l.authSectionLanguage),
              _languageCard(theme),
              const SizedBox(height: 16),
              _signOutCard(theme),
              const SizedBox(height: 24),
              _sectionLabel(theme, l.authSectionDangerZone,
                  color: theme.colorScheme.error),
              _dangerCard(theme),
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }

  /// DOMOVINA Plus status + entry point. Active → supporter confirmation +
  /// (mobile) manage link; inactive → upgrade CTA opening the paywall.
  Widget _plusCard(ThemeData theme) {
    final cs = theme.colorScheme;
    final l = AppLocalizations.of(context);
    return ValueListenableBuilder<bool>(
      valueListenable: EntitlementService.instance.isPlus,
      builder: (context, isPlus, _) {
        if (isPlus) {
          return _card(
            theme,
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Row(
                children: [
                  Icon(Icons.verified, color: cs.primary),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          Text(AppBrand.config.plusDisplayName,
                              style: theme.textTheme.titleMedium
                                  ?.copyWith(fontWeight: FontWeight.bold)),
                          const SizedBox(width: 8),
                          const PlusBadge(),
                        ]),
                        const SizedBox(height: 2),
                        Text(AppBrand.config.flags.domainScore ? l.authPlusThanks : l.supportThanksGeneric,
                            style: theme.textTheme.bodySmall
                                ?.copyWith(color: cs.onSurfaceVariant)),
                      ],
                    ),
                  ),
                  TextButton(
                    onPressed: () => openPaywall(context),
                    child: Text(l.authDetails),
                  ),
                ],
              ),
            ),
          );
        }
        return _card(
          theme,
          child: ListTile(
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
            leading: Icon(Icons.workspace_premium_outlined, color: cs.primary),
            title: Text(l.authBecomePlus(AppBrand.config.plusDisplayName)),
            subtitle: Text(
              l.authPlusBenefits,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: cs.onSurfaceVariant),
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => openPaywall(context, UpgradeTrigger.generic),
          ),
        );
      },
    );
  }

  /// Ulaz u puni popis spremljenih (lajkanih) epizoda — `/favorites`.
  /// Broj se čita iz [FavoritesService] (lokalni cache), pa je točan i offline.
  Widget _favoritesCard(ThemeData theme) {
    final cs = theme.colorScheme;
    final l = AppLocalizations.of(context);
    return ListenableBuilder(
      listenable: FavoritesService.instance,
      builder: (context, _) => FutureBuilder<List<FavoriteEntry>>(
        future: FavoritesService.instance.entries(),
        builder: (context, snap) {
          final count = snap.data?.length;
          return _card(
            theme,
            child: ListTile(
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
              leading: Icon(Icons.favorite_outline, color: cs.primary),
              title: Text(l.favoritesTitle),
              subtitle: Text(
                count == null || count == 0
                    ? l.favoritesAccountSubtitle
                    : '${l.favoritesCount(count)} · ${l.favoritesAccountSubtitle}',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: cs.onSurfaceVariant),
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => drillDown(context, '/favorites'),
            ),
          );
        },
      ),
    );
  }

  /// „Tvoj niz" — niz, najduži niz i ukupan broj glasova + ulaz na `/glasanje`.
  ///
  /// Plan: `docs/plans/2026-08-08-glasanje-o-kanalima.md` §8.6.
  ///
  /// Prikazani niz je **projekcija za današnji dan** (`displayFor()`), ne sirovi
  /// `streak` iz baze: niz koji je pukao, a korisnik to još nije vidio, ovdje je
  /// 0 — isti broj koji stoji u zaglavlju glasanja i na home chipu.
  ///
  /// Ukupan broj glasova se prikazuje samo kad ga server pošalje
  /// (`total_votes`); v1.1 ugovor ga još ne nosi pa redak tada izostane.
  Widget _votingCard(ThemeData theme) {
    final cs = theme.colorScheme;
    final l = AppLocalizations.of(context);

    // Bez potvrde e-Osobnom nema ni niza ni glasa — kartica je tada čisti
    // poziv, bez ijedne brojke. Vodi na `/glasanje`, ne izravno u Certilia
    // flow: ondje uz traku za potvrdu stoji i ljestvica koja objašnjava zašto
    // se uopće potvrđuje. Nikakav RPC se pritom ne okida.
    if (!(AuthService.instance.currentUser?.isVerified ?? false)) {
      return _card(
        theme,
        child: ListTile(
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
          leading: Icon(Icons.how_to_vote_outlined, color: AppTheme.brandAccent),
          title: Text(l.votingAccountVerifyTitle),
          subtitle: Text(
            l.votingAccountVerifyBody,
            style:
                theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
          ),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => drillDown(context, '/glasanje'),
        ),
      );
    }

    return ListenableBuilder(
      listenable: VotingService.instance,
      builder: (context, _) {
        final service = VotingService.instance;
        final state = service.state;
        final display = service.displayFor();
        final niz = display?.displayedStreak ?? state?.streak ?? 0;
        final ugrozen = display?.streakAtRisk ?? false;
        final najduzi = state?.longestStreak ?? 0;
        final ukupno = state?.totalVotes;

        final dijelovi = <String>[
          if (najduzi > 0) l.votingLongestStreak(najduzi),
          if (ukupno != null) l.votingTotalVotes(ukupno),
        ];
        final podnaslov = dijelovi.isNotEmpty
            ? dijelovi.join(' · ')
            : (state?.canVote ?? false
                ? l.votingHaveVote
                : l.votingHomeChipTooltip);

        return _card(
          theme,
          child: ListTile(
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
            leading: Icon(
              niz > 0 ? Icons.local_fire_department : Icons.how_to_vote_outlined,
              color: ugrozen ? AppTheme.brandAccent : cs.primary,
            ),
            title: Text(niz > 0 ? l.votingStreakDays(niz) : l.votingStreakNone),
            subtitle: Text(
              podnaslov,
              style:
                  theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if ((state?.flags ?? 0) > 0)
                  StreakFlags(imaZastavica: state!.flags, visina: 11),
                const SizedBox(width: 6),
                const Icon(Icons.chevron_right),
              ],
            ),
            onTap: () => drillDown(context, '/glasanje'),
          ),
        );
      },
    );
  }

  Widget _sectionLabel(ThemeData theme, String text, {Color? color}) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Text(
        text,
        style: theme.textTheme.labelSmall?.copyWith(
          color: color ?? theme.colorScheme.onSurfaceVariant,
          letterSpacing: 1.2,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _card(ThemeData theme, {required Widget child}) {
    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.6),
        ),
      ),
      child: child,
    );
  }

  /// Ulaz na ekran Obavijesti (samo kad ljuska ima push — iOS/Android).
  Widget _notificationsCard(ThemeData theme) {
    final cs = theme.colorScheme;
    final l = AppLocalizations.of(context);
    return ListenableBuilder(
      listenable: PushTopics.instance,
      builder: (context, _) {
        final on = PushTopics.instance.enabled;
        return _card(
          theme,
          child: ListTile(
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
            leading: Icon(
              on
                  ? Icons.notifications_active_outlined
                  : Icons.notifications_outlined,
              color: cs.primary,
            ),
            title: Text(l.notificationsTitle),
            subtitle: Text(
              on ? l.notificationsAccountOn : l.notificationsAccountOff,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: cs.onSurfaceVariant),
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => drillDown(context, '/obavijesti'),
          ),
        );
      },
    );
  }

  /// „Reprodukcija u pozadini" — nastavlja li ono što svira raditi kad app ili
  /// tab izgubi prvi plan. Default uključeno; pref je lokalan (uređaj/preglednik),
  /// ne veže se uz račun. ListenableBuilder jer BackgroundPlayback vrijednost
  /// učitava lazy (bez init() poziva u main()) pa stigne nakon prvog builda.
  Widget _backgroundPlaybackCard(ThemeData theme) {
    final cs = theme.colorScheme;
    final l = AppLocalizations.of(context);
    return ListenableBuilder(
      listenable: BackgroundPlayback.instance,
      builder: (context, _) => _card(
        theme,
        child: SwitchListTile(
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
          secondary: Icon(Icons.headset_outlined, color: cs.primary),
          title: Text(l.mediaBackgroundPlaybackTitle),
          subtitle: Text(
            l.mediaBackgroundPlaybackSubtitle,
            style: theme.textTheme.bodySmall
                ?.copyWith(color: cs.onSurfaceVariant),
          ),
          value: BackgroundPlayback.instance.enabled,
          onChanged: (v) => BackgroundPlayback.instance.setEnabled(v),
        ),
      ),
    );
  }

  /// UI jezik (HR/EN). Imena jezika su endonimi ("Hrvatski"/"English") pa ih
  /// korisnik prepoznaje neovisno o trenutnom jeziku — namjerno NISU prevedeni.
  /// MaterialApp sluša LocaleController (vidi main.dart), pa se ekran sam
  /// rebuilda na promjenu — bez ručnog setState.
  Widget _languageCard(ThemeData theme) {
    final current = LocaleController.instance.locale.languageCode;
    return _card(
      theme,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Icon(Icons.translate, color: theme.colorScheme.primary),
            const SizedBox(width: 12),
            Expanded(
              child: SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'hr', label: Text('Hrvatski')),
                  ButtonSegment(value: 'en', label: Text('English')),
                ],
                selected: {current},
                showSelectedIcon: false,
                // Dvosmjerna sprega: uz UI jezik spremi i preferirani jezik
                // sadržaja (sticky pref za buduće epizode) — vidi
                // language_toggle_button.dart / language_toggle_chip.dart.
                onSelectionChanged: (sel) {
                  LocaleController.instance.setLocale(Locale(sel.first));
                  savePreferredLanguage(sel.first == 'en'
                      ? EpisodeLanguage.en
                      : EpisodeLanguage.hr);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _profileCard(ThemeData theme, AppUser user) {
    final cs = theme.colorScheme;
    final l = AppLocalizations.of(context);
    final initial = (user.displayName ?? user.email ?? '?')
        .replaceAll(RegExp(r'[^A-Za-zČčĆćĐđŠšŽž]'), '')
        .characters
        .firstOrNull
        ?.toUpperCase() ??
        '?';
    return _card(
      theme,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          children: [
            Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.fromBorderSide(
                  AppTheme.brandRim(theme.brightness),
                ),
              ),
              child: CircleAvatar(
                radius: 26,
                backgroundColor: AppTheme.brandPrimary,
                child: Text(
                  initial,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 22,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    user.displayName ?? l.authUserFallback,
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  if (user.email != null)
                    Text(
                      user.email!,
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: cs.onSurfaceVariant),
                    ),
                  if (user.isVerified)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.verified, size: 14, color: cs.primary),
                          const SizedBox(width: 4),
                          Text(
                            l.authVerifiedIdentity,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: cs.primary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _identitiesCard(ThemeData theme) {
    final cs = theme.colorScheme;
    final l = AppLocalizations.of(context);
    final providers = AuthService.instance.linkedProviders;
    return _card(
      theme,
      child: Column(
        children: [
          if (providers.isEmpty)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                l.authNoLinkedMethods,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: cs.onSurfaceVariant),
              ),
            )
          else
            ...providers.map((p) => ListTile(
                  leading: Icon(_providerIcon(p), color: cs.primary),
                  title: Text(p.displayName),
                  subtitle: Text(_providerSubtitle(p)),
                  dense: true,
                )),
        ],
      ),
    );
  }

  IconData _providerIcon(AuthProvider p) => switch (p) {
        AuthProvider.google => Icons.g_mobiledata,
        AuthProvider.apple => Icons.apple,
        AuthProvider.email => Icons.alternate_email,
        AuthProvider.passkey => Icons.fingerprint,
        AuthProvider.certilia => Icons.badge_outlined,
      };

  String _providerSubtitle(AuthProvider p) {
    final l = AppLocalizations.of(context);
    return switch (p) {
      AuthProvider.google => l.authProviderGoogle,
      AuthProvider.apple => l.authProviderApple,
      AuthProvider.email => l.authProviderEmail,
      AuthProvider.passkey => l.authProviderPasskey,
      AuthProvider.certilia => l.authProviderCertilia,
    };
  }

  Widget _passkeysCard(ThemeData theme) {
    final cs = theme.colorScheme;
    final l = AppLocalizations.of(context);
    return _card(
      theme,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_passkeysLoading)
            const Padding(
              padding: EdgeInsets.all(20),
              child: Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            )
          else if (_passkeysUnsupported)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                l.authPasskeysSoon,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: cs.onSurfaceVariant),
              ),
            )
          else if (_passkeysError != null)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Icon(Icons.error_outline, size: 18, color: cs.error),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _passkeysError!,
                      style:
                          theme.textTheme.bodySmall?.copyWith(color: cs.error),
                    ),
                  ),
                  TextButton(
                    onPressed: _loadPasskeys,
                    child: Text(l.commonRetry),
                  ),
                ],
              ),
            )
          else if (_passkeys == null || _passkeys!.isEmpty)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                l.authNoPasskeys,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: cs.onSurfaceVariant),
              ),
            )
          else
            ..._passkeys!.map((pk) => ListTile(
                  leading: Icon(Icons.fingerprint, color: cs.primary),
                  title: Text(pk.deviceName ?? l.authProviderPasskey),
                  subtitle: Text(_passkeyMeta(pk)),
                  dense: true,
                  trailing: IconButton(
                    icon: Icon(Icons.delete_outline, color: cs.error, size: 20),
                    tooltip: l.authRemovePasskey,
                    onPressed: () => _confirmDeletePasskey(pk),
                  ),
                )),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.all(8),
            child: TextButton.icon(
              icon: const Icon(Icons.add, size: 18),
              label: Text(l.authAddPasskeyHere),
              onPressed: _addPasskey,
            ),
          ),
          const Divider(height: 1),
          _passkeyProviderHint(theme),
        ],
      ),
    );
  }

  /// Uputa o passkey store-u, adaptirano iz pay.domovina.ai/wallet
  /// (passkeyProviderHint). HARD WebAuthn limit: stranica NE MOŽE birati
  /// manager (Apple Passwords vs LastPass) — to korisnik bira u OS
  /// postavkama, pa ga copy tamo i upućuje.
  Widget _passkeyProviderHint(ThemeData theme) {
    final cs = theme.colorScheme;
    final l = AppLocalizations.of(context);
    final steps = switch (defaultTargetPlatform) {
      TargetPlatform.iOS ||
      TargetPlatform.macOS =>
        l.authPasskeyStepsApple,
      TargetPlatform.android => l.authPasskeyStepsAndroid,
      _ => l.authPasskeyStepsGeneric,
    };
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.tips_and_updates_outlined,
                  size: 16, color: cs.primary),
              const SizedBox(width: 8),
              Text(
                l.authWherePasskeyStored,
                style: theme.textTheme.labelMedium
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            l.authPasskeyHintBody(
                Uri.parse(AppBrand.config.endpoints.site).host, steps),
            style: theme.textTheme.bodySmall?.copyWith(
              color: cs.onSurfaceVariant,
              height: 1.45,
            ),
          ),
        ],
      ),
    );
  }

  String _passkeyMeta(PasskeyInfo pk) {
    final l = AppLocalizations.of(context);
    final created = pk.createdAt;
    final used = pk.lastUsedAt;
    final parts = <String>[
      if (created != null)
        l.authPasskeyAdded('${created.day}.${created.month}.${created.year}.'),
      if (used != null)
        l.authPasskeyLastUsed('${used.day}.${used.month}.${used.year}.'),
    ];
    return parts.isEmpty ? l.authProviderPasskey : parts.join(' · ');
  }

  Future<void> _addPasskey() async {
    final result = await AuthService.instance
        .linkIdentity(context, AuthProvider.passkey);
    if (!mounted) return;
    final l = AppLocalizations.of(context);
    switch (result.status) {
      case AuthFlowStatus.success:
        rootScaffoldMessengerKey.currentState?.showSnackBar(
          SnackBar(content: Text(result.message ?? l.authPasskeyAddedToast)),
        );
        _loadPasskeys();
      case AuthFlowStatus.failure:
        rootScaffoldMessengerKey.currentState?.showSnackBar(
          SnackBar(content: Text(result.message ?? l.authPasskeyAddFailed)),
        );
      case AuthFlowStatus.redirect:
      case AuthFlowStatus.emailSent:
      case AuthFlowStatus.cancelled:
        break;
    }
  }

  Future<void> _confirmDeletePasskey(PasskeyInfo pk) async {
    final l = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.authRemovePasskeyTitle),
        content: Text(
          l.authRemovePasskeyBody(pk.deviceName ?? l.authProviderPasskey),
        ),
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
            child: Text(l.authRemove),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await PasskeyService.instance.deletePasskey(pk.id);
      if (!mounted) return;
      rootScaffoldMessengerKey.currentState?.showSnackBar(
        SnackBar(content: Text(l.authPasskeyRemoved)),
      );
      _loadPasskeys();
    } on PasskeyFailure catch (e) {
      if (!mounted) return;
      rootScaffoldMessengerKey.currentState?.showSnackBar(
        SnackBar(content: Text(e.message)),
      );
    }
  }

  Widget _devicesCard(ThemeData theme) {
    final l = AppLocalizations.of(context);
    return _card(
      theme,
      child: ListTile(
        leading:
            Icon(Icons.devices_other, color: theme.colorScheme.primary),
        title: Text(l.authSwitchDevice),
        subtitle: Text(l.authDevicesSubtitle),
        trailing: const Icon(Icons.arrow_forward_ios, size: 14),
        onTap: () => drillDown(context, '/handoff'),
      ),
    );
  }

  Widget _signOutCard(ThemeData theme) {
    final l = AppLocalizations.of(context);
    return _card(
      theme,
      child: ListTile(
        leading: Icon(Icons.logout, color: theme.colorScheme.onSurfaceVariant),
        title: Text(l.commonSignOut),
        subtitle: Text(l.authSignOutSubtitle),
        onTap: () => confirmAndSignOut(context),
      ),
    );
  }

  Widget _dangerCard(ThemeData theme) {
    final cs = theme.colorScheme;
    final l = AppLocalizations.of(context);
    return Container(
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.error.withValues(alpha: 0.4)),
      ),
      child: ListTile(
        leading: Icon(Icons.delete_forever_outlined, color: cs.error),
        title: Text(l.authDeleteAccount, style: TextStyle(color: cs.error)),
        subtitle: Text(l.authDeleteAccountSubtitle),
        trailing: _deleting
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : null,
        onTap: _deleting ? null : _confirmDeleteAccount,
      ),
    );
  }

  Future<void> _confirmDeleteAccount() => confirmAndDeleteAccount(
        context,
        onBusy: (busy) {
          if (mounted) setState(() => _deleting = busy);
        },
      );
}

/// Type-to-confirm, delete the account and report the result. Shared by the
/// account screen and the AccountChip menu, so deletion is one tap away from
/// the avatar (App Store Guideline 5.1.1(v): reviewers must find it easily).
///
/// The caller's [context] may unmount once the session flips to anonymous
/// (the AccountChip rebuilds), so everything needed afterwards is captured
/// before the await and the snackbar goes through the root messenger.
Future<void> confirmAndDeleteAccount(BuildContext context,
    {ValueChanged<bool>? onBusy}) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => const _DeleteAccountDialog(),
  );
  if (confirmed != true || !context.mounted) return;

  final l = AppLocalizations.of(context);
  final router = GoRouter.of(context);
  onBusy?.call(true);
  final result = await AuthService.instance.deleteAccount();
  onBusy?.call(false);

  rootScaffoldMessengerKey.currentState?.showSnackBar(
    SnackBar(
      content: Text(result.message ??
          (result.status == AuthFlowStatus.success
              ? l.authAccountDeleted
              : l.authDeleteFailed)),
      duration: const Duration(seconds: 5),
    ),
  );
  if (result.status == AuthFlowStatus.success) router.go('/');
}

/// Potvrda odjave — dijeli ju AccountChip menu i Moj račun ekran.
Future<void> confirmAndSignOut(BuildContext context) async {
  final l = AppLocalizations.of(context);
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(l.authSignOutTitle),
      content: Text(l.authSignOutBody),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: Text(l.commonCancel),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(l.commonSignOut),
        ),
      ],
    ),
  );
  if (confirmed == true && context.mounted) {
    await AuthService.instance.signOut(context);
  }
}

/// Type-to-confirm dialog za trajno brisanje računa.
class _DeleteAccountDialog extends StatefulWidget {
  const _DeleteAccountDialog();

  @override
  State<_DeleteAccountDialog> createState() => _DeleteAccountDialogState();
}

class _DeleteAccountDialogState extends State<_DeleteAccountDialog> {
  final _ctrl = TextEditingController();
  bool _matches = false;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final l = AppLocalizations.of(context);
    final confirmWord = l.authDeleteConfirmWord;
    return AlertDialog(
      // Type-to-confirm polje diže tipkovnicu — bez scrollable dialog
      // overflowa na niskim ekranima.
      scrollable: true,
      title: Text(l.authDeleteConfirmTitle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l.authDeleteConfirmBody(confirmWord)),
          const SizedBox(height: 12),
          TextField(
            controller: _ctrl,
            autofocus: true,
            textCapitalization: TextCapitalization.characters,
            onChanged: (v) => setState(() =>
                _matches = v.trim().toUpperCase() == confirmWord.toUpperCase()),
            decoration: InputDecoration(
              hintText: confirmWord,
              isDense: true,
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text(l.commonCancel),
        ),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: cs.error),
          onPressed: _matches ? () => Navigator.pop(context, true) : null,
          child: Text(l.authDeletePermanently),
        ),
      ],
    );
  }
}
