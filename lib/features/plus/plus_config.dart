/// Firestore `app_config/kampusteyim_plus`
class PlusConfig {
  const PlusConfig({
    this.trialDays = 60,
    this.features = const PlusFeatures(),
    this.rateLimitsFree = const PlusRateLimits.freeDefaults(),
    this.rateLimitsPlus = const PlusRateLimits.plusDefaults(),
    this.pricingNote = '',
    this.iban = '',
    this.ibanHolder = '',
    this.discountNote = '',
  });

  final int trialDays;
  final PlusFeatures features;
  final PlusRateLimits rateLimitsFree;
  final PlusRateLimits rateLimitsPlus;
  final String pricingNote;
  final String iban;
  final String ibanHolder;
  final String discountNote;

  static const defaults = PlusConfig();

  factory PlusConfig.fromMap(Map<String, dynamic>? m) {
    if (m == null) return defaults;
    return PlusConfig(
      trialDays: (m['trialDays'] as num?)?.toInt() ?? 60,
      features: PlusFeatures.fromMap(
        m['features'] is Map
            ? Map<String, dynamic>.from(m['features'] as Map)
            : null,
      ),
      rateLimitsFree: PlusRateLimits.fromMap(
        m['rateLimitsFree'] is Map
            ? Map<String, dynamic>.from(m['rateLimitsFree'] as Map)
            : null,
        fallback: const PlusRateLimits.freeDefaults(),
      ),
      rateLimitsPlus: PlusRateLimits.fromMap(
        m['rateLimitsPlus'] is Map
            ? Map<String, dynamic>.from(m['rateLimitsPlus'] as Map)
            : null,
        fallback: const PlusRateLimits.plusDefaults(),
      ),
      pricingNote: '${m['pricingNote'] ?? ''}',
      iban: '${m['iban'] ?? ''}',
      ibanHolder: '${m['ibanHolder'] ?? ''}',
      discountNote: '${m['discountNote'] ?? ''}',
    );
  }

  Map<String, dynamic> toMap() => {
        'trialDays': trialDays,
        'features': features.toMap(),
        'rateLimitsFree': rateLimitsFree.toMap(),
        'rateLimitsPlus': rateLimitsPlus.toMap(),
        'pricingNote': pricingNote,
        'iban': iban,
        'ibanHolder': ibanHolder,
        'discountNote': discountNote,
        'updatedAt': DateTime.now().toIso8601String(),
      };
}

class PlusFeatures {
  const PlusFeatures({
    this.filePosts = true,
    this.cvTheme = true,
    this.cvAllLanguages = true,
    this.higherCvQuota = true,
    this.greenBadge = true,
  });

  final bool filePosts;
  final bool cvTheme;
  final bool cvAllLanguages;
  final bool higherCvQuota;
  final bool greenBadge;

  factory PlusFeatures.fromMap(Map<String, dynamic>? m) {
    if (m == null) return const PlusFeatures();
    return PlusFeatures(
      filePosts: m['filePosts'] != false,
      cvTheme: m['cvTheme'] != false,
      cvAllLanguages: m['cvAllLanguages'] != false,
      higherCvQuota: m['higherCvQuota'] != false,
      greenBadge: m['greenBadge'] != false,
    );
  }

  Map<String, dynamic> toMap() => {
        'filePosts': filePosts,
        'cvTheme': cvTheme,
        'cvAllLanguages': cvAllLanguages,
        'higherCvQuota': higherCvQuota,
        'greenBadge': greenBadge,
      };

  PlusFeatures copyWith({
    bool? filePosts,
    bool? cvTheme,
    bool? cvAllLanguages,
    bool? higherCvQuota,
    bool? greenBadge,
  }) =>
      PlusFeatures(
        filePosts: filePosts ?? this.filePosts,
        cvTheme: cvTheme ?? this.cvTheme,
        cvAllLanguages: cvAllLanguages ?? this.cvAllLanguages,
        higherCvQuota: higherCvQuota ?? this.higherCvQuota,
        greenBadge: greenBadge ?? this.greenBadge,
      );
}

/// 0 = sınırsız. post/story/file şimdilik yer tutucu (UI + admin).
class PlusRateLimits {
  const PlusRateLimits({
    required this.cvAiDaily,
    required this.postsDaily,
    required this.storiesDaily,
    required this.filePostsDaily,
  });

  const PlusRateLimits.freeDefaults()
      : cvAiDaily = 2,
        postsDaily = 30,
        storiesDaily = 20,
        filePostsDaily = 0;

  const PlusRateLimits.plusDefaults()
      : cvAiDaily = 20,
        postsDaily = 0,
        storiesDaily = 0,
        filePostsDaily = 15;

  final int cvAiDaily;
  final int postsDaily;
  final int storiesDaily;
  final int filePostsDaily;

  factory PlusRateLimits.fromMap(
    Map<String, dynamic>? m, {
    required PlusRateLimits fallback,
  }) {
    if (m == null) return fallback;
    return PlusRateLimits(
      cvAiDaily: (m['cvAiDaily'] as num?)?.toInt() ?? fallback.cvAiDaily,
      postsDaily: (m['postsDaily'] as num?)?.toInt() ?? fallback.postsDaily,
      storiesDaily:
          (m['storiesDaily'] as num?)?.toInt() ?? fallback.storiesDaily,
      filePostsDaily:
          (m['filePostsDaily'] as num?)?.toInt() ?? fallback.filePostsDaily,
    );
  }

  Map<String, dynamic> toMap() => {
        'cvAiDaily': cvAiDaily,
        'postsDaily': postsDaily,
        'storiesDaily': storiesDaily,
        'filePostsDaily': filePostsDaily,
      };
}
