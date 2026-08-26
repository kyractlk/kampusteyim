import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme/app_colors.dart';
import 'payments_service.dart';

/// Admin · PayTR / Shopier / IBAN — anahtarlar + callback URL’leri
class AdminPaymentsPanel extends StatefulWidget {
  const AdminPaymentsPanel({super.key});

  @override
  State<AdminPaymentsPanel> createState() => _AdminPaymentsPanelState();
}

class _AdminPaymentsPanelState extends State<AdminPaymentsPanel> {
  final _iban = TextEditingController();
  final _ibanHolder = TextEditingController();
  final _ibanBank = TextEditingController();
  final _ibanNote = TextEditingController();
  final _paytrMerchantId = TextEditingController();
  final _paytrKey = TextEditingController();
  final _paytrSalt = TextEditingController();
  final _shopierKey = TextEditingController();
  final _shopierSecret = TextEditingController();
  final _shopierIndex = TextEditingController(text: '1');
  final _productName = TextEditingController(text: 'KampüsteyimPlus');
  final _amount = TextEditingController();
  final _days = TextEditingController(text: '30');
  final _okUrl = TextEditingController();
  final _failUrl = TextEditingController();
  final _paytrCb = TextEditingController();
  final _shopierCb = TextEditingController();
  final _shopierPay = TextEditingController();
  final _installmentToken = TextEditingController(
    text: 'cf322a02b0690c8492d89adcba8a56ba9d6c7117e932f9072c4e43edf2d86a86',
  );

