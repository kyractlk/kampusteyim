class BusinessPartner {
  const BusinessPartner({
    required this.id,
    required this.name,
    required this.blurb,
    required this.logoUrl,
    required this.linkUrl,
    required this.logoSize,
    required this.sortOrder,
  });

  final String id;
  final String name;
  final String blurb;
  final String logoUrl;
  final String linkUrl;
  /// UI’da logo kenar uzunluğu (px), admin slider ile ayarlanır.
  final double logoSize;
  final int sortOrder;

  BusinessPartner copyWith({
    String? name,
    String? blurb,
    String? logoUrl,
    String? linkUrl,
    double? logoSize,
    int? sortOrder,
  }) {
    return BusinessPartner(
      id: id,
      name: name ?? this.name,
      blurb: blurb ?? this.blurb,
      logoUrl: logoUrl ?? this.logoUrl,
      linkUrl: linkUrl ?? this.linkUrl,
      logoSize: logoSize ?? this.logoSize,
      sortOrder: sortOrder ?? this.sortOrder,
    );
  }

  Map<String, dynamic> toJson() => {
        'name': name,
        'blurb': blurb,
        'logoUrl': logoUrl,
        'linkUrl': linkUrl,
        'logoSize': logoSize,
        'sortOrder': sortOrder,
        'updatedAt': DateTime.now().toIso8601String(),
      };

  factory BusinessPartner.fromJson(String id, Map<String, dynamic> m) {
    final size = (m['logoSize'] is num)
        ? (m['logoSize'] as num).toDouble()
        : 56.0;
    return BusinessPartner(
      id: id,
      name: '${m['name'] ?? ''}'.trim(),
      blurb: '${m['blurb'] ?? ''}'.trim(),
      logoUrl: '${m['logoUrl'] ?? ''}'.trim(),
      linkUrl: '${m['linkUrl'] ?? ''}'.trim(),
      logoSize: size.clamp(32, 140),
      sortOrder: (m['sortOrder'] is num) ? (m['sortOrder'] as num).toInt() : 0,
    );
  }
}
