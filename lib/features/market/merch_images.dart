/// Merch görselleri — API `imageUrl` yoksa web market fallback.
String? merchImageUrl(Map<String, dynamic> item) {
  final raw = '${item['imageUrl'] ?? item['image'] ?? ''}'.trim();
  if (raw.startsWith('http')) return raw;

  const base = 'https://app.kampusteyim.app/market';
  final sku = '${item['sku'] ?? item['id'] ?? ''}'.toLowerCase().trim();
  return switch (sku) {
    'tshirt' || 'tee' || 'tişört' => '$base/merch_tshirt_white.jpg',
    'hoodie' || 'sweat' => '$base/merch_hoodie_black.jpg',
    'cap' || 'hat' || 'şapka' => '$base/merch_cap_navy.jpg',
    'tote' || 'bag' || 'çanta' => '$base/merch_tote_beige.jpg',
    _ => raw.isNotEmpty && raw.startsWith('/')
        ? 'https://app.kampusteyim.app$raw'
        : null,
  };
}
