import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme/app_colors.dart';
import 'payments_service.dart';

/// Plus / merch / etkinlik ödemesi — aktif provider’a göre
Future<void> openPaymentCheckout(
  BuildContext context, {
  String product = 'plus',
  String? provider,
  double? amount,
  int? months,
  String? eventId,
  String? tierLabel,
  String? discountCode,
  String? sku,
  String? size,
  String? city,
  String? shipName,
}) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => _CheckoutSheet(
      product: product,
      provider: provider,
      amount: amount,
      months: months,
      eventId: eventId,
      tierLabel: tierLabel,
      discountCode: discountCode,
      sku: sku,
      size: size,
      city: city,
      shipName: shipName,
    ),
  );
}

class _CheckoutSheet extends StatefulWidget {
  const _CheckoutSheet({
    required this.product,
    this.provider,
    this.amount,
    this.months,
    this.eventId,
    this.tierLabel,
    this.discountCode,
    this.sku,
    this.size,
    this.city,
    this.shipName,
  });

  final String product;
  final String? provider;
  final double? amount;
  final int? months;
  final String? eventId;
  final String? tierLabel;
  final String? discountCode;
  final String? sku;
  final String? size;
  final String? city;
  final String? shipName;

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
  final _codeCtrl = TextEditingController();
  int _months = 1;
  List<Map<String, dynamic>> _myCodes = [];
  String? _previewNote;

  @override
  void initState() {
    super.initState();
    _months = widget.months ?? 1;
    if (widget.discountCode != null && widget.discountCode!.isNotEmpty) {
      _codeCtrl.text = widget.discountCode!;
    }
    _boot();
  }

  @override
  void dispose() {
    _codeCtrl.dispose();
    super.dispose();
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
      List<Map<String, dynamic>> mine = const [];
      try {
        mine = await PaymentsService.myCampaigns();
      } catch (_) {}
      setState(() {
        _pub = pub;
        _selected = enabled.isEmpty ? null : sel;
        _myCodes = mine;
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

  double get _baseAmount {
    if (widget.product == 'merch' || widget.product == 'event') {
      return widget.amount ?? 0;
    }
    final unit = _pub?.plusAmount ?? widget.amount ?? 0;
    return unit * _months;
  }

  Future<void> _previewCode() async {
    final code = _codeCtrl.text.trim();
    if (code.isEmpty) {
      setState(() => _previewNote = null);
      return;
    }
    try {
      final r = await PaymentsService.previewCampaign(
        code: code,
        product: widget.product,
        amount: _baseAmount,
      );
      setState(() {
        _previewNote =
            'İndirim ${((r['discountAmount'] as num?)?.toDouble() ?? 0).toStringAsFixed(0)} TL → '
            '${((r['amount'] as num?)?.toDouble() ?? 0).toStringAsFixed(0)} TL';
      });
    } catch (e) {
      setState(() => _previewNote = '$e');
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
        months: widget.product == 'plus' ? _months : widget.months,
        eventId: widget.eventId,
        tierLabel: widget.tierLabel,
        discountCode: _codeCtrl.text.trim().isEmpty
            ? widget.discountCode
            : _codeCtrl.text.trim(),
        sku: widget.sku,
        size: widget.size,
        city: widget.city,
        shipName: widget.shipName,
      );
      setState(() => _order = order);
      if (order.provider == 'free') {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(order.message ?? 'Kampanya uygulandı')),
        );
        Navigator.pop(context);
        return;
      }
      final payLink = order.payUrl ?? order.iframeUrl;
      if (order.provider == 'paytr' && payLink != null) {
        await launchUrl(
          Uri.parse(payLink),
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
                            : widget.product == 'merch'
                                ? 'Market siparişi'
                                : 'Ödeme',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w900,
                        ),
                  ),
                  if (_pub != null) ...[
                    const SizedBox(height: 6),
                    Text(
                      widget.product == 'event' || widget.product == 'merch'
                          ? '${_baseAmount.toStringAsFixed(2)} TL'
                          : '${_baseAmount.toStringAsFixed(2)} TL'
                              ' · ${_months * (_pub!.plusDays)} gün',
                      style: const TextStyle(color: AppColors.textSecondary),
                    ),
                  ],
                  if (_pub?.paytrReady == true) ...[
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.navy.withValues(alpha: 0.06),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.lock_rounded, size: 18, color: AppColors.navy),
                          SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Kart ile güvenle öde · PayTR',
                              style: TextStyle(
                                fontWeight: FontWeight.w800,
                                color: AppColors.navy,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  if (widget.product == 'plus' && (_pub?.plusPlans.isNotEmpty ?? false)) ...[
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      children: [
                        for (final p in _pub!.plusPlans)
                          ChoiceChip(
                            label: Text('${p['label']}'),
                            selected: _months == (p['months'] as num?)?.toInt(),
                            onSelected: (_) => setState(() {
                              _months = (p['months'] as num?)?.toInt() ?? 1;
                            }),
                          ),
                      ],
                    ),
                  ],
                  if (widget.product == 'plus' || widget.product == 'merch') ...[
                    const SizedBox(height: 12),
                    TextField(
                      controller: _codeCtrl,
                      textCapitalization: TextCapitalization.characters,
                      decoration: InputDecoration(
                        labelText: 'Kampanya kodu',
                        hintText: 'Varsa gir',
                        border: const OutlineInputBorder(),
                        suffixIcon: IconButton(
                          tooltip: 'Uygula',
                          onPressed: _previewCode,
                          icon: const Icon(Icons.check_circle_outline),
                        ),
                      ),
                      onSubmitted: (_) => _previewCode(),
                    ),
                    if (_previewNote != null) ...[
                      const SizedBox(height: 6),
                      Text(
                        _previewNote!,
                        style: const TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: AppColors.navy,
                        ),
                      ),
                    ],
                    if (_myCodes.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      const Text(
                        'Sana tanımlı çekler',
                        style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          for (final c in _myCodes)
                            ActionChip(
                              label: Text('${c['code']}'),
                              onPressed: () {
                                _codeCtrl.text = '${c['code']}';
                                _previewCode();
                              },
                            ),
                        ],
                      ),
                    ],
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
