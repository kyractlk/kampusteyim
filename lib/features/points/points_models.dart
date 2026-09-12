import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';

FirebaseFunctions get pointsFunctions =>
    FirebaseFunctions.instanceFor(region: 'europe-west1');

class PointsEarnRates {
  const PointsEarnRates({
    this.post = 5,
    this.reel = 8,
    this.story = 3,
    this.likeReceived = 2,
    this.commentReceived = 3,
    this.repostReceived = 4,
  });

  final int post;
  final int reel;
  final int story;
  final int likeReceived;
  final int commentReceived;
  final int repostReceived;

  factory PointsEarnRates.fromMap(Map<String, dynamic>? m) {
    final d = m ?? const {};
    int n(dynamic v, int f) => (num.tryParse('$v') ?? f).round();
    return PointsEarnRates(
      post: n(d['post'], 5),
      reel: n(d['reel'], 8),
      story: n(d['story'], 3),
      likeReceived: n(d['likeReceived'], 2),
      commentReceived: n(d['commentReceived'], 3),
      repostReceived: n(d['repostReceived'], 4),
    );
  }

  Map<String, dynamic> toMap() => {
        'post': post,
        'reel': reel,
        'story': story,
        'likeReceived': likeReceived,
        'commentReceived': commentReceived,
        'repostReceived': repostReceived,
      };
}

class SilSupurSegment {
  const SilSupurSegment({
    required this.id,
    required this.label,
    required this.weight,
    required this.type,
    this.points,
    this.title,
    this.packageCode,
    this.slug,
  });

  final String id;
  final String label;
  /// Çıkma yüzdesi (0–100). Örn. 0.005 gibi küçük ondalıklar desteklenir.
  final double weight;
  final String type; // none | points | esim | gift
  final int? points;
  final String? title;
  final String? packageCode;
  final String? slug;

  factory SilSupurSegment.fromMap(Map<String, dynamic> m) => SilSupurSegment(
        id: '${m['id'] ?? ''}',
        label: '${m['label'] ?? ''}',
        weight: parseSilPercent(m['weight'] ?? m['percent']),
        type: '${m['type'] ?? 'none'}',
        points: m['points'] == null
            ? null
            : (num.tryParse('${m['points']}') ?? 0).round(),
        title: m['title']?.toString(),
        packageCode: m['packageCode']?.toString(),
        slug: m['slug']?.toString(),
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'label': label,
        'weight': weight,
        'percent': weight,
        'type': type,
        if (points != null) 'points': points,
        if (title != null) 'title': title,
        if (packageCode != null) 'packageCode': packageCode,
        if (slug != null) 'slug': slug,
      };
}

class SilSupurConfig {
  const SilSupurConfig({
    this.enabled = true,
    this.weekday = 3,
    this.hour = 12,
    this.minute = 0,
    this.freeSpinsPerWeek = 1,
    this.segments = const [],
    this.notifyTitle = 'Sil Süpür başladı!',
    this.notifyBody = 'Bu haftanın hediyeleri seni bekliyor. Hemen çevir!',
  });

  final bool enabled;
  final int weekday;
  final int hour;
  final int minute;
  final int freeSpinsPerWeek;
  final List<SilSupurSegment> segments;
  final String notifyTitle;
  final String notifyBody;

  static const weekdayLabels = [
    'Pazar',
    'Pazartesi',
    'Salı',
    'Çarşamba',
    'Perşembe',
    'Cuma',
    'Cumartesi',
  ];

  factory SilSupurConfig.fromMap(Map<String, dynamic>? m) {
    final d = m ?? const {};
    final segs = (d['segments'] as List? ?? [])
        .whereType<Map>()
        .map((e) => SilSupurSegment.fromMap(Map<String, dynamic>.from(e)))
        .toList();
    return SilSupurConfig(
      enabled: d['enabled'] != false,
      weekday: (num.tryParse('${d['weekday']}') ?? 3).round(),
      hour: (num.tryParse('${d['hour']}') ?? 12).round(),
      minute: (num.tryParse('${d['minute']}') ?? 0).round(),
      freeSpinsPerWeek: (num.tryParse('${d['freeSpinsPerWeek']}') ?? 1).round(),
      segments: segs,
      notifyTitle: '${d['notifyTitle'] ?? 'Sil Süpür başladı!'}',
      notifyBody:
          '${d['notifyBody'] ?? 'Bu haftanın hediyeleri seni bekliyor. Hemen çevir!'}',
    );
  }

