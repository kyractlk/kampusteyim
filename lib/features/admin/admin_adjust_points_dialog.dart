import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../models/models.dart';

/// Admin · kullanıcı KP bakiyesi görüntüle / güncelle.
Future<void> showAdminAdjustPointsDialog({
  required BuildContext context,
  required AppUser user,
}) async {
  final fn = FirebaseFunctions.instanceFor(region: 'europe-west1');
  final deltaCtrl = TextEditingController();
  final noteCtrl = TextEditingController(text: 'admin_users_menu');
  int? balance;
  String? loadError;
  var loading = true;
  var saving = false;

  Future<void> loadBalance(StateSetter setLocal) async {
    setLocal(() {
      loading = true;
      loadError = null;
    });
    try {
      final snap = await FirebaseFirestore.instance
          .doc('user_points/${user.id}')
          .get();
      final bal = snap.exists
          ? (snap.data()?['balance'] as num?)?.toInt() ?? 0
          : 0;
      setLocal(() {
        balance = bal;
        loading = false;
      });
    } catch (e) {
      setLocal(() {
        loadError = '$e';
        loading = false;
      });
    }
  }

  if (!context.mounted) return;
  await showDialog<void>(
    context: context,
    builder: (ctx) {
      return StatefulBuilder(
        builder: (ctx, setLocal) {
          if (loading && balance == null && loadError == null) {
            loadBalance(setLocal);
          }
          final full = user.fullName.trim();
          final first = user.firstName.trim();
          final uname = (user.username ?? '').trim();
          final name = full.isNotEmpty
              ? full
              : (first.isNotEmpty
                  ? first
                  : (uname.isNotEmpty ? uname : user.id));
          return AlertDialog(
            title: const Text('Kampüsteyim Puan'),
            content: SizedBox(
              width: 360,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  Text(
                    user.email.isNotEmpty ? user.email : user.id,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (loading)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  else if (loadError != null)
                    Text(loadError!, style: const TextStyle(color: AppColors.crimson))
                  else
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF0B1F3A), Color(0xFF12355C)],
                        ),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Güncel bakiye',
                            style: TextStyle(
                              color: Color(0xFFA8C5E2),
                              fontSize: 12,
                            ),
                          ),
                          Text(
                            '${balance ?? 0} KP',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 28,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ],
                      ),
                    ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: deltaCtrl,
                    autofocus: true,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Delta (örn. 50 veya -20)',
                      helperText: 'Negatif değer puan düşer',
                    ),
                  ),
                  TextField(
                    controller: noteCtrl,
                    decoration: const InputDecoration(labelText: 'Not'),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: saving ? null : () => Navigator.pop(ctx),
                child: const Text('Kapat'),
              ),
              FilledButton(
                onPressed: saving
                    ? null
                    : () async {
                        final delta = int.tryParse(deltaCtrl.text.trim()) ?? 0;
                        if (delta == 0) return;
                        setLocal(() => saving = true);
                        try {
                          final res = await fn
                              .httpsCallable('adminAdjustPoints')
                              .call({
                            'uid': user.id,
                            'delta': delta,
                            'note': noteCtrl.text.trim().isEmpty
                                ? 'admin_users_menu'
                                : noteCtrl.text.trim(),
                          });
                          final data = Map<String, dynamic>.from(
                            res.data as Map? ?? {},
                          );
                          final next = (data['balance'] as num?)?.toInt();
                          setLocal(() {
                            if (next != null) balance = next;
                            saving = false;
                            deltaCtrl.clear();
                          });
                          if (ctx.mounted) {
                            ScaffoldMessenger.of(ctx).showSnackBar(
                              SnackBar(
                                content: Text(
                                  'Güncellendi · bakiye ${next ?? balance} KP',
                                ),
                              ),
                            );
                          }
                        } catch (e) {
                          setLocal(() => saving = false);
                          if (ctx.mounted) {
                            ScaffoldMessenger.of(ctx).showSnackBar(
                              SnackBar(content: Text('$e')),
                            );
                          }
                        }
                      },
                child: saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Uygula'),
              ),
            ],
          );
        },
      );
    },
  );
  deltaCtrl.dispose();
  noteCtrl.dispose();
}
