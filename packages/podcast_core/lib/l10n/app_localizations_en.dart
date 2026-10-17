// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String appTitle(String app) {
    return '$app';
  }

  @override
  String get updateAvailable => 'A new version is available';

  @override
  String get updateRefresh => 'Refresh';

  @override
  String get commonCancel => 'Cancel';

  @override
  String get commonClose => 'Close';

  @override
  String get commonBack => 'Back';

  @override
  String get commonSave => 'Save';

  @override
  String get commonConfirm => 'Confirm';

  @override
  String get commonDone => 'Done';

  @override
  String get commonContinue => 'Continue';

  @override
  String get commonRetry => 'Try again';

  @override
  String get commonSeeAll => 'See all';

  @override
  String get commonUndo => 'Undo';

  @override
  String get commonCopy => 'Copy';

  @override
  String get commonShare => 'Share';

  @override
  String get commonCopyLink => 'Copy link';

  @override
  String get commonLinkCopied => 'Link copied';

  @override
  String get commonOk => 'OK';

  @override
  String get commonSignIn => 'Sign in';

  @override
  String get commonSignOut => 'Sign out';

  @override
  String get commonLoading => 'Loading…';

  @override
  String get commonGoHome => 'Back to home';

  @override
  String get commonOpenSource => 'Open source';

  @override
  String get commonThanksForSupport => 'Thank you for your support';

  @override
  String commonErrorWithDetails(String details) {
    return 'Error: $details';
  }

  @override
  String get authAccountTitle => 'My account';

  @override
  String get authAnonTitle => 'You\'re not signed in yet';

  @override
  String get authAnonSubtitle =>
      'Sign in to manage your account, passkeys, and data.';

  @override
  String authLearnAboutPlus(String plus) {
    return 'Discover $plus';
  }

  @override
  String get authSectionSubscription => 'Subscription';

  @override
  String get authSectionSignInMethods => 'Sign-in methods';

  @override
  String get authSectionPasskeys => 'Passkeys';

  @override
  String get authSectionDevices => 'Devices';

  @override
  String get authSectionDangerZone => 'Danger zone';

  @override
  String get authPlusThanks => 'Thank you for supporting the Croatian archive.';

  @override
  String get supportThanksGeneric => 'Thank you for your support.';

  @override
  String get authDetails => 'Details';

  @override
  String authBecomePlus(String plus) {
    return 'Get $plus';
  }

  @override
  String get authPlusBenefits =>
      'Broader search, a supporter badge, and support for the archive.';

  @override
  String get authUserFallback => 'User';

  @override
  String get authVerifiedIdentity => 'Verified identity (eID)';

  @override
  String get authNoLinkedMethods => 'No linked sign-in methods yet.';

  @override
  String get authProviderGoogle => 'Google account';

  @override
  String get authProviderApple => 'Apple account';

  @override
  String get authProviderEmail => 'Sign-in link or code by email';

  @override
  String get authProviderPasskey => 'Passkey';

  @override
  String get authProviderCertilia => 'Croatian eID (Certilia / NIAS)';

  @override
  String get authPasskeysSoon =>
      'Viewing and removing passkeys is coming soon. You can already add a new one.';

  @override
  String get authNoPasskeys =>
      'You have no passkeys yet. A passkey is the safest and fastest way to sign in — no password, just Face ID or your fingerprint.';

  @override
  String get authPasskeyFetchFailed => 'We couldn\'t load your passkeys.';

  @override
  String get authRemovePasskey => 'Remove passkey';

  @override
  String get authAddPasskeyHere => 'Add a passkey on this device';

  @override
  String get authWherePasskeyStored => 'Where is your passkey stored?';

  @override
  String authPasskeyHintBody(String site, String steps) {
    return 'We recommend Apple Passwords or Google Password Manager — that way your passkey is tied to Face ID or your fingerprint and synced across all your devices. If you use an extension like LastPass or 1Password, turn it off for $site (or remove it as the default key manager), as it intercepts the passkey prompt and breaks sign-in.\n\n$steps';
  }

  @override
  String get authPasskeyStepsApple =>
      'Settings → Apps → Passwords → Password Options → \"AutoFill\" — choose Passwords (iCloud).';

  @override
  String get authPasskeyStepsAndroid =>
      'Settings → Passwords & accounts → Default passkey service → choose Google Password Manager.';

  @override
  String get authPasskeyStepsGeneric =>
      'In your OS settings, choose the system passkey manager (Apple Passwords or Google Password Manager).';

  @override
  String authPasskeyAdded(String date) {
    return 'added $date';
  }

  @override
  String authPasskeyLastUsed(String date) {
    return 'last used $date';
  }

  @override
  String get authPasskeyAddedToast => 'Passkey added.';

  @override
  String get authPasskeyAddFailed => 'Couldn\'t add passkey.';

  @override
  String get authRemovePasskeyTitle => 'Remove passkey?';

  @override
  String authRemovePasskeyBody(String name) {
    return '\"$name\" will no longer be able to sign in to this account. This action is permanent.';
  }

  @override
  String get authRemove => 'Remove';

  @override
  String get authPasskeyRemoved => 'Passkey removed.';

  @override
  String get authSwitchDevice => 'Switch to another device';

  @override
  String get authDevicesSubtitle =>
      'Generate a code and sign in on your TV or phone';

  @override
  String get authSignOutSubtitle =>
      'Continue as a guest — your data stays on your account';

  @override
  String get authDeleteAccount => 'Delete account';

  @override
  String get authDeleteAccountSubtitle =>
      'Permanently deletes your account, favorites, progress, and all related data.';

  @override
  String get authAccountDeleted => 'Your account has been deleted.';

  @override
  String get authDeleteFailed => 'Deletion failed.';

  @override
  String get authSignOutTitle => 'Sign out?';

  @override
  String get authSignOutBody =>
      'Your progress and favorites stay saved on your account — they\'ll return when you sign back in.';

  @override
  String get authDeleteConfirmTitle => 'Permanently delete account?';

  @override
  String get authDeleteConfirmWord => 'DELETE';

  @override
  String authDeleteConfirmBody(String word) {
    return 'This deletes your account, favorites, watch progress, passkeys, and all related settings. This action cannot be undone.\n\nType $word to confirm:';
  }

  @override
  String get authDeletePermanently => 'Delete permanently';

  @override
  String get authErrLinkExpired =>
      'Your sign-in link has expired — request a new one.';

  @override
  String get authErrUserBanned => 'This account is temporarily blocked.';

  @override
  String get authErrSignupDisabled =>
      'New account sign-ups are currently unavailable.';

  @override
  String get authErrAccessDenied => 'Sign-in was denied or cancelled.';

  @override
  String get authErrServerError =>
      'Server error — please try again in a minute.';

  @override
  String get authErrGeneric => 'Sign-in failed. Please try again.';

  @override
  String get authErrTimeout =>
      'Sign-in is taking too long or was interrupted. Please try again.';

  @override
  String authSignedInAs(String name) {
    return 'You\'re signed in as $name.';
  }

  @override
  String get authSigningIn => 'Signing you in…';

  @override
  String get authInviteTitle => 'Accept invitation';

  @override
  String get authInviteProcessing => 'Processing your invitation…';

  @override
  String get authInviteError =>
      'Something went wrong, or the link has expired.';

  @override
  String get authM3Toast =>
      'Saved on this device. Sync your favorites across all devices?';

  @override
  String get authSync => 'Sync';

  @override
  String get authTabSend => 'Send';

  @override
  String get authTabReceive => 'Receive';

  @override
  String get authHandoffSignInFirst => 'Sign in first';

  @override
  String get authHandoffSignInFirstBody =>
      'To move all your progress to another device, sign in here first — then the other device can access the same account.';

  @override
  String get authHandoffSendTitle => 'Send your sign-in to another device';

  @override
  String get authHandoffSendSheetSub =>
      'To send a sign-in to another device, sign in here first.';

  @override
  String authHandoffSendBody(String app) {
    return 'Open $app/handoff on the other device and enter the code below. The code is valid for 5 minutes.';
  }

  @override
  String get authGenerateCode => 'Generate code';

  @override
  String get authNewCode => 'New code';

  @override
  String get authValid5Min => 'Valid for 5 minutes';

  @override
  String get authCodeCopied => 'Code copied';

  @override
  String get authHandoffReceiveTitle => 'Have a code from another device?';

  @override
  String get authHandoffReceiveBody =>
      'Enter the six-digit code from the other device to bring its account here.';

  @override
  String get authReceiveSignIn => 'Bring sign-in here';

  @override
  String get authCode6Digits => 'The code must be 6 digits.';

  @override
  String get authOpeningSignIn => 'Opening sign-in…';

  @override
  String get authOpeningSignInBody =>
      'If a browser opens, confirm the sign-in, then return to the app.';

  @override
  String get authSuccess => 'Success!';

  @override
  String get authSignInWithPasskey => 'Continue with a passkey';

  @override
  String get authPasskeyTileSub =>
      'Face ID or fingerprint — if you already added a key';

  @override
  String get authBadgeRecommended => 'Recommended';

  @override
  String get authBadgeLastUsed => 'Last used';

  @override
  String get authSignInWithEid => 'Continue with eID';

  @override
  String get authContinueWithGoogle => 'Continue with Google';

  @override
  String get authContinueWithApple => 'Continue with Apple';

  @override
  String get authEmailMagicLink => 'Continue with email';

  @override
  String get authEmailTileSub => 'We\'ll send you a link and a code to sign in';

  @override
  String get authEmailHint => 'name@example.com';

  @override
  String get authSendCode => 'Send code';

  @override
  String get authResendCode => 'Send a new code';

  @override
  String authResendCodeIn(int seconds) {
    return 'Send a new code (${seconds}s)';
  }

  @override
  String get authChangeEmail => 'Change email';

  @override
  String get authEmailTitle => 'Sign in with email';

  @override
  String get authCheckEmail => 'Check your email';

  @override
  String get authEmailEntrySub =>
      'We\'ll send you a link and a six-digit code to sign in — no password.';

  @override
  String get authUsePassword => 'Sign in with password';

  @override
  String get authPasswordEntrySub => 'For accounts that have a password.';

  @override
  String get authPasswordHint => 'Password';

  @override
  String authOtpSentTo(String email) {
    return 'We sent a link and a code to $email. Enter the code — or open the link in your email.';
  }

  @override
  String authHeadlineAccount(String app) {
    return 'Sign in to $app';
  }

  @override
  String get authHeadlineMoment3 => 'Save favorites to your account';

  @override
  String get authHeadlineHandoff => 'Finish signing in on this device';

  @override
  String get authSubAccount =>
      'No password. Signing in for the first time creates your account.';

  @override
  String get authHeadlineGuest => 'Save your progress and favourites';

  @override
  String get authSubGuest =>
      'You\'re listening as a guest — progress and favourites stay only on this device.';

  @override
  String get authGuestBarTitle => 'You\'re listening as a guest';

  @override
  String get authGuestBarBody =>
      'Progress, favourites and settings stay on this device only';

  @override
  String get authSubMoment3 =>
      'So your favorites stay available on all your devices.';

  @override
  String get authSubHandoff =>
      'Your code is verified — choose how you\'d like to continue.';

  @override
  String authPasskeyMissingNotice(String app) {
    return 'There\'s no passkey for $app on this device yet. Sign in another way — then add a passkey in My account.';
  }

  @override
  String get authInvalidEmail => 'Enter a valid email address.';

  @override
  String get authSendFailed => 'We couldn\'t send it.';

  @override
  String authNewCodeSentTo(String email) {
    return 'A new code was sent to $email.';
  }

  @override
  String get authCodeInvalid => 'That code isn\'t valid.';

  @override
  String get authSignInFailed => 'Sign-in failed.';

  @override
  String get authYourEmail => 'your email';

  @override
  String authLinkCodeSent(String email) {
    return 'A link and a code were sent to $email — check your inbox.';
  }

  @override
  String get authLegalPrefix => 'By continuing, you agree to ';

  @override
  String get authLegalTerms => 'the Terms of Use';

  @override
  String get authLegalAnd => ' and ';

  @override
  String get authLegalPrivacy => 'the Privacy Policy';

  @override
  String get authLegalSuffix => '.';

  @override
  String get authReassurance =>
      'Your current progress is kept safe and securely linked to your account.';

  @override
  String get authOr => 'or';

  @override
  String get channelClaimOwnership => 'Claim ownership';

  @override
  String get channelAudioOnly => 'Audio only';

  @override
  String get channelInProcessing => 'Processing';

  @override
  String get channelAllChannels => 'All channels';

  @override
  String get channelSearchChannelsHint => 'Search channels…';

  @override
  String get channelClear => 'Clear';

  @override
  String channelChannelsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count channels',
      one: '$count channel',
    );
    return '$_temp0';
  }

  @override
  String channelResultsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count results',
      one: '$count result',
    );
    return '$_temp0';
  }

  @override
  String get channelNoChannels => 'No channels.';

  @override
  String channelNoChannelsForQuery(String query) {
    return 'No channels for “$query”.';
  }

  @override
  String get channelSortChannels => 'Sort channels';

  @override
  String get channelShuffle => 'Shuffle';

  @override
  String get channelKeywordSearch => 'Keyword search';

  @override
  String get channelKeywordSearchHint => 'Search by keyword (typo-tolerant)…';

  @override
  String channelSearchUnavailable(String url) {
    return 'Meilisearch is unavailable at $url. Start the Docker container and populate the index (domovina-rag repository).';
  }

  @override
  String get channelSearching => 'Searching…';

  @override
  String channelResultsInMs(int count, int ms) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count results in $ms ms · typo-tolerant',
      one: '$count result in $ms ms · typo-tolerant',
    );
    return '$_temp0';
  }

  @override
  String get channelSearchPrompt => 'Type a term for instant episode search.';

  @override
  String get channelAll => 'All';

  @override
  String get channelSearchStart => 'Keyword search — start typing.';

  @override
  String channelNoResultsForQuery(String query) {
    return 'No results for “$query”.';
  }

  @override
  String channelTriggerGenericHeadline(String plus) {
    return 'Go $plus';
  }

  @override
  String get channelTriggerGenericSubtitle =>
      'Support the Croatian archive and unlock every benefit.';

  @override
  String get channelTriggerGenericSubtitleNeutral =>
      'Unlock every Plus benefit.';

  @override
  String get channelTriggerSearchHeadline => 'Broader search';

  @override
  String get channelTriggerSearchSubtitle =>
      'Up to 30 search results instead of 12.';

  @override
  String get channelTriggerBadgeHeadline => 'Become an archive supporter';

  @override
  String get channelTriggerBadgeSubtitle =>
      'A supporter badge on your account.';

  @override
  String get channelPlanAnnual => 'Annual';

  @override
  String get channelPlanPerYear => '/ yr';

  @override
  String get channelPlanSaveBadge => '~33% cheaper';

  @override
  String get channelPlanMonthly => 'Monthly';

  @override
  String get channelPlanPerMonth => '/ mo';

  @override
  String get channelPlanLifetime => 'Lifetime';

  @override
  String get channelPlanOneTime => 'one-time';

  @override
  String channelTrialThen(int days, String price) {
    return '$days-day free trial, then $price';
  }

  @override
  String get channelPlanFounderBadge => 'Founder';

  @override
  String get channelBenefitSearch =>
      'Broader search — up to 30 results instead of 12';

  @override
  String get channelBenefitBadge => 'A supporter badge on your account';

  @override
  String get channelBenefitSupport =>
      'You support the archive\'s development and running costs';

  @override
  String get plusRoadmapTitle => 'On the roadmap';

  @override
  String get plusRoadmapDisclaimer =>
      'These are directions we\'re exploring, not part of what you\'re buying today. No timelines — if and when they arrive, they\'ll be included in Plus at no extra cost.';

  @override
  String get plusRoadmapOffline => 'Downloading episodes for offline listening';

  @override
  String get plusRoadmapExport => 'Exporting transcripts and summaries';

  @override
  String get channelSignInToContinue => 'Sign in to continue';

  @override
  String get channelSubscriptionTiedToAccount =>
      'Your subscription is tied to your account so it works on every device.';

  @override
  String channelWelcomeToPlus(String plus) {
    return 'Welcome to $plus! Thank you for your support.';
  }

  @override
  String get channelPurchaseUnavailableDevice =>
      'Purchases aren’t available on this device.';

  @override
  String get channelPurchaseFailed =>
      'The purchase didn’t go through. Please try again.';

  @override
  String get channelSubscriptionRestored =>
      'Your subscription has been restored.';

  @override
  String get channelNoPurchaseToRestore =>
      'We couldn’t find a purchase to restore.';

  @override
  String get channelWebBillingSoon =>
      'Web billing is coming soon. For now, subscribe in the mobile app.';

  @override
  String get channelSignInFirst => 'Sign in first';

  @override
  String get channelRestorePurchases => 'Restore purchases';

  @override
  String get channelManageSubscription => 'Manage subscription';

  @override
  String get channelCheckoutNote =>
      'Checkout is handled by secure RevenueCat / Stripe. The final price is shown on the checkout page.';

  @override
  String get channelPricesIndicative =>
      'Prices are indicative; the final price is shown in the store.';

  @override
  String channelAlreadyPlus(String plus) {
    return 'You already have $plus';
  }

  @override
  String get channelThanksSupportingArchive =>
      'Thank you for supporting the Croatian archive.';

  @override
  String get channelLegalAutoRenew =>
      'Your subscription renews automatically until you cancel. You can cancel any time in your store settings. The lifetime plan is a one-time purchase.';

  @override
  String get channelLegalAutoRenewSubscriptionsOnly =>
      'Your subscription renews automatically until you cancel. You can cancel any time in your store settings.';

  @override
  String get channelTalkToFounder => 'Talk to the founder';

  @override
  String get channelCannotFetchSlots => 'We couldn’t load the available times.';

  @override
  String get channelNoSlotsThreeWeeks =>
      'There are no open slots in the next three weeks.';

  @override
  String get channelPickDay => 'Pick a day';

  @override
  String get channelAvailableSlots => 'Available times';

  @override
  String get channelFullName => 'Full name';

  @override
  String get channelEnterName => 'Enter your name';

  @override
  String get channelEmail => 'Email';

  @override
  String get channelEnterEmail => 'Enter your email';

  @override
  String get channelInvalidEmail => 'Invalid email';

  @override
  String get channelTopicOptional => 'What you’d like to discuss (optional)';

  @override
  String get channelConfirmSlot => 'Confirm time';

  @override
  String get channelNetworkError => 'Network error. Please try again.';

  @override
  String get channelSlotConfirmed => 'You’re booked!';

  @override
  String channelDayAtTime(String day, String time) {
    return '$day at $time';
  }

  @override
  String channelInviteSentTo(String email) {
    return 'We’ve sent the invite and Google Meet link to $email.';
  }

  @override
  String get channelOpenGoogleMeet => 'Open Google Meet';

  @override
  String channelFounderCallTitle(String brand) {
    return 'Be part of the $brand story';
  }

  @override
  String get channelFounderCallSubtitle =>
      '15 min on Google Meet · one-on-one with the founder · help shape the platform';

  @override
  String get channelChange => 'Change';

  @override
  String episodeNotFoundDetailed(String id) {
    return 'Episode “$id” wasn’t found on the CDN.\n\nCheck that the ID is correct and that the files have been uploaded.';
  }

  @override
  String episodeNotFound(String id) {
    return 'Episode “$id” wasn’t found.';
  }

  @override
  String episodeLoadError(String details) {
    return 'Couldn’t load this episode:\n$details';
  }

  @override
  String get episodeLoading => 'Loading episode';

  @override
  String episodeLinkCopied(String label) {
    return 'Link copied ($label)';
  }

  @override
  String get episodeWholeEpisode => 'whole episode';

  @override
  String get clipShareTitle => 'Chapter as a clip';

  @override
  String get clipTooltip => 'Download or share this chapter';

  @override
  String get clipDownload => 'Download chapter';

  @override
  String clipDownloadSubtitle(int size, int minutes) {
    return 'MP4 · ~$size MB · $minutes min';
  }

  @override
  String get clipCopyLink => 'Copy clip link';

  @override
  String get clipCopyLinkSubtitle => 'To send in a message or chat';

  @override
  String get clipLinkCopied => 'Clip link copied';

  @override
  String get clipHint =>
      'The first time, the clip takes a few seconds to prepare.';

  @override
  String get episodeOpenOnYouTube => 'Open on YouTube';

  @override
  String get episodeOpenOnX => 'Open on 𝕏';

  @override
  String get episodeCopyMomentLink => 'Copy link to this moment';

  @override
  String get episodeVideo => 'Video';

  @override
  String get episodeLanguageLabel => 'Language:';

  @override
  String get episodeContents => 'Contents';

  @override
  String get episodeArticle => 'Article';

  @override
  String get episodeListen => 'Listen to episode';

  @override
  String get episodeWatchOnYouTube => 'Watch on YouTube';

  @override
  String get episodeStageQueuedBadge => 'Queued';

  @override
  String get episodeStageFetchedBadge => 'Downloading';

  @override
  String get episodeStageMediaReadyBadge => 'Transcribing';

  @override
  String get episodeStageTranscribedBadge => 'Writing article';

  @override
  String get episodeStageQueuedHeadline =>
      'This episode hasn’t been downloaded yet';

  @override
  String get episodeStageFetchedHeadline => 'Downloading the audio and video';

  @override
  String get episodeStageMediaReadyHeadline => 'Transcribing the conversation';

  @override
  String get episodeStageTranscribedHeadline =>
      'Writing the summary and article';

  @override
  String get episodeStagePublishedHeadline => 'This episode is fully processed';

  @override
  String get episodeStageQueuedBody =>
      'We know about it from the channel, but the files aren’t with us yet — the download either failed or hasn’t run. Watch it at the source in the meantime.';

  @override
  String get episodeStageFetchedBody =>
      'We have the title, description and thumbnail; the audio and video aren’t here yet. Playback on our side won’t work until they are — watch the episode at the source for now.';

  @override
  String get episodeStageMediaReadyBodyVideo =>
      'You can watch the video right away. The transcript, summary, chapters, article and theological analysis arrive as soon as processing produces them.';

  @override
  String get episodeStageMediaReadyBodyAudio =>
      'You can listen right away. The transcript, summary, chapters, article and theological analysis arrive as soon as processing produces them.';

  @override
  String get episodeStageTranscribedBody =>
      'The transcript is done. The summary, chapters, article and theological analysis arrive as soon as processing produces them.';

  @override
  String get episodeStagePublishedBody => 'All the content is ready.';

  @override
  String get episodeStepFetch => 'Episode fetched';

  @override
  String get episodeStepMedia => 'Audio and video';

  @override
  String get episodeStepTranscript => 'Transcript';

  @override
  String get episodeStepSummary => 'Summary';

  @override
  String get episodeStepArticle => 'Article';

  @override
  String get episodeStepMagisterium => 'Theological analysis';

  @override
  String get episodeStatusStepsTitle => 'Processing progress';

  @override
  String get episodeWatchHere => 'Watch here';

  @override
  String get episodeWatchInApp => 'Watch in the app';

  @override
  String get episodeWatchOurPlayer => 'Watch the episode';

  @override
  String get episodeEmbedBlocked =>
      'The owner disabled the embedded player for this episode, so it opens on YouTube.';

  @override
  String episodeStatusNotOnCdn(String id) {
    return 'Episode “$id” wasn’t found on the CDN.';
  }

  @override
  String get episodeYouTubeUntilProcessed =>
      'Watch on YouTube until we finish processing this episode.';

  @override
  String get episodeMediaUnavailable =>
      'Media isn’t available for this episode.';

  @override
  String get episodeNoChapters => 'No chapters for this episode.';

  @override
  String get episodeKeyTopics => 'Key topics';

  @override
  String get episodeKeyTakeaways => 'Key takeaways';

  @override
  String get episodeSpeakers => 'Speakers';

  @override
  String get episodeTabPlayer => 'Player';

  @override
  String get episodeTabChapters => 'Chapters';

  @override
  String get episodeTabInfo => 'Info';

  @override
  String get episodeMetadata => 'Metadata';

  @override
  String get episodeMetaChannel => 'Channel';

  @override
  String get episodeMetaModelSummary => 'Model (summary)';

  @override
  String get episodeMetaModelArticle => 'Model (article)';

  @override
  String get episodeMetaModelTheology => 'Model (theology)';

  @override
  String get episodeMetaGenerated => 'Generated';

  @override
  String get episodeMetaLanguage => 'Language';

  @override
  String get episodeMetaContentType => 'Content type';

  @override
  String get episodeMetaSentiment => 'Sentiment';

  @override
  String get episodeMetaDate => 'Date';

  @override
  String get episodeMetaDuration => 'Duration';

  @override
  String homeChannelCardMeta(int count, String duration) {
    return 'Channel · $count ep · $duration';
  }

  @override
  String homeChannelMagisteriumTooltip(String label) {
    return '$label\nAn estimate of alignment with Catholic teaching (0–100).';
  }

  @override
  String get homeFooterAbout => 'About';

  @override
  String homeFooterAboutText(String app) {
    return '$app uses artificial intelligence to transcribe, summarise and analyse Croatian Catholic podcasts. The Magisterium AI agent rates their alignment with Catholic teaching.';
  }

  @override
  String homeFooterAboutTextGeneric(String app) {
    return '$app uses artificial intelligence to transcribe podcasts, split them into chapters and turn them into articles you can read, with speakers and search by meaning.';
  }

  @override
  String get homeFooterLinks => 'Links';

  @override
  String get homeFooterSuggestEpisode => 'Suggest an episode';

  @override
  String homeFooterEpisodeSuggestionSubject(String app) {
    return '$app — episode suggestion';
  }

  @override
  String get homeFooterContact => 'Contact';

  @override
  String get homeFooterPrivacy => 'Privacy';

  @override
  String get homeFooterTerms => 'Terms of use';

  @override
  String get homeFooterStats => 'Statistics';

  @override
  String homeFooterStatChannels(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'channels',
      one: 'channel',
    );
    return '$_temp0';
  }

  @override
  String homeFooterStatEpisodes(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'episodes',
      one: 'episode',
    );
    return '$_temp0';
  }

  @override
  String homeFooterStatHours(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'hours processed',
      one: 'hour processed',
    );
    return '$_temp0';
  }

  @override
  String get homeFooterStatAvgScore => 'average Magisterium score';

  @override
  String get homeFooterSoon => 'Soon';

  @override
  String homeFooterCopyright(int year, String app) {
    return '© $year $app';
  }

  @override
  String get homeFooterMadeIn => 'Made in Croatia';

  @override
  String get homeSearchPlaceholderFull => 'Search channels and episodes';

  @override
  String get homeSearchTooltip => 'Search';

  @override
  String get homeSortNewest => 'Newest';

  @override
  String get homeSortMostEpisodes => 'Most episodes';

  @override
  String get homeSortMagisterium => 'Magisterium score';

  @override
  String get homeSortAlphabetical => 'Alphabetical';

  @override
  String get homeSortCustom => 'My order';

  @override
  String get homeReasonShortHiQualityRecent => 'Top pick';

  @override
  String get homeReasonShortHiQuality => 'High Magisterium score';

  @override
  String get homeReasonShortAnyMagisterium => 'AI-processed';

  @override
  String get homeReasonShortNewest => 'Newest';

  @override
  String homeHeroRotationTooltip(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          'Each day we pick the $count best episodes — they rotate automatically.',
      one: 'Each day we pick the best episode — they rotate automatically.',
    );
    return '$_temp0';
  }

  @override
  String get homeHeroRotationBadge => 'In rotation';

  @override
  String get homeHeroEyebrow => 'Featured';

  @override
  String get homeHeroListen => 'Listen';

  @override
  String get homeHeroWhyButton => 'Why?';

  @override
  String get homeWhyDialogTitle => 'Why this is featured';

  @override
  String get homeWhyAlgorithmHeading => 'How the algorithm works';

  @override
  String get homeWhyDialogExplainer =>
      'The featured episode changes every day at midnight — the algorithm shortlists the five best candidates from the active tier and picks one based on the day of the year. The choice stays the same throughout the day (deterministic).';

  @override
  String get homeWhyGotIt => 'Got it';

  @override
  String get homeReasonHeadlineHiQualityRecent => 'High score, fresh episode';

  @override
  String get homeReasonHeadlineHiQuality => 'High Magisterium score';

  @override
  String get homeReasonHeadlineAnyMagisterium => 'AI-processed episode';

  @override
  String get homeReasonHeadlineNewest => 'Newest episode';

  @override
  String get homeWhyFactChannel => 'Channel';

  @override
  String get homeWhyFactScore => 'Magisterium score';

  @override
  String get homeWhyFactPublished => 'Published';

  @override
  String get homeWhyFactAiProcessing => 'AI processing';

  @override
  String get homeWhyFactAiYes =>
      'Yes (transcript, summary and Magisterium analysis)';

  @override
  String get homeWhyFactAiYesGeneric =>
      'Yes (transcript, article and chapters)';

  @override
  String get homeWhyFactAiNo => 'No';

  @override
  String get homeWhyFactWeight => 'Algorithm weight';

  @override
  String homeWhyFactWeightValue(String weight) {
    return '$weight (score × 0.6 + recency × 0.4)';
  }

  @override
  String get homeWhyFactPool => 'Candidate pool';

  @override
  String homeWhyFactPoolValue(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count episodes in the same tier',
      one: '$count episode in the same tier',
    );
    return '$_temp0';
  }

  @override
  String get homeTier1Title => '1. Top pick';

  @override
  String get homeTier1Desc =>
      'AI processing + score ≥ 70 + published in the last 14 days. Ranked by (score × 0.6 + recency × 0.4). The top five enter the daily rotation.';

  @override
  String get homeTier2Title => '2. High score';

  @override
  String get homeTier2Desc =>
      'AI processing + score ≥ 70 (any date). Ranked by score.';

  @override
  String get homeTier3Title => '3. AI-processed';

  @override
  String get homeTier3Desc => 'Any episode with AI processing. Ranked by date.';

  @override
  String get homeTier4Title => '4. Newest';

  @override
  String get homeTier4Desc =>
      'Fallback — the newest episode with no processing at all.';

  @override
  String get homeAgoToday => 'today';

  @override
  String get homeAgoYesterday => 'yesterday';

  @override
  String homeAgoDays(int days) {
    String _temp0 = intl.Intl.pluralLogic(
      days,
      locale: localeName,
      other: '$days days ago',
      one: '$days day ago',
    );
    return '$_temp0';
  }

  @override
  String homeAgoWeeks(int weeks) {
    String _temp0 = intl.Intl.pluralLogic(
      weeks,
      locale: localeName,
      other: '$weeks weeks ago',
      one: '$weeks week ago',
    );
    return '$_temp0';
  }

  @override
  String homeAgoMonths(int months) {
    String _temp0 = intl.Intl.pluralLogic(
      months,
      locale: localeName,
      other: '$months months ago',
      one: '$months month ago',
    );
    return '$_temp0';
  }

  @override
  String homeAgoYears(int years) {
    String _temp0 = intl.Intl.pluralLogic(
      years,
      locale: localeName,
      other: '$years years ago',
      one: '$years year ago',
    );
    return '$_temp0';
  }

  @override
  String get homeComingSoonSnack => 'This feature is coming soon';

  @override
  String homeChannelsLoadError(String error) {
    return 'Couldn\'t load the channels:\n$error';
  }

  @override
  String get homeRailContinue => 'Continue listening';

  @override
  String get homeRailLatest => 'Latest episodes';

  @override
  String get homeRailFeaturedShows => 'Featured shows';

  @override
  String get homeRailFavorites => 'Your saved episodes';

  @override
  String get favoritesTitle => 'Saved episodes';

  @override
  String favoritesCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count episodes',
      one: '$count episode',
    );
    return '$_temp0';
  }

  @override
  String get favoritesEmptyTitle => 'Nothing saved yet';

  @override
  String get favoritesEmptyBody =>
      'Tap the heart on an episode and you\'ll find it here — newest first.';

  @override
  String get favoritesBrowse => 'Browse episodes';

  @override
  String get favoritesSaved => 'Saved';

  @override
  String get favoritesRemoved => 'Removed from saved';

  @override
  String get favoritesAccountSubtitle => 'The full list, newest first';

  @override
  String get authSectionLibrary => 'My library';

  @override
  String get homeRailFreshlyArrived => 'Just arrived';

  @override
  String get homeStatusProcessing => 'Processing';

  @override
  String get homeChannelsEyebrow => 'Channels';

  @override
  String get homeAllChannelsTitle => 'All channels';

  @override
  String homeAllChannelsSubtitle(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Browse and search all $count channels',
      one: 'Browse and search $count channel',
    );
    return '$_temp0';
  }

  @override
  String homeLoadingChannels(int loaded, int total) {
    return 'Loading $loaded/$total channels…';
  }

  @override
  String get homeSearchBarrierLabel => 'Close search';

  @override
  String get homeSearchHint => 'Search channels, episodes and content…';

  @override
  String get homeSearchClear => 'Clear search';

  @override
  String homeSearchNoResults(String query) {
    return 'No results for “$query”';
  }

  @override
  String get homeSearchSearching => 'Searching…';

  @override
  String get homeSearchSectionChannels => 'Channels';

  @override
  String get homeSearchSectionEpisodes => 'Episodes';

  @override
  String get homeSearchEmptyTitle => 'Start typing to search';

  @override
  String get homeSearchEmptySubtitle =>
      'Searches channels, episodes and the conversations themselves';

  @override
  String get homeSearchKeyboardHint => '↑ ↓ to move · ↵ to open';

  @override
  String homeSearchChannelMeta(int count, String duration) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count episodes · $duration',
      one: '$count episode · $duration',
    );
    return '$_temp0';
  }

  @override
  String get homeSearchOpenById => 'Open by YouTube ID';

  @override
  String get homeSearchShowAll => 'Show all results';

  @override
  String homeSearchJumpTo(String time) {
    return 'Play from $time';
  }

  @override
  String get homeSearchIdHint => 'e.g. H-p2Hl6x7I0';

  @override
  String legalLastUpdated(String date) {
    return 'Last updated: $date';
  }

  @override
  String get legalPrivacyPushTitle => 'Push notifications';

  @override
  String get legalPrivacyPushBody =>
      'If you turn on notifications in the iOS or Android app, we let you know when a new episode arrives — all new episodes, or only from the channels you choose on the Notifications screen. Delivery uses Google Firebase Cloud Messaging: your device receives a registration token and subscribes to the topics you chose (such as \"all new episodes\" or a single channel). We do not store the token or the topic list with your account; your choice of topics is kept only on your device, and Google holds the subscriptions as a data processor.\n\nWe send notifications on the basis of your consent (Article 6(1)(a) GDPR), which you give by turning notifications on and granting the system permission. You can withdraw it at any time on the Notifications screen or in your device settings. We do not send notifications between 10 pm and 7 am.';

  @override
  String get legalContactTitle => 'Contact';

  @override
  String get legalPrivacyTitle => 'Privacy Policy';

  @override
  String legalPrivacyIntro(String app) {
    return '$app is an application that transcribes, summarises and analyses Croatian Catholic podcasts using artificial intelligence.';
  }

  @override
  String legalPrivacyIntroGeneric(String app) {
    return '$app is an application that uses artificial intelligence to transcribe podcasts, split them into chapters and turn them into readable articles.';
  }

  @override
  String get legalPrivacyDataTitle => 'What data we collect';

  @override
  String legalPrivacyDataBody(String email) {
    return 'ITalk d.o.o., acting as the Data Controller, processes your personal data in compliance with the General Data Protection Regulation (GDPR - Regulation EU 2016/679).\n\nWhen you sign in (via Certilia IDP, Google, Apple, or email), we collect basic identification data (email, name, and national ID/OIB if using the e-Citizens/Certilia system) solely to provide the service. Your playback progress, favourite markers, and votes are stored for cross-device synchronisation.\n\nFor \"Plus\" subscriptions, purchase data is processed via third-party processors (Apple, Google, RevenueCat); we do not store or access your credit card details. We implement the highest technical and organisational security measures (encryption in transit and at rest).\n\nYou have the right to access, rectify, restrict, port, and erase your data (you may permanently delete your account within the app at any time). For privacy enquiries, contact $email. In case of suspected data breaches, you have the right to lodge a complaint with the Croatian Personal Data Protection Agency (AZOP).';
  }

  @override
  String get legalPrivacyAnalyticsTitle => 'Usage analytics';

  @override
  String legalPrivacyAnalyticsBody(String email) {
    return 'To understand how the application is used and to improve it, we record usage events: opening the app, the pages and episodes you open, playback (start, pause, seeking, speed and how much of an episode you listened to), the queries you type into search and which result you open, session length, and views of and clicks on sponsor messages. With each event we store a random device identifier (created by the app on first launch and kept in your browser\'s or device\'s storage), a session identifier, device and browser type, app version, language, screen size, and approximate location (country, region and city) as determined by Cloudflare. If you are signed in, we also link events to your account identifier. We do not store your IP address.\n\nWe process this data on the basis of legitimate interest (Article 6(1)(f) GDPR): to measure and improve the service, including search, and to record the display of sponsor messages. We do not use third-party tracking tools (such as Google Analytics). The data is stored on our own server in the European Union (Frankfurt), with Cloudflare transmitting it as a data processor. We do not sell it or share it with third parties for advertising. We keep it for 25 months. You can remove the device identifier by clearing the app\'s data or your browser storage. To have events linked to your account deleted, contact $email.';
  }

  @override
  String legalPrivacyContactBody(String email) {
    return 'The application is operated by ITalk d.o.o. za informacijske tehnologije, IX. Južna obala 20, 10000 Zagreb, Croatia, VAT: 54872935051. For privacy-related enquiries, please contact Matija Stepanić at $email.';
  }

  @override
  String get legalTermsTitle => 'Terms of Use';

  @override
  String legalTermsIntro(String app) {
    return 'By using the $app application, you accept these Terms of Use.';
  }

  @override
  String get legalTermsContentTitle => 'Content';

  @override
  String get legalTermsContentBody =>
      'All audio and video materials are sourced from publicly available channels. The application is provided on an \"as-is\" and \"as-available\" basis without warranties of any kind. ITalk d.o.o. shall not be liable for any direct or indirect damages arising from the use of the app, and total liability is limited to the subscription amount paid in the preceding 3 months. \"Plus\" subscriptions renew according to the terms of third-party providers (Apple/Google). These terms are governed by the laws of the Republic of Croatia, subject to the jurisdiction of courts in Zagreb.';

  @override
  String get legalTermsAiTitle => 'AI analysis';

  @override
  String get legalTermsAiBody =>
      'Analyses, summaries, and Magisterium ratings are generated automatically using Artificial Intelligence (AI) and may contain errors or inaccuracies (hallucinations). They do not represent the official position of the Catholic Church. The User utilises AI features at their own risk, and ITalk d.o.o. disclaims all liability for the accuracy and legal consequences of such generated content.';

  @override
  String get legalTermsAiBodyGeneric =>
      'Articles, summaries, chapters and speaker labels are generated automatically using Artificial Intelligence (AI) and may contain errors or inaccuracies (hallucinations). The User utilises AI features at their own risk, and ITalk d.o.o. disclaims all liability for the accuracy and legal consequences of such generated content.';

  @override
  String legalTermsContactBody(String email) {
    return 'The application is operated by ITalk d.o.o. za informacijske tehnologije, IX. Južna obala 20, 10000 Zagreb, Croatia, VAT: 54872935051. For any enquiries, please contact Matija Stepanić at $email.';
  }

  @override
  String get magisteriumScoreActivelyPromotes =>
      'Actively promotes Catholic teaching';

  @override
  String get magisteriumScoreMostlyAligned => 'Mostly aligned';

  @override
  String get magisteriumScorePartiallyAligned => 'Partially aligned';

  @override
  String get magisteriumScoreDeviates => 'Departs from teaching';

  @override
  String get magisteriumScoreContradicts => 'Contradicts teaching';

  @override
  String get magisteriumAlignmentSubtitle =>
      'Alignment with Catholic teaching and Sacred Scripture';

  @override
  String magisteriumTheologicalConcerns(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count theological concerns',
      one: '$count theological concern',
    );
    return '$_temp0';
  }

  @override
  String get magisteriumArticleHeaderTitle =>
      'Magisterium AI — Theological analysis';

  @override
  String get magisteriumArticleHeaderSubtitle =>
      'Chronological review of alignment with Catholic teaching';

  @override
  String magisteriumAnalysisGeneratedBy(String model, String date) {
    return 'Analysis generated by model $model • $date';
  }

  @override
  String magisteriumSourcesFromChurchDocs(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count sources from Church documents',
      one: '$count source from Church documents',
    );
    return '$_temp0';
  }

  @override
  String get magisteriumTabEvaluation => 'Evaluation';

  @override
  String get magisteriumTabPrompt => 'Prompt';

  @override
  String get magisteriumFullHeaderTitle =>
      'Magisterium AI — Theological evaluation';

  @override
  String magisteriumModelCitations(String model, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count citations',
      one: '$count citation',
    );
    return '$model  •  $_temp0';
  }

  @override
  String get magisteriumSourcesTitle => 'Sources';

  @override
  String magisteriumCitationsFromChurchDocs(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count citations from Church documents',
      one: '$count citation from Church documents',
    );
    return '$_temp0';
  }

  @override
  String get magisteriumScoreCaption => 'Magisterium score';

  @override
  String get magisteriumOpenOnMagisterium => 'Open on Magisterium.com';

  @override
  String get mediaYouTubeHigherQuality => 'YouTube player (higher quality)';

  @override
  String get mediaSubtitlesOff => 'Turn off subtitles (C)';

  @override
  String get mediaSubtitlesOn => 'Subtitles (C)';

  @override
  String get mediaBoostVolume => 'Turn on sound';

  @override
  String get mediaRemotePlay => 'Play on TV';

  @override
  String get mediaRemoteConnecting => 'Connecting to TV…';

  @override
  String get mediaRemoteConnected => 'Playing on TV';

  @override
  String get mediaMute => 'Mute (M)';

  @override
  String get mediaPause => 'Pause';

  @override
  String get mediaPlay => 'Play';

  @override
  String get mediaChapters => 'Chapters';

  @override
  String get mediaYouTubeQualityHint =>
      'YouTube player — choose quality in the player settings';

  @override
  String mediaNativePlayerLabel(String brand) {
    return '$brand player';
  }

  @override
  String get mediaLanguageSelection => 'Display language selection';

  @override
  String get mediaTranslationDisclaimer =>
      'Translation is literal, without AI hallucinations.';

  @override
  String get mediaSwitchToCroatian => 'Switch to Croatian';

  @override
  String get mediaSwitchToEnglish => 'Switch to English';

  @override
  String get mediaRemoveFavorite => 'Remove from favorites';

  @override
  String get mediaAddFavorite => 'Add to favorites';

  @override
  String mediaResumingFrom(String time) {
    return 'Resuming from $time';
  }

  @override
  String get mediaSwitchToLightTheme => 'Switch to light theme';

  @override
  String get mediaSwitchToDarkTheme => 'Switch to dark theme';

  @override
  String get mediaViewSimple => 'Simple';

  @override
  String get mediaViewDetailed => 'Detailed';

  @override
  String get mediaViewSimpleTooltip =>
      'Switch to the simple view — large player and chapters, without the article (ideal for listening in the car)';

  @override
  String get mediaViewDetailedTooltip =>
      'Switch to the detailed view — article, Magisterium score and chapters alongside the video';

  @override
  String get mediaViewDetailedTooltipGeneric =>
      'Switch to the detailed view — article and chapters alongside the video';

  @override
  String get mediaUserFallback => 'User';

  @override
  String mediaViaProvider(String provider) {
    return 'via $provider';
  }

  @override
  String get mediaVerifiedIdentity => 'Verified identity';

  @override
  String get mediaMyAccount => 'My account';

  @override
  String get mediaMyChannels => 'My channels';

  @override
  String get mediaSwitchDevice => 'Switch to another device';

  @override
  String mediaMinAmount(String amount) {
    return 'Minimum amount is $amount €';
  }

  @override
  String get mediaPaymentCreateFailed =>
      'Could not create the payment. Please try again.';

  @override
  String get mediaSupportEpisode => 'Support this episode';

  @override
  String get mediaSupportBlurb =>
      'Donate with a single scan — SEPA, no fees. Funds go directly to the creator, transparently on-chain.';

  @override
  String mediaRaisedProgress(String raised, String goal, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '# supporters',
      one: '# supporter',
    );
    return 'Raised $raised € of $goal € · $_temp0';
  }

  @override
  String get mediaPreparing => 'Preparing…';

  @override
  String mediaSupportWithAmount(String amount) {
    return 'Support with $amount €';
  }

  @override
  String get mediaScanInBankApp => 'Scan in your banking app';

  @override
  String mediaAmountValue(String amount) {
    return 'Amount: $amount €';
  }

  @override
  String get mediaRecipient => 'Recipient';

  @override
  String get mediaPaymentReference => 'Payment reference';

  @override
  String get mediaAwaitingPayment => 'Awaiting payment confirmation…';

  @override
  String get mediaPaymentConfirmedOnChain => 'Payment confirmed on-chain.';

  @override
  String mediaCopiedLabel(String label) {
    return 'Copied: $label';
  }

  @override
  String get mediaOtherAmount => 'Other';

  @override
  String get ownershipCrumbHome => 'Home';

  @override
  String get ownershipCrumbOwnership => 'Ownership';

  @override
  String get ownershipChannelFallback => 'Channel';

  @override
  String get ownershipMyChannels => 'My channels';

  @override
  String get ownershipLoadChannelFailed => 'We couldn\'t load the channel.';

  @override
  String get ownershipOpenAuthFailed =>
      'We couldn\'t open the authorization page.';

  @override
  String get ownershipSignInToClaim => 'Sign in first to claim this channel.';

  @override
  String get ownershipNoYoutubeId =>
      'This channel isn\'t linked to a YouTube ID yet, so it can\'t be claimed right now.';

  @override
  String get ownershipChannelNotFound => 'Channel not found.';

  @override
  String get ownershipNotOwnerTitle => 'Not the channel owner?';

  @override
  String ownershipNotOwnerBody(String app) {
    return 'If you know the owner, send them a message to claim ownership and verify on $app.';
  }

  @override
  String get ownershipInviteOwnerWhatsApp => 'Invite the owner (WhatsApp)';

  @override
  String ownershipInviteMessage(String channelTitle, String link, String app) {
    return 'Hello! Your YouTube channel \"$channelTitle\" is on $app. You can claim ownership for free and manage your content and payouts — verify yourself as the channel owner here: $link';
  }

  @override
  String get ownershipStepConfirmTitle => 'Confirm ownership';

  @override
  String get ownershipReverifySubtitle =>
      'Ownership is older than 90 days — please confirm it again.';

  @override
  String get ownershipOwnershipVerifiedSubtitle =>
      'Ownership confirmed via your YouTube account.';

  @override
  String get ownershipSignInYoutubeSubtitle =>
      'Sign in with the YouTube account that owns this channel.';

  @override
  String get ownershipOwnershipNote =>
      'Only the Google account that owns the channel can claim it. Editors and managers added in YouTube settings (Channel permissions) can\'t — YouTube doesn\'t list them as owners. If the channel belongs to a Brand account, sign in with the Google account that manages it.';

  @override
  String get ownershipReverifyAction => 'Re-verify';

  @override
  String get ownershipLoginYoutube => 'Sign in with YouTube';

  @override
  String get ownershipStepVerifyIdentityTitle => 'Verify your identity';

  @override
  String get ownershipIdentityVerifiedSubtitle =>
      'Identity verified (eID card).';

  @override
  String get ownershipConnectEosobnaSubtitle =>
      'Connect your eID card (Certilia) — required before payout.';

  @override
  String get ownershipVerifyWithEosobna => 'Verify with eID card';

  @override
  String get ownershipStepConnectWalletTitle => 'Connect a wallet';

  @override
  String get ownershipWalletLockedSubtitle =>
      'Available after ownership and identity verification.';

  @override
  String get ownershipWalletSubtitle =>
      'Register a payout wallet address (destination).';

  @override
  String get ownershipManageWallet => 'Manage wallet';

  @override
  String get ownershipCheckingOwnership => 'Verifying ownership…';

  @override
  String get ownershipMissingAuthData => 'Authorization data is missing.';

  @override
  String ownershipOwnershipConfirmedWithName(String name) {
    return 'Ownership confirmed: $name';
  }

  @override
  String ownershipRequestReceivedWithStatus(String status) {
    return 'Request received (status: $status).';
  }

  @override
  String get ownershipCallbackTitle => 'Ownership confirmation';

  @override
  String get ownershipRevokeDialogTitle => 'Release ownership?';

  @override
  String ownershipRevokeDialogBody(String name) {
    return 'You\'re giving up ownership of \"$name\". Verification and payout status will be reset, and the channel becomes available to claim again. You can reclaim it any time.';
  }

  @override
  String get ownershipRevokeAction => 'Release';

  @override
  String get ownershipRevokedSnack => 'Ownership released.';

  @override
  String get ownershipClaimedChannelsTitle => 'Claimed channels';

  @override
  String get ownershipPayoutWalletsTitle => 'Payout wallets';

  @override
  String get ownershipPayoutWalletsDesc =>
      'The destination where your collected funds are paid out — your crypto wallet (0x, Gnosis). When you request a payout, the platform transfers to this address.\n\nThis is NOT the address that receives donations: each campaign has its own Safe where contributions arrive (visible to everyone on Gnosisscan); you start a payout from campaign management.';

  @override
  String get ownershipNoClaimsBody =>
      'You haven\'t claimed any channels yet. Open a channel and choose \"Claim ownership\" to start verification.';

  @override
  String get ownershipBrowseChannels => 'Browse channels';

  @override
  String get ownershipNeedsReverifyTag => 'needs re-verification';

  @override
  String get ownershipOptionsTooltip => 'Options';

  @override
  String get ownershipCampaignsMenu => 'Campaigns (Support Wall)';

  @override
  String get ownershipRevokeMenu => 'Release ownership';

  @override
  String get ownershipWalletDestVerified => 'Payout destination · verified';

  @override
  String get ownershipWalletDest => 'Payout destination';

  @override
  String get ownershipWalletAddressLabel => 'Your payout wallet address (0x…)';

  @override
  String get ownershipWalletAddressHelper =>
      'The EVM address (Gnosis) where you receive payouts.';

  @override
  String get ownershipAddWallet => 'Add wallet';

  @override
  String get ownershipCampaignFallback => 'Campaign';

  @override
  String get ownershipTabEdit => 'Edit';

  @override
  String get ownershipTabEpisodes => 'Episodes';

  @override
  String get ownershipTabStats => 'Stats';

  @override
  String get ownershipTabPayout => 'Payout';

  @override
  String get ownershipCampaignNotFound => 'Campaign not found.';

  @override
  String get ownershipSaved => 'Saved';

  @override
  String get ownershipSaveFailed => 'Couldn\'t save changes.';

  @override
  String get ownershipFieldTitle => 'Title';

  @override
  String get ownershipFieldDescription => 'Description';

  @override
  String get ownershipFieldGoal => 'Goal (€)';

  @override
  String get ownershipFieldGoalHint => 'empty = no goal';

  @override
  String get ownershipFieldMinAmount => 'Min. amount (€)';

  @override
  String get ownershipFieldState => 'Status';

  @override
  String get ownershipFieldVisibility => 'Visibility';

  @override
  String get ownershipEditNote =>
      'Note: SEPA and on-chain details (IBAN, Safe address) and the slug aren\'t changed here.';

  @override
  String get ownershipSaveChanges => 'Save changes';

  @override
  String get ownershipStateDraft => 'Draft';

  @override
  String get ownershipStateActive => 'Active';

  @override
  String get ownershipStateClosed => 'Closed';

  @override
  String get ownershipStateCancelled => 'Cancelled';

  @override
  String get ownershipStateFunded => 'Funded';

  @override
  String get ownershipVisPublic => 'Public';

  @override
  String get ownershipVisUnlisted => 'Unlisted';

  @override
  String get ownershipVisPrivate => 'Private';

  @override
  String ownershipSupportersContributions(int supporters, int contributions) {
    String _temp0 = intl.Intl.pluralLogic(
      supporters,
      locale: localeName,
      other: '$supporters supporters',
      one: '$supporters supporter',
    );
    String _temp1 = intl.Intl.pluralLogic(
      contributions,
      locale: localeName,
      other: '$contributions contributions',
      one: '$contributions contribution',
    );
    return '$_temp0 · $_temp1';
  }

  @override
  String get ownershipSupportWall => 'Support Wall';

  @override
  String get ownershipNoPublicContributions => 'No public contributions yet.';

  @override
  String get ownershipEnterValidAmount => 'Enter a valid amount.';

  @override
  String get ownershipAmountExceedsAvailable =>
      'Amount exceeds the available balance.';

  @override
  String get ownershipEnterDestination =>
      'Enter a destination (0x address or IBAN).';

  @override
  String get ownershipPayoutRequestSent => 'Payout request sent';

  @override
  String get ownershipRequestFailedRetry =>
      'The request failed. Please try again.';

  @override
  String get ownershipErrKycRequired =>
      'eID (KYC) verification is required before payout.';

  @override
  String get ownershipErrInvalidDestination =>
      'Invalid destination (0x address or IBAN).';

  @override
  String get ownershipErrInvalidAmount => 'Invalid amount.';

  @override
  String get ownershipErrNotAuthorized =>
      'You\'re not authorized for this campaign.';

  @override
  String get ownershipErrRequestFailed => 'The request failed.';

  @override
  String get ownershipPayoutNeedsKyc =>
      'Payout requires eID (KYC) verification. Complete it in \"My channels\".';

  @override
  String get ownershipRequestPayout => 'Request payout';

  @override
  String get ownershipDestinationLabel => 'Destination (0x address or IBAN)';

  @override
  String get ownershipAmountLabel => 'Amount (€)';

  @override
  String ownershipAvailableHelper(String amount) {
    return 'Available: $amount €';
  }

  @override
  String get ownershipPayoutHistory => 'Payout history';

  @override
  String get ownershipNoPayouts => 'No payouts yet.';

  @override
  String get ownershipChangeFailed => 'The change failed.';

  @override
  String get ownershipYieldTitle => 'Earn yield (Aave v3 · Gnosis)';

  @override
  String get ownershipYieldSubtitle =>
      'While funds await payout, they earn yield (~3.5% APY, variable). The yield belongs to the campaign. DeFi risk — principal isn\'t guaranteed.';

  @override
  String get ownershipYieldInPool => 'Earning yield (Aave)';

  @override
  String get ownershipYieldAccrued => 'Accrued yield';

  @override
  String ownershipYieldLastSync(String time) {
    return 'last sync: $time';
  }

  @override
  String get ownershipYieldTokenLink => 'aGnoEURe on Gnosisscan';

  @override
  String get ownershipSummaryRaised => 'Raised';

  @override
  String get ownershipSummaryYield => 'Yield (Aave)';

  @override
  String get ownershipSummaryPending => 'In progress';

  @override
  String get ownershipSummaryPaid => 'Paid out';

  @override
  String get ownershipSummaryAvailable => 'Available';

  @override
  String get ownershipPayoutStateRequested => 'Requested';

  @override
  String get ownershipPayoutStateApproved => 'Approved';

  @override
  String get ownershipPayoutStateFailed => 'Failed';

  @override
  String get ownershipCampaignsTitle => 'Campaigns';

  @override
  String get ownershipSignInToManageCampaigns =>
      'Sign in first to manage campaigns.';

  @override
  String get ownershipNotVerifiedOwner =>
      'You\'re not a verified owner of this channel.';

  @override
  String ownershipEpisodesCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count episodes',
      one: '$count episode',
    );
    return '$_temp0';
  }

  @override
  String get ownershipNoCampaignsTitle => 'No campaigns for this channel yet.';

  @override
  String get ownershipNoCampaignsBody =>
      'Campaigns are created on pinka.io (which also generates the payout Safe). After creating one, link the campaign to your channel so you can manage it here and assign episodes.';

  @override
  String get ownershipEpisodesSaved => 'Episodes saved';

  @override
  String get ownershipEpisodeTaken =>
      'One of the episodes is already in another campaign.';

  @override
  String get ownershipSaveFailedRetry => 'Couldn\'t save. Please try again.';

  @override
  String get ownershipNoEpisodesAvailable =>
      'No episodes available for this channel.';

  @override
  String ownershipSelectedCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count episodes',
      one: '$count episode',
    );
    return 'Selected: $_temp0';
  }

  @override
  String get pinkaWallTitle => 'Wall of Support';

  @override
  String get pinkaSupport => 'Support';

  @override
  String get pinkaNoCampaign =>
      'There\'s no active support campaign for this yet.';

  @override
  String get pinkaWallEmpty =>
      'Be the first to show support — your message will appear here.';

  @override
  String get pinkaRaisedLabel => 'raised';

  @override
  String pinkaOfGoal(String amount) {
    return 'of €$amount goal';
  }

  @override
  String pinkaRaised(String amount) {
    return 'Raised €$amount';
  }

  @override
  String pinkaRaisedOfGoal(String raised, String goal) {
    return 'Raised €$raised of €$goal';
  }

  @override
  String pinkaSupportersCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count supporters',
      one: '$count supporter',
    );
    return '$_temp0';
  }

  @override
  String pinkaPaymentsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count payments',
      one: '$count payment',
    );
    return '$_temp0';
  }

  @override
  String get pinkaVerifyOnchainTitle => 'Verify on-chain';

  @override
  String get pinkaVerifyOnchainBody =>
      'Contributions go straight to the campaign\'s Safe (EURe on Gnosis). Anyone can verify the balance — independently of us.';

  @override
  String pinkaOnchainBalance(String amount) {
    return 'Currently on the Safe: $amount €';
  }

  @override
  String get pinkaEureBalanceOnGnosisscan => 'EURe balance on Gnosisscan';

  @override
  String get pinkaInflowHistory => 'Inflow history (transfers)';

  @override
  String get pinkaFundsWorkingAave =>
      'Funds are currently working on Aave v3 (Gnosis)';

  @override
  String pinkaInAaveLabel(String amount) {
    return 'In Aave: €$amount';
  }

  @override
  String pinkaAaveYieldLabel(String amount) {
    return 'yield: €$amount';
  }

  @override
  String get pinkaAaveExplainer =>
      'That\'s why the EURe balance on the Safe itself is low — the funds are deposited to earn yield and are withdrawn at payout.';

  @override
  String get pinkaAgnoEureBalanceOnGnosisscan =>
      'aGnoEURe balance on Gnosisscan';

  @override
  String pinkaMinAmount(String amount) {
    return 'The minimum amount is €$amount';
  }

  @override
  String get pinkaPaymentCreateFailed =>
      'We couldn\'t prepare the payment. Please try again.';

  @override
  String get pinkaPaymentSentPending =>
      'Payment sent — it will appear on the wall as soon as it\'s confirmed on-chain.';

  @override
  String get pinkaWalletSendFailed =>
      'Sending from the wallet failed or was cancelled.';

  @override
  String get pinkaOnchainBlurb =>
      'Send EURe (Gnosis) directly on-chain — transparent and without intermediaries.';

  @override
  String get pinkaSepaBlurb =>
      'Donate with a single scan — SEPA, no fees. Funds go directly to the author.';

  @override
  String get pinkaCustomAmountHint => 'Other';

  @override
  String get pinkaCustomAmountPlaceholder => '19.91';

  @override
  String get pinkaSafeAddressCopied =>
      'Safe Wallet address copied to clipboard.';

  @override
  String get pinkaCopySafeAddress => 'Copy the Safe Wallet address';

  @override
  String pinkaStepOf(int current, int total) {
    return 'Step $current/$total';
  }

  @override
  String get pinkaStepPaymentTitle => 'Payment from your bank';

  @override
  String get pinkaStepPaymentCustodian => 'Custodian: your bank';

  @override
  String get pinkaStepProcessingTitle => 'Received — processing and checks';

  @override
  String get pinkaStepProcessingCustodian =>
      'Custodian: Monerium (regulated e-money issuer)';

  @override
  String get pinkaStepMintedTitle => 'EURe minted';

  @override
  String get pinkaStepMintedCustodian => 'On the blockchain (Gnosis)';

  @override
  String get pinkaStepForwardingTitle => 'Forwarding to the recipient';

  @override
  String get pinkaStepForwardingCustodian => 'MPT relay';

  @override
  String get pinkaStepSettledTitle => 'With the recipient';

  @override
  String get pinkaStepSettledCustodian => 'Custodian: the recipient';

  @override
  String get pinkaIntentRejected =>
      'The payment was rejected during processing — funds are returned to the sender.';

  @override
  String get pinkaIntentExpired =>
      'The payment window has expired. If you did send the payment, it will appear on the wall once it arrives.';

  @override
  String get pinkaNameHint => 'Name or nickname (optional)';

  @override
  String get pinkaMessageHint => 'A message with your support (optional)';

  @override
  String get pinkaNameLabel => 'Name or nickname';

  @override
  String get pinkaNameHelper => 'This is how you\'ll be credited on the wall';

  @override
  String get pinkaLinkLabel => 'Link (optional)';

  @override
  String get pinkaLinkHelper => 'Your site, project or company';

  @override
  String get pinkaLinkInvalid => 'Check the link — it must start with https://';

  @override
  String get pinkaMessageLabel => 'Message (optional)';

  @override
  String get pinkaPreviewHeading => 'This is how your card will look';

  @override
  String get pinkaPreviewNamePlaceholder => 'Your name or nickname';

  @override
  String get pinkaPreviewMessagePlaceholder => 'Your message';

  @override
  String get pinkaWallOpenLink => 'Open link';

  @override
  String get pinkaWallCardDetails => 'Show full message';

  @override
  String get pinkaAnonymousLabel =>
      'Donate anonymously (don\'t show me on the wall of support)';

  @override
  String get pinkaPreparing => 'Preparing…';

  @override
  String pinkaSupportWithAmount(String amount) {
    return 'Support with €$amount';
  }

  @override
  String get pinkaWalletConnecting => 'Connecting wallet…';

  @override
  String get pinkaWalletOpening => 'Opening wallet…';

  @override
  String get pinkaWalletConfirming => 'Confirming on-chain…';

  @override
  String pinkaPayFromDomovinaWallet(String amount, String brand) {
    return 'Pay €$amount from your $brand wallet';
  }

  @override
  String get pinkaOrScanOtherWallet => 'or scan with another wallet';

  @override
  String pinkaScanWithWallet(String amount) {
    return 'Scan with your wallet (MetaMask / Monerium) and send €$amount in EURe.';
  }

  @override
  String get pinkaRecipient => 'Recipient';

  @override
  String get pinkaToken => 'Token';

  @override
  String get pinkaOnchainArrivalNote =>
      'Your donation appears on the wall of support once it lands on-chain (~1–2 min).';

  @override
  String get pinkaScanInBankApp => 'Scan in your banking app';

  @override
  String pinkaAmountLabel(String amount) {
    return 'Amount: €$amount';
  }

  @override
  String get pinkaPaymentReference => 'Payment reference';

  @override
  String get pinkaAwaitingPayment => 'Waiting for payment confirmation…';

  @override
  String get pinkaThanksForSupport => 'Thank you for your support!';

  @override
  String get pinkaPaymentConfirmedOnchain =>
      'Your payment is confirmed on-chain.';

  @override
  String get pinkaSepaReceivedProcessing =>
      'Payment received. EURe is being issued.';

  @override
  String get pinkaSepaFirstPaymentReview =>
      'The first payment from a new account can take a while to be checked. You don\'t need to do anything.';

  @override
  String get pinkaSepaMintedForwarding =>
      'EURe issued, being forwarded to the campaign…';

  @override
  String pinkaIntentRejectedReason(String reason) {
    return 'Reason: $reason';
  }

  @override
  String get pinkaDonateAgain => 'Donate again';

  @override
  String pinkaCopiedLabel(String label) {
    return 'Copied: $label';
  }

  @override
  String get pinkaLink => 'link';

  @override
  String get pinkaAnonymous => 'Anonymous';

  @override
  String get sectionArticle => 'Article';

  @override
  String sectionPlayFrom(String timestamp) {
    return 'Play from $timestamp';
  }

  @override
  String sectionPersonSpeaksHere(String name) {
    return '$name speaks here';
  }

  @override
  String sectionPersonMentionedHere(String name) {
    return 'Mentioned here: $name';
  }

  @override
  String get sectionCopyLink => 'Copy link';

  @override
  String sectionLinkCopied(String timestamp) {
    return 'Link copied: $timestamp';
  }

  @override
  String get sectionTheologicalAssessment => 'Theological assessment';

  @override
  String sectionSources(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count sources',
      one: '$count source',
    );
    return '$_temp0';
  }

  @override
  String get sectionSummary => 'Summary';

  @override
  String get sectionKeyTopics => 'Key topics';

  @override
  String get sectionSpeakers => 'Speakers';

  @override
  String get sectionKeyTakeaways => 'Key takeaways';

  @override
  String get sectionChapters => 'Chapters';

  @override
  String get sectionPeople => 'People';

  @override
  String get sectionPlaces => 'Places';

  @override
  String get sectionOrganizations => 'Organizations';

  @override
  String get sectionContents => 'Contents';

  @override
  String get sectionAgeToday => 'today';

  @override
  String get sectionAgeYesterday => 'yesterday';

  @override
  String sectionAgeDays(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count days ago',
      one: '$count day ago',
    );
    return '$_temp0';
  }

  @override
  String sectionAgeWeeks(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count wks ago',
      one: 'a week ago',
    );
    return '$_temp0';
  }

  @override
  String sectionAgeMonths(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count mo ago',
      one: 'a month ago',
    );
    return '$_temp0';
  }

  @override
  String sectionAgeYears(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count yrs ago',
      one: 'a year ago',
    );
    return '$_temp0';
  }

  @override
  String sectionPublishedOn(String date) {
    return 'Published: $date';
  }

  @override
  String get sectionTheologicalAnalysisSubtitle =>
      'Theological analysis, section by section';

  @override
  String get sectionNoTheologicalAnalysis =>
      'No theological analysis for this section.';

  @override
  String get sectionAudio => 'Audio';

  @override
  String get serviceUnavailable =>
      'This service is currently unavailable. Please try again shortly.';

  @override
  String serviceSignedInAs(String name) {
    return 'You\'re signed in as $name.';
  }

  @override
  String get serviceGenericUser => 'user';

  @override
  String get serviceContinueSignInBrowser =>
      'Continue signing in in your browser…';

  @override
  String get serviceUnexpectedSignInError =>
      'Something went wrong while signing in. Please try again.';

  @override
  String get serviceAuthRateLimited =>
      'Too many attempts — please wait a minute and try again.';

  @override
  String get serviceAuthEmailInvalid =>
      'That email address doesn\'t look right. Please check it.';

  @override
  String get serviceAuthOtpExpired =>
      'The code has expired — request a new one.';

  @override
  String get serviceAuthOtpDisabled =>
      'Sign-in by code is currently unavailable.';

  @override
  String get serviceAuthUserBanned => 'This account is temporarily blocked.';

  @override
  String get serviceAuthSignupDisabled =>
      'New account sign-ups are currently disabled.';

  @override
  String get serviceAuthProviderDisabled =>
      'This sign-in method is currently unavailable.';

  @override
  String get serviceAuthEmailNotConfirmed =>
      'This email address hasn\'t been confirmed yet.';

  @override
  String get serviceAuthNoServerConnection =>
      'Can\'t reach the server. Check your connection and try again.';

  @override
  String get serviceAuthSignInFailed => 'Sign-in failed. Please try again.';

  @override
  String get serviceAccountNoEmailPasskey =>
      'Your account has no email address, so a passkey isn\'t possible right now.';

  @override
  String get servicePasskeyAddedToAccount =>
      'Your passkey was added to your account.';

  @override
  String get servicePasskeyCreated => 'Your passkey was created.';

  @override
  String get serviceEmailSendFailed =>
      'We couldn\'t send the email. Please try again.';

  @override
  String get serviceSignInSuccess => 'You\'re signed in.';

  @override
  String get serviceOtpInvalidOrExpired =>
      'The code is incorrect or has expired — check it or request a new one.';

  @override
  String get servicePasswordInvalid => 'Wrong email or password.';

  @override
  String get serviceOtpCheckFailed => 'We couldn\'t verify the code.';

  @override
  String get serviceAccountDeleteUnavailable =>
      'Deleting your account from the app isn\'t available yet. Email privacy@italk.hr and we\'ll delete it for you.';

  @override
  String serviceAccountDeleteFailedWithStatus(String status) {
    return 'We couldn\'t delete your account ($status). Please try again.';
  }

  @override
  String get serviceAccountDeleteFailed =>
      'We couldn\'t delete your account. Please try again.';

  @override
  String get serviceAccountDeleted =>
      'Your account has been permanently deleted.';

  @override
  String get serviceSignedOutGuest =>
      'You\'re signed out — continuing as a guest.';

  @override
  String get serviceEmailDialogTitle => 'Your email';

  @override
  String get serviceEmailDialogMessage =>
      'We\'ll send you a link and a six-digit code to sign in.';

  @override
  String get serviceEmailDialogHint => 'name@example.com';

  @override
  String get serviceEmailDialogConfirm => 'Send';

  @override
  String get servicePasskeyRequestInProgress =>
      'A passkey request is already in progress — wait for it to finish or refresh the page.';

  @override
  String get servicePasskeyRegisterCancelled =>
      'Passkey registration was cancelled or timed out. Please try again.';

  @override
  String get servicePasskeyPasswordManagerBlockRegister =>
      'A password manager (e.g. LastPass) is blocking the passkey. In its dialog choose \"Use a different passkey\" and pick iCloud/Apple Passwords — or disable LastPass for this site.';

  @override
  String get servicePasskeyAlreadyExists =>
      'This device already has a passkey for this account.';

  @override
  String get servicePasskeyDomainNotAssociated =>
      'This domain isn\'t set up for passkeys. Please try again later.';

  @override
  String get servicePasskeyDeviceUnsupported =>
      'This device doesn\'t support passkeys.';

  @override
  String get servicePasskeyCreateFailed =>
      'A passkey can\'t be created on this device.';

  @override
  String get servicePasskeyNoneOnDevice =>
      'There\'s no passkey saved on this device.';

  @override
  String get servicePasskeyLoginCancelled =>
      'Passkey sign-in was cancelled or timed out. Please try again.';

  @override
  String get servicePasskeyPasswordManagerBlockLogin =>
      'A password manager (e.g. LastPass) is blocking the passkey. In its dialog choose \"Use a different passkey\" — or disable LastPass for this site.';

  @override
  String get servicePasskeyLoginFailed => 'Passkey sign-in failed.';

  @override
  String get servicePasskeyManageUnavailable =>
      'Managing passkeys isn\'t available yet.';

  @override
  String servicePasskeyFetchFailedWithStatus(String status) {
    return 'We couldn\'t load your passkeys ($status).';
  }

  @override
  String get servicePasskeyRemoveUnavailable =>
      'Removing passkeys isn\'t available yet.';

  @override
  String servicePasskeyRemoveFailedWithStatus(String status) {
    return 'We couldn\'t remove the passkey ($status).';
  }

  @override
  String get servicePasskeyFinishFailed =>
      'We couldn\'t finish signing in with your passkey.';

  @override
  String get serviceBackendNoSignInData =>
      'The server didn\'t return the sign-in details.';

  @override
  String get servicePasskeyEmailRequired =>
      'Enter an email to create an account with a passkey.';

  @override
  String servicePasskeyPrepareFailedWithStatus(String status) {
    return 'We couldn\'t prepare the passkey ($status).';
  }

  @override
  String get servicePasskeyNotVerified =>
      'The passkey couldn\'t be verified. Please try again.';

  @override
  String get servicePasskeyUnknownCredential =>
      'This passkey isn\'t recognised — it may belong to a different account.';

  @override
  String get servicePasskeyAccountExists =>
      'An account with that email already exists — sign in with your passkey or Google.';

  @override
  String get serviceSessionExpired =>
      'Your session has expired. Please try again.';

  @override
  String servicePasskeyFinishFailedWithStatus(String status) {
    return 'We couldn\'t finish signing in with your passkey ($status).';
  }

  @override
  String get serviceCertiliaCancelled =>
      'Sign-in with your e-ID was cancelled.';

  @override
  String get serviceCertiliaServerUnavailable =>
      'Certilia is currently unavailable. Please try again shortly.';

  @override
  String get serviceCertiliaFailed => 'Sign-in with your e-ID failed.';

  @override
  String get serviceCertiliaMissingToken =>
      'Certilia didn\'t return a token. Please try again.';

  @override
  String get serviceCertiliaFinishFailed =>
      'We couldn\'t finish signing in with your e-ID.';

  @override
  String get serviceCertiliaInvalidToken =>
      'The Certilia token is invalid. Please try again.';

  @override
  String get serviceCertiliaNoOib =>
      'Certilia didn\'t return an OIB, so sign-in isn\'t possible.';

  @override
  String serviceCertiliaLinkFailedWithStatus(String status) {
    return 'We couldn\'t link your account ($status).';
  }

  @override
  String get serviceHandoffCodeSixDigits =>
      'The code must be exactly six digits.';

  @override
  String get serviceHandoffNoSignInLink =>
      'The server didn\'t return a sign-in link.';

  @override
  String get serviceHandoffNoActiveSession =>
      'This device has no active session — refresh the page and try again.';

  @override
  String get serviceHandoffInvalidOrExpiredCode =>
      'This code doesn\'t exist or has expired.';

  @override
  String get serviceHandoffRequestError =>
      'There was a problem reaching the server. Please try again.';

  @override
  String serviceHandoffTransferFailedWithStatus(String status) {
    return 'The transfer failed ($status).';
  }

  @override
  String get serviceClaimNoAuthUrl =>
      'The server didn\'t return an authorization link.';

  @override
  String get serviceClaimMismatchNoChannel =>
      'The signed-in Google account doesn\'t own this channel. This account doesn\'t manage any YouTube channel. Sign in with the Google account that owns the channel (not just an editor).';

  @override
  String serviceClaimMismatchWithChannel(String name) {
    return 'The signed-in Google account doesn\'t own this channel. With this account you manage the channel: $name. Sign in with the Google account that owns the channel (not just an editor).';
  }

  @override
  String get serviceClaimRevokeFailed =>
      'We couldn\'t release ownership of the channel.';

  @override
  String get serviceClaimChannelMismatch =>
      'The signed-in YouTube account doesn\'t own this channel.';

  @override
  String get serviceClaimNoChannel =>
      'This Google account has no YouTube channel.';

  @override
  String get serviceClaimInvalidState =>
      'The authorization expired. Please try again.';

  @override
  String get serviceClaimAlreadyClaimed =>
      'This channel has already been claimed by another user.';

  @override
  String get serviceClaimNotSignedIn =>
      'You must be signed in to claim a channel.';

  @override
  String get serviceClaimVerifyFailed =>
      'We couldn\'t verify ownership. Please try again.';

  @override
  String get serviceSafeNotEligible =>
      'You don\'t meet the payout requirements yet (ownership, verified identity and a recent re-check).';

  @override
  String get serviceSafeKycRequired =>
      'To receive a payout, first verify your identity with your e-ID (Certilia).';

  @override
  String get serviceSafeWalletNotRegistered =>
      'This wallet address isn\'t registered to your account.';

  @override
  String get serviceSafeNoSafe => 'There\'s no wallet for this episode yet.';

  @override
  String get serviceSafeFrozen => 'This episode\'s wallet is currently frozen.';

  @override
  String get serviceSafeReverifyNeeded =>
      'Ownership needs to be re-verified before a payout.';

  @override
  String get serviceSafeConnectFailed =>
      'We couldn\'t connect to the wallet. Please try again.';

  @override
  String get serviceWalletInvalidAddress =>
      'That wallet address isn\'t valid (it should be 0x followed by 40 hexadecimal characters).';

  @override
  String get serviceWalletNotSignedIn =>
      'You must be signed in to register a wallet.';

  @override
  String get serviceWalletSaveFailed => 'We couldn\'t save your wallet.';

  @override
  String get serviceWalletRemoveFailed => 'We couldn\'t remove your wallet.';

  @override
  String get servicePurchasePackageUnavailable =>
      'This plan is no longer available. Please try again.';

  @override
  String get servicePurchaseNotActivated =>
      'The purchase didn\'t activate your subscription.';

  @override
  String get servicePurchaseFailed =>
      'The purchase didn\'t go through. Please try again.';

  @override
  String get serviceRestoreNoSubscription =>
      'We couldn\'t find an active subscription to restore.';

  @override
  String get serviceRestoreFailed =>
      'We couldn\'t restore your purchases. Please try again.';

  @override
  String get servicePurchaseNotAllowed =>
      'Purchases aren\'t allowed on this device.';

  @override
  String get servicePurchasePending =>
      'Your payment is processing — your subscription activates once it\'s confirmed.';

  @override
  String get servicePurchaseAlreadyOwned =>
      'You already have this subscription. Try \"Restore purchases\".';

  @override
  String get servicePurchaseNetworkError =>
      'Can\'t reach the store. Check your connection and try again.';

  @override
  String get servicePurchaseStoreProblem =>
      'The store isn\'t responding right now. Please try again later.';

  @override
  String tvChannelLoadError(String details) {
    return 'We couldn\'t load this channel:\n$details';
  }

  @override
  String get tvChannelNoEpisodes => 'This channel has no episodes yet.';

  @override
  String tvEpisodeCountPlural(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count episodes',
      one: '$count episode',
    );
    return '$_temp0';
  }

  @override
  String get tvReaderPreparing => 'Preparing reader…';

  @override
  String get tvReaderNotAiProcessed =>
      'This episode hasn\'t been processed by AI yet.\nReader view isn\'t available.';

  @override
  String tvLoadError(String details) {
    return 'Something went wrong while loading:\n$details';
  }

  @override
  String get tvReaderOpenClassic => 'Open standard view';

  @override
  String tvReaderSectionOf(int current, int total) {
    return 'Section $current / $total';
  }

  @override
  String get tvLive => 'Live';

  @override
  String get tvPaused => 'Paused';

  @override
  String get tvReaderNoCommentary =>
      'No theological commentary for this passage.';

  @override
  String get tvReaderChurchTeaching => 'Church teaching for this passage';

  @override
  String get tvReaderOpenFullCommentary => 'OK — open full commentary';

  @override
  String get tvHintPlayPause => 'play/pause';

  @override
  String get tvHintSections => 'sections';

  @override
  String get tvHintVideo => 'video';

  @override
  String get tvReaderHeadingAssessment => 'Assessment';

  @override
  String get tvReaderHeadingConcerns => 'Points of caution';

  @override
  String get tvReaderHeadingEnrichment => 'Further context';

  @override
  String get tvReaderHeadingCitations => 'Citations from the Magisterium';

  @override
  String get tvReaderCloseHint => 'BACK or OK = close';

  @override
  String get tvRead => 'Read';

  @override
  String get tvFullscreen => 'Fullscreen';

  @override
  String get tvExitFullscreen => 'Exit fullscreen';

  @override
  String get tvLoadingEpisode => 'Loading episode…';

  @override
  String tvEpisodeNotFound(String id) {
    return 'Episode \"$id\" not found.';
  }

  @override
  String get tvBufferStartingEngine => 'Starting the media engine…';

  @override
  String get tvBufferLoadingVideo => 'Loading video…';

  @override
  String get tvBufferFilling => 'Buffering…';

  @override
  String get tvHintRead => 'Read / Fullscreen';

  @override
  String get tvHintExit => 'exit';

  @override
  String tvChaptersWithCount(int count) {
    return 'Chapters ($count)';
  }

  @override
  String get tvSearch => 'Search';

  @override
  String get tvRailContinueListening => 'Continue listening';

  @override
  String get tvRailLatestEpisodes => 'Latest episodes';

  @override
  String tvChannelsWithCount(int count) {
    return 'Channels ($count)';
  }

  @override
  String get tvSortEpisodes => 'Episodes';

  @override
  String get tvSortAlpha => 'A–Z';

  @override
  String get tvSortShuffle => 'Shuffle';

  @override
  String tvLoadingChannels(int loaded, int total) {
    return 'Loading $loaded/$total channels…';
  }

  @override
  String get tvTipsPreparingCatalog => 'Preparing the catalogue…';

  @override
  String get tvPlay => 'Play';

  @override
  String get authSectionLanguage => 'Language';

  @override
  String personEpisodesCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count episodes',
      one: '$count episode',
    );
    return '$_temp0';
  }

  @override
  String get personAppearsOn => 'Appears on';

  @override
  String get personActivityOverTime => 'Activity over time';

  @override
  String get personEpisodesHeading => 'Episodes';

  @override
  String get personNotFoundTitle => 'Person not found';

  @override
  String get personNotFoundBody =>
      'We don\'t have this person yet — neither as a speaker nor as a mention in processed episodes.';

  @override
  String get personShareTooltip => 'Share profile';

  @override
  String get personLinkCopied => 'Profile link copied';

  @override
  String get personMentionedIn => 'Mentioned in';

  @override
  String personMentionsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count mentions',
      one: '$count mention',
    );
    return '$_temp0';
  }

  @override
  String personMentionAtTime(String time) {
    return 'mentioned at $time';
  }

  @override
  String get personMentionWholeEpisode => 'mentioned somewhere in the episode';

  @override
  String get personMentionedOn => 'Mentioned on';

  @override
  String get personMentionOnlyNote =>
      'This person hasn\'t appeared as a guest in processed episodes — this profile tracks where they are talked about.';

  @override
  String appInstallBannerIos(String app) {
    return '$app also has an iPhone app.';
  }

  @override
  String appInstallBannerAndroid(String app) {
    return '$app also has an Android app.';
  }

  @override
  String get appInstallBannerAction => 'Get it';

  @override
  String get pinkaGridIntro =>
      'Every square is one contribution — the closer to the centre, the bigger the support.';

  @override
  String get pinkaGridTapHint => 'Tap a free square to pick your amount.';

  @override
  String get pinkaGridZoneOuterBelt => 'Outer belt';

  @override
  String get pinkaGridZoneDefenseRing => 'Defense ring';

  @override
  String get pinkaGridZoneMidBelt => 'Midfield belt';

  @override
  String get pinkaGridZoneHighZone => 'High ground';

  @override
  String get pinkaGridZoneGoldenCircle => 'Golden circle';

  @override
  String get pinkaGridZoneBusiness => 'Business zone';

  @override
  String get pinkaGridZoneExecutive => 'Executive zone';

  @override
  String get pinkaGridZonePrestige => 'Prestige';

  @override
  String get pinkaGridZoneElite => 'Elite';

  @override
  String get pinkaGridZoneCore => 'Core';

  @override
  String pinkaGridZonePriceLabel(String name, String price) {
    return '$name · $price €';
  }

  @override
  String pinkaGridAmountSet(String name, String price) {
    return '$name — amount set to $price €.';
  }

  @override
  String get pinkaGridTakenTitle => 'This square is already taken';

  @override
  String get pinkaSlotIntro =>
      'Pick your square — the closer to the centre, the bigger the contribution. Your spot is held while you pay.';

  @override
  String pinkaSlotZoneFallback(int index) {
    return 'Zone $index';
  }

  @override
  String get pinkaSlotStatusHeld => 'Held — someone is paying right now';

  @override
  String get pinkaSlotStatusBlocked => 'This spot is not for sale';

  @override
  String get pinkaSlotHeldTitle => 'This square is held';

  @override
  String get pinkaSlotHeldBody =>
      'Someone is paying for it right now. If the payment doesn\'t land, the square goes back up — try later or pick another one.';

  @override
  String pinkaSlotPriceLocked(String price) {
    return 'Price of this spot: $price €';
  }

  @override
  String get pinkaSlotTopUpHint =>
      'You can give more — less than the price of the spot you can\'t.';

  @override
  String get pinkaSlotTopUpLabel => 'Amount';

  @override
  String get pinkaSlotClear => 'Cancel';

  @override
  String pinkaSlotBelowPrice(String price) {
    return 'The amount can\'t be lower than the price of the spot ($price €).';
  }

  @override
  String get pinkaSlotSignInRequired =>
      'Sign in to reserve a spot on the wall. A regular donation works without signing in.';

  @override
  String get pinkaGuestRateLimited =>
      'Too many payments from this network in the last hour. Try again a bit later or sign in.';

  @override
  String get pinkaSlotTakenError =>
      'Someone was faster — that square has just been taken. Pick another one.';

  @override
  String pinkaSlotHoldCountdown(String time) {
    return 'Your spot is held for another $time.';
  }

  @override
  String get pinkaSlotHoldExpired =>
      'The hold expired, but your payment still counts — once it lands you get the same square if it\'s free, otherwise the nearest one in the same or a pricier zone.';

  @override
  String get pinkaSlotHoldReserved => 'Your spot is held.';

  @override
  String get pinkaSlotHoldReassure =>
      'If the transfer stalls at your bank\'s or the recipient\'s checks, don\'t worry — as long as it arrives within 24 hours we\'ll process it.';

  @override
  String get pinkaSlotPickerOpen => 'Zoom in';

  @override
  String get pinkaSlotPickerTitle => 'Pick your spot';

  @override
  String get pinkaSlotPickerHint =>
      'Drag and pinch to zoom; the square under the crosshair is your pick.';

  @override
  String pinkaSlotPickerConfirm(String price) {
    return 'Confirm spot · $price €';
  }

  @override
  String get pinkaSlotPickerTaken => 'This spot is taken';

  @override
  String get pinkaSlotPickerOffGrid => 'Move the crosshair onto the grid';

  @override
  String get authSectionPlayback => 'Playback';

  @override
  String get mediaBackgroundPlaybackTitle => 'Background playback';

  @override
  String get mediaBackgroundPlaybackSubtitle =>
      'Keep listening when you lock the screen or switch to another app.';

  @override
  String get mediaPlaybackSpeed => 'Playback speed';

  @override
  String mediaPlaybackSpeedSet(String rate) {
    return 'Speed: $rate×';
  }

  @override
  String get mediaBackgroundPlaybackTooltipOn => 'Background playback is on';

  @override
  String get mediaBackgroundPlaybackTooltipOff => 'Background playback is off';

  @override
  String get mediaBackgroundPlaybackToastOn =>
      'It will keep playing when you leave the app';

  @override
  String get mediaBackgroundPlaybackToastOff =>
      'Playback will stop when you leave the app';

  @override
  String mediaSeekUndo(String time) {
    return 'Back to $time';
  }

  @override
  String get mediaSeekUndoTooltip => 'Undo the jump';

  @override
  String personCardMeta(int count, String duration) {
    return 'Person · $count ep · $duration';
  }

  @override
  String personVirtualChannelSubtitle(
    int episodes,
    int channels,
    String fromYear,
    String toYear,
  ) {
    String _temp0 = intl.Intl.pluralLogic(
      episodes,
      locale: localeName,
      other: '$episodes episodes',
      one: '$episodes episode',
    );
    String _temp1 = intl.Intl.pluralLogic(
      channels,
      locale: localeName,
      other: '$channels channels',
      one: '$channels channel',
    );
    return 'Guest in $_temp0 across $_temp1, $fromYear–$toYear.';
  }

  @override
  String personVirtualChannelSubtitleOneYear(
    int episodes,
    int channels,
    String year,
  ) {
    String _temp0 = intl.Intl.pluralLogic(
      episodes,
      locale: localeName,
      other: '$episodes episodes',
      one: '$episodes episode',
    );
    String _temp1 = intl.Intl.pluralLogic(
      channels,
      locale: localeName,
      other: '$channels channels',
      one: '$channels channel',
    );
    return 'Guest in $_temp0 across $_temp1, $year.';
  }

  @override
  String get personSectionEpisodes => 'Episodes';

  @override
  String get personSectionCameo => 'Short appearances';

  @override
  String get personSectionCameoHint =>
      'Episodes where they speak only briefly — part of a wider conversation rather than the main guest.';

  @override
  String get personSourceChannelUntracked =>
      'We don\'t cover this channel yet, so it has no page here.';

  @override
  String get personReportError => 'Report an error';

  @override
  String get personReportErrorThanks =>
      'Thanks for the tip — we\'ll check this episode.';

  @override
  String get personOptedOut =>
      'At this person\'s request we no longer show the list of their appearances. The episodes remain available on their own pages.';

  @override
  String get personFollow => 'Follow';

  @override
  String get personFollowing => 'Following';

  @override
  String get channelFollow => 'Follow';

  @override
  String get channelFollowing => 'Following';

  @override
  String get channelsFilterAll => 'All';

  @override
  String get channelsFilterChannels => 'Channels';

  @override
  String get channelsFilterPersons => 'People';

  @override
  String get homePersonsRailTitle => 'People';

  @override
  String get homeFollowedRailTitle => 'New from your follows';

  @override
  String get searchSectionPeople => 'People';

  @override
  String get tvRailPersons => 'People';

  @override
  String get votingTitle => 'Who\'s next';

  @override
  String get votingScreenTitle => 'Who\'s next?';

  @override
  String get votingElectionDayPlain => 'Election day';

  @override
  String votingElectionDay(String date) {
    return 'Election day · $date';
  }

  @override
  String votingRoundLabel(int number) {
    return 'Round $number';
  }

  @override
  String votingRoundDaysLeft(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count days left',
      one: '$count day left',
    );
    return '$_temp0';
  }

  @override
  String get votingRoundLastDay => 'last day of the round';

  @override
  String votingRoundVotes(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count votes this round',
      one: '$count vote this round',
    );
    return '$_temp0';
  }

  @override
  String votingRoundVoters(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count voters',
      one: '$count voter',
    );
    return '$_temp0';
  }

  @override
  String votingStreakDays(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count-day streak',
      one: '$count-day streak',
    );
    return '$_temp0';
  }

  @override
  String get votingStreakNone => 'No streak yet';

  @override
  String get votingFlagsTooltip =>
      'A flag automatically saves a missed election day. You can hold two at most.';

  @override
  String votingFlagsLeft(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count flags',
      one: '$count flag',
    );
    return '$_temp0';
  }

  @override
  String get votingGuestTitle => 'The leaderboard is public, the vote is not.';

  @override
  String get votingGuestBody =>
      'An election day runs from midnight to midnight, Croatian time.';

  @override
  String get votingHaveVote => 'You have 1 vote. Use it before midnight.';

  @override
  String votingLossAversion(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Your streak is $count days — vote today so it doesn\'t break.',
      one: 'Your streak is $count day — vote today so it doesn\'t break.',
    );
    return '$_temp0';
  }

  @override
  String get votingVotedToday => 'Today\'s vote is in.';

  @override
  String get votingComeBackTomorrow =>
      'Come back tomorrow at 00:00 Croatian time.';

  @override
  String get votingYourVoteToday => 'Your vote today';

  @override
  String votingAtRiskTitle(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'A flag is guarding your streak — $count days.',
      one: 'A flag is guarding your streak — $count day.',
    );
    return '$_temp0';
  }

  @override
  String get votingAtRiskBody => 'Vote today and the streak carries on.';

  @override
  String votingAtRiskBurn(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Vote today and $count flags are spent to carry the streak on.',
      one: 'Vote today and $count flag is spent to carry the streak on.',
    );
    return '$_temp0';
  }

  @override
  String votingBrokenTitle(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'The streak stopped at $count days.',
      one: 'The streak stopped at $count day.',
    );
    return '$_temp0';
  }

  @override
  String get votingBrokenTitleUnknown => 'The streak has stopped.';

  @override
  String votingBrokenLongest(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Your longest stays $count days.',
      one: 'Your longest stays $count day.',
    );
    return '$_temp0';
  }

  @override
  String get votingBrokenCta => 'Start over';

  @override
  String get votingVerifyBarTitle => 'Verify with your eID and vote';

  @override
  String get votingVerifyBarBody => 'One person, one vote every 24 hours.';

  @override
  String get votingVerifyCta => 'Verify';

  @override
  String get votingSortLeaderboard => 'Leaderboard';

  @override
  String get votingSortRandom => 'Random';

  @override
  String get votingSortLeastVotes => 'Fewest votes';

  @override
  String get votingSearchHint => 'Search candidates…';

  @override
  String get votingTagAll => 'All topics';

  @override
  String get votingEmpty => 'No candidates match this selection.';

  @override
  String get votingEmptyClear => 'Clear filters';

  @override
  String get votingLoadFailed => 'The leaderboard failed to load.';

  @override
  String get votingVoteUp => 'Vote up';

  @override
  String get votingVoteDown => 'Vote down';

  @override
  String votingNetLabel(int value) {
    return 'Net score $value';
  }

  @override
  String votingVotesCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count votes',
      one: '$count vote',
    );
    return '$_temp0';
  }

  @override
  String votingSubscribers(String value) {
    return '$value subscribers';
  }

  @override
  String get votingSubscribersLabel => 'Subscribers';

  @override
  String get votingEpisodesLabel => 'Episodes (estimate)';

  @override
  String get votingHosts => 'Hosts';

  @override
  String votingCountThousands(String value) {
    return '${value}K';
  }

  @override
  String votingCountMillions(String value) {
    return '${value}M';
  }

  @override
  String get votingStatusWinner => 'Winner';

  @override
  String get votingStatusOnboarding => 'Processing';

  @override
  String get votingStatusOnboarded => 'Already in the app';

  @override
  String get votingStatusWithdrawn => 'Withdrawn';

  @override
  String get votingConsentTitle => 'This is not a secret ballot';

  @override
  String get votingConsentBody =>
      'Your vote is tied to your verified identity in our database. We never publish individual votes — only totals are public. A vote for a channel with a political or religious leaning can indirectly reveal your beliefs, so we tell you before your first vote.';

  @override
  String get votingConsentAccept => 'Understood, vote';

  @override
  String get votingAlreadyVoted => 'Today\'s vote is already used.';

  @override
  String get votingVoteRecorded => 'Vote recorded.';

  @override
  String votingStreakSaved(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count flags saved your streak.',
      one: '$count flag saved your streak.',
    );
    return '$_temp0';
  }

  @override
  String votingStreakBrokeBurned(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Streak broken — $count flags spent.',
      one: 'Streak broken — $count flag spent.',
    );
    return '$_temp0';
  }

  @override
  String get votingErrorNotVerified => 'Voting requires eID verification.';

  @override
  String get votingErrorCandidateGone =>
      'This candidate is no longer in the running.';

  @override
  String get votingErrorRoundClosed => 'The round has closed in the meantime.';

  @override
  String get votingErrorGeneric => 'The vote was not recorded. Try again.';

  @override
  String get votingHomeChipTooltip =>
      'Vote for the podcast that gets processed next';

  @override
  String get votingUnusedVote => 'You have an unused vote.';

  @override
  String votingLongestStreak(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Longest streak $count days',
      one: 'Longest streak $count day',
    );
    return '$_temp0';
  }

  @override
  String votingTotalVotes(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count votes in total',
      one: '$count vote in total',
    );
    return '$_temp0';
  }

  @override
  String get votingChannelsBarTitle => 'Missing your podcast?';

  @override
  String get votingChannelsBarBody =>
      'Vote for the podcast that gets processed next.';

  @override
  String get votingChannelsBarCta => 'Vote';

  @override
  String get votingRailSeeAll => 'All candidates';

  @override
  String votingRailRank(int rank) {
    return 'Rank $rank';
  }

  @override
  String get votingRailCtaTitle => 'Vote for what comes next';

  @override
  String get votingRailCtaBody =>
      'The leaderboard is decided by citizens verified with eID.';

  @override
  String get votingAccountVerifyTitle => 'Vote for the next podcast';

  @override
  String get votingAccountVerifyBody =>
      'Verify with your eID and you get one vote every day.';

  @override
  String get ebookTooltip => 'Episode ebook';

  @override
  String get ebookSheetTitle => 'Ebook';

  @override
  String get ebookEditionHr => 'Croatian edition';

  @override
  String get ebookEditionEn => 'English edition';

  @override
  String get ebookShareHint => 'Shared as a file — WhatsApp, email, Books.';

  @override
  String get ebookDownloadHint => 'Downloads to your device.';

  @override
  String get ebookPreparing => 'Preparing the book…';

  @override
  String ebookDownloaded(String file) {
    return 'Downloaded: $file';
  }

  @override
  String get ebookFailed => 'The book could not be fetched. Please try again.';

  @override
  String get ebookCopyLink => 'Copy link to the book';

  @override
  String get ebookLinkCopied => 'Link to the book copied';

  @override
  String get ebookRights =>
      'This edition is derived from the episode; rights to the spoken content remain with the original channel.';

  @override
  String get ebookCardTitle => 'Take the episode with you';

  @override
  String get ebookCardBody =>
      'The whole episode as an ebook: chapters, images and links back to the recording. Reads in Books, Play Books or Kindle.';

  @override
  String get ebookCardAction => 'Ebook (EPUB)';

  @override
  String get sponsorsInVideoTitle => 'With support from';

  @override
  String get sponsorsInVideoIntro =>
      'Partners who made this episode possible. Thank you for supporting creators.';

  @override
  String get sponsorsInVideoRoleSponsor => 'Episode sponsor';

  @override
  String get sponsorsInVideoRolePartner => 'Podcast partner';

  @override
  String get sponsorsInVideoRoleWardrobe => 'Wardrobe';

  @override
  String get sponsorsInVideoRoleStudio => 'Studio equipment';

  @override
  String get sponsorsInVideoRoleOther => 'Support';

  @override
  String get sponsorsInVideoListen => 'Listen to the sponsor message';

  @override
  String get sponsorsInVideoListenRubric => 'Listen to the sponsored segment';

  @override
  String sponsorsInVideoThanksAt(String time) {
    return 'Thanks at $time';
  }

  @override
  String sponsorsInVideoChapterAt(String time) {
    return 'Chapter at $time';
  }

  @override
  String sponsorsInVideoAt(String time) {
    return 'At $time';
  }

  @override
  String get sponsorsInVideoWebsite => 'Website';

  @override
  String get sponsorsInVideoMore => 'more';

  @override
  String get sponsorsInVideoLess => 'less';

  @override
  String get sponsorsInVideoEnded => 'The sponsor message has ended';

  @override
  String get sponsorsInVideoListenShort => 'Listen';

  @override
  String get sponsorsInVideoRubricShort => 'Segment';

  @override
  String sponsorsInVideoMessageAt(String time) {
    return 'Sponsor message at $time';
  }

  @override
  String sponsorsInVideoRubricAt(String time) {
    return 'Sponsored segment at $time';
  }

  @override
  String get ytWatchTitle => 'YouTube video';

  @override
  String get ytWatchOpenEpisode => 'Open processed episode';

  @override
  String get ytWatchInvalidId => 'Invalid YouTube link.';

  @override
  String get ytWatchEmbedUnsupported =>
      'This browser cannot show the YouTube player inside the page, so the video opens on YouTube.';

  @override
  String get findInEpisodeTitle => 'Find in episode';

  @override
  String get findInEpisodeHint => 'Word, name or phrase';

  @override
  String get findInEpisodeClear => 'Clear';

  @override
  String get findInEpisodeNoHits => 'No matches in this episode.';

  @override
  String get findInEpisodeError =>
      'Search is not working right now. Try again a little later.';

  @override
  String findInEpisodeCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count moments',
      one: '$count moment',
    );
    return '$_temp0';
  }

  @override
  String findInEpisodeCountPartial(int shown, int total) {
    return 'Showing $shown of $total moments';
  }

  @override
  String get findInEpisodeApproximate => 'Approximate matches';

  @override
  String get sponsoredLabel => 'Sponsored';

  @override
  String sponsoredBy(String brand) {
    return 'Sponsored · $brand';
  }

  @override
  String sponsoredPaidBy(String brand) {
    return 'Paid for by $brand';
  }

  @override
  String get sponsoredWebsite => 'Website';

  @override
  String sponsoredAt(String time) {
    return 'Sponsored moment at $time';
  }

  @override
  String get sponsoredListen => 'Listen';

  @override
  String get sponsoredNow => 'Playing now';

  @override
  String get sponsorStoreEntry => 'Advertise';

  @override
  String sponsorStoreTitle(String channel) {
    return 'Advertise on $channel';
  }

  @override
  String get sponsorStoreIntro =>
      'Pick a moment in an episode and your brand is shown as the sponsor of exactly that part. You pay once by SEPA transfer, and the ad goes live as soon as the payment arrives.';

  @override
  String get sponsorStoreEmpty =>
      'This channel has no sponsor moments on offer right now.';

  @override
  String get sponsorStoreLoadFailed => 'The offer could not be loaded.';

  @override
  String sponsorStoreFreeCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count moments available',
      one: '$count moment available',
    );
    return '$_temp0';
  }

  @override
  String sponsorStoreFromPrice(String price) {
    return 'from €$price';
  }

  @override
  String get sponsorStoreAvoidTitle => 'Don\'t show me next to…';

  @override
  String get sponsorStoreAvoidHint =>
      'Brand safety is your call. Topic labels are a rough estimate, so every episode also lists its actual topics.';

  @override
  String get sponsorStoreAllFiltered =>
      'No episode matches the selected filter.';

  @override
  String get sponsorTopicFaith => 'Faith';

  @override
  String get sponsorTopicPolitics => 'Politics';

  @override
  String get sponsorTopicBusiness => 'Business and tech';

  @override
  String get sponsorMapTitle => 'Sponsor moments';

  @override
  String get sponsorMapIntro =>
      'Each moment is a part of the episode, shown with the article section that starts in it. Listen before you buy.';

  @override
  String get sponsorMapTopics => 'Episode topics';

  @override
  String get sponsorStateFree => 'Available';

  @override
  String get sponsorStateHeld => 'Being purchased';

  @override
  String get sponsorStateSold => 'Taken';

  @override
  String sponsorStateSoldUntil(String date) {
    return 'Taken until $date';
  }

  @override
  String get sponsorStateBlocked => 'Not on offer';

  @override
  String get sponsorZoneZatvaranje => 'Closing';

  @override
  String get sponsorZoneTijelo => 'Main part';

  @override
  String get sponsorZoneOtvaranje => 'Opening';

  @override
  String sponsorPriceGross(String price) {
    return '€$price incl. VAT';
  }

  @override
  String sponsorRunDays(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'live for $count days after payment',
      one: 'live for $count day after payment',
    );
    return '$_temp0';
  }

  @override
  String get sponsorPick => 'Choose';

  @override
  String get sponsorLegend => 'The bar shows the whole episode.';

  @override
  String get sponsorCheckoutTitle => 'Order';

  @override
  String sponsorCheckoutMoment(String range, String zone) {
    return 'Moment $range · $zone';
  }

  @override
  String get sponsorCheckoutChange => 'Change moment';

  @override
  String get sponsorCreativeSection => 'Your ad';

  @override
  String get sponsorFieldBrand => 'Brand name';

  @override
  String get sponsorFieldBrandHelp =>
      'Shown next to the “Sponsored” label and cannot be anonymous.';

  @override
  String get sponsorFieldTagline => 'One sentence (optional)';

  @override
  String get sponsorFieldLink => 'Link, https:// (optional)';

  @override
  String get sponsorFieldLogo =>
      'Logo: PNG, JPG or WebP, up to 200 kB (optional)';

  @override
  String get sponsorLogoPick => 'Add logo';

  @override
  String get sponsorLogoRemove => 'Remove logo';

  @override
  String get sponsorLogoTooBig => 'The logo is larger than 200 kB.';

  @override
  String get sponsorLogoBadType => 'The logo must be PNG, JPG or WebP.';

  @override
  String get sponsorLogoUploadFailed =>
      'The logo was not uploaded. Try again or continue without it.';

  @override
  String get sponsorCompanySection => 'Invoice details';

  @override
  String get sponsorFieldCompany => 'Company name';

  @override
  String get sponsorFieldOib => 'Croatian OIB (optional)';

  @override
  String get sponsorFieldVat => 'VAT ID (optional)';

  @override
  String get sponsorFieldStreet => 'Street address';

  @override
  String get sponsorFieldCity => 'City';

  @override
  String get sponsorFieldPostal => 'Postal code';

  @override
  String get sponsorFieldCountry => 'Country (HR, SI, DE…)';

  @override
  String get sponsorFieldEmail => 'Invoice email address';

  @override
  String get sponsorFieldReference => 'Purchase order number (optional)';

  @override
  String get sponsorPreviewTitle => 'This is how your ad will look';

  @override
  String get sponsorTermsAccept => 'I accept the advertising terms';

  @override
  String get sponsorTermsRead => 'Read the terms';

  @override
  String get sponsorTermsTitle => 'Advertising terms';

  @override
  String get sponsorTermsBody =>
      'The ad is published automatically as soon as the payment arrives, without prior approval, and runs for the number of days shown with the moment.\n\nThe ad is labelled “Sponsored” together with your brand name, in line with Article 26 of Regulation (EU) 2022/2065.\n\nContent that is unlawful, misleading, offensive or discriminatory is not allowed, nor is advertising for tobacco products, weapons, gambling or prescription medicines.\n\nThe channel owner may withdraw an ad that breaches these terms. In that case, and when a payment arrives after the moment has been sold to someone else, we refund the amount manually.\n\nThe price includes VAT. The invoice is issued automatically and sent to the email address given in the order.';

  @override
  String get sponsorErrorRequired => 'Required';

  @override
  String get sponsorErrorOib => 'This OIB is not valid';

  @override
  String get sponsorErrorVat => 'This VAT ID is not valid (e.g. HR12345678903)';

  @override
  String get sponsorErrorEmail => 'This email address is not valid';

  @override
  String get sponsorErrorLink => 'The link must start with https://';

  @override
  String sponsorErrorTooLong(int max) {
    return 'At most $max characters';
  }

  @override
  String get sponsorErrorCountry => 'Two-letter country code, e.g. HR';

  @override
  String get sponsorErrorTerms => 'You need to accept the terms to order.';

  @override
  String get sponsorSubmit => 'Continue to payment';

  @override
  String get sponsorSlotTaken =>
      'Someone just took that moment. The map has been refreshed, please pick another one.';

  @override
  String get sponsorTooManyHolds =>
      'You already have three unpaid orders. Pay one or wait for it to expire.';

  @override
  String get sponsorSignInRequired =>
      'Sign in to order a sponsored moment. What you entered stays in the form.';

  @override
  String get sponsorSignInHeadline => 'Sign in to order';

  @override
  String get sponsorSignInSubtitle =>
      'The order, invoice and payment status are tied to your account.';

  @override
  String get sponsorCheckoutFailed =>
      'The order could not be created. Please try again.';

  @override
  String sponsorCheckoutFieldRejected(String field) {
    return 'Check the “$field” field.';
  }

  @override
  String get sponsorPayTitle => 'Payment';

  @override
  String get sponsorMemoVerbatim =>
      'Copy the payment reference exactly, without any changes. We match the payment to the order by it. If your accounts team shortens or retypes it, the payment will not be matched automatically.';

  @override
  String sponsorHoldUntil(String time) {
    return 'The moment is reserved for you until $time.';
  }

  @override
  String get sponsorHoldExpired =>
      'The reservation has expired. If the payment still arrives and the moment is free, we assign it automatically.';

  @override
  String get sponsorWaitingPayment =>
      'Waiting for the payment. This page updates itself when it arrives.';

  @override
  String get sponsorOrderLinkHint =>
      'Save this link. It always shows the state of your order.';

  @override
  String get sponsorPaidTitle => 'Payment received, your ad is live';

  @override
  String sponsorPaidUntil(String date) {
    return 'The moment is yours until $date';
  }

  @override
  String get sponsorUnderpaid =>
      'The payment is lower than the price of the moment, so it was not assigned. We will contact you about a refund or the difference.';

  @override
  String get sponsorSlotUnassigned =>
      'The payment arrived after the reservation expired and the moment has since been sold. We will refund the amount manually.';

  @override
  String get sponsorHidden =>
      'The channel owner has withdrawn the ad. We will refund the amount manually.';

  @override
  String get sponsorOrderExpired => 'The order expired without a payment.';

  @override
  String get sponsorOrderFailed => 'The payment did not go through.';

  @override
  String sponsorInvoiceSent(String number) {
    return 'Invoice $number has been sent to the email address in the order.';
  }

  @override
  String get sponsorInvoicePending =>
      'The invoice will arrive by email once processed.';

  @override
  String get sponsorStatsPending =>
      'View and click counts will appear here once measurement is switched on.';

  @override
  String get sponsorViewOnEpisode => 'See it on the episode';

  @override
  String get sponsorOrderNotFound => 'Order not found.';

  @override
  String sponsorLeaseEnded(String date) {
    return 'The moment was live until $date';
  }

  @override
  String get sponsorLeavePayTitle => 'Leave the payment?';

  @override
  String get sponsorLeavePayBody =>
      'The moment stays reserved until it expires, but you will no longer see the QR code and payment reference. The order status stays at the link in the address bar.';

  @override
  String get sponsorLeavePayConfirm => 'Leave';

  @override
  String get notificationsTitle => 'Notifications';

  @override
  String get notificationsIntro =>
      'We\'ll let you know when a new episode arrives. You choose what about.';

  @override
  String get notificationsEnable => 'Turn on notifications';

  @override
  String get notificationsEnabledStatus => 'Notifications are on';

  @override
  String get notificationsDeniedTitle =>
      'Notifications are turned off in your device settings';

  @override
  String get notificationsDeniedBody =>
      'Turn them on in settings and we\'ll let you know about new episodes.';

  @override
  String get notificationsOpenSettings => 'Open settings';

  @override
  String get notificationsAllTitle => 'All new episodes';

  @override
  String get notificationsAllSubtitle => 'About one to four a day';

  @override
  String get notificationsChannelsSection => 'Channels';

  @override
  String get notificationsCoveredByAll => 'Included in All new episodes';

  @override
  String get notificationsSearchHint => 'Search channels';

  @override
  String get notificationsQuietHours =>
      'We don\'t send notifications between 10 pm and 7 am.';

  @override
  String get notificationsChannelsError =>
      'The channel list is not available right now.';

  @override
  String get notificationsAppOnly =>
      'Notifications are available in the iOS and Android app.';

  @override
  String get notificationsAccountOn => 'On';

  @override
  String get notificationsAccountOff => 'Off';

  @override
  String get notificationsBellOn => 'Turn off notifications for this channel';

  @override
  String get notificationsBellOff =>
      'Notify me about new episodes from this channel';

  @override
  String get notificationsFollowingLabel => 'Following';

  @override
  String get episodeVariant => 'Variant';

  @override
  String episodeVariantNumbered(int n) {
    return 'Variant $n';
  }
}
