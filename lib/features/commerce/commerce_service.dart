import 'package:cloud_functions/cloud_functions.dart';

FirebaseFunctions get _fn =>
    FirebaseFunctions.instanceFor(region: 'europe-west1');

Map<String, dynamic> _map(dynamic data) =>
    Map<String, dynamic>.from(data as Map? ?? {});

class CommerceService {
  static Future<Map<String, dynamic>> getOrganizerDashboard() async {
    final res = await _fn.httpsCallable('getOrganizerDashboard').call();
    return _map(res.data);
  }

  static Future<void> savePayoutIban({
    required String iban,
    required String holder,
    String bank = '',
  }) async {
    await _fn.httpsCallable('saveOrganizerPayoutIban').call({
      'payoutIban': iban,
      'payoutIbanHolder': holder,
      'payoutBank': bank,
    });
  }

  static Future<void> requestWithdrawal(double amount) async {
    await _fn.httpsCallable('requestWithdrawal').call({'amount': amount});
  }

  static Future<void> adminReviewWithdrawal({
    required String id,
    required bool approve,
  }) async {
    await _fn.httpsCallable('adminReviewWithdrawal').call({
      'id': id,
      'approve': approve,
    });
  }

  static Future<void> adminSetOrganizerCommerce({
    required String companyId,
    double? commissionPercent,
    double? minWithdrawal,
    bool? isEventOrganizer,
  }) async {
    await _fn.httpsCallable('adminSetOrganizerCommerce').call({
      'companyId': companyId,
      if (commissionPercent != null) 'commissionPercent': commissionPercent,
      if (minWithdrawal != null) 'minWithdrawal': minWithdrawal,
      if (isEventOrganizer != null) 'isEventOrganizer': isEventOrganizer,
    });
  }

  static Future<void> createDiscount({
    required String eventId,
    required String code,
    required String type,
    required double value,
    int maxUses = 0,
  }) async {
    await _fn.httpsCallable('createEventDiscount').call({
      'eventId': eventId,
      'code': code,
      'type': type,
      'value': value,
      'maxUses': maxUses,
    });
  }

  static Future<void> submitAd(Map<String, dynamic> payload) async {
    await _fn.httpsCallable('submitAdCampaign').call(payload);
  }

  static Future<List<Map<String, dynamic>>> getMyAds() async {
    final res = await _fn.httpsCallable('getMyAdCampaigns').call();
    final data = _map(res.data);
    return (data['ads'] as List? ?? const [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
  }

  static Future<Map<String, dynamic>> acceptAdQuote(String adId) async {
    final res = await _fn.httpsCallable('acceptAdQuote').call({'adId': adId});
    return _map(res.data);
  }

  static Future<void> declineAdQuote(String adId, {String reason = ''}) async {
    await _fn.httpsCallable('declineAdQuote').call({
      'adId': adId,
      'reason': reason,
    });
  }

  static Future<void> updateAd(
    String adId,
    Map<String, dynamic> edits,
  ) async {
    await _fn.httpsCallable('updateAdCampaign').call({
      'adId': adId,
      ...edits,
    });
  }

  static Future<void> deleteAd(String adId) async {
    await _fn.httpsCallable('deleteAdCampaign').call({'adId': adId});
  }

  static Future<void> adminDeleteAd(String adId) async {
    await _fn.httpsCallable('adminDeleteAdCampaign').call({'adId': adId});
  }

  static Future<void> trackAd({
    required String adId,
    required String event,
    required String placement,
    String? city,
    String? university,
  }) async {
    await _fn.httpsCallable('trackAdEvent').call({
      'adId': adId,
      'event': event,
      'placement': placement,
      if (city != null) 'city': city,
      if (university != null) 'university': university,
    });
  }

  static Future<Map<String, dynamic>> quoteAd({
    required String adId,
    required double quotedAmount,
    String quoteNote = '',
  }) async {
    final res = await _fn.httpsCallable('quoteAdCampaign').call({
      'adId': adId,
      'quotedAmount': quotedAmount,
      'quoteNote': quoteNote,
    });
    return _map(res.data);
  }

  static Future<void> adminReviewAd({
    required String id,
    required String status,
    Map<String, dynamic>? edits,
    String adminNote = '',
  }) async {
    await _fn.httpsCallable('adminReviewAdCampaign').call({
      'id': id,
      'status': status,
      'adminNote': adminNote,
      ...?edits,
    });
  }

  static Future<void> dispatchAdReach({
    required String adId,
    bool force = false,
  }) async {
    await _fn.httpsCallable('dispatchAdCampaignReach').call({
      'adId': adId,
      'force': force,
    });
  }

  static Future<List<Map<String, dynamic>>> getActiveAds({
    String? placement,
    String? city,
    String? university,
  }) async {
    final res = await _fn.httpsCallable('getActiveAds').call({
      if (placement != null) 'placement': placement,
      if (city != null) 'city': city,
      if (university != null) 'university': university,
    });
    final data = _map(res.data);
    final list = data['ads'] as List? ?? const [];
    return list
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
  }

  static Future<List<Map<String, dynamic>>> getMyTickets() async {
    final res = await _fn.httpsCallable('getMyTickets').call();
    final data = _map(res.data);
    final list = data['tickets'] as List? ?? const [];
    return list
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
  }
}
