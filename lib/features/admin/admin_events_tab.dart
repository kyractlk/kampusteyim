import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_colors.dart';

/// Admin · bekleyen / tüm kampüs dışı etkinlikler.
class AdminEventsTab extends StatelessWidget {
  const AdminEventsTab({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('events')
          .orderBy('startsAt', descending: false)
          .limit(120)
          .snapshots(),
      builder: (context, snap) {
        if (snap.hasError) {
          return Center(child: Text('Hata: ${snap.error}'));
        }
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final docs = snap.data!.docs;
        final pending = docs
            .where((d) => '${d.data()['status'] ?? ''}' == 'pending')
            .toList();
        final others = docs
            .where((d) => '${d.data()['status'] ?? ''}' != 'pending')
            .toList();

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text(
              'Etkinlik onayları',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
            ),
            const SizedBox(height: 6),
            const Text(
              'Organizatör firmaların kampüs dışı etkinlikleri burada onaylanır. '
              'Onay sonrası kullanıcıya “Kampüs dışı” sekmesinde görünür. '
              'Admin her etkinliği silebilir.',
              style: TextStyle(
                fontSize: 12.5,
                color: AppColors.textSecondary,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Bekleyen (${pending.length})',
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            if (pending.isEmpty)
              const Text(
                'Bekleyen etkinlik yok.',
                style: TextStyle(color: AppColors.textSecondary),
              ),
            for (final d in pending) _tile(context, d),
            const SizedBox(height: 20),
            Text(
              'Diğer (${others.length})',
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            for (final d in others.take(80)) _tile(context, d, compact: true),
          ],
        );
      },
    );
  }

  Widget _tile(
    BuildContext context,
    QueryDocumentSnapshot<Map<String, dynamic>> d, {
    bool compact = false,
  }) {
    final data = d.data();
    final title = '${data['title'] ?? ''}';
    final city = '${data['city'] ?? 'Gaziantep'}';
    final status = '${data['status'] ?? 'approved'}';
    final org =
        '${data['organizerCompanyName'] ?? data['communityName'] ?? ''}';
    final starts = DateTime.tryParse('${data['startsAt'] ?? ''}');
    final date = starts == null
        ? '—'
        : DateFormat('d MMM yyyy · HH:mm', 'tr').format(starts);

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
                IconButton(
                  tooltip: 'Etkinliği sil',
                  visualDensity: VisualDensity.compact,
                  onPressed: () => _confirmDelete(context, d.id, title),
                  icon: const Icon(Icons.delete_outline, color: AppColors.crimson),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              '$date · $city'
              '${org.isNotEmpty ? ' · $org' : ''}'
              ' · $status',
              style: const TextStyle(
                fontSize: 12.5,
                color: AppColors.textSecondary,
              ),
            ),
            if (!compact && status == 'pending') ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => _review(context, d.id, 'rejected'),
                      child: const Text('Reddet'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton(
                      onPressed: () => _review(context, d.id, 'approved'),
                      child: const Text('Onayla'),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _confirmDelete(
    BuildContext context,
    String id,
    String title,
  ) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Etkinliği sil'),
        content: Text(
          '"$title" kalıcı olarak silinecek. Devam edilsin mi?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Vazgeç'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Sil'),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    await _delete(context, id);
  }

  Future<void> _delete(BuildContext context, String id) async {
    try {
      final callable = FirebaseFunctions.instanceFor(region: 'europe-west1')
          .httpsCallable('adminDeleteEvent');
      await callable.call({'eventId': id});
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Etkinlik silindi')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Silinemedi: $e')),
        );
      }
    }
  }

  Future<void> _review(BuildContext context, String id, String status) async {
    try {
      final callable = FirebaseFunctions.instanceFor(region: 'europe-west1')
          .httpsCallable('adminReviewEvent');
      await callable.call({'eventId': id, 'status': status});
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(status == 'approved' ? 'Onaylandı' : 'Reddedildi'),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('İşlem başarısız: $e')),
        );
      }
    }
  }
}
