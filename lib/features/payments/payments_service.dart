import 'package:cloud_functions/cloud_functions.dart';

FirebaseFunctions get _fn =>
    FirebaseFunctions.instanceFor(region: 'europe-west1');

Map<String, dynamic> _map(dynamic data) =>
    Map<String, dynamic>.from(data as Map? ?? {});

class PaymentsAdminConfig {
  PaymentsAdminConfig({
    required this.raw,
  });

  final Map<String, dynamic> raw;

  String get activeProvider => '${raw['activeProvider'] ?? 'iban'}';
  List<String> get enabledProviders =>
      (raw['enabledProviders'] as List? ?? const ['iban', 'paytr', 'shopier'])
          .map((e) => '$e')
          .toList();

  String get iban => '${raw['iban'] ?? ''}';
  String get ibanHolder => '${raw['ibanHolder'] ?? ''}';
  String get ibanBank => '${raw['ibanBank'] ?? ''}';
  String get ibanNote => '${raw['ibanNote'] ?? ''}';
  String get paytrMerchantId => '${raw['paytrMerchantId'] ?? ''}';
  bool get paytrTestMode => raw['paytrTestMode'] != false;
  bool get paytrKeySet => raw['paytrKeySet'] == true;
  bool get paytrSaltSet => raw['paytrSaltSet'] == true;
  String get shopierApiKeyMasked => '${raw['shopierApiKey'] ?? ''}';
  bool get shopierKeySet => raw['shopierKeySet'] == true;
  bool get shopierSecretSet => raw['shopierSecretSet'] == true;
  int get shopierWebsiteIndex =>
      (raw['shopierWebsiteIndex'] as num?)?.toInt() ?? 1;
  String get plusProductName => '${raw['plusProductName'] ?? 'KampüsteyimPlus'}';
  double get plusAmount => (raw['plusAmount'] as num?)?.toDouble() ?? 0;
  int get plusDays => (raw['plusDays'] as num?)?.toInt() ?? 30;
  String get currency => '${raw['currency'] ?? 'TL'}';
  String get okUrl => '${raw['okUrl'] ?? ''}';
  String get failUrl => '${raw['failUrl'] ?? ''}';
  String get paytrCallbackUrl => '${raw['paytrCallbackUrl'] ?? ''}';
  String get shopierCallbackUrl => '${raw['shopierCallbackUrl'] ?? ''}';
  String get shopierPayPageUrl => '${raw['shopierPayPageUrl'] ?? ''}';

  Map<String, dynamic> get defaults =>
      Map<String, dynamic>.from(raw['defaults'] as Map? ?? {});
}

class PaymentsPublicConfig {
  PaymentsPublicConfig(this.raw);
  final Map<String, dynamic> raw;

  String get activeProvider => '${raw['activeProvider'] ?? 'iban'}';
  List<String> get enabledProviders =>
      (raw['enabledProviders'] as List? ?? const [])
          .map((e) => '$e')
          .toList();
  String get iban => '${raw['iban'] ?? ''}';
  String get ibanHolder => '${raw['ibanHolder'] ?? ''}';
  String get ibanBank => '${raw['ibanBank'] ?? ''}';
  String get ibanNote => '${raw['ibanNote'] ?? ''}';
  String get plusProductName => '${raw['plusProductName'] ?? 'KampüsteyimPlus'}';
  double get plusAmount => (raw['plusAmount'] as num?)?.toDouble() ?? 0;
  int get plusDays => (raw['plusDays'] as num?)?.toInt() ?? 30;
  String get currency => '${raw['currency'] ?? 'TL'}';
  String get marketUrl =>
      '${raw['marketUrl'] ?? 'https://app.kampusteyim.app/market'}';
  List<Map<String, dynamic>> get plusPlans {
    final rawPlans = raw['plusPlans'];
    if (rawPlans is! List) return const [];
    return rawPlans
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }
  bool get paytrReady => raw['paytrReady'] == true;
  bool get shopierReady => raw['shopierReady'] == true;
  bool get ibanReady => raw['ibanReady'] == true;
}

class PaymentOrderResult {
  PaymentOrderResult(this.raw);
  final Map<String, dynamic> raw;

  String get provider => '${raw['provider'] ?? ''}';
  String get orderId => '${raw['orderId'] ?? ''}';
  double get amount => (raw['amount'] as num?)?.toDouble() ?? 0;
  String? get iframeUrl => raw['iframeUrl']?.toString();
  String? get payUrl => raw['payUrl']?.toString();
  String? get iban => raw['iban']?.toString();
  String? get ibanHolder => raw['ibanHolder']?.toString();
  String? get ibanBank => raw['ibanBank']?.toString();
  String? get transferDescription => raw['transferDescription']?.toString();
  String? get note => raw['note']?.toString();
}

class PaymentsService {
  static Future<PaymentsAdminConfig> getAdmin() async {
    final res = await _fn.httpsCallable('getPaymentsAdmin').call();
    final data = _map(res.data);
    return PaymentsAdminConfig(raw: _map(data['config']));
  }

  static Future<PaymentsAdminConfig> updateAdmin(
    Map<String, dynamic> payload,
  ) async {
    final res =
        await _fn.httpsCallable('updatePaymentsConfig').call(payload);
    final data = _map(res.data);
    return PaymentsAdminConfig(raw: _map(data['config']));
  }

  static Future<PaymentsPublicConfig> getPublic() async {
    final res = await _fn.httpsCallable('getPaymentsPublic').call();
    return PaymentsPublicConfig(_map(res.data));
  }

  static Future<PaymentOrderResult> createOrder({
    String product = 'plus',
    String? provider,
    double? amount,
    int? months,
    String? eventId,
    String? tierLabel,
    String? discountCode,
    String source = 'app',
  }) async {
    final res = await _fn.httpsCallable('createPaymentOrder').call({
      'product': product,
      if (provider != null) 'provider': provider,
      if (amount != null) 'amount': amount,
      if (months != null) 'months': months,
      if (eventId != null) 'eventId': eventId,
      if (tierLabel != null) 'tierLabel': tierLabel,
      if (discountCode != null) 'discountCode': discountCode,
      'source': source,
    });
    return PaymentOrderResult(_map(res.data));
  }

  static Future<String> confirmIban(String orderId) async {
    final res = await _fn.httpsCallable('confirmIbanTransfer').call({
      'orderId': orderId,
    });
    final data = _map(res.data);
    return '${data['message'] ?? 'Bildirim alındı'}';
  }

  static Future<void> reviewOrder({
    required String orderId,
    required bool approve,
  }) async {
    await _fn.httpsCallable('adminReviewPaymentOrder').call({
      'orderId': orderId,
      'approve': approve,
    });
  }
}
