import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../auth/data/auth_provider.dart';
import 'notification_prefs.dart';
import 'push_service.dart';

/// Profil → bildirim / izin tercihleri.
class NotificationSettingsScreen extends StatefulWidget {
  const NotificationSettingsScreen({super.key});

  @override
  State<NotificationSettingsScreen> createState() =>
      _NotificationSettingsScreenState();
}

class _NotificationSettingsScreenState
    extends State<NotificationSettingsScreen> {
  late NotificationPrefs _prefs;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _prefs = context.read<AuthProvider>().user?.notificationPrefs ??
        NotificationPrefs.defaults;
  }

  Future<void> _save(NotificationPrefs next) async {
    setState(() {
      _prefs = next;
      _saving = true;
    });
    final auth = context.read<AuthProvider>();
    auth.updateNotificationPrefs(next);
    final user = auth.user;
    if (user != null) {
      try {
        await FirebaseFirestore.instance.collection('users').doc(user.id).set({
          'notificationPrefs': next.toJson(),
          'updatedAt': DateTime.now().toIso8601String(),
        }, SetOptions(merge: true));
      } catch (_) {}
      if (next.pushEnabled) {
        await PushService.instance.init();
        await PushService.instance.getToken();
      }
    }
    if (mounted) {
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Bildirim tercihleri kaydedildi')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Bildirim izinleri'),
        actions: [
          if (_saving)
            const Padding(
              padding: EdgeInsets.all(16),
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          const Text(
            'Hangi bildirimleri almak istediğini seç. Kapalı olanlar cihazına push olarak gelmez.',
            style: TextStyle(color: AppColors.textSecondary),
          ),
          const SizedBox(height: 12),
          SwitchListTile(
            title: const Text('Tüm push bildirimleri'),
            subtitle: const Text('Ana anahtar'),
            value: _prefs.pushEnabled,
            onChanged: (v) => _save(_prefs.copyWith(pushEnabled: v)),
          ),
          const Divider(),
          Consumer<AuthProvider>(
            builder: (context, auth, _) {
              final allow = auth.user?.allowMentions ?? true;
              return SwitchListTile(
                title: const Text('Etiketlenmeye izin ver'),
                subtitle: const Text(
                  'Kapalıysa diğerleri seni @ ile seçemez',
                ),
                value: allow,
                onChanged: (v) => auth.updateAllowMentions(v),
              );
            },
          ),
          const Divider(),
          SwitchListTile(
            title: const Text('Beğeniler'),
            value: _prefs.likes,
            onChanged: !_prefs.pushEnabled
                ? null
                : (v) => _save(_prefs.copyWith(likes: v)),
          ),
          SwitchListTile(
            title: const Text('Yorumlar'),
            value: _prefs.comments,
            onChanged: !_prefs.pushEnabled
                ? null
                : (v) => _save(_prefs.copyWith(comments: v)),
          ),
          SwitchListTile(
            title: const Text('Takip'),
            value: _prefs.follows,
            onChanged: !_prefs.pushEnabled
                ? null
                : (v) => _save(_prefs.copyWith(follows: v)),
          ),
          SwitchListTile(
            title: const Text('Repost'),
            value: _prefs.reposts,
            onChanged: !_prefs.pushEnabled
                ? null
                : (v) => _save(_prefs.copyWith(reposts: v)),
          ),
          SwitchListTile(
            title: const Text('Bahsetmeler (@)'),
            subtitle: const Text('Birisi senden bahsettiğinde'),
            value: _prefs.mentions,
            onChanged: !_prefs.pushEnabled
                ? null
                : (v) => _save(_prefs.copyWith(mentions: v)),
          ),
          SwitchListTile(
            title: const Text('Staj / iş ilanları'),
            subtitle: const Text('Firma ilanları ve başvurular'),
            value: _prefs.jobs,
            onChanged: !_prefs.pushEnabled
                ? null
                : (v) => _save(_prefs.copyWith(jobs: v)),
          ),
          SwitchListTile(
            title: const Text('Firma teklifleri'),
            value: _prefs.offers,
            onChanged: !_prefs.pushEnabled
                ? null
                : (v) => _save(_prefs.copyWith(offers: v)),
          ),
          SwitchListTile(
            title: const Text('Topluluk duyuruları'),
            value: _prefs.community,
            onChanged: !_prefs.pushEnabled
                ? null
                : (v) => _save(_prefs.copyWith(community: v)),
          ),
          SwitchListTile(
            title: const Text('Takip edilenlerin hareketleri'),
            subtitle: const Text('Yeni gönderi, duyuru (Twitter tarzı)'),
            value: _prefs.activity,
            onChanged: !_prefs.pushEnabled
                ? null
                : (v) => _save(_prefs.copyWith(activity: v)),
          ),
          SwitchListTile(
            title: const Text('Admin duyuruları'),
            value: _prefs.admin,
            onChanged: !_prefs.pushEnabled
                ? null
                : (v) => _save(_prefs.copyWith(admin: v)),
          ),
        ],
      ),
    );
  }
}