  Map<String, dynamic> toMap() => {
        'enabled': enabled,
        'weekday': weekday,
        'hour': hour,
        'minute': minute,
        'freeSpinsPerWeek': freeSpinsPerWeek,
        'notifyTitle': notifyTitle,
        'notifyBody': notifyBody,
        'segments': segments.map((s) => s.toMap()).toList(),
      };
}

class PointsConfig {
  const PointsConfig({
    this.enabled = true,
    this.tlPerPoint = 0.1,
    this.usdTryRate = 42,
    this.usdTrySource = 'manual',
    this.usdTryUpdatedAt,
    this.usdTryAuto = true,
    this.defaultMarginPercent = 35,
    this.earn = const PointsEarnRates(),
    this.silSupur = const SilSupurConfig(),
  });

  final bool enabled;
  /// 1 KP kaç ₺ (Kampüsteyim Puan).
  final double tlPerPoint;
  final double usdTryRate;
  final String usdTrySource;
  final String? usdTryUpdatedAt;
  final bool usdTryAuto;
  final double defaultMarginPercent;
  final PointsEarnRates earn;
  final SilSupurConfig silSupur;

  factory PointsConfig.fromMap(Map<String, dynamic>? m) {
    final d = m ?? const {};
    return PointsConfig(
      enabled: d['enabled'] != false,
      tlPerPoint: (num.tryParse('${d['tlPerPoint']}') ?? 0.1).toDouble(),
      usdTryRate: (num.tryParse('${d['usdTryRate']}') ?? 42).toDouble(),
      usdTrySource: '${d['usdTrySource'] ?? 'manual'}',
      usdTryUpdatedAt: d['usdTryUpdatedAt']?.toString(),
      usdTryAuto: d['usdTryAuto'] != false,
      defaultMarginPercent:
          (num.tryParse('${d['defaultMarginPercent']}') ?? 35).toDouble(),
      earn: PointsEarnRates.fromMap(
        d['earn'] is Map ? Map<String, dynamic>.from(d['earn'] as Map) : null,
      ),
      silSupur: SilSupurConfig.fromMap(
        d['silSupur'] is Map
            ? Map<String, dynamic>.from(d['silSupur'] as Map)
            : null,
      ),
    );
  }

  Map<String, dynamic> toMap() => {
        'enabled': enabled,
        'tlPerPoint': tlPerPoint,
        'usdTryRate': usdTryRate,
        'usdTrySource': usdTrySource,
        'usdTryUpdatedAt': usdTryUpdatedAt,
        'usdTryAuto': usdTryAuto,
        'defaultMarginPercent': defaultMarginPercent,
        'earn': earn.toMap(),
        'silSupur': silSupur.toMap(),
      };

  PointsConfig copyWith({
    bool? enabled,
    double? tlPerPoint,
    double? usdTryRate,
    String? usdTrySource,
    String? usdTryUpdatedAt,
    bool? usdTryAuto,
    double? defaultMarginPercent,
    PointsEarnRates? earn,
    SilSupurConfig? silSupur,
  }) =>
      PointsConfig(
        enabled: enabled ?? this.enabled,
        tlPerPoint: tlPerPoint ?? this.tlPerPoint,
        usdTryRate: usdTryRate ?? this.usdTryRate,
        usdTrySource: usdTrySource ?? this.usdTrySource,
        usdTryUpdatedAt: usdTryUpdatedAt ?? this.usdTryUpdatedAt,
        usdTryAuto: usdTryAuto ?? this.usdTryAuto,
        defaultMarginPercent: defaultMarginPercent ?? this.defaultMarginPercent,
        earn: earn ?? this.earn,
        silSupur: silSupur ?? this.silSupur,
      );

