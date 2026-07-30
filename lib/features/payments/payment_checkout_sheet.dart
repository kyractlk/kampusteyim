import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme/app_colors.dart';
import 'payments_service.dart';

/// Plus (veya etkinlik) ödemesi — aktif provider’a göre
Future<void> openPaymentCheckout(
  BuildContext context, {
  String product = 'plus',
  String? provider,
  double? amount,
  String? eventId,
  String? tierLabel,
  String? discountCode,
}) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => _CheckoutSheet(
      product: product,
      provider: provider,
      amount: amount,
      eventId: eventId,
      tierLabel: tierLabel,
      discountCode: discountCode,
    ),
  );
}

class _CheckoutSheet extends StatefulWidget {
  const _CheckoutSheet({
    required this.product,
    this.provider,
    this.amount,
    this.eventId,
    this.tierLabel,
    this.discountCode,
  });

  final String product;
  final String? provider;
  final double? amount;
  final String? eventId;
  final String? tierLabel;
  final String? discountCode;

  @override
  State<_CheckoutSheet> createState() => _CheckoutSheetState();
}

class _CheckoutSheetState extends State<_CheckoutSheet> {
  PaymentsPublicConfig? _pub;
  String? _selected;
  bool _loading = true;
  bool _busy = false;
  PaymentOrderResult? _order;
  String? _error;

  @override
  void initState() {
    super.initState();
    _boot();
  }

  Future<void> _boot() async {
    try {
      final pub = await PaymentsService.getPublic();
      final enabled = pub.enabledProviders
          .where((p) {
            if (p == 'paytr') return pub.paytrReady;
            if (p == 'shopier') return pub.shopierReady;
            if (p == 'iban') return pub.ibanReady;
            return false;
          })
          .toList();
      var sel = widget.provider ?? pub.activeProvider;
      if (!enabled.contains(sel) && enabled.isNotEmpty) sel = enabled.first;
      setState(() {
        _pub = pub;
        _selected = enabled.isEmpty ? null : sel;
        _loading = false;
        if (enabled.isEmpty) {
          _error = 'Ödeme yöntemi henüz yapılandırılmamış.';
        }
      });
    } catch (e) {
      setState(() {
        _loading = false;
        _error = 'Yüklenemedi: $e';
      });
    }
  }

  Future<void> _pay() async {
    if (_selected == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final order = await PaymentsService.createOrder(
        product: widget.product,
        provider: _selected,
        amount: widget.amount ?? _pub?.plusAmount,
        eventId: widget.eventId,
        tierLabel: widget.tierLabel,
        discountCode: widget.discountCode,
      );
      setState(() => _order = order);
      if (order.provider == 'paytr' && order.iframeUrl != null) {
        await launchUrl(
          Uri.parse(order.iframeUrl!),
          mode: LaunchMode.externalApplication,
        );
      } else if (order.provider == 'shopier' && order.payUrl != null) {
        await launchUrl(
          Uri.parse(order.payUrl!),
          mode: LaunchMode.externalApplication,
        );
      }
    } catch (e) {
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _confirmIban() async {
    final id = _order?.orderId;
    if (id == null) return;
    setState(() => _busy = true);
    try {
      final msg = await PaymentsService.confirmIban(id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
      Navigator.pop(context);
    } catch (e) {
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 8, 20, 20 + bottom),
      child: _loading
          ? const SizedBox(
              height: 160,
              child: Center(child: CircularProgressIndicator()),
            )
          : SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    widget.product == 'plus'
                        ? 'KampüsteyimPlus satın al'
                        : widget.product == 'event'
                            ? 'Etkinlik bileti'
                            : 'Ödeme',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w900,
                        ),
                  ),
                  if (_pub != null) ...[
                    const SizedBox(height: 6),
                    Text(
                      widget.product == 'event'
                          ? '${(widget.amount ?? 0).toStringAsFixed(2)} TL'
                          : '${(_pub!.plusAmount > 0 ? _pub!.plusAmount : widget.amount ?? 0).toStringAsFixed(2)} TL'
                              ' · ${_pub!.plusDays} gün',
                      style: const TextStyle(color: AppColors.textSecondary),
                    ),
                  ],
                  if (widget.product == 'event') ...[
                    const SizedBox(height: 8),
                    const Text(
                      'Ödeyen hesap katılımcı hesaptır. İade/iptal yoktur.',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(_error!, style: const TextStyle(color: Colors.red)),
                  ],
                  if (_order == null) ...[
                    const SizedBox(height: 16),
                    if (_pub != null)
                      ..._pub!.enabledProviders
                          .where((p) {
                            if (p == 'paytr') return _pub!.paytrReady;
                            if (p == 'shopier') return _pub!.shopierReady;
                            if (p == 'iban') return _pub!.ibanReady;
                            return false;
                          })
                          .map(
                            (p) => RadioListTile<String>(
                              value: p,
                              groupValue: _selected,
                              onChanged: (v) => setState(() => _selected = v),
                              title: Text(_label(p)),
                              contentPadding: EdgeInsets.zero,
                            ),
                          ),
                    const SizedBox(height: 8),
                    FilledButton(
                      onPressed: _busy || _selected == null ? null : _pay,
                      child: _busy
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Ödemeye devam et'),
                    ),
                  ] else if (_order!.provider == 'iban') ...[
                    const SizedBox(height: 16),
                    const Text(
                      'Aşağıdaki IBAN’a havale/EFT yap. Açıklamaya yalnızca kodu yaz.',
                      style: TextStyle(height: 1.35),
                    ),
                    const SizedBox(height: 12),
                    _copyRow('IBAN', _order!.iban ?? ''),
                    _copyRow('Alıcı', _order!.ibanHolder ?? ''),
                    if ((_order!.ibanBank ?? '').isNotEmpty)
                      _copyRow('Banka', _order!.ibanBank!),
                    _copyRow('Tutar', '${_order!.amount.toStringAsFixed(2)} TL'),
                    _copyRow('Açıklama kodu', _order!.transferDescription ?? ''),
                    if ((_order!.note ?? '').isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        _order!.note!,
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: _busy ? null : _confirmIban,
                      child: const Text('Havale yaptım · bildir'),
                    ),
                  ] else ...[
                    const SizedBox(height: 16),
                    Text(
                      _order!.provider == 'paytr'
                          ? 'PayTR ödeme sayfası açıldı. Ödeme bitince uygulamaya dön.'
                          : 'Shopier ödeme sayfası açıldı. Ödeme bitince uygulamaya dön.',
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton(
                      onPressed: () {
                        final url = _order!.iframeUrl ?? _order!.payUrl;
                        if (url != null) {
                          launchUrl(
                            Uri.parse(url),
                            mode: LaunchMode.externalApplication,
                          );
                        }
                      },
                      child: const Text('Ödeme sayfasını tekrar aç'),
                    ),
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Kapat'),
                    ),
                  ],
                ],
              ),
            ),
    );
  }

  String _label(String p) {
    switch (p) {
      case 'paytr':
        return 'Kredi / banka kartı (PayTR)';
      case 'shopier':
        return 'Shopier';
      case 'iban':
        return 'Havale / EFT (IBAN)';
      default:
        return p;
    }
  }

  Widget _copyRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.textSecondary,
                  ),
                ),
                SelectableText(
                  value,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Kopyala',
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: value));
              if (!mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('$label kopyalandı')),
              );
            },
            icon: const Icon(Icons.copy, size: 18),
          ),
        ],
      ),
    );
  }
}
