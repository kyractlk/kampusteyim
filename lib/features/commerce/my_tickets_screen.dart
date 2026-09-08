import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../core/theme/app_colors.dart';
import '../../core/utils/app_nav.dart';
import '../commerce/commerce_service.dart';

class MyTicketsScreen extends StatefulWidget {
  const MyTicketsScreen({super.key});

  @override
  State<MyTicketsScreen> createState() => _MyTicketsScreenState();
}

class _MyTicketsScreenState extends State<MyTicketsScreen> {
  List<Map<String, dynamic>> _tickets = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list = await CommerceService.getMyTickets();
      setState(() => _tickets = list);
    } catch (e) {
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _statusLabel(String raw) {
    switch (raw) {
      case 'used':
      case 'checked_in':
        return 'Giriş yapıldı';
      case 'active':
        return 'Aktif';
      case 'refunded':
      case 'cancelled':
        return 'İade edildi';
      default:
        return raw.isEmpty ? 'Aktif' : raw;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Biletlerim'),
        actions: [
          IconButton(onPressed: _load, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!))
              : _tickets.isEmpty
                  ? const Center(
                      child: Padding(
                        padding: EdgeInsets.all(24),
                        child: Text(
                          'Henüz biletin yok.\n'
                          'Ücretli etkinliklerde ödeme hesabın ile katılım aynıdır.\n'
                          'İade, etkinliğin satış şartına bağlıdır.',
                          textAlign: TextAlign.center,
                          style: TextStyle(height: 1.45),
                        ),
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                      itemCount: _tickets.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 14),
                      itemBuilder: (context, i) {
                        final t = _tickets[i];
                        return _TicketPass(
                          ticket: t,
                          statusLabel:
                              _statusLabel('${t['status'] ?? 'active'}'),
                          onOpenEvent: () {
                            final id = '${t['eventId'] ?? ''}'.trim();
                            if (id.isEmpty) return;
                            AppNav.openEvent(context, id);
                          },
                          onShowQr: () => _showTicketQr(t),
                        );
                      },
                    ),
      bottomNavigationBar: const SafeArea(
        child: Padding(
          padding: EdgeInsets.all(12),
          child: Text(
            'Satış sözleşmesi ve KVKK: uygulama yasal sayfalarında. '
            'Bilet kişiye özeldir; ödeyen hesap = katılımcı.',
            style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }

  Future<void> _showTicketQr(Map<String, dynamic> t) async {
    final st = '${t['status'] ?? 'active'}';
    if (st == 'refunded' || st == 'cancelled') {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Bu bilet iade edildi, QR geçersiz.')),
      );
      return;
    }
    final payload = '${t['qrPayload'] ?? t['id'] ?? ''}'.trim();
    final code = formatTicketShortCode(
      '${t['shortCode'] ?? t['displayCode'] ?? ''}',
    );
    final starts = DateTime.tryParse('${t['startsAt'] ?? ''}');
    final date = starts == null
        ? ''
        : DateFormat('d MMM yyyy · HH:mm', 'tr').format(starts);
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) {
        final maxW = MediaQuery.sizeOf(ctx).width;
        final qrSize = (maxW - 80).clamp(180.0, 280.0);
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '${t['eventTitle'] ?? 'Etkinlik'}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 18,
                  ),
                ),
                if (date.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    date,
                    style: const TextStyle(color: AppColors.textSecondary),
                  ),
                ],
                const SizedBox(height: 16),
                if (payload.isEmpty)
                  const Text('QR henüz oluşturulamadı')
                else
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: QrImageView(
                      data: payload,
                      size: qrSize,
                      backgroundColor: Colors.white,
                    ),
                  ),
                if (code.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  Text(
                    code,
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 22,
                      letterSpacing: 3,
                    ),
                  ),
                  TextButton.icon(
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: code.replaceAll('-', '')));
                      ScaffoldMessenger.of(ctx).showSnackBar(
                        const SnackBar(content: Text('Kısa kod kopyalandı')),
                      );
                    },
                    icon: const Icon(Icons.copy_rounded, size: 16),
                    label: const Text('Kodu kopyala'),
                  ),
                ],
                const SizedBox(height: 8),
                Text(
                  [
                    if ('${t['userName'] ?? ''}'.trim().isNotEmpty)
                      '${t['userName']}',
                    if ('${t['tierLabel'] ?? ''}'.isNotEmpty) '${t['tierLabel']}',
                    '${t['amountPaid'] ?? 0} TL',
                    'Durum: ${_statusLabel('${t['status'] ?? 'active'}')}',
                  ].join(' · '),
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 13),
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: () {
                    Navigator.pop(ctx);
                    final id = '${t['eventId'] ?? ''}'.trim();
                    if (id.isNotEmpty) AppNav.openEvent(context, id);
                  },
                  icon: const Icon(Icons.event_outlined),
                  label: const Text('Etkinliği aç'),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