  String tlLabel(int kp) {
    final tl = kp * tlPerPoint;
    return '≈ ${tl.toStringAsFixed(tl >= 10 ? 0 : 2)} ₺';
  }

  /// Tedarikçi USD maliyeti + kar marjı → KP.
  int kpFromUsd(double costUsd, {double? marginPercent}) {
    final m = ((marginPercent ?? defaultMarginPercent) / 100).clamp(0, 20);
    final saleTry = costUsd * usdTryRate * (1 + m);
    if (tlPerPoint <= 0) return saleTry.round().clamp(1, 999999999);
    return (saleTry / tlPerPoint).ceil().clamp(1, 999999999);
  }

  double saleTryFromUsd(double costUsd, {double? marginPercent}) {
    final m = ((marginPercent ?? defaultMarginPercent) / 100).clamp(0, 20);
    return costUsd * usdTryRate * (1 + m);
  }
}

class PointsCatalogItem {
  const PointsCatalogItem({
    required this.id,
    required this.type,
    required this.title,
    this.description = '',
    this.imageUrl,
    this.pointsCost = 0,
    this.cashPriceTl,
    this.active = true,
    this.silSupurEligible = false,
    this.silSupurWeight = 0,
    this.silSupurPercent = 0,
    this.sort = 0,
    this.locationLabel,
    this.packageCode,
    this.slug,
    this.stock,
    this.costUsd,
    this.marginPercent,
    this.locationCodes,
  });

  final String id;
  final String type;
  final String title;
  final String description;
  final String? imageUrl;
  final int pointsCost;
  final double? cashPriceTl;
  final bool active;
  final bool silSupurEligible;
  /// Sil Süpür çıkma yüzdesi (0–100). `silSupurWeight` ile aynı değer (geriye uyum).
  /// Örn. 0.005 gibi binde/on binde basamakları destekler.
  final double silSupurWeight;
  final double silSupurPercent;
  final int sort;
  final String? locationLabel;
  final String? packageCode;
  final String? slug;
  final int? stock;
  final double? costUsd;
  final double? marginPercent;
  final String? locationCodes;

  bool get isEsim => type == 'esim';

  factory PointsCatalogItem.fromMap(String id, Map<String, dynamic> m) {
    final esim = m['esim'] is Map ? Map<String, dynamic>.from(m['esim'] as Map) : {};
    return PointsCatalogItem(
      id: id,
      type: '${m['type'] ?? 'gift'}',
      title: '${m['title'] ?? ''}',
      description: '${m['description'] ?? ''}',
      imageUrl: m['imageUrl']?.toString(),
      pointsCost: (num.tryParse('${m['pointsCost']}') ?? 0).round(),
      cashPriceTl: m['cashPriceTl'] == null
          ? null
          : (num.tryParse('${m['cashPriceTl']}') ?? 0).toDouble(),
      active: m['active'] != false,
      silSupurEligible: m['silSupurEligible'] == true,
      silSupurWeight: parseSilPercent(m['silSupurPercent'] ?? m['silSupurWeight']),
      silSupurPercent: parseSilPercent(m['silSupurPercent'] ?? m['silSupurWeight']),
      sort: (num.tryParse('${m['sort']}') ?? 0).round(),
      locationLabel: m['locationLabel']?.toString(),
      packageCode: '${esim['packageCode'] ?? m['packageCode'] ?? ''}'.nullIfEmpty,
      slug: '${esim['slug'] ?? m['slug'] ?? ''}'.nullIfEmpty,
      stock: m['stock'] == null ? null : (num.tryParse('${m['stock']}') ?? 0).round(),
      costUsd: m['costUsd'] == null ? null : (num.tryParse('${m['costUsd']}') ?? 0).toDouble(),
      marginPercent: m['marginPercent'] == null
          ? null
          : (num.tryParse('${m['marginPercent']}') ?? 0).toDouble(),
      locationCodes: '${m['locationCodes'] ?? esim['location'] ?? ''}'.nullIfEmpty,
    );
  }
}

