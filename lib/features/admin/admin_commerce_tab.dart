import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../../core/widgets/safe_network_image.dart';
import '../auth/data/auth_provider.dart';
import '../commerce/commerce_service.dart';
import '../payments/admin_payments_panel.dart';
import '../payments/payments_service.dart';
import 'admin_market_campaigns_panel.dart';
import 'admin_market_orders_panel.dart';
import 'admin_market_products_panel.dart';
import 'admin_permissions.dart';
import 'admin_provider.dart';
import 'admin_user_search_field.dart';

/// Admin · Market — sol submenu hub
class AdminMarketTab extends StatefulWidget {
  const AdminMarketTab({super.key});

  @override
  State<AdminMarketTab> createState() => _AdminMarketTabState();
}

/// Geriye uyumluluk
typedef AdminCommerceTab = AdminMarketTab;

class _AdminMarketTabState extends State<AdminMarketTab> {
  final _companyId = TextEditingController();
  final _commission = TextEditingController(text: '10');
  final _minWithdraw = TextEditingController(text: '500');

  /// status | orders | products | campaigns | pay_settings | payments | withdrawals | ads | company | smtp
  String _section = 'status';

  @override
  void dispose() {
    _companyId.dispose();
    _commission.dispose();
    _minWithdraw.dispose();
    super.dispose();
  }

