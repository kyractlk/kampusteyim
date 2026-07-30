import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_colors.dart';
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
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
                          'İade / iptal talebi yoktur.',
                          textAlign: TextAlign.center,
                          style: TextStyle(height: 1.45),
                        ),
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.all(16),
                      itemCount: _tickets.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 10),
                      itemBuilder: (context, i) {
                        final t = _tickets[i];
                        final starts = DateTime.tryParse('${t['startsAt'] ?? ''}');
                        final date = starts == null
                            ? ''
                            : DateFormat('d MMM yyyy · HH:mm', 'tr')
                                .format(starts);
                        return Card(
                          child: ListTile(
                            title: Text(
                              '${t['eventTitle'] ?? 'Etkinlik'}',
                              style: const TextStyle(fontWeight: FontWeight.w800),
                            ),
                            subtitle: Text(
                              [
                                if (date.isNotEmpty) date,
                                if ('${t['tierLabel'] ?? ''}'.isNotEmpty)
                                  '${t['tierLabel']}',
                                '${t['amountPaid'] ?? 0} TL',
                                if ('${t['ibanReference'] ?? ''}'.isNotEmpty)
                                  'Kod: ${t['ibanReference']}',
                                'Durum: ${t['status'] ?? 'active'}',
                              ].join('\n'),
                            ),
                            isThreeLine: true,
                            trailing: const Icon(Icons.confirmation_number_outlined),
                            onTap: () {
                              final id = '${t['eventId'] ?? ''}';
                              if (id.isNotEmpty) context.push('/events/$id');
                            },
                          ),
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
}
