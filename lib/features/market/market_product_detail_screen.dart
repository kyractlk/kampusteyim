import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../../core/utils/auth_gate.dart';
import '../../core/widgets/web_safe_image.dart';
import '../../models/models.dart';
import '../auth/data/auth_provider.dart';
import '../payments/payment_checkout_sheet.dart';
import 'delivery_address_form.dart';
import 'merch_images.dart';

/// Ürün detay — görsel, açıklama, beden, adres, ödeme.
class MarketProductDetailScreen extends StatefulWidget {
  const MarketProductDetailScreen({
    super.key,
    required this.item,
    this.paytrReady = false,
    this.merchPaytrEnabled = true,
  });

  final Map<String, dynamic> item;
  final bool paytrReady;
  final bool merchPaytrEnabled;

  @override
  State<MarketProductDetailScreen> createState() =>
      _MarketProductDetailScreenState();
}

class _MarketProductDetailScreenState extends State<MarketProductDetailScreen> {
  late String _size;
  late List<String> _sizes;
  String? _selectedAddressId;
  final _codeCtrl = TextEditingController();
  var _busy = false;

  @override
  void initState() {
    super.initState();
    _sizes = (widget.item['sizes'] as List? ?? const [])
        .map((e) => '$e')
        .where((s) => s.isNotEmpty)
        .toList();
    if (_sizes.isEmpty) _sizes = ['Tek beden'];
    _size = _sizes.first;
  }

  @override
  void dispose() {
    _codeCtrl.dispose();
    super.dispose();
  }

