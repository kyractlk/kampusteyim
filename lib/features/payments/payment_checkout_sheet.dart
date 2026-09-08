import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/constants/app_info.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/breakpoints.dart';
import 'payment_webview_screen.dart';
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
  String? shipAddress,
  String? shipDistrict,
  String? shipPhone,
  bool? refundsAllowed,
}) async {
  final sheet = _CheckoutSheet(
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
    shipAddress: shipAddress,
    shipDistrict: shipDistrict,
    shipPhone: shipPhone,
    refundsAllowed: refundsAllowed,
  );
  if (kIsWeb || AppBreakpoints.isWide(context)) {
    await showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480, maxHeight: 720),
          child: sheet,
        ),
      ),
    );
    return;
  }
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => sheet,
  );
}

Future<void> openPaymentLink(
  BuildContext context, {
  required String payUrl,
  String? orderId,
  String? product,
}) async {
  if (kIsWeb) {
    final uri = Uri.tryParse(payUrl);
    if (uri == null) return;
    await launchUrl(uri, webOnlyWindowName: '_blank');
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Ödeme yeni sekmede açıldı. Kartı girdikten sonra bu sekmeye dön.',
          ),
        ),
      );
    }
    return;
  }
  await Navigator.of(context).push<void>(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => PaymentWebViewScreen(
        payUrl: payUrl,
        orderId: orderId,
        product: product,
      ),
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
    this.shipAddress,
    this.shipDistrict,
    this.shipPhone,
    this.refundsAllowed,
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
  final String? shipAddress;
  final String? shipDistrict;
  final String? shipPhone;
  final bool? refundsAllowed;

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
  bool _salesAccepted = false;

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
    if (!_salesAccepted) {
      setState(() => _error = 'Satış sözleşmesini onayla.');
      return;
    }
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
        shipAddress: widget.shipAddress,
        shipDistrict: widget.shipDistrict,
        shipPhone: widget.shipPhone,
        salesTermsAccepted: _salesAccepted,
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
      if ((order.provider == 'paytr' || order.provider == 'shopier') &&
          payLink != null) {
        if (!mounted) return;
        final nav = Navigator.of(context);
        nav.pop();
        await openPaymentLink(
          context,
          payUrl: payLink,
          orderId: order.orderId,
          product: widget.product,
        );
        return;
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
    final maxH = MediaQuery.sizeOf(context).height * 0.92;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(20, 8, 20, 20 + bottom),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxH),
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
                    const Text(
                      'Süre seç',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final p in _pub!.plusPlans)
                          Builder(
                            builder: (context) {
                              final months =
                                  (p['months'] as num?)?.toInt() ?? 1;
                              final selected = _months == months;
                              return ChoiceChip(
                                label: Text(
                                  '${p['label']}'
                                  '${p['amount'] != null ? ' · ${(p['amount'] as num).toStringAsFixed(0)}₺' : ''}',
                                  style: TextStyle(
                                    color: selected
                                        ? Colors.white
                                        : AppColors.textPrimary,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                selected: selected,
                                selectedColor: AppColors.navy,
                                backgroundColor: AppColors.surfaceMuted,
                                checkmarkColor: Colors.white,
                                side: BorderSide(
                                  color: selected
                                      ? AppColors.navy
                                      : AppColors.border,
                                ),
                                onSelected: (_) =>
                                    setState(() => _months = months),
                              );
                            },
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
                    Text(
                      widget.refundsAllowed == true
                          ? 'Ödeyen hesap katılımcı hesaptır. Bu etkinlikte iade yapılabilir; onaylanan iadede organizatör bakiyesinden net tutar düşülür, platform komisyonu iade edilmez.'
                          : 'Ödeyen hesap katılımcı hesaptır. Bu etkinlikte iade / iptal yoktur.',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: _salesAccepted,
                    onChanged: (v) =>
                        setState(() => _salesAccepted = v == true),
                    controlAffinity: ListTileControlAffinity.leading,
                    title: Wrap(
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        const Text('Satış sözleşmesini okudum, kabul ediyorum. '),
                        GestureDetector(
                          onTap: () {
                            final uri = Uri.parse(AppInfo.salesUrl);
                            launchUrl(uri, mode: LaunchMode.externalApplication);
                          },
                          child: const Text(
                            'Sözleşmeyi aç',
                            style: TextStyle(
                              color: AppColors.cyan,
                              fontWeight: FontWeight.w800,
                              decoration: TextDecoration.underline,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
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
                      onPressed: _busy || _selected == null || !_salesAccepted
                          ? null
                          : _pay,
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
                          ? (kIsWeb
                              ? 'Ödeme tarayıcıda yeni sekmede açılır.'
                              : 'Ödeme ekranı uygulamada açılır; kart bilgisini güvenle girebilirsin.')
                          : (kIsWeb
                              ? 'Shopier ödeme ekranı yeni sekmede açılır.'
                              : 'Shopier ödeme ekranı uygulamada açılır.'),
                    ),
                    const SizedBox(height: 12),
                    FilledButton(
                      onPressed: () async {
                        final url = _order!.payUrl ?? _order!.iframeUrl;
                        if (url == null) return;
                        final nav = Navigator.of(context);
                        nav.pop();
                        await openPaymentLink(
                          context,
                          payUrl: url,
                          orderId: _order!.orderId,
                          product: widget.product,
                        );
                      },
                      child: const Text('Ödeme ekranını aç'),
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
