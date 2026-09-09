import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../../core/widgets/panel_chrome.dart';
import '../auth/data/auth_provider.dart';
import '../feed/feed_provider.dart';
import 'commerce_service.dart';

/// Firma organizatörü: bakiye, satışlar, IBAN, çekim, indirim
class CompanyOrganizerHubScreen extends StatefulWidget {
  const CompanyOrganizerHubScreen({super.key});

  @override
  State<CompanyOrganizerHubScreen> createState() =>
      _CompanyOrganizerHubScreenState();
}

class _CompanyOrganizerHubScreenState extends State<CompanyOrganizerHubScreen> {
  Map<String, dynamic>? _data;
  bool _loading = true;
  String? _error;
  String? _salesEventId;
  /// null = karşılama menüsü; aksi halde açık bölüm.
  String? _section;

  final _iban = TextEditingController();
  final _holder = TextEditingController();
  final _bank = TextEditingController();
  final _withdraw = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _iban.dispose();
    _holder.dispose();
    _bank.dispose();
    _withdraw.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await CommerceService.getOrganizerDashboard();
      final s = Map<String, dynamic>.from(data['settings'] as Map? ?? {});
      _iban.text = '${s['payoutIban'] ?? ''}';
      _holder.text = '${s['payoutIbanHolder'] ?? ''}';
      _bank.text = '${s['payoutBank'] ?? ''}';
      setState(() => _data = data);
    } catch (e) {
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Map<String, dynamic> get _settings =>
      Map<String, dynamic>.from(_data?['settings'] as Map? ?? {});

  Future<void> _saveIban() async {
    try {
      await CommerceService.savePayoutIban(
        iban: _iban.text.trim(),
        holder: _holder.text.trim(),
        bank: _bank.text.trim(),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Çekim IBAN kaydedildi')),
      );
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Hata: $e')),
      );
    }
  }

  Future<void> _doWithdraw() async {
    final amount = double.tryParse(_withdraw.text.trim().replaceAll(',', '.'));
    if (amount == null) return;
    try {
      await CommerceService.requestWithdrawal(amount);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Çekim talebi yönetime iletildi')),
      );
      _withdraw.clear();
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Hata: $e')),
      );
    }
  }

  String _statusLabel(String raw) {
    switch (raw) {
      case 'used':
      case 'checked_in':
        return 'giriş yapıldı';
      case 'refunded':
        return 'iade';
      case 'cancelled':
        return 'iptal';
      case 'active':
        return 'aktif';
      case 'pending':
        return 'beklemede';
      case 'paid':
      case 'approved':
        return 'ödendi';
      case 'rejected':
        return 'reddedildi';
      default:
        return raw.isEmpty ? 'aktif' : raw;
    }
  }

  String _csvCell(Object? v) {
    final s = '${v ?? ''}'.replaceAll('"', '""');
    return '"$s"';
  }

  Future<void> _exportCsv() async {
    final tickets = (_data?['tickets'] as List? ?? const [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    final buf = StringBuffer(
      'etkinlik,biletId,ad,eposta,paket,tutar,durum,kisaKod,olusturma,giris\n',
    );
    for (final t in tickets) {
      buf.writeln(
        [
          _csvCell(t['eventTitle']),
          _csvCell(t['id'] ?? t['ticketId']),
          _csvCell(t['userName']),
          _csvCell(t['userEmail']),
          _csvCell(t['tierLabel']),
          t['amountPaid'] ?? 0,
          _csvCell(_statusLabel('${t['status'] ?? ''}')),
          _csvCell(t['shortCode']),
          _csvCell(t['createdAt']),
          _csvCell(t['checkedInAt']),
        ].join(','),
      );
    }
    if (tickets.isEmpty) {
      final sales = (_data?['salesByEvent'] as List? ?? const []);
      buf.writeln('# ozet');
      buf.writeln('eventId,eventTitle,netBilet,iadeBilet,netCiro,iadeTutar');
      for (final raw in sales) {
        final e = Map<String, dynamic>.from(raw as Map);
        buf.writeln(
          '${_csvCell(e['eventId'])},${_csvCell(e['eventTitle'])},'
          '${e['count'] ?? 0},${e['refundedCount'] ?? 0},'
          '${e['revenue'] ?? 0},${e['refundedRevenue'] ?? 0}',
        );
      }
    }
    await Clipboard.setData(ClipboardData(text: buf.toString()));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Satış CSV panoya kopyalandı (iadeler dahil)'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final me = context.watch<AuthProvider>().user;
    if (me == null || !me.isCompany) {
      return const Scaffold(body: Center(child: Text('Firma hesabı gerekli')));
    }
    if (!me.isEventOrganizer) {
      return Scaffold(
        appBar: AppBar(title: const Text('Organizatör')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.lock_outline, size: 42, color: AppColors.navy),
                const SizedBox(height: 12),
                const Text(
                  'Bu bölüm yalnızca etkinlik organizatörü firmalar içindir.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontWeight: FontWeight.w700, height: 1.35),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Bilet, bakiye ve etkinlik yönetimi burada yer alır. '
                  'Reklam ve iş ilanları için firma paneline dönün.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.textSecondary, height: 1.35),
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () => context.go('/firma/ads'),
                  child: const Text('Reklam paneline git'),
                ),
                TextButton(
                  onPressed: () => context.go('/firma/dashboard'),
                  child: const Text('Firma paneline dön'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_error != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Organizatör')),
        body: Center(child: Text(_error!)),
      );
    }

    final s = _settings;
    final balance = (s['balance'] as num?)?.toDouble() ?? 0;
    final minW = (s['minWithdrawal'] as num?)?.toDouble() ?? 500;
    final commission = (s['commissionPercent'] as num?)?.toDouble() ?? 10;
    final hasIban = s['hasPayoutIban'] == true;
    final sales = (_data?['salesByEvent'] as List? ?? const [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    final withdrawals = (_data?['withdrawals'] as List? ?? const []);
    final discounts = (_data?['discounts'] as List? ?? const []);
    final events = context
        .watch<FeedProvider>()
        .events
        .where((e) => e.organizerCompanyId == me.id)
        .toList();
    final salesEventId = _salesEventId ??
        (sales.isNotEmpty ? '${sales.first['eventId']}' : null);
    Map<String, dynamic>? selectedSales;
    if (sales.isNotEmpty) {
      selectedSales = sales.firstWhere(
        (e) => '${e['eventId']}' == salesEventId,
        orElse: () => sales.first,
      );
    }

    final sectionTitle = switch (_section) {
      'balance' => 'Bakiye',
      'iban' => 'Çekim hesabı',
      'withdraw' => 'Çekim talebi',
      'sales' => 'Satışlar',
      'discounts' => 'İndirim kodları',
      _ => 'Organizatör paneli',
    };

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(sectionTitle),
        leading: _section == null
            ? null
            : IconButton(
                icon: const Icon(Icons.arrow_back_rounded),
                onPressed: () => setState(() => _section = null),
              ),
        actions: [
          if (_section == 'sales' || _section == null)
            IconButton(
              tooltip: 'CSV kopyala',
              onPressed: _exportCsv,
              icon: const Icon(Icons.download_outlined),
            ),
          IconButton(
            onPressed: _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      floatingActionButton: _section == null
          ? FloatingActionButton.extended(
              onPressed: () => context.push('/firma/organizer/scan'),
              icon: const Icon(Icons.qr_code_scanner),
              label: const Text('QR doğrula'),
            )
          : null,
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
        children: [
          if (_section == null) ...[
            const PanelWelcomeHeader(
              title: 'Organizatör paneli',
              subtitle: 'Bakiye, satış, çekim ve bilet işlemleri',
            ),
            if (!hasIban) ...[
              const SizedBox(height: 12),
              PanelCard(
                color: const Color(0xFFFFF4E5),
                child: const Row(
                  children: [
                    Icon(Icons.info_outline, color: Color(0xFFB45309)),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Etkinlik açmadan önce çekim IBAN’ını kaydet.',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          height: 1.35,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 12),
            PanelNavTile(
              accent: true,
              icon: Icons.qr_code_scanner_rounded,
              title: 'Kapı girişi',
              subtitle: 'Bilet QR doğrula',
              onTap: () => context.push('/firma/organizer/scan'),
            ),
            const SizedBox(height: 10),
            PanelNavTile(
              icon: Icons.account_balance_wallet_outlined,
              title: 'Bakiye',
              subtitle: '${balance.toStringAsFixed(2)} TL',
              onTap: () => setState(() => _section = 'balance'),
            ),
            const SizedBox(height: 10),
            PanelNavTile(
              icon: Icons.account_balance_outlined,
              title: 'Çekim hesabı',
              subtitle: hasIban ? 'IBAN kayıtlı' : 'IBAN ekle',
              onTap: () => setState(() => _section = 'iban'),
            ),
            const SizedBox(height: 10),
            PanelNavTile(
              icon: Icons.payments_outlined,
              title: 'Çekim talebi',
              subtitle: 'Bakiyeden talep oluştur',
              onTap: () => setState(() => _section = 'withdraw'),
            ),
            const SizedBox(height: 10),
            PanelNavTile(
              icon: Icons.receipt_long_outlined,
              title: 'Satışlar',
              subtitle: 'Etkinlik bazlı bilet ve iadeler',
              onTap: () => setState(() => _section = 'sales'),
            ),
            const SizedBox(height: 10),
            PanelNavTile(
              icon: Icons.local_offer_outlined,
              title: 'İndirim kodları',
              subtitle: 'Kod oluştur ve takip et',
              onTap: () => setState(() => _section = 'discounts'),
            ),
            const SizedBox(height: 10),
            PanelNavTile(
              icon: Icons.campaign_outlined,
              title: 'Reklamlar',
              subtitle: 'Firma reklam paneline git',
              onTap: () => context.push('/firma/ads'),
            ),
            const SizedBox(height: 10),
            PanelNavTile(
              icon: Icons.group_add_outlined,
              title: 'Yönetim kadrosu',
              subtitle: 'Üye davet et ve yetki ver',
              onTap: () => context.push('/firma/staff'),
            ),
          ] else if (_section == 'balance') ...[
            PanelCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Bakiye',
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${balance.toStringAsFixed(2)} TL',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w900,
                        ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Komisyon %${commission.toStringAsFixed(0)} · '
                    'Minimum çekim ${minW.toStringAsFixed(0)} TL',
                    style: const TextStyle(color: AppColors.textSecondary),
                  ),
                ],
              ),
            ),
          ] else if (_section == 'iban') ...[
            PanelCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const PanelSectionLabel(
                    'Çekim hesabı',
                    subtitle: 'Bilet gelirleri bu IBAN’a aktarılır',
                  ),
                  TextField(
                    controller: _iban,
                    decoration: const InputDecoration(labelText: 'IBAN'),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _holder,
                    decoration:
                        const InputDecoration(labelText: 'Hesap sahibi'),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _bank,
                    decoration: const InputDecoration(labelText: 'Banka'),
                  ),
                  const SizedBox(height: 12),
                  FilledButton(
                    onPressed: _saveIban,
                    child: const Text('IBAN kaydet'),
                  ),
                ],
              ),
            ),
          ] else if (_section == 'withdraw') ...[
            PanelCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const PanelSectionLabel(
                    'Çekim talebi',
                    subtitle: 'Bakiyenden yönetim onayına gönderilir',
                  ),
                  TextField(
                    controller: _withdraw,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: InputDecoration(
                      labelText: 'Tutar',
                      hintText: 'En az ${minW.toStringAsFixed(0)} TL',
                      prefixIcon: const Icon(Icons.payments_outlined),
                    ),
                  ),
                  const SizedBox(height: 12),
                  FilledButton(
                    onPressed: balance >= minW ? _doWithdraw : null,
                    child: const Text('Talep et'),
                  ),
                  if (withdrawals.isNotEmpty) ...[
                    const SizedBox(height: 14),
                    const Text(
                      'Son talepler',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 6),
                    ...withdrawals.take(5).map((raw) {
                      final w = Map<String, dynamic>.from(raw as Map);
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                '${w['amount']} TL',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            Text(
                              _statusLabel('${w['status']}'),
                              style: const TextStyle(
                                color: AppColors.textSecondary,
                                fontSize: 12.5,
                              ),
                            ),
                          ],
                        ),
                      );
                    }),
                  ],
                ],
              ),
            ),
          ] else if (_section == 'sales') ...[
          PanelCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: PanelSectionLabel(
                        'Satışlar',
                        subtitle: 'Etkinlik seç, iadeler ayrı görünür',
                      ),
                    ),
                    TextButton(onPressed: _exportCsv, child: const Text('CSV')),
                  ],
                ),
                if (sales.isEmpty)
                  const Text(
                    'Henüz bilet satışı yok.',
                    style: TextStyle(color: AppColors.textSecondary),
                  )
                else ...[
                  if (sales.length > 1)
                    DropdownButtonFormField<String>(
                      initialValue: salesEventId,
                      items: [
                        for (final e in sales)
                          DropdownMenuItem(
                            value: '${e['eventId']}',
                            child: Text(
                              '${e['eventTitle']}',
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                      onChanged: (v) => setState(() => _salesEventId = v),
                      decoration: const InputDecoration(labelText: 'Etkinlik'),
                    ),
                  if (selectedSales != null) ...[
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _pill(
                          '${selectedSales['count'] ?? 0} net bilet',
                          AppColors.navy,
                        ),
                        _pill(
                          '${selectedSales['refundedCount'] ?? 0} iade',
                          AppColors.crimson,
                        ),
                        _pill(
                          '${selectedSales['revenue'] ?? 0} TL net',
                          const Color(0xFF166534),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    ...((selectedSales['buyers'] as List? ?? const []).map((bRaw) {
                      final b = Map<String, dynamic>.from(bRaw as Map);
                      final st = '${b['status'] ?? ''}';
                      final refunded = st == 'refunded' || st == 'cancelled';
                      final used =
                          st == 'used' || st == 'checked_in' || b['checkedInAt'] != null;
                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                        title: Text('${b['name'] ?? b['email'] ?? b['uid']}'),
                        subtitle: Text(
                          [
                            '${b['email'] ?? ''}',
                            '${b['tierLabel'] ?? ''}',
                            '${b['amount']} TL',
                            _statusLabel(st),
                          ].where((x) => x.trim().isNotEmpty).join(' · '),
                        ),
                        trailing: Icon(
                          refunded
                              ? Icons.undo_rounded
                              : used
                                  ? Icons.verified
                                  : Icons.confirmation_number_outlined,
                          color: refunded
                              ? AppColors.crimson
                              : used
                                  ? AppColors.lime
                                  : AppColors.textSecondary,
                        ),
                      );
                    })),
                  ],
                ],
              ],
            ),
          ),
          const SizedBox(height: 12),
          PanelCard(
            onTap: () => context.push('/firma/ads'),
            child: const Row(
              children: [
                Icon(Icons.campaign_outlined, color: AppColors.navy),
                SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Reklamlar',
                        style: TextStyle(fontWeight: FontWeight.w800),
                      ),
                      Text(
                        'Görsel yükleme ve yayın talepleri',
                        style: TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 12.5,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right),
              ],
            ),
          ),
          ] else if (_section == 'discounts') ...[
          PanelCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const PanelSectionLabel('İndirim kodları'),
                FilledButton.tonal(
                  onPressed: events.isEmpty
                      ? null
                      : () => _createDiscount(
                            context,
                            events.map((e) => e.id).toList(),
                            events.map((e) => e.title).toList(),
                          ),
                  child: const Text('Yeni indirim'),
                ),
                ...discounts.map((raw) {
                  final d = Map<String, dynamic>.from(raw as Map);
                  return ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: Text('${d['code']} · ${d['type']} ${d['value']}'),
                    subtitle: Text(
                      'Kullanım: ${d['usedCount']}/${d['maxUses'] ?? '∞'}',
                    ),
                  );
                }),
              ],
            ),
          )
          ],
        ],
      ),
    );
  }

  Widget _pill(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w800,
          fontSize: 12,
        ),
      ),
    );
  }

  Future<void> _createDiscount(
    BuildContext context,
    List<String> eventIds,
    List<String> titles,
  ) async {
    var eventId = eventIds.first;
    final code = TextEditingController();
    final value = TextEditingController(text: '10');
    final maxUses = TextEditingController(text: '50');
    var type = 'percent';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('İndirim kodu'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  value: eventId,
                  items: [
                    for (var i = 0; i < eventIds.length; i++)
                      DropdownMenuItem(
                        value: eventIds[i],
                        child: Text(titles[i], overflow: TextOverflow.ellipsis),
                      ),
                  ],
                  onChanged: (v) => setLocal(() => eventId = v ?? eventId),
                  decoration: const InputDecoration(labelText: 'Etkinlik'),
                ),
                TextField(
                  controller: code,
                  decoration: const InputDecoration(labelText: 'Kod'),
                ),
                DropdownButtonFormField<String>(
                  value: type,
                  items: const [
                    DropdownMenuItem(value: 'percent', child: Text('% indirim')),
                    DropdownMenuItem(value: 'fixed', child: Text('Sabit TL')),
                  ],
                  onChanged: (v) => setLocal(() => type = v ?? type),
                ),
                TextField(
                  controller: value,
                  decoration: const InputDecoration(labelText: 'Değer'),
                ),
                TextField(
                  controller: maxUses,
                  decoration: const InputDecoration(labelText: 'Max kullanım'),
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
              child: const Text('Oluştur'),
            ),
          ],
        ),
      ),
    );
    if (ok != true) return;
    try {
      await CommerceService.createDiscount(
        eventId: eventId,
        code: code.text.trim(),
        type: type,
        value: double.tryParse(value.text.trim()) ?? 0,
        maxUses: int.tryParse(maxUses.text.trim()) ?? 0,
      );
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }
}