extension on String {
  String? get nullIfEmpty {
    final t = trim();
    return t.isEmpty ? null : t;
  }
}

/// Sil Süpür çıkma % (0–100). En fazla 6 ondalık basamak.
double parseSilPercent(dynamic v) {
  final raw = '$v'.trim().replaceAll(',', '.');
  final n = num.tryParse(raw)?.toDouble() ?? 0;
  if (!n.isFinite || n <= 0) return 0;
  if (n > 100) return 100;
  return double.parse(n.toStringAsFixed(6));
}

/// Gösterim: 5 → "5", 0.005 → "0.005", 1.200000 → "1.2"
String formatSilPercent(num value) {
  final p = value.toDouble();
  if (p == 0) return '0';
  var s = p.toStringAsFixed(6);
  if (s.contains('.')) {
    s = s.replaceFirst(RegExp(r'0+$'), '');
    s = s.replaceFirst(RegExp(r'\.$'), '');
  }
  return s;
}

class UserReward {
  const UserReward({
    required this.id,
    required this.type,
    required this.title,
    required this.source,
    required this.status,
    this.paidWith,
    this.orderNo,
    this.iccid,
    this.esimTranNo,
    this.qrCodeUrl,
    this.shortUrl,
    this.ac,
    this.esimStatus,
    this.smdpStatus,
    this.totalVolume,
    this.totalDuration,
    this.orderUsage,
    this.expiredTime,
    this.activateTime,
    this.packageCode,
    this.slug,
    this.imageUrl,
    this.description,
    this.createdAt,
    this.locationCodes,
  });

  final String id;
  final String type;
  final String title;
  final String source;
  final String status;
  final String? paidWith;
  final String? orderNo;
  final String? iccid;
  final String? esimTranNo;
  final String? qrCodeUrl;
  final String? shortUrl;
  final String? ac;
  final String? esimStatus;
  final String? smdpStatus;
  final int? totalVolume;
  final int? totalDuration;
  final int? orderUsage;
  final String? expiredTime;
  final String? activateTime;
  final String? packageCode;
  final String? slug;
  final String? imageUrl;
  final String? description;
  final DateTime? createdAt;
  final String? locationCodes;

  bool get isEsim => type == 'esim';
  bool get isGift => !isEsim;

  double get remainGb {
    final total = totalVolume ?? 0;
    final used = orderUsage ?? 0;
    return ((total - used) / 1073741824).clamp(0, 9999);
  }

  double get totalGb => ((totalVolume ?? 0) / 1073741824);

  String get paidLabel {
    if (paidWith == 'points') return 'KP';
    if (paidWith == 'sil_supur') return 'Hediye';
    if (paidWith == 'cash') return 'Ödendi';
    return source == 'sil_supur' ? 'Hediye' : 'Market';
  }

  factory UserReward.fromMap(String id, Map<String, dynamic> m) {
    DateTime? ts;
    final c = m['createdAt'];
    if (c is String) ts = DateTime.tryParse(c);
    return UserReward(
      id: id,
      type: '${m['type'] ?? 'gift'}',
      title: '${m['title'] ?? 'Ödül'}',
      source: '${m['source'] ?? ''}',
      status: '${m['status'] ?? ''}',
      paidWith: m['paidWith']?.toString(),
      orderNo: m['orderNo']?.toString(),
      iccid: m['iccid']?.toString(),
      esimTranNo: m['esimTranNo']?.toString(),
      qrCodeUrl: m['qrCodeUrl']?.toString(),
      shortUrl: m['shortUrl']?.toString(),
      ac: m['ac']?.toString(),
      esimStatus: m['esimStatus']?.toString(),
      smdpStatus: m['smdpStatus']?.toString(),
      totalVolume: m['totalVolume'] == null
          ? null
          : (num.tryParse('${m['totalVolume']}') ?? 0).round(),
      totalDuration: m['totalDuration'] == null
          ? null
          : (num.tryParse('${m['totalDuration']}') ?? 0).round(),
      orderUsage: m['orderUsage'] == null
          ? null
          : (num.tryParse('${m['orderUsage']}') ?? 0).round(),
      expiredTime: m['expiredTime']?.toString(),
      activateTime: m['activateTime']?.toString(),
      packageCode: m['packageCode']?.toString(),
      slug: m['slug']?.toString(),
      imageUrl: m['imageUrl']?.toString(),
      description: m['description']?.toString(),
      createdAt: ts,
      locationCodes: m['locationCodes']?.toString(),
    );
  }
}