String formatTicketShortCode(String raw) {
  final s = raw.replaceAll(RegExp(r'[^A-Za-z0-9]'), '').toUpperCase();
  if (s.length != 6) return s;
  return '${s.substring(0, 3)}-${s.substring(3)}';
}

class _TicketPass extends StatelessWidget {
  const _TicketPass({
    required this.ticket,
    required this.statusLabel,
    required this.onOpenEvent,
    required this.onShowQr,
  });

  final Map<String, dynamic> ticket;
  final String statusLabel;
  final VoidCallback onOpenEvent;
  final VoidCallback onShowQr;

  @override
  Widget build(BuildContext context) {
    final starts = DateTime.tryParse('${ticket['startsAt'] ?? ''}');
    final date = starts == null
        ? ''
        : DateFormat('d MMM yyyy · HH:mm', 'tr').format(starts);
    final used = statusLabel == 'Giriş yapıldı';
    final refunded = statusLabel == 'İade edildi';
    final code = formatTicketShortCode(
      '${ticket['shortCode'] ?? ticket['displayCode'] ?? ''}',
    );
    final accent = refunded
        ? AppColors.crimson
        : used
            ? const Color(0xFF166534)
            : AppColors.navy;

    return Material(
      color: AppColors.surface,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: accent.withValues(alpha: 0.28), width: 1.4),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onShowQr,
        child: Column(
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    accent,
                    accent.withValues(alpha: 0.82),
                  ],
                ),
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(18.5),
                ),
              ),
              child: Row(
                children: [
                  const Icon(Icons.confirmation_number_outlined,
                      color: Colors.white, size: 22),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '${ticket['eventTitle'] ?? 'Etkinlik'}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 15.5,
                      ),
                    ),
                  ),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      statusLabel,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (date.isNotEmpty)
                          Text(
                            date,
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 13,
                            ),
                          ),
                        const SizedBox(height: 4),
                        Text(
                          [
                            if ('${ticket['userName'] ?? ''}'.trim().isNotEmpty)
                              '${ticket['userName']}',
                            if ('${ticket['tierLabel'] ?? ''}'.isNotEmpty)
                              '${ticket['tierLabel']}',
                            if ('${ticket['entryType'] ?? ''}' == 'multi')
                              'Giriş ${ticket['entriesUsed'] ?? 0}/${ticket['entryLimit'] ?? 0}',
                            '${ticket['amountPaid'] ?? 0} TL',
                          ].join(' · '),
                          style: const TextStyle(
                            fontSize: 12.5,
                            color: AppColors.textSecondary,
                            height: 1.35,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (code.isNotEmpty)
                    Column(
                      children: [
                        Text(
                          code,
                          style: TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 18,
                            letterSpacing: 1.4,
                            color: accent,
                          ),
                        ),
                        const Text(
                          'Kısa kod',
                          style: TextStyle(
                            fontSize: 10,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 10),
              child: CustomPaint(
                painter: _DashPainter(),
                child: SizedBox(width: double.infinity, height: 12),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
              child: Row(
                children: [
                  TextButton.icon(
                    onPressed: onShowQr,
                    icon: const Icon(Icons.qr_code_2_rounded, size: 18),
                    label: const Text('QR göster'),
                  ),
                  const Spacer(),
                  IconButton(
                    tooltip: 'Etkinlik',
                    onPressed: onOpenEvent,
                    icon: const Icon(Icons.chevron_right),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DashPainter extends CustomPainter {
  const _DashPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppColors.border
      ..strokeWidth = 1.2;
    const dash = 6.0;
    const gap = 5.0;
    var x = 0.0;
    final y = size.height / 2;
    while (x < size.width) {
      canvas.drawLine(Offset(x, y), Offset(x + dash, y), paint);
      x += dash + gap;
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
