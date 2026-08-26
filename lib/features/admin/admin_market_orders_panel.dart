import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';

FirebaseFunctions get _fn =>
    FirebaseFunctions.instanceFor(region: 'europe-west1');

const _fulfillmentOptions = <(String, String)>[
  ('awaiting_payment', 'Ödeme bekleniyor'),
  ('preparing', 'Hazırlanıyor'),
  ('packed', 'Paketlendi'),
  ('shipped', 'Kargoya verildi'),
  ('delivered', 'Teslim edildi'),
  ('return_pending', 'İade sürecinde'),
  ('refunded', 'İade edildi'),
  ('cancelled', 'İptal'),
];

/// Admin · Market siparişleri
class AdminMarketOrdersPanel extends StatefulWidget {
  const AdminMarketOrdersPanel({super.key});

  @override
  State<AdminMarketOrdersPanel> createState() => _AdminMarketOrdersPanelState();
}

class _AdminMarketOrdersPanelState extends State<AdminMarketOrdersPanel> {
  List<Map<String, dynamic>> _items = [];
  bool _loading = true;
  String? _filter;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final res = await _fn.httpsCallable('listMarketOrders').call({
        if (_filter != null) 'fulfillmentStatus': _filter,
      });
      final data = Map<String, dynamic>.from(res.data as Map? ?? {});
      final list = (data['items'] as List? ?? const [])
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
      if (mounted) setState(() => _items = list);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Siparişler yüklenemedi: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _edit(Map<String, dynamic> order) async {
    final statusCtrl = ValueNotifier<String>(
      '${order['fulfillmentStatus'] ?? 'preparing'}',
    );
    final tracking = TextEditingController(
      text: '${order['trackingNo'] ?? ''}',
    );
    final note = TextEditingController(text: '${order['adminNote'] ?? ''}');
    var notify = true;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setLocal) {
            return AlertDialog(
              title: const Text('Sipariş durumu'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      '${order['merchName'] ?? order['product']} · '
                      '${order['amount']} TL',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 4),
                    SelectableText(
                      '${order['email']}\n${order['id']}',
                      style: const TextStyle(fontSize: 12),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      initialValue: statusCtrl.value,
                      decoration: const InputDecoration(
                        labelText: 'Durum',
                        border: OutlineInputBorder(),
                      ),
                      items: [
                        for (final o in _fulfillmentOptions)
                          DropdownMenuItem(value: o.$1, child: Text(o.$2)),
                      ],
                      onChanged: (v) {
                        if (v != null) {
                          statusCtrl.value = v;
                          setLocal(() {});
                        }
                      },
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: tracking,
                      decoration: const InputDecoration(
                        labelText: 'Kargo takip no (opsiyonel)',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: note,
                      maxLines: 2,
                      decoration: const InputDecoration(
                        labelText: 'Müşteriye not (mailde görünür)',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Müşteriye anlık mail'),
                      subtitle: const Text('Durum değişince e-posta gönder'),
                      value: notify,
                      onChanged: (v) => setLocal(() => notify = v),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Vazgeç'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('Kaydet'),
                ),
              ],
            );
          },
        );
      },
    );
    if (ok != true || !mounted) {
      tracking.dispose();
      note.dispose();
      statusCtrl.dispose();
      return;
    }
    try {
      final res = await _fn.httpsCallable('updateMarketOrderStatus').call({
        'orderId': order['id'],
        'fulfillmentStatus': statusCtrl.value,
        'trackingNo': tracking.text.trim(),
        'adminNote': note.text.trim(),
        'notify': notify,
      });
      tracking.dispose();
      note.dispose();
      statusCtrl.dispose();
      final data = Map<String, dynamic>.from(res.data as Map? ?? {});
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            data['mailSent'] == true
                ? 'Durum güncellendi · müşteriye mail gitti'
                : 'Durum güncellendi',
          ),
        ),
      );
      await _load();
    } catch (e) {
      tracking.dispose();
      note.dispose();
      statusCtrl.dispose();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Güncellenemedi: $e')),
        );
      }
    }
  }

  Future<void> _refund(Map<String, dynamic> order) async {
    if ('${order['status']}' != 'paid' && '${order['status']}' != 'refunded') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Yalnızca ödenmiş sipariş iade edilir')),
      );
      return;
    }
    final orderAmount =
        double.tryParse('${order['amount']}'.replaceAll(',', '.')) ?? 0;
    final already =
        double.tryParse('${order['refundedAmount'] ?? 0}'.replaceAll(',', '.')) ??
            0;
    final remaining =
        ((orderAmount - already) * 100).roundToDouble() / 100;
    if (remaining <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('İade edilecek tutar kalmadı')),
      );
      return;
    }
    final amountCtrl = TextEditingController(text: remaining.toStringAsFixed(2));
    final mode = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('İade tutarı'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Sipariş: ${orderAmount.toStringAsFixed(2)} TL · '
              'Kalan: ${remaining.toStringAsFixed(2)} TL'
              '${order['product'] == 'plus' ? '\nPlus iadesinde üyelik anında kapanır.' : '\nÜrün iade sürecine alınır.'}',
            ),
            const SizedBox(height: 12),
            TextField(
              controller: amountCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'İade tutarı (TL)',
                border: OutlineInputBorder(),
                helperText: 'Kısmi veya tam',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Vazgeç'),
          ),
          OutlinedButton(
            onPressed: () {
              amountCtrl.text = remaining.toStringAsFixed(2);
              Navigator.pop(ctx, 'full');
            },
            child: const Text('Tam iade'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, 'partial'),
            child: const Text('Devam'),
          ),
        ],
      ),
    );
    if (mode == null || !mounted) {
      amountCtrl.dispose();
      return;
    }
    final returnAmount = mode == 'full'
        ? remaining
        : (double.tryParse(amountCtrl.text.replaceAll(',', '.')) ?? 0);
    amountCtrl.dispose();
    if (returnAmount <= 0 || returnAmount > remaining + 0.001) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Geçersiz iade tutarı')),
      );
      return;
    }
    final ok1 = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('1. onay'),
        content: Text(
          '${returnAmount.toStringAsFixed(2)} TL PayTR üzerinden iade edilecek. Emin misin?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Vazgeç'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Evet, devam'),
          ),
        ],
      ),
    );
    if (ok1 != true || !mounted) return;
    final ok2 = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('2. onay · son adım'),
        content: const Text(
          'Bu işlem geri alınamaz. PayTR iade API çağrılacak.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('İptal'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.crimson),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('İadeyi başlat'),
          ),
        ],
      ),
    );
    if (ok2 != true || !mounted) return;
    try {
      final res = await _fn.httpsCallable('adminRefundPaymentOrder').call({
        'orderId': order['id'],
        'returnAmount': returnAmount,
        'confirm': true,
        'confirm2': true,
      });
      final data = Map<String, dynamic>.from(res.data as Map? ?? {});
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'İade OK · ${data['returnAmount']} TL '
            '(${data['refundStatus']})',
          ),
        ),
      );
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('İade hatası: $e')),
        );
      }
    }
  }

  Color _statusColor(String s) {
    return switch (s) {
      'delivered' => const Color(0xFF166534),
      'shipped' || 'packed' => AppColors.navy,
      'cancelled' || 'refunded' => AppColors.crimson,
      'return_pending' => const Color(0xFF92400E),
      'awaiting_payment' => const Color(0xFF92400E),
      _ => AppColors.textSecondary,
    };
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Siparişler',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w900,
              ),
        ),
        const SizedBox(height: 4),
        const Text(
          'Merch, etkinlik bileti ve KampüsteyimPlus siparişleri. Durumu güncelleyince müşteriye mail gider.',
          style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
        ),
        const SizedBox(height: 12),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              FilterChip(
                label: Text(
                  'Tümü',
                  style: TextStyle(
                    color: _filter == null ? Colors.white : AppColors.textPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                selected: _filter == null,
                selectedColor: AppColors.navy,
                backgroundColor: Colors.white,
                checkmarkColor: Colors.white,
                side: BorderSide(
                  color: _filter == null ? AppColors.navy : AppColors.border,
                ),
                onSelected: (_) {
                  setState(() => _filter = null);
                  _load();
                },
              ),
              const SizedBox(width: 6),
              for (final o in _fulfillmentOptions) ...[
                FilterChip(
                  label: Text(
                    o.$2,
                    style: TextStyle(
                      color: _filter == o.$1
                          ? Colors.white
                          : AppColors.textPrimary,
                      fontWeight: FontWeight.w700,
                      fontSize: 12.5,
                    ),
                  ),
                  selected: _filter == o.$1,
                  selectedColor: AppColors.navy,
                  backgroundColor: Colors.white,
                  checkmarkColor: Colors.white,
                  side: BorderSide(
                    color: _filter == o.$1 ? AppColors.navy : AppColors.border,
                  ),
                  onSelected: (_) {
                    setState(() => _filter = o.$1);
                    _load();
                  },
                ),
                const SizedBox(width: 6),
              ],
              IconButton(
                tooltip: 'Yenile',
                onPressed: _loading ? null : _load,
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        if (_loading)
          const Padding(
            padding: EdgeInsets.all(32),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (_items.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Text(
              'Bu filtrede sipariş yok.',
              style: TextStyle(color: AppColors.textSecondary),
            ),
          )
        else
          ..._items.map((o) {
            final fs = '${o['fulfillmentStatus'] ?? ''}';
            final ship = [
              if ('${o['shipName']}'.isNotEmpty) o['shipName'],
              if ('${o['shipAddress']}'.isNotEmpty) o['shipAddress'],
              if ('${o['shipDistrict']}'.isNotEmpty) o['shipDistrict'],
              if ('${o['shipCity']}'.isNotEmpty) o['shipCity'],
              if ('${o['shipPhone']}'.isNotEmpty) o['shipPhone'],
            ].join(' · ');
            return Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.border),
                color: AppColors.surfaceMuted,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${o['merchName']?.toString().isNotEmpty == true ? o['merchName'] : o['product']} · ${o['amount']} TL',
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: _statusColor(fs).withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          '${o['fulfillmentLabel'] ?? fs}',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            color: _statusColor(fs),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${switch ('${o['product']}') {
                      'event' => 'Bilet',
                      'plus' =>
                        'Plus${o['months'] != null ? ' · ${o['months']} ay' : ''}',
                      _ => 'Merch',
                    }}'
                    '${o['size'] != null ? ' · ${o['size']}' : ''}'
                    ' · ödeme: ${o['status']}',
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  SelectableText(
                    '${o['email']}',
                    style: const TextStyle(fontSize: 12.5),
                  ),
                  if (ship.isNotEmpty)
                    Text(
                      ship,
                      style: const TextStyle(fontSize: 12, height: 1.35),
                    ),
                  if ('${o['trackingNo']}'.isNotEmpty)
                    SelectableText(
                      'Takip: ${o['trackingNo']}',
                      style: const TextStyle(fontSize: 12),
                    ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      FilledButton.tonalIcon(
                        onPressed: () => _edit(o),
                        icon: const Icon(Icons.local_shipping_outlined, size: 18),
                        label: const Text('Durumu güncelle'),
                      ),
                      if ('${o['status']}' == 'paid' ||
                          '${o['refundStatus']}' == 'partial')
                        OutlinedButton.icon(
                          onPressed: () => _refund(o),
                          icon: const Icon(Icons.undo, size: 18),
                          label: Text(
                            o['refundStatus'] == 'partial'
                                ? 'Kısmi iade devam'
                                : 'İade',
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            );
          }),
      ],
    );
  }
}