  String _active = 'paytr';
  final Set<String> _enabled = {'paytr'};
  bool _paytrTest = false;
  bool _marketInApp = true;
  bool _merchPaytr = true;
  bool _installmentTable = false;
  bool _installmentsDefault = true;
  bool _loading = true;
  bool _saving = false;
  bool _paytrKeySet = false;
  bool _paytrSaltSet = false;
  bool _shopierKeySet = false;
  bool _shopierSecretSet = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final c in [
      _iban,
      _ibanHolder,
      _ibanBank,
      _ibanNote,
      _paytrMerchantId,
      _paytrKey,
      _paytrSalt,
      _shopierKey,
      _shopierSecret,
      _shopierIndex,
      _productName,
      _amount,
      _days,
      _okUrl,
      _failUrl,
      _paytrCb,
      _shopierCb,
      _shopierPay,
      _installmentToken,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final cfg = await PaymentsService.getAdmin();
      _apply(cfg);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ödeme ayarları yüklenemedi: $e')),
        );
      }
    }
    if (mounted) setState(() => _loading = false);
  }

  void _apply(PaymentsAdminConfig cfg) {
    _active = cfg.activeProvider;
    _enabled
      ..clear()
      ..addAll(cfg.enabledProviders);
    if (_enabled.isEmpty) _enabled.addAll(['iban', 'paytr', 'shopier']);
    _iban.text = cfg.iban;
    _ibanHolder.text = cfg.ibanHolder;
    _ibanBank.text = cfg.ibanBank;
    _ibanNote.text = cfg.ibanNote;
    _paytrMerchantId.text = cfg.paytrMerchantId;
    _paytrTest = cfg.paytrTestMode;
    _marketInApp = cfg.raw['marketInAppVisible'] != false;
    _merchPaytr = cfg.raw['merchPaytrEnabled'] != false;
    _installmentTable = cfg.raw['installmentTableEnabled'] == true;
    _installmentsDefault = cfg.raw['installmentsDefaultEnabled'] != false;
    final tok = '${cfg.raw['installmentTableToken'] ?? ''}'.trim();
    if (tok.isNotEmpty) _installmentToken.text = tok;
    _paytrKey.clear();
    _paytrSalt.clear();
    _shopierKey.clear();
    _shopierSecret.clear();
    _shopierIndex.text = '${cfg.shopierWebsiteIndex}';
    _productName.text = cfg.plusProductName;
    _amount.text = cfg.plusAmount > 0 ? cfg.plusAmount.toStringAsFixed(2) : '';
    _days.text = '${cfg.plusDays}';
    final d = cfg.defaults;
    _okUrl.text = cfg.okUrl.isNotEmpty ? cfg.okUrl : '${d['okUrl'] ?? ''}';
    _failUrl.text = cfg.failUrl.isNotEmpty
        ? cfg.failUrl
        : '${d['failUrl'] ?? ''}';
    _paytrCb.text = cfg.paytrCallbackUrl.isNotEmpty
        ? cfg.paytrCallbackUrl
        : '${d['paytrCallbackUrl'] ?? ''}';
    _shopierCb.text = cfg.shopierCallbackUrl.isNotEmpty
        ? cfg.shopierCallbackUrl
        : '${d['shopierCallbackUrl'] ?? ''}';
    _shopierPay.text = cfg.shopierPayPageUrl.isNotEmpty
        ? cfg.shopierPayPageUrl
        : '${d['shopierPayPageUrl'] ?? ''}';
    _paytrKeySet = cfg.paytrKeySet;
    _paytrSaltSet = cfg.paytrSaltSet;
    _shopierKeySet = cfg.shopierKeySet;
    _shopierSecretSet = cfg.shopierSecretSet;
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final payload = <String, dynamic>{
        'activeProvider': _active,
        'enabledProviders': _enabled.toList(),
        'iban': _iban.text.trim(),
        'ibanHolder': _ibanHolder.text.trim(),
        'ibanBank': _ibanBank.text.trim(),
        'ibanNote': _ibanNote.text.trim(),
        'paytrMerchantId': _paytrMerchantId.text.trim(),
        'paytrTestMode': _paytrTest,
        'marketInAppVisible': _marketInApp,
        'merchPaytrEnabled': _merchPaytr,
        'installmentTableEnabled': _installmentTable,
        'installmentTableToken': _installmentToken.text.trim(),
        'installmentsDefaultEnabled': _installmentsDefault,
        'shopierWebsiteIndex': int.tryParse(_shopierIndex.text.trim()) ?? 1,
        'plusProductName': _productName.text.trim(),
        'plusAmount':
            double.tryParse(_amount.text.trim().replaceAll(',', '.')) ?? 0,
        'plusDays': int.tryParse(_days.text.trim()) ?? 30,
        'okUrl': _okUrl.text.trim(),
        'failUrl': _failUrl.text.trim(),
        'paytrCallbackUrl': _paytrCb.text.trim(),
        'shopierCallbackUrl': _shopierCb.text.trim(),
        'shopierPayPageUrl': _shopierPay.text.trim(),
      };
      if (_paytrKey.text.trim().isNotEmpty) {
        payload['paytrMerchantKey'] = _paytrKey.text.trim();
      }
      if (_paytrSalt.text.trim().isNotEmpty) {
        payload['paytrMerchantSalt'] = _paytrSalt.text.trim();
      }
      if (_shopierKey.text.trim().isNotEmpty) {
        payload['shopierApiKey'] = _shopierKey.text.trim();
      }
      if (_shopierSecret.text.trim().isNotEmpty) {
        payload['shopierApiSecret'] = _shopierSecret.text.trim();
      }
      final cfg = await PaymentsService.updateAdmin(payload);
      _apply(cfg);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Ödeme ayarları kaydedildi')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Kaydedilemedi: $e')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _copy(String label, String value) async {
    await Clipboard.setData(ClipboardData(text: value));
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('$label kopyalandı')));
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Ödeme ayarları',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w900,
              ),
        ),
        const SizedBox(height: 4),
        const Text(
          'Market ve Plus satışları PayTR ile işlenir. Anahtarlar gizli saklanır.',
          style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
        ),
        const SizedBox(height: 16),
        _card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: _paytrTest
                          ? const Color(0xFFFEF3C7)
                          : const Color(0xFFDCFCE7),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      _paytrTest ? 'TEST MODU' : 'CANLI',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 11,
                        color: _paytrTest
                            ? const Color(0xFF92400E)
                            : const Color(0xFF166534),
                      ),
                    ),
                  ),
                  const Spacer(),
                  Text(
                    _paytrKeySet && _paytrSaltSet && _paytrMerchantId.text.isNotEmpty
                        ? 'PayTR hazır'
                        : 'PayTR eksik',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: _paytrKeySet && _paytrSaltSet
                          ? AppColors.navy
                          : AppColors.crimson,
                    ),
                  ),
                ],
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('PayTR test modu'),
                subtitle: Text(
                  _paytrTest
                      ? 'Gerçek tahsilat yok — canlıya alınca kapat'
                      : 'Canlı kart ödemesi açık',
                ),
                value: _paytrTest,
                onChanged: (v) => setState(() => _paytrTest = v),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Uygulama içi Market'),
                subtitle: const Text('Kapalıysa Ayarlar → Market gizlenir'),
                value: _marketInApp,
                onChanged: (v) => setState(() => _marketInApp = v),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Taksit (varsayılan)'),
                subtitle: const Text(
                  'Kapalıysa tüm siparişlerde peşin (ürün özel açabilir)',
                ),
                value: _installmentsDefault,
                onChanged: (v) => setState(() => _installmentsDefault = v),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Ödeme sayfasında taksit tablosu'),
                subtitle: const Text('PayTR taksit karşılaştırma kutusu'),
                value: _installmentTable,
                onChanged: (v) => setState(() => _installmentTable = v),
              ),
              if (_installmentTable) ...[
                const SizedBox(height: 6),
                TextField(
                  controller: _installmentToken,
                  decoration: const InputDecoration(
                    labelText: 'Taksit tablosu token',
                    border: OutlineInputBorder(),
                    helperText: 'PayTR panel → Taksit ayarları',
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 14),
        _section('Plus fiyatı'),
        TextField(
          controller: _productName,
          decoration: const InputDecoration(
            labelText: 'Ürün adı',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _amount,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'Aylık tutar (TL)',
                  border: OutlineInputBorder(),
                  helperText: '1/3/6/12 ay otomatik çarpılır',
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: _days,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(
                  labelText: '1 ay = gün',
                  border: OutlineInputBorder(),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        _section('PayTR kimlik bilgileri'),
        TextField(
          controller: _paytrMerchantId,
          decoration: const InputDecoration(
            labelText: 'Merchant ID',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _paytrKey,
          decoration: InputDecoration(
            labelText: _paytrKeySet
                ? 'Merchant Key (kayıtlı · değiştirmek için yaz)'
                : 'Merchant Key',
            border: const OutlineInputBorder(),
          ),
          obscureText: true,
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _paytrSalt,
          decoration: InputDecoration(
            labelText: _paytrSaltSet
                ? 'Merchant Salt (kayıtlı · değiştirmek için yaz)'
                : 'Merchant Salt',
            border: const OutlineInputBorder(),
          ),
          obscureText: true,
        ),
        const SizedBox(height: 16),
        _section('Dönüş URL’leri'),
        const Text(
          'PayTR Mağaza Paneli → Bildirim URL’ye callback adresini yapıştır.',
          style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
        ),
        const SizedBox(height: 8),
        _urlField('Başarı (ok) URL', _okUrl),
        _urlField('Hata (fail) URL', _failUrl),
        _urlField(
          'PayTR bildirim (Callback) URL',
          _paytrCb,
          hint: 'PayTR paneline yapıştır',
          copyOnlyImportant: true,
        ),
        const SizedBox(height: 8),
        Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: const Text(
              'Gelişmiş / eski yöntemler',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
            ),
            subtitle: const Text(
              'Shopier ve IBAN — Market’te kullanılmıyor',
              style: TextStyle(fontSize: 12),
            ),
            children: [
              const SizedBox(height: 4),
              const Text('Aktif / açık yöntemler', style: TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                children: [
                  for (final p in ['paytr', 'shopier', 'iban'])
                    ChoiceChip(
                      label: Text(p.toUpperCase()),
                      selected: _active == p,
                      onSelected: (_) => setState(() => _active = p),
                    ),
                ],
              ),
              Wrap(
                spacing: 4,
                children: [
                  for (final p in ['paytr', 'shopier', 'iban'])
                    FilterChip(
                      label: Text(p.toUpperCase()),
                      selected: _enabled.contains(p),
                      onSelected: (v) => setState(() {
                        if (v) {
                          _enabled.add(p);
                        } else {
                          _enabled.remove(p);
                        }
                      }),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              _section('Shopier'),
              TextField(
                controller: _shopierKey,
                decoration: InputDecoration(
                  labelText: _shopierKeySet
                      ? 'API Key (kayıtlı)'
                      : 'API Key',
                  border: const OutlineInputBorder(),
                ),
                obscureText: true,
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _shopierSecret,
                decoration: InputDecoration(
                  labelText: _shopierSecretSet
                      ? 'API Secret (kayıtlı)'
                      : 'API Secret',
                  border: const OutlineInputBorder(),
                ),
                obscureText: true,
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _shopierIndex,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Website index',
                  border: OutlineInputBorder(),
                ),
              ),
              _urlField('Shopier callback', _shopierCb),
              _urlField('Shopier pay page', _shopierPay),
              const SizedBox(height: 8),
              _section('IBAN'),
              TextField(
                controller: _iban,
                decoration: const InputDecoration(
                  labelText: 'IBAN',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _ibanHolder,
                decoration: const InputDecoration(
                  labelText: 'Hesap sahibi',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _ibanBank,
                decoration: const InputDecoration(
                  labelText: 'Banka',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _ibanNote,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: 'Kullanıcıya not',
                  border: OutlineInputBorder(),
                ),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Merch için PayTR'),
                subtitle: const Text('Kapalıysa merch IBAN’a düşer (önerilmez)'),
                value: _merchPaytr,
                onChanged: (v) => setState(() => _merchPaytr = v),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Ödeme ayarlarını kaydet'),
        ),
      ],
    );
  }

  Widget _card({required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surfaceMuted,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: child,
    );
  }

  Widget _section(String title) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
  );

  Widget _urlField(
    String label,
    TextEditingController c, {
    String? hint,
    bool copyOnlyImportant = false,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: TextField(
        controller: c,
        decoration: InputDecoration(
          labelText: label,
          helperText: hint,
          border: const OutlineInputBorder(),
          suffixIcon: IconButton(
            tooltip: 'Kopyala',
            icon: Icon(
              Icons.copy,
              color: copyOnlyImportant ? AppColors.navy : null,
            ),
            onPressed: () => _copy(label, c.text.trim()),
          ),
        ),
      ),
    );
  }
}

/// Ticaret · reklam / etkinlik IBAN onayları.
class AdminPaymentReviewsPanel extends StatelessWidget {
  const AdminPaymentReviewsPanel({
    super.key,
    this.includeProducts = const {'ad', 'event'},
    this.scrollable = true,
  });

  final Set<String> includeProducts;
  final bool scrollable;

  @override
  Widget build(BuildContext context) {
    return _PendingIbanOrders(
      includeProducts: includeProducts,
      scrollable: scrollable,
    );
  }
}

/// Plus sekmesi · yalnızca KampüsteyimPlus IBAN onayları.
class AdminPlusPaymentReviewsPanel extends StatelessWidget {
  const AdminPlusPaymentReviewsPanel({super.key});

  @override
  Widget build(BuildContext context) {
    return const _PendingIbanOrders(
      includeProducts: {'plus'},
      scrollable: false,
    );
  }
}

class _PendingIbanOrders extends StatelessWidget {
  const _PendingIbanOrders({
    required this.includeProducts,
    this.scrollable = false,
  });

  final Set<String> includeProducts;
  final bool scrollable;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('payment_orders')
          .where('status', isEqualTo: 'awaiting_review')
          .orderBy('createdAt', descending: true)
          .limit(200)
          .snapshots(),
      builder: (context, snap) {
        if (snap.hasError) {
          return Text(
            'Liste yüklenemedi (index gerekebilir): ${snap.error}',
            style: const TextStyle(color: Colors.orange, fontSize: 12),
          );
        }
        if (!snap.hasData) {
          return const Padding(
            padding: EdgeInsets.all(12),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        final docs = snap.data!.docs
            .where(
              (d) => includeProducts.contains(
                '${d.data()['product'] ?? 'plus'}'.toLowerCase(),
              ),
            )
            .toList();
        if (docs.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Text(
                includeProducts.length == 1 && includeProducts.contains('plus')
                    ? 'Bekleyen Plus ödemesi yok.'
                    : 'Bekleyen ticari ödeme yok.',
                style: const TextStyle(color: AppColors.textSecondary),
              ),
            ),
          );
        }
        final children = [
          for (final d in docs) _OrderTile(id: d.id, data: d.data()),
        ];
        if (scrollable) {
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            children: children,
          );
        }
        return Column(children: children);
      },
    );
  }
}

class _OrderTile extends StatefulWidget {
  const _OrderTile({required this.id, required this.data});
  final String id;
  final Map<String, dynamic> data;

  @override
  State<_OrderTile> createState() => _OrderTileState();
}

class _OrderTileState extends State<_OrderTile> {
  bool _busy = false;

  Future<void> _act(bool approve) async {
    setState(() => _busy = true);
    try {
      await PaymentsService.reviewOrder(orderId: widget.id, approve: approve);
      if (mounted) {
        final product = '${widget.data['product'] ?? 'plus'}';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              approve
                  ? switch (product) {
                      'plus' => 'Onaylandı · Plus açıldı',
                      'ad' => 'Onaylandı · reklam ödemesi doğrulandı',
                      'event' => 'Onaylandı · etkinlik ödemesi doğrulandı',
                      _ => 'Ödeme onaylandı',
                    }
                  : 'Ödeme reddedildi',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Hata: $e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final amount = widget.data['amount'];
    final email = '${widget.data['email'] ?? ''}';
    final code = '${widget.data['ibanReference'] ?? ''}';
    final uid = '${widget.data['uid'] ?? ''}';
    final product = '${widget.data['product'] ?? 'plus'}';
    final productLabel = switch (product) {
      'ad' => 'Reklam',
      'event' => 'Etkinlik',
      'plus' => 'KampüsteyimPlus',
      _ => product,
    };
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '$productLabel · $amount TL${email.isNotEmpty ? ' · $email' : ''}',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            SelectableText('Kod: $code'),
            Text('uid: $uid', style: const TextStyle(fontSize: 11)),
            const SizedBox(height: 8),
            Row(
              children: [
                FilledButton(
                  onPressed: _busy ? null : () => _act(true),
                  child: const Text('Onayla'),
                ),
                const SizedBox(width: 8),
                OutlinedButton(
                  onPressed: _busy ? null : () => _act(false),
                  child: const Text('Reddet'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
