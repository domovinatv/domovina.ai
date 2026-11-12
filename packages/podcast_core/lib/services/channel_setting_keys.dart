/// Imena ključeva postavki kanala kao konstante za pozivna mjesta provedbe
/// (S5). Ugovor je [kChannelSettingDefs] u `models/channel_settings.dart`;
/// `test/channel_visibility_service_test.dart` provjerava da je svako ime
/// ovdje i tamo.
library;

abstract final class ChannelKey {
  static const channelEnabled = 'channel_enabled';
  static const homeFeatured = 'home_featured';
  static const inAppSearch = 'in_app_search';
  static const pushNotifications = 'push_notifications';
  static const magisterium = 'magisterium';
  static const personsMentions = 'persons_mentions';
  static const donations = 'donations';
  static const paidSponsorMoments = 'paid_sponsor_moments';

  static const all = [
    channelEnabled,
    homeFeatured,
    inAppSearch,
    pushNotifications,
    magisterium,
    personsMentions,
    donations,
    paidSponsorMoments,
  ];
}
