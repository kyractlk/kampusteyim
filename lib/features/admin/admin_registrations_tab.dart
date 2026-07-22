import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme/app_colors.dart';
import '../../core/widgets/safe_network_image.dart';
import '../../models/models.dart';
import '../auth/data/auth_provider.dart';
import '../auth/registration_security_config.dart';
import 'admin_provider.dart';

/// Bekleyen öğrenci kayıtları + anlık güvenlik toggles.
class AdminRegistrationsTab extends StatefulWidget {
  const AdminRegistrationsTab({super.key});

  @override
  State<AdminRegistrationsTab> createState() => _AdminRegistrationsTabState();
}

class _AdminRegistrationsTabState extends State<AdminRegistrationsTab> {
  RegistrationSecurityConfig _security = RegistrationSecurityConfig.defaults;
  bool _loadingCfg = true;
  bool _savingCfg = false;

  @override
  void initState() {
    super.initState();
    _loadCfg();
  }

  Future<void> _loadCfg() async {
    final s = await RegistrationSecurityConfig.load();
    if (mounted) {
      setState(() {
        _security = s;
        _loadingCfg = false;
      });
    }
  }

  Future<void> _toggle(RegistrationSecurityConfig next) async {
    setState(() {
      _security = next;
      _savingCfg = true;
    });
    try {
      await next.save();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Kayıt güvenlik ayarı güncellendi')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Kaydedilemedi: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _savingCfg = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final pending = auth.directory
        .where(
          (u) =>
              u.accountStatus == 'pending' && !u.isCommunity && !u.isCompany,
        )
        .toList();

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      children: [
        _SecurityPanel(
          loading: _loadingCfg,
          saving: _savingCfg,
          security: _security,
          onChanged: _toggle,
        ),
        const SizedBox(height: 16),
        Text(
          'Bekleyen kayıtlar (${pending.length})',
          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
        ),
        const SizedBox(height: 10),
        if (pending.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(child: Text('Bekleyen kayıt yok')),
          )
        else
          ...pending.map((u) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _PendingCard(user: u),
              )),
      ],
    );
  }
}

class _SecurityPanel extends StatelessWidget {
  const _SecurityPanel({
    required this.loading,
    required this.saving,
    required this.security,
    required this.onChanged,
  });

  final bool loading;
  final bool saving;
  final RegistrationSecurityConfig security;
  final ValueChanged<RegistrationSecurityConfig> onChanged;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: AppColors.border),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Kayıt güvenlik ayarları',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
                if (loading || saving)
                  const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            const Text(
              'Değişiklikler anında kayıt ekranına yansır.',
              style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Belge doğrulaması zorunlu'),
              subtitle: const Text('Kapalıysa kayıt doğrudan onaylanır'),
              value: security.requireStudentVerification,
              onChanged: loading || saving
                  ? null
                  : (v) => onChanged(
                        security.copyWith(requireStudentVerification: v),
                      ),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Öğrenci kartı (ön/arka)'),
              value: security.allowStudentCard,
              onChanged: loading || saving
                  ? null
                  : (v) => onChanged(security.copyWith(allowStudentCard: v)),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Kartta iki yüz zorunlu'),
              value: security.requireCardBothSides,
              onChanged: loading || saving || !security.allowStudentCard
                  ? null
                  : (v) =>
                      onChanged(security.copyWith(requireCardBothSides: v)),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Öğrenci belgesi PDF'),
              value: security.allowStudentDocumentPdf,
              onChanged: loading || saving
                  ? null
                  : (v) =>
                      onChanged(security.copyWith(allowStudentDocumentPdf: v)),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Zararlı dosya taraması'),
              subtitle: const Text('Magic-byte + exe/arşiv engeli'),
              value: security.malwareScanEnabled,
              onChanged: loading || saving
                  ? null
                  : (v) =>
                      onChanged(security.copyWith(malwareScanEnabled: v)),
            ),
          ],
        ),
      ),
    );
  }
}