class PointsService {
  PointsService._();

  static Future<Map<String, dynamic>> getConfig() async {
    final res = await pointsFunctions.httpsCallable('getPointsConfig').call();
    return Map<String, dynamic>.from(res.data as Map? ?? {});
  }

  static Future<List<PointsCatalogItem>> listCatalog({bool admin = false}) async {
    final res = await pointsFunctions
        .httpsCallable('listPointsCatalog')
        .call({'admin': admin});
    final items = (res.data as Map?)?['items'] as List? ?? [];
    return items
        .whereType<Map>()
        .map((e) {
          final m = Map<String, dynamic>.from(e);
          return PointsCatalogItem.fromMap('${m['id']}', m);
        })
        .toList();
  }

  static Future<Map<String, dynamic>> redeem(String id) async {
    final res = await pointsFunctions
        .httpsCallable('redeemPointsCatalogItem')
        .call({'id': id});
    return Map<String, dynamic>.from(res.data as Map? ?? {});
  }

  static Future<Map<String, dynamic>> playSilSupur() async {
    final res = await pointsFunctions.httpsCallable('playSilSupur').call();
    return Map<String, dynamic>.from(res.data as Map? ?? {});
  }

  static Future<List<UserReward>> listRewards({String? type}) async {
    final res = await pointsFunctions
        .httpsCallable('listMyRewards')
        .call({if (type != null) 'type': type});
    final items = (res.data as Map?)?['items'] as List? ?? [];
    return items.whereType<Map>().map((e) {
      final m = Map<String, dynamic>.from(e);
      return UserReward.fromMap('${m['id']}', m);
    }).toList();
  }

  static Future<UserReward> refreshEsim(String rewardId) async {
    final res = await pointsFunctions
        .httpsCallable('refreshMyEsim')
        .call({'rewardId': rewardId});
    final r = Map<String, dynamic>.from(
      ((res.data as Map?)?['reward'] as Map?) ?? {},
    );
    return UserReward.fromMap('${r['id'] ?? rewardId}', r);
  }

  static Future<Map<String, dynamic>> claimPointsQr(String code) async {
    final res = await pointsFunctions
        .httpsCallable('claimPointsQr')
        .call({'code': code});
    return Map<String, dynamic>.from(res.data as Map? ?? {});
  }

  static Future<List<Map<String, dynamic>>> adminListPointsQr() async {
    final res = await pointsFunctions.httpsCallable('adminListPointsQr').call();
    final items = (res.data as Map?)?['items'] as List? ?? [];
    return items
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  static Future<Map<String, dynamic>> adminUpsertPointsQr(
    Map<String, dynamic> data,
  ) async {
    final res =
        await pointsFunctions.httpsCallable('adminUpsertPointsQr').call(data);
    return Map<String, dynamic>.from(res.data as Map? ?? {});
  }

  static Future<List<Map<String, dynamic>>> adminListPointsQrClaims(
    String qrId,
  ) async {
    final res = await pointsFunctions
        .httpsCallable('adminListPointsQrClaims')
        .call({'qrId': qrId});
    final items = (res.data as Map?)?['items'] as List? ?? [];
    return items
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  static Future<void> adminDeletePointsQr(String id) async {
    await pointsFunctions.httpsCallable('adminDeletePointsQr').call({'id': id});
  }

  static Future<void> applyEngagement({
    required String kind,
    required String targetUid,
    required String contentId,
  }) async {
    try {
      await pointsFunctions.httpsCallable('applyEngagementPoints').call({
        'kind': kind,
        'targetUid': targetUid,
        'contentId': contentId,
      });
    } catch (e) {
      debugPrint('[points] engagement: $e');
    }
  }
}
