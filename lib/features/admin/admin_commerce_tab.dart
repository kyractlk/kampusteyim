import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme/app_colors.dart';
import '../commerce/commerce_service.dart';
import 'admin_user_search_field.dart';

/// Admin: çekim + reklam teklif/onay/reach
class AdminCommerceTab extends StatefulWidget {
  const AdminCommerceTab({super.key});

  @override
  State<AdminCommerceTab> createState() => _AdminCommerceTabState();
}

class _AdminCommerceTabState extends State<AdminCommerceTab> {
  final _companyId = TextEditingController();
  final _commission = TextEditingController(text: '10');
  final _minWithdraw = TextEditingController(text: '500');

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
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          'Ticaret · komisyon / çekim / reklam',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w900,
              ),
        ),
        const SizedBox(height: 16),
        const Text('Firma ayarları', style: TextStyle(fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        AdminUserSearchField(
          controller: _companyId,
          labelText: 'Firma / org ara (ad / e-posta / uid)',
          hintText: 'Ornek: Acme A.S. veya info@firma.com',
          filter: (u) => u.isCompany || u.isCommunity || u.isEventOrganizer,
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
        FilledButton(onPressed: _saveCompany, child: const Text('Kaydet')),
        const Divider(height: 32),
        const Text('SMTP (süper admin)', style: TextStyle(fontWeight: FontWeight.w800)),
        const _SmtpBox(),
        const Divider(height: 32),
        const Text('Bekleyen çekimler', style: TextStyle(fontWeight: FontWeight.w800)),
        _Withdrawals(),
        const Divider(height: 32),
        const Text('Reklam kuyruğu', style: TextStyle(fontWeight: FontWeight.w800)),
        const Text(
          'pending / pending_quote / awaiting_payment / approved',
          style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
        ),
        const SizedBox(height: 8),
        _AdsQueue(),
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
      await FirebaseFunctions.instanceFor(region: 'europe-west1')
          .httpsCallable('updateSmtpConfig')
          .call({
        'smtp_host': _host.text.trim(),
        'smtp_port': _port.text.trim(),
        'smtp_user': _user.text.trim(),
        'smtp_pass': _pass.text.trim(),
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('SMTP kaydedildi')),
      );
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
          return Text('${snap.error}', style: const TextStyle(color: Colors.orange));
        }
        final docs = snap.data?.docs ?? [];
        if (docs.isEmpty) {
          return const Text('Bekleyen çekim yok.',
              style: TextStyle(color: AppColors.textSecondary));
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
                            onPressed: () => CommerceService.adminReviewWithdrawal(
                              id: d.id,
                              approve: true,
                            ),
                            child: const Text('Ödendi'),
                          ),
                          const SizedBox(width: 8),
                          OutlinedButton(
                            onPressed: () => CommerceService.adminReviewWithdrawal(
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

class _AdsQueue extends StatelessWidget {
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
          return Text('${snap.error}', style: const TextStyle(color: Colors.orange));
        }
        final docs = snap.data?.docs ?? [];
        if (docs.isEmpty) {
          return const Text('Reklam yok.',
              style: TextStyle(color: AppColors.textSecondary));
        }
        return Column(
          children: [
            for (final d in docs)
              _AdAdminCard(id: d.id, data: d.data()),
          ],
        );
      },
    );
  }
}

class _AdAdminCard extends StatefulWidget {
  const _AdAdminCard({required this.id, required this.data});
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
  late final TextEditingController _end;

  @override
  void initState() {
    super.initState();
    _title = TextEditingController(text: '${widget.data['title'] ?? ''}');
    _body = TextEditingController(text: '${widget.data['body'] ?? ''}');
    _note = TextEditingController();
    _quote = TextEditingController();
    _end = TextEditingController(text: '${widget.data['scheduleEnd'] ?? ''}');
  }

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    _note.dispose();
    _quote.dispose();
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
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Reklam: $status')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Future<void> _sendQuote() async {
    final amount = double.tryParse(_quote.text.trim().replaceAll(',', '.'));
    if (amount == null) return;
    try {
      final res = await CommerceService.quoteAd(
        adId: widget.id,
        quotedAmount: amount,
      );
      if (!mounted) return;
      final code = '${res['ibanReference'] ?? ''}';
      await Clipboard.setData(ClipboardData(text: code));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Teklif: $amount TL · kod kopyalandı: $code')),
      );
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
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '${widget.data['ownerName'] ?? widget.data['companyName']} · $status',
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
            Text(
              '${widget.data['adKind']} · $placements',
              style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
            ),
            Text('Hedef: $targets',
                style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
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
            if (status == 'pending_quote' ||
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
            ],
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (status == 'awaiting_payment')
                  FilledButton(
                    onPressed: () => _act('approved'),
                    child: const Text('Ödeme OK · onayla'),
                  ),
                if (status == 'pending' || status == 'pending_quote')
                  FilledButton(
                    onPressed: () => _act('approved'),
                    child: const Text('Onayla'),
                  ),
                OutlinedButton(
                  onPressed: () => _act('rejected'),
                  child: const Text('Reddet'),
                ),
                if (status == 'approved') ...[
                  OutlinedButton(
                    onPressed: () => _act('ended'),
                    child: const Text('Erken bitir'),
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
              ],
            ),
          ],
        ),
      ),
    );
  }
}