class _PendingCard extends StatelessWidget {
  const _PendingCard({required this.user});

  final AppUser user;

  @override
  Widget build(BuildContext context) {
    final type = user.studentVerificationType;
    final typeLabel = switch (type) {
      'card' => 'Öğrenci kartı',
      'document' => 'PDF belge',
      _ => 'Belge',
    };

    return Material(
      color: AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: AppColors.border),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              user.fullName,
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 4),
            Text(
              '${user.studentNo} · ${user.university}\n${user.email}\nTip: $typeLabel',
              style: const TextStyle(
                color: AppColors.textSecondary,
                height: 1.35,
              ),
            ),
            const SizedBox(height: 10),
            if (type == 'card') ...[
              Row(
                children: [
                  Expanded(
                    child: _DocThumb(
                      label: 'Ön yüz',
                      url: user.studentIdFrontUrl ?? user.studentIdDocUrl,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _DocThumb(
                      label: 'Arka yüz',
                      url: user.studentIdBackUrl,
                    ),
                  ),
                ],
              ),
            ] else if (user.studentIdDocUrl != null) ...[
              OutlinedButton.icon(
                onPressed: () => launchUrl(
                  Uri.parse(user.studentIdDocUrl!),
                  mode: LaunchMode.externalApplication,
                ),
                icon: const Icon(Icons.picture_as_pdf_outlined, size: 18),
                label: const Text('PDF belgesini aç'),
              ),
            ],
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: FilledButton(
                    onPressed: () => _review(context, user, true),
                    child: const Text('Onayla'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => _review(context, user, false),
                    child: const Text('Reddet'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _review(BuildContext context, AppUser u, bool approve) async {
    String? reason;
    if (!approve) {
      reason = await showDialog<String>(
        context: context,
        builder: (ctx) {
          final c = TextEditingController();
          return AlertDialog(
            title: const Text('Red sebebi'),
            content: TextField(
              controller: c,
              decoration: const InputDecoration(
                hintText: 'Örn. Belge okunaksız / bilgiler eşleşmiyor',
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Vazgeç'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, c.text.trim()),
                child: const Text('Reddet'),
              ),
            ],
          );
        },
      );
      if (reason == null) return;
    }
    try {
      final callable = FirebaseFunctions.instanceFor(region: 'europe-west1')
          .httpsCallable('reviewStudentRegistration');
      await callable.call({
        'userId': u.id,
        'approve': approve,
        'reason': reason,
      });
      if (!context.mounted) return;
      final auth = context.read<AuthProvider>();
      auth.upsertUser(
        u.copyWith(accountStatus: approve ? 'approved' : 'rejected'),
      );
      context.read<AdminProvider>().status =
          approve ? 'Kayıt onaylandı' : 'Kayıt reddedildi';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            approve ? '${u.fullName} onaylandı' : '${u.fullName} reddedildi',
          ),
        ),
      );
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('İşlem başarısız: $e')),
        );
      }
    }
  }
}

class _DocThumb extends StatelessWidget {
  const _DocThumb({required this.label, this.url});

  final String label;
  final String? url;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          label,
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
        ),
        const SizedBox(height: 6),
        AspectRatio(
          aspectRatio: 1.55,
          child: Material(
            color: AppColors.surfaceMuted,
            borderRadius: BorderRadius.circular(10),
            clipBehavior: Clip.antiAlias,
            child: url == null || url!.isEmpty
                ? const Center(
                    child: Text(
                      'Yok',
                      style: TextStyle(color: AppColors.textSecondary),
                    ),
                  )
                : InkWell(
                    onTap: () => launchUrl(
                      Uri.parse(url!),
                      mode: LaunchMode.externalApplication,
                    ),
                    child: SafeNetworkImage(url: url!, fit: BoxFit.cover),
                  ),
          ),
        ),
      ],
    );
  }
}