  Future<void> _saveCompany() async {
    final id = _companyId.text.trim();
    if (id.isEmpty) return;
    try {
      await CommerceService.adminSetOrganizerCommerce(
        companyId: id,
        commissionPercent: double.tryParse(_commission.text.trim()) ?? 0,
        minWithdrawal: double.tryParse(_minWithdraw.text.trim()) ?? 0,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Firma ticaret ayarları kaydedildi')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final me = context.watch<AuthProvider>().user;
    final admin = context.watch<AdminProvider>();
    final canAds = admin.can(me, AdminPermission.manageAds);
    final canPayments = admin.can(me, AdminPermission.reviewPayments);
    final canMarket = admin.can(me, AdminPermission.manageMarket) ||
        admin.can(me, AdminPermission.managePlus);
    final canCompany =
        canAds ||
        admin.can(me, AdminPermission.createCompany) ||
        admin.can(me, AdminPermission.reviewLeads);
    final canSmtp = me?.isSuperAdmin == true;

    final sections = <(String, String, IconData)>[
      if (canMarket) ('status', 'Market durumu', Icons.toggle_on_outlined),
      if (canMarket) ('orders', 'Siparişler', Icons.receipt_long_outlined),
      if (canMarket) ('products', 'Ürünler', Icons.inventory_2_outlined),
      if (canMarket) ('campaigns', 'Kampanyalar', Icons.local_offer_outlined),
      if (canMarket) ('pay_settings', 'Ödeme ayarları', Icons.payments_outlined),
      if (canPayments) ('payments', 'Ödeme onayları', Icons.fact_check_outlined),
      if (canPayments) ('withdrawals', 'Çekimler', Icons.account_balance_outlined),
      if (canAds) ('ads', 'Reklamlar', Icons.campaign_outlined),
      if (canCompany) ('company', 'Firma ayarları', Icons.business_outlined),
      if (canSmtp) ('smtp', 'SMTP', Icons.mail_outline),
    ];
    if (sections.isEmpty) {
      return const Center(child: Text('Bu sekme için yetkin yok.'));
    }
    final effectiveSection = sections.any((s) => s.$1 == _section)
        ? _section
        : sections.first.$1;
    if (effectiveSection != _section) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _section = effectiveSection);
      });
    }

    final wide = MediaQuery.sizeOf(context).width >= 900;

    final menu = Material(
      color: AppColors.surfaceMuted,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(8, 12, 8, 24),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Market',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Durum, sipariş, ürün, kampanya ve ödeme',
                  style: TextStyle(
                    fontSize: 11.5,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          for (final s in sections)
            Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: ListTile(
                dense: true,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                selected: effectiveSection == s.$1,
                selectedTileColor: AppColors.navy.withValues(alpha: 0.1),
                selectedColor: AppColors.navy,
                iconColor: effectiveSection == s.$1
                    ? AppColors.navy
                    : AppColors.textSecondary,
                textColor: effectiveSection == s.$1
                    ? AppColors.navy
                    : AppColors.textPrimary,
                leading: Icon(s.$3, size: 20),
                title: Text(
                  s.$2,
                  style: TextStyle(
                    fontWeight: effectiveSection == s.$1
                        ? FontWeight.w800
                        : FontWeight.w600,
                    fontSize: 13.5,
                  ),
                ),
                onTap: () => setState(() => _section = s.$1),
              ),
            ),
        ],
      ),
    );

    final body = switch (effectiveSection) {
      'status' => const SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(16, 12, 16, 32),
          child: _MarketStatusPanel(),
        ),
      'orders' => const SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(16, 12, 16, 32),
          child: AdminMarketOrdersPanel(),
        ),
      'products' => const SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(16, 12, 16, 32),
          child: AdminMarketProductsPanel(),
        ),
      'campaigns' => const SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(16, 12, 16, 32),
          child: AdminMarketCampaignsPanel(),
        ),
      'pay_settings' => const SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(16, 12, 16, 32),
          child: AdminPaymentsPanel(),
        ),
      'payments' => const AdminPaymentReviewsPanel(),
      'withdrawals' => ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text(
              'Bekleyen çekimler',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            _Withdrawals(),
          ],
        ),
      'company' => ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text(
              'Firma ayarları',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            AdminUserSearchField(
              controller: _companyId,
              labelText: 'Firma / org ara (ad / e-posta / uid)',
              hintText: 'Ornek: Acme A.S. veya info@firma.com',
              filter: (u) =>
                  u.isCompany || u.isCommunity || u.isEventOrganizer,
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _commission,
                    decoration: const InputDecoration(
                      labelText: 'Komisyon %',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _minWithdraw,
                    decoration: const InputDecoration(
                      labelText: 'Min çekim TL',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            FilledButton(
              onPressed: _saveCompany,
              child: const Text('Kaydet'),
            ),
          ],
        ),
      'smtp' => ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text(
              'SMTP (süper admin)',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            const _SmtpBox(),
          ],
        ),
      _ => const _AdsQueue(),
    };

    if (wide) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(width: 220, child: menu),
          const VerticalDivider(width: 1),
          Expanded(child: body),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 52,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            children: [
              for (final s in sections)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    avatar: Icon(
                      s.$3,
                      size: 16,
                      color: effectiveSection == s.$1
                          ? Colors.white
                          : AppColors.navy,
                    ),
                    label: Text(
                      s.$2,
                      style: TextStyle(
                        color: effectiveSection == s.$1
                            ? Colors.white
                            : AppColors.textPrimary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    selected: effectiveSection == s.$1,
                    selectedColor: AppColors.navy,
                    backgroundColor: Colors.white,
                    side: BorderSide(
                      color: effectiveSection == s.$1
                          ? AppColors.navy
                          : AppColors.border,
                    ),
                    showCheckmark: false,
                    onSelected: (_) => setState(() => _section = s.$1),
                  ),
                ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(child: body),
      ],
    );
  }
}


class _SmtpBox extends StatefulWidget {
  const _SmtpBox();

  @override
  State<_SmtpBox> createState() => _SmtpBoxState();
}

class _SmtpBoxState extends State<_SmtpBox> {
  final _host = TextEditingController(text: 'smtp.kampusteyim.app');
  final _port = TextEditingController(text: '465');
  final _user = TextEditingController(text: 'info@kampusteyim.app');
  final _pass = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _host.dispose();
    _port.dispose();
    _user.dispose();
    _pass.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _busy = true);
    try {
      await FirebaseFunctions.instanceFor(
        region: 'europe-west1',
      ).httpsCallable('updateSmtpConfig').call({
        'smtp_host': _host.text.trim(),
        'smtp_port': _port.text.trim(),
        'smtp_user': _user.text.trim(),
        'smtp_pass': _pass.text.trim(),
      });
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('SMTP kaydedildi')));
      _pass.clear();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        TextField(
          controller: _host,
          decoration: const InputDecoration(
            labelText: 'SMTP host',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: _port,
          decoration: const InputDecoration(
            labelText: 'Port',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: _user,
          decoration: const InputDecoration(
            labelText: 'User',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: _pass,
          obscureText: true,
          decoration: const InputDecoration(
            labelText: 'Password (boş = değiştirme)',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 8),
        FilledButton(
          onPressed: _busy ? null : _save,
          child: const Text('SMTP kaydet'),
        ),
      ],
    );
  }
}

