import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../../models/models.dart';
import '../ads/ad_campaign_form.dart';
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
        const SnackBar(content: Text('Çekim talebi admin’e iletildi')),
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

  Future<void> _exportCsv() async {
    final sales = (_data?['salesByEvent'] as List? ?? const []);
    final buf = StringBuffer('eventId,eventTitle,count,revenue,buyers\n');
    for (final raw in sales) {
      final e = Map<String, dynamic>.from(raw as Map);
      final buyers = (e['buyers'] as List? ?? const [])
          .map((b) {
            final m = Map<String, dynamic>.from(b as Map);
            return '${m['email']}|${m['amount']}';
          })
          .join(';');
      buf.writeln(
        '"${e['eventId']}","${e['eventTitle']}",${e['count']},${e['revenue']},"$buyers"',
      );
    }
    await Clipboard.setData(ClipboardData(text: buf.toString()));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Satış CSV panoya kopyalandı')),
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
    final sales = (_data?['salesByEvent'] as List? ?? const []);
    final withdrawals = (_data?['withdrawals'] as List? ?? const []);
    final discounts = (_data?['discounts'] as List? ?? const []);
    final events = context
        .watch<FeedProvider>()
        .events
        .where((e) => e.organizerCompanyId == me.id)
        .toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Organizatör paneli'),
        actions: [
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
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (!hasIban)
            Container(
              padding: const EdgeInsets.all(12),
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: Colors.orange.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.orange),
              ),
              child: const Text(
                'Etkinlik açmadan önce çekim IBAN’ını kaydetmelisin.',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
          Text(
            'Bakiye: ${balance.toStringAsFixed(2)} TL',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w900,
                ),
          ),
          Text(
            'Komisyon: %${commission.toStringAsFixed(0)} · Min. çekim: ${minW.toStringAsFixed(0)} TL',
            style: const TextStyle(color: AppColors.textSecondary),
          ),
          const SizedBox(height: 16),
          const Text('Çekim IBAN’ı', style: TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          TextField(
            controller: _iban,
            decoration: const InputDecoration(
              labelText: 'IBAN',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _holder,
            decoration: const InputDecoration(
              labelText: 'Hesap sahibi',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _bank,
            decoration: const InputDecoration(
              labelText: 'Banka',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          FilledButton(onPressed: _saveIban, child: const Text('IBAN kaydet')),
          const SizedBox(height: 20),
          const Text('Çekim talebi', style: TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _withdraw,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    labelText: 'Tutar (min $minW)',
                    border: const OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: balance >= minW ? _doWithdraw : null,
                child: const Text('Talep et'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ...withdrawals.take(5).map((raw) {
            final w = Map<String, dynamic>.from(raw as Map);
            return ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: Text('${w['amount']} TL · ${w['status']}'),
              subtitle: Text('${w['createdAt'] ?? ''}'),
            );
          }),
          const Divider(height: 32),
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Satışlar',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
              TextButton(onPressed: _exportCsv, child: const Text('CSV')),
            ],
          ),
          if (sales.isEmpty)
            const Text(
              'Henüz bilet satışı yok.',
              style: TextStyle(color: AppColors.textSecondary),
            ),
          ...sales.map((raw) {
            final e = Map<String, dynamic>.from(raw as Map);
            final buyers = e['buyers'] as List? ?? const [];
            return Card(
              child: ExpansionTile(
                title: Text(
                  '${e['eventTitle']}',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                subtitle: Text(
                  '${e['count']} bilet · ${e['revenue']} TL brüt',
                ),
                children: [
                  for (final bRaw in buyers)
                    Builder(builder: (_) {
                      final b = Map<String, dynamic>.from(bRaw as Map);
                      return ListTile(
                        dense: true,
                        title: Text('${b['name'] ?? b['email'] ?? b['uid']}'),
                        subtitle: Text(
                          '${b['email']} · ${b['tierLabel'] ?? ''} · ${b['amount']} TL',
                        ),
                      );
                    }),
                ],
              ),
            );
          }),
          const Divider(height: 32),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.campaign_outlined),
            title: const Text('Reklamlar'),
            subtitle: const Text('Görsel yükleme ve yayın talepleri'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/firma/ads'),
          ),
          const Divider(height: 32),
          const Text('İndirim kodları', style: TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          FilledButton.tonal(
            onPressed: events.isEmpty
                ? null
                : () => _createDiscount(context, events.map((e) => e.id).toList(),
                    events.map((e) => e.title).toList()),
            child: const Text('Yeni indirim'),
          ),
          ...discounts.map((raw) {
            final d = Map<String, dynamic>.from(raw as Map);
            return ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: Text('${d['code']} · ${d['type']} ${d['value']}'),
              subtitle: Text(
                'Kullanım: ${d['usedCount']}/${d['maxUses'] ?? '∞'} · ${d['eventId']}',
              ),
            );
          }),
          const Divider(height: 32),
          const Text('Firmaya kadro davet', style: TextStyle(fontWeight: FontWeight.w800)),
          const _CompanyStaffInvite(),
        ],
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

class _CompanyStaffInvite extends StatefulWidget {
  const _CompanyStaffInvite();

  @override
  State<_CompanyStaffInvite> createState() => _CompanyStaffInviteState();
}

class _CompanyStaffInviteState extends State<_CompanyStaffInvite> {
  final _query = TextEditingController();
  bool _panel = true;
  bool _badge = true;
  bool _busy = false;

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final me = context.watch<AuthProvider>().user;
    final auth = context.watch<AuthProvider>();
    if (me == null) return const SizedBox.shrink();
    final q = _query.text.trim();
    final hits = q.isEmpty
        ? <AppUser>[]
        : auth
            .searchUsers(q)
            .where((u) => !u.isCommunity && !u.isCompany)
            .take(15)
            .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Panele erişim'),
          value: _panel,
          onChanged: (v) => setState(() => _panel = v),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Mavi tick'),
          value: _badge,
          onChanged: (v) => setState(() => _badge = v),
        ),
        TextField(
          controller: _query,
          decoration: const InputDecoration(
            labelText: 'Kullanıcı ara',
            border: OutlineInputBorder(),
          ),
          onChanged: (_) => setState(() {}),
        ),
        ...hits.map(
          (u) => ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(u.fullName),
            subtitle: Text(u.email),
            trailing: FilledButton(
              onPressed: _busy
                  ? null
                  : () async {
                      setState(() => _busy = true);
                      try {
                        await OrgInviteService.invite(
                          orgId: me.id,
                          orgType: 'company',
                          inviteeUid: u.id,
                          grantPanelAccess: _panel,
                          grantBlueBadge: _badge,
                        );
                        if (!mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('${u.fullName} davet edildi')),
                        );
                      } catch (e) {
                        if (!mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('$e')),
                        );
                      } finally {
                        if (mounted) setState(() => _busy = false);
                      }
                    },
              child: const Text('Davet'),
            ),
          ),
        ),
      ],
    );
  }
}
