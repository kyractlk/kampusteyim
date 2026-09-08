import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../auth/data/auth_provider.dart';

/// Admin · ad / soyad değişikliği talepleri.
class AdminNameRequestsTab extends StatefulWidget {
  const AdminNameRequestsTab({super.key});

  @override
  State<AdminNameRequestsTab> createState() => _AdminNameRequestsTabState();
}

class _AdminNameRequestsTabState extends State<AdminNameRequestsTab> {
  List<Map<String, dynamic>> _items = [];
  bool _loading = true;
  String _filter = 'pending';
  String? _busyId;

  FirebaseFunctions get _fn =>
      FirebaseFunctions.instanceFor(region: 'europe-west1');

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final snap = await FirebaseFirestore.instance
          .collection('name_change_requests')
          .orderBy('createdAt', descending: true)
          .limit(200)
          .get();
      _items = snap.docs
          .map((d) => {'id': d.id, ...d.data()})
          .toList();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Yüklenemedi: $e')),
        );
      }
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _review(Map<String, dynamic> row, {required bool approve}) async {
    final noteCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(approve ? 'İsmi onayla' : 'Talebi reddet'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${row['currentFirstName'] ?? ''} ${row['currentLastName'] ?? ''}'
              '  →  '
              '${row['requestedFirstName'] ?? ''} ${row['requestedLastName'] ?? ''}',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: noteCtrl,
              maxLines: 2,
              decoration: InputDecoration(
                labelText: approve ? 'Not (opsiyonel)' : 'Red sebebi',
                border: const OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Vazgeç'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(approve ? 'Onayla' : 'Reddet'),
          ),
        ],
      ),
    );
    final note = noteCtrl.text.trim();
    noteCtrl.dispose();
    if (ok != true || !mounted) return;
    setState(() => _busyId = '${row['id']}');
    try {
      final res = await _fn.httpsCallable('reviewNameChange').call({
        'requestId': row['id'],
        'approve': approve,
        'note': note,
      });
      final data = Map<String, dynamic>.from(res.data as Map? ?? {});
      if (!mounted) return;
      final auth = context.read<AuthProvider>();
      final userId = '${data['userId'] ?? row['uid'] ?? ''}';
      final existing = auth.findUser(userId);
      if (approve && existing != null) {
        auth.upsertUser(
          existing.copyWith(
            firstName: '${data['firstName'] ?? ''}',
            lastName: '${data['lastName'] ?? ''}',
          ),
          syncRemote: false,
        );
      }
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(approve ? 'İsim güncellendi' : 'Talep reddedildi'),
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('İşlem başarısız: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final list = _filter == 'all'
        ? _items
        : _items.where((e) => '${e['status']}' == _filter).toList();
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  initialValue: _filter,
                  decoration: const InputDecoration(
                    labelText: 'Durum',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'pending', child: Text('Bekleyen')),
                    DropdownMenuItem(value: 'approved', child: Text('Onaylı')),
                    DropdownMenuItem(value: 'rejected', child: Text('Red')),
                    DropdownMenuItem(value: 'all', child: Text('Tümü')),
                  ],
                  onChanged: (v) {
                    if (v == null) return;
                    setState(() => _filter = v);
                  },
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filledTonal(
                onPressed: _loading ? null : _load,
                icon: _loading
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.refresh),
              ),
            ],
          ),
        ),
        Expanded(
          child: _loading && _items.isEmpty
              ? const Center(child: CircularProgressIndicator())
              : list.isEmpty
                  ? const Center(child: Text('İsim talebi yok'))
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                      itemCount: list.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 10),
                      itemBuilder: (context, i) {
                        final r = list[i];
                        final pending = '${r['status']}' == 'pending';
                        final created = DateTime.tryParse('${r['createdAt']}');
                        final busy = _busyId == '${r['id']}';
                        return Material(
                          color: AppColors.surface,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                            side: BorderSide(
                              color: pending
                                  ? AppColors.cyan.withValues(alpha: 0.5)
                                  : AppColors.border,
                            ),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '${r['userName'] ?? r['email'] ?? r['uid']}',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  '${r['currentFirstName'] ?? ''} ${r['currentLastName'] ?? ''}'
                                  '  →  '
                                  '${r['requestedFirstName'] ?? ''} ${r['requestedLastName'] ?? ''}',
                                ),
                                if ('${r['reason'] ?? ''}'.trim().isNotEmpty) ...[
                                  const SizedBox(height: 4),
                                  Text(
                                    'Gerekçe: ${r['reason']}',
                                    style: const TextStyle(
                                      color: AppColors.textSecondary,
                                      fontSize: 13,
                                    ),
                                  ),
                                ],
                                const SizedBox(height: 4),
                                Text(
                                  '${r['status']} · ${r['email'] ?? ''}'
                                  '${created == null ? '' : ' · ${DateFormat('d MMM HH:mm', 'tr').format(created)}'}',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: AppColors.textSecondary,
                                  ),
                                ),
                                if (pending) ...[
                                  const SizedBox(height: 10),
                                  Row(
                                    children: [
                                      FilledButton(
                                        onPressed: busy
                                            ? null
                                            : () => _review(r, approve: true),
                                        child: const Text('Onayla'),
                                      ),
                                      const SizedBox(width: 8),
                                      OutlinedButton(
                                        onPressed: busy
                                            ? null
                                            : () => _review(r, approve: false),
                                        child: const Text('Reddet'),
                                      ),
                                      if (busy) ...[
                                        const SizedBox(width: 10),
                                        const SizedBox(
                                          width: 18,
                                          height: 18,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ],
                              ],
                            ),
                          ),
                        );
                      },
                    ),
        ),
      ],
    );
  }
}