  Future<void> _checkout() async {
    if (!AuthGate.requireAuth(context)) return;
    final auth = context.read<AuthProvider>();
    var addresses =
        List<DeliveryAddress>.from(auth.user?.deliveryAddresses ?? const []);
    if (addresses.isEmpty) {
      final addr = await showDeliveryAddressEditor(
        context,
        required: true,
        title: 'Teslimat adresi ekle',
      );
      if (addr == null) return;
      await auth.upsertDeliveryAddress(addr);
      addresses = List.from(auth.user?.deliveryAddresses ?? [addr]);
    }

    final selectedId = _selectedAddressId ??
        auth.user?.defaultDeliveryAddress?.id ??
        addresses.first.id;
    final ship = addresses.firstWhere(
      (a) => a.id == selectedId,
      orElse: () => addresses.first,
    );

    setState(() => _busy = true);
    try {
      if (!mounted) return;
      await openPaymentCheckout(
        context,
        product: 'merch',
        amount: (widget.item['amount'] as num?)?.toDouble(),
        sku: '${widget.item['sku']}',
        size: _size,
        city: ship.city,
        shipName: ship.fullName,
        shipAddress: ship.line1,
        shipDistrict: ship.district,
        shipPhone: ship.phone,
        discountCode:
            _codeCtrl.text.trim().isEmpty ? null : _codeCtrl.text.trim(),
        provider: (widget.paytrReady && widget.merchPaytrEnabled)
            ? 'paytr'
            : null,
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final img = merchImageUrl(item);
    final name = '${item['name'] ?? 'Ürün'}';
    final short = '${item['short'] ?? item['description'] ?? ''}';
    final amount = (item['amount'] as num?)?.toDouble();
    final auth = context.watch<AuthProvider>();
    final addresses = auth.user?.deliveryAddresses ?? const <DeliveryAddress>[];
    final selectedId = _selectedAddressId ??
        auth.user?.defaultDeliveryAddress?.id ??
        (addresses.isNotEmpty ? addresses.first.id : null);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            pinned: true,
            expandedHeight: 320,
            backgroundColor: AppColors.navy,
            foregroundColor: Colors.white,
            flexibleSpace: FlexibleSpaceBar(
              background: Stack(
                fit: StackFit.expand,
                children: [
                  if (img != null)
                    webSafeNetworkImage(
                      img,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => _imageFallback(),
                    )
                  else
                    _imageFallback(),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.black.withValues(alpha: 0.15),
                          Colors.black.withValues(alpha: 0.55),
                        ],
                      ),
                    ),
                  ),
                  Positioned(
                    left: 20,
                    right: 20,
                    bottom: 20,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w900,
                            fontSize: 26,
                            height: 1.15,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          amount != null
                              ? '${amount.toStringAsFixed(0)} TL'
                              : '—',
                          style: const TextStyle(
                            color: AppColors.cyan,
                            fontWeight: FontWeight.w800,
                            fontSize: 20,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 120),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (short.isNotEmpty) ...[
                    Text(
                      short,
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        height: 1.45,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 20),
                  ],
                  const Text(
                    'Beden',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final s in _sizes)
                        ChoiceChip(
                          label: Text(
                            s,
                            style: TextStyle(
                              color: _size == s
                                  ? Colors.white
                                  : AppColors.textPrimary,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          selected: _size == s,
                          selectedColor: AppColors.navy,
                          backgroundColor: AppColors.surface,
                          checkmarkColor: Colors.white,
                          side: BorderSide(
                            color: _size == s
                                ? AppColors.navy
                                : AppColors.border,
                          ),
                          onSelected: (_) => setState(() => _size = s),
                        ),
                    ],
                  ),
                  const SizedBox(height: 22),
                  Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Teslimat adresi',
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 15,
                          ),
                        ),
                      ),
                      TextButton.icon(
                        onPressed: () async {
                          final addr = await showDeliveryAddressEditor(context);
                          if (addr == null) return;
                          await auth.upsertDeliveryAddress(addr);
                          setState(() => _selectedAddressId = addr.id);
                        },
                        icon: const Icon(Icons.add_rounded, size: 18),
                        label: const Text('Ekle'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  if (addresses.isEmpty)
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceMuted,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: const Text(
                        'Sipariş için teslimat adresi gerekli.',
                        style: TextStyle(color: AppColors.textSecondary),
                      ),
                    )
                  else
                    ...addresses.map((a) {
                      final sel = a.id == selectedId;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Material(
                          color: sel
                              ? AppColors.navy.withValues(alpha: 0.06)
                              : AppColors.surface,
                          borderRadius: BorderRadius.circular(14),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(14),
                            onTap: () =>
                                setState(() => _selectedAddressId = a.id),
                            child: Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                  color: sel
                                      ? AppColors.navy.withValues(alpha: 0.35)
                                      : AppColors.border,
                                ),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    sel
                                        ? Icons.check_circle_rounded
                                        : Icons.circle_outlined,
                                    size: 20,
                                    color: sel
                                        ? AppColors.navy
                                        : AppColors.textSecondary,
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          a.title,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w800,
                                          ),
                                        ),
                                        Text(
                                          '${a.fullName} · ${a.summaryLine}',
                                          style: const TextStyle(
                                            fontSize: 12.5,
                                            color: AppColors.textSecondary,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                    }),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _codeCtrl,
                    textCapitalization: TextCapitalization.characters,
                    decoration: InputDecoration(
                      labelText: 'Kampanya kodu',
                      hintText: 'Varsa gir',
                      filled: true,
                      fillColor: AppColors.surface,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    widget.paytrReady
                        ? 'Kart bilgisi uygulama içinde güvenle alınır · PayTR'
                        : 'Ödeme yakında',
                    style: const TextStyle(
                      fontSize: 12.5,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: FilledButton(
            onPressed: _busy ? null : _checkout,
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.navy,
              foregroundColor: Colors.white,
              minimumSize: const Size.fromHeight(50),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            child: _busy
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : Text(
                    amount != null
                        ? 'Satın al · ${amount.toStringAsFixed(0)} TL'
                        : 'Satın al',
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
          ),
        ),
      ),
    );
  }

  Widget _imageFallback() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.navy, Color(0xFF0E3A4A), AppColors.cyan],
        ),
      ),
      child: const Center(
        child: Icon(Icons.shopping_bag_outlined, size: 72, color: Colors.white54),
      ),
    );
  }
}