class _Withdrawals extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('withdrawal_requests')
          .where('status', isEqualTo: 'pending')
          .orderBy('createdAt', descending: true)
          .limit(40)
          .snapshots(),
      builder: (context, snap) {
        if (snap.hasError) {
          return Text(
            '${snap.error}',
            style: const TextStyle(color: Colors.orange),
          );
        }
        final docs = snap.data?.docs ?? [];
        if (docs.isEmpty) {
          return const Text(
            'Bekleyen çekim yok.',
            style: TextStyle(color: AppColors.textSecondary),
          );
        }
        return Column(
          children: [
            for (final d in docs)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${d.data()['companyName']} · ${d.data()['amount']} TL',
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                      SelectableText('IBAN: ${d.data()['payoutIban']}'),
                      Row(
                        children: [
                          FilledButton(
                            onPressed: () =>
                                CommerceService.adminReviewWithdrawal(
                                  id: d.id,
                                  approve: true,
                                ),
                            child: const Text('Ödendi'),
                          ),
                          const SizedBox(width: 8),
                          OutlinedButton(
                            onPressed: () =>
                                CommerceService.adminReviewWithdrawal(
                                  id: d.id,
                                  approve: false,
                                ),
                            child: const Text('Reddet'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _AdsQueue extends StatefulWidget {
  const _AdsQueue();

  @override
  State<_AdsQueue> createState() => _AdsQueueState();
}

class _AdsQueueState extends State<_AdsQueue> {
  String _filter = 'action';

  static bool _matchesFilter(String status, String filter) {
    return switch (filter) {
      'action' => [
        'pending',
        'pending_review',
        'pending_quote',
        'quoted',
        'quote_declined',
        'awaiting_payment',
        'paid_review',
      ].contains(status),
      'active' => ['active', 'approved', 'paused'].contains(status),
      'archive' => [
        'completed',
        'ended',
        'rejected',
        'cancelled',
      ].contains(status),
      _ => true,
    };
  }

  static String _statusLabel(String status) {
    return switch (status) {
      'pending' || 'pending_review' => 'İnceleme',
      'pending_quote' => 'Teklif bekliyor',
      'quoted' => 'Teklif gönderildi',
      'quote_declined' => 'Teklif reddedildi',
      'awaiting_payment' => 'Ödeme bekleniyor',
      'paid_review' => 'Ödeme kontrol',
      'active' || 'approved' => 'Yayında',
      'paused' => 'Duraklatıldı',
      'completed' || 'ended' => 'Tamamlandı',
      'rejected' => 'Reddedildi',
      'cancelled' => 'İptal',
      _ => status,
    };
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('ad_campaigns')
          .orderBy('createdAt', descending: true)
          .limit(60)
          .snapshots(),
      builder: (context, snap) {
        if (snap.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                '${snap.error}',
                style: const TextStyle(color: Colors.orange),
              ),
            ),
          );
        }
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final docs = snap.data?.docs ?? [];
        final actionCount = docs
            .where(
              (d) => _matchesFilter('${d.data()['status'] ?? ''}', 'action'),
            )
            .length;
        final visible = docs
            .where(
              (d) => _matchesFilter('${d.data()['status'] ?? ''}', _filter),
            )
            .toList();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'Reklam kuyruğu',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${visible.length} reklam · tek tek açıp inceleyin',
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String>(
                    key: ValueKey('ads_filter_$_filter'),
                    initialValue: _filter,
                    decoration: const InputDecoration(
                      labelText: 'Durum filtresi',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    items: [
                      DropdownMenuItem(
                        value: 'action',
                        child: Text('İşlem bekleyen ($actionCount)'),
                      ),
                      const DropdownMenuItem(
                        value: 'active',
                        child: Text('Yayında'),
                      ),
                      const DropdownMenuItem(
                        value: 'archive',
                        child: Text('Arşiv'),
                      ),
                      DropdownMenuItem(
                        value: 'all',
                        child: Text('Tümü (${docs.length})'),
                      ),
                    ],
                    onChanged: (v) {
                      if (v == null) return;
                      setState(() => _filter = v);
                    },
                  ),
                ],
              ),
            ),
            Expanded(
              child: docs.isEmpty
                  ? const Center(
                      child: Text(
                        'Reklam yok.',
                        style: TextStyle(color: AppColors.textSecondary),
                      ),
                    )
                  : visible.isEmpty
                  ? const Center(
                      child: Text(
                        'Bu kuyrukta reklam yok.',
                        style: TextStyle(color: AppColors.textSecondary),
                      ),
                    )
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                      children: [
                        ExpansionPanelList.radio(
                          key: ValueKey('ads_panel_$_filter'),
                          elevation: 0,
                          expandedHeaderPadding: EdgeInsets.zero,
                          children: [
                            for (final d in visible)
                              ExpansionPanelRadio(
                                value: d.id,
                                canTapOnHeader: true,
                                backgroundColor: AppColors.surface,
                                headerBuilder: (context, isExpanded) {
                                  final data = d.data();
                                  final status = '${data['status'] ?? ''}';
                                  final owner =
                                      '${data['ownerName'] ?? data['companyName'] ?? 'Firma'}';
                                  final title = '${data['title'] ?? ''}';
                                  final kind = '${data['adKind'] ?? ''}';
                                  final needsAction = _matchesFilter(
                                    status,
                                    'action',
                                  );
                                  return ListTile(
                                    contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 4,
                                    ),
                                    leading: Icon(
                                      Icons.campaign_outlined,
                                      color: needsAction
                                          ? AppColors.crimson
                                          : AppColors.textSecondary,
                                    ),
                                    title: Text(
                                      title.isNotEmpty
                                          ? '$owner · $title'
                                          : owner,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                    subtitle: Text(
                                      '${_statusLabel(status)}'
                                      '${kind.isNotEmpty ? ' · $kind' : ''}'
                                      '${data['quotedAmount'] != null ? ' · ${data['quotedAmount']} TL' : ''}',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  );
                                },
                                body: _AdAdminCard(
                                  key: ValueKey(
                                    '${d.id}-${d.data()['updatedAt']}',
                                  ),
                                  id: d.id,
                                  data: d.data(),
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
            ),
          ],
        );
      },
    );
  }
}

class _AdAdminCard extends StatefulWidget {
  const _AdAdminCard({super.key, required this.id, required this.data});
  final String id;
  final Map<String, dynamic> data;

  @override
  State<_AdAdminCard> createState() => _AdAdminCardState();
}

class _AdAdminCardState extends State<_AdAdminCard> {
  late final TextEditingController _title;
  late final TextEditingController _body;
  late final TextEditingController _note;
  late final TextEditingController _quote;
  late final TextEditingController _quoteNote;
  late final TextEditingController _end;

  @override
  void initState() {
    super.initState();
    _title = TextEditingController(text: '${widget.data['title'] ?? ''}');
    _body = TextEditingController(text: '${widget.data['body'] ?? ''}');
    _note = TextEditingController();
    _quote = TextEditingController();
    _quoteNote = TextEditingController(
      text: '${widget.data['quoteNote'] ?? ''}',
    );
    _end = TextEditingController(text: '${widget.data['scheduleEnd'] ?? ''}');
  }

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    _note.dispose();
    _quote.dispose();
    _quoteNote.dispose();
    _end.dispose();
    super.dispose();
  }

  Future<void> _act(String status) async {
    try {
      await CommerceService.adminReviewAd(
        id: widget.id,
        status: status,
        adminNote: _note.text.trim(),
        edits: {
          'title': _title.text.trim(),
          'body': _body.text.trim(),
          if (_end.text.trim().isNotEmpty) 'scheduleEnd': _end.text.trim(),
        },
      );
      if (status == 'active' &&
          [
            'paid_review',
            'pending',
            'pending_review',
          ].contains('${widget.data['status'] ?? ''}')) {
        try {
          await CommerceService.dispatchAdReach(adId: widget.id);
        } catch (_) {
          // Feed/Reels/Hikâye kampanyalarında push/mail olmayabilir.
        }
      }
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Reklam: $status')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Future<void> _sendQuote() async {
    final amount = double.tryParse(_quote.text.trim().replaceAll(',', '.'));
    if (amount == null) return;
    try {
      await CommerceService.adminReviewAd(
        id: widget.id,
        status: 'pending_quote',
        adminNote: _note.text.trim(),
        edits: {
          'title': _title.text.trim(),
          'body': _body.text.trim(),
          if (_end.text.trim().isNotEmpty) 'scheduleEnd': _end.text.trim(),
        },
      );
      final res = await CommerceService.quoteAd(
        adId: widget.id,
        quotedAmount: amount,
        quoteNote: _quoteNote.text.trim(),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Teklif firmaya gönderildi: '
            '${(res['amount'] as num?)?.toStringAsFixed(2) ?? amount} TL',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Reklamı sil?'),
        content: const Text(
          'Reklam kuyruğundan kalıcı olarak silinecek. Bu işlem geri alınamaz.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Vazgeç'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Sil'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await CommerceService.adminDeleteAd(widget.id);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Reklam silindi')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Future<void> _reach({bool force = false}) async {
    try {
      await CommerceService.dispatchAdReach(adId: widget.id, force: force);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Push/mail reach gönderildi')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final status = '${widget.data['status'] ?? ''}';
    final placements = (widget.data['placements'] as List? ?? []).join(', ');
    final targets =
        '${(widget.data['targetCities'] as List? ?? []).join(', ')} / '
        '${(widget.data['targetUniversities'] as List? ?? []).join(', ')}';
    final metrics = Map<String, dynamic>.from(
      widget.data['metrics'] as Map? ?? {},
    );
    final image = '${widget.data['imageUrl'] ?? ''}';
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '${widget.data['adKind']} · $placements',
            style: const TextStyle(
              fontSize: 12,
              color: AppColors.textSecondary,
            ),
          ),
          Text(
            'Hedef: $targets',
            style: const TextStyle(
              fontSize: 11,
              color: AppColors.textSecondary,
            ),
          ),
          if (image.isNotEmpty) ...[
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: AspectRatio(
                aspectRatio: 16 / 9,
                child: SafeNetworkImage(url: image, fit: BoxFit.cover),
              ),
            ),
          ],
          const SizedBox(height: 8),
          Wrap(
            spacing: 12,
            runSpacing: 6,
            children: [
              Text('Erişim ${metrics['reach'] ?? 0}'),
              Text('Gösterim ${metrics['impressions'] ?? 0}'),
              Text('Tıklama ${metrics['clicks'] ?? 0}'),
              Text(
                'Mail ${metrics['emailSent'] ?? widget.data['reachMailCount'] ?? 0}',
              ),
              Text(
                'Push ${metrics['pushSent'] ?? widget.data['reachPushCount'] ?? 0}',
              ),
            ],
          ),
          if (widget.data['ibanReference'] != null)
            SelectableText(
              'Kod: ${widget.data['ibanReference']} · ${widget.data['quotedAmount']} TL',
            ),
          const SizedBox(height: 8),
          TextField(
            controller: _title,
            decoration: const InputDecoration(
              labelText: 'Başlık',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 6),
          TextField(
            controller: _body,
            maxLines: 2,
            decoration: const InputDecoration(
              labelText: 'Metin',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 6),
          TextField(
            controller: _end,
            decoration: const InputDecoration(
              labelText: 'Bitiş (erken sonlandır / kısalt)',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 6),
          TextField(
            controller: _note,
            decoration: const InputDecoration(
              labelText: 'Admin notu',
              border: OutlineInputBorder(),
            ),
          ),
          if (['pending_quote', 'quote_declined', 'quoted'].contains(status) ||
              '${widget.data['adKind']}' == 'sponsor_paid') ...[
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _quote,
                    decoration: const InputDecoration(
                      labelText: 'Teklif tutarı TL',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton.tonal(
                  onPressed: _sendQuote,
                  child: const Text('IBAN teklif'),
                ),
              ],
            ),
            const SizedBox(height: 6),
            TextField(
              controller: _quoteNote,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Teklif açıklaması',
                hintText: 'Süre, mecralar ve dahil olan hizmetler',
                border: OutlineInputBorder(),
              ),
            ),
          ],
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (status == 'paid_review')
                FilledButton(
                  onPressed: () => _act('active'),
                  child: const Text('Ödeme OK · yayına al'),
                ),
              if (status == 'pending' || status == 'pending_review')
                FilledButton(
                  onPressed: () => _act('active'),
                  child: const Text('Yayına al'),
                ),
              OutlinedButton(
                onPressed: () => _act('rejected'),
                child: const Text('Reddet'),
              ),
              if (status == 'active' || status == 'approved') ...[
                OutlinedButton(
                  onPressed: () => _act('paused'),
                  child: const Text('Duraklat'),
                ),
                OutlinedButton(
                  onPressed: () => _act('completed'),
                  child: const Text('Tamamla'),
                ),
                FilledButton.tonal(
                  onPressed: () => _reach(),
                  child: const Text('Push/Mail gönder'),
                ),
                TextButton(
                  onPressed: () => _reach(force: true),
                  child: const Text('Tekrar gönder'),
                ),
              ],
              if (status == 'paused')
                FilledButton(
                  onPressed: () => _act('active'),
                  child: const Text('Yayına devam et'),
                ),
              if (['active', 'approved', 'paused'].contains(status))
                FilledButton.tonalIcon(
                  onPressed: () =>
                      _act(status == 'approved' ? 'active' : status),
                  icon: const Icon(Icons.save_outlined),
                  label: const Text('Değişiklikleri kaydet'),
                ),
              OutlinedButton.icon(
                onPressed: _delete,
                icon: const Icon(Icons.delete_outline),
                label: const Text('Sil'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Market · uygulama içi görünürlük aç/kapa
class _MarketStatusPanel extends StatefulWidget {
  const _MarketStatusPanel();

  @override
  State<_MarketStatusPanel> createState() => _MarketStatusPanelState();
}

class _MarketStatusPanelState extends State<_MarketStatusPanel> {
  bool _loading = true;
  bool _saving = false;
  bool _visible = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final cfg = await PaymentsService.getAdmin();
      _visible = cfg.raw['marketInAppVisible'] == true;
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Durum okunamadı: $e')),
        );
      }
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _setVisible(bool value) async {
    setState(() {
      _visible = value;
      _saving = true;
    });
    try {
      await PaymentsService.updateAdmin({'marketInAppVisible': value});
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              value
                  ? 'Market uygulama içinde açık'
                  : 'Market uygulama içinde kapalı',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _visible = !value);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Kaydedilemedi: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 18),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    _visible
                        ? Icons.storefront
                        : Icons.storefront_outlined,
                    color: _visible ? AppColors.lime : AppColors.textSecondary,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _visible ? 'Market aktif' : 'Market kapalı',
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                      ),
                    ),
                  ),
                  if (_saving)
                    const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              const Text(
                'Kapalıyken Ayarlar → Market gizlenir; ürün / sipariş paneli '
                'admin’de kalır. Açınca öğrenciler uygulamadan marketi görür.',
                style: TextStyle(
                  color: AppColors.textSecondary,
                  height: 1.4,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 12),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Uygulama içi Market'),
                subtitle: Text(
                  _visible ? 'Öğrenciler görebilir' : 'Öğrencilerden gizli',
                ),
                value: _visible,
                onChanged: _saving ? null : _setVisible,
              ),
            ],
          ),
        ),
      ],
    );
  }
}
