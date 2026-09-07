import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/icons/mt_icons.dart';
import '../../core/theme/app_colors.dart';
import '../../models/models.dart';
import '../auth/data/auth_provider.dart';
import '../jobs/jobs_provider.dart';

/// Çıkış yapmadan bağlı hesaplar arasında geçiş.
class LinkedAccountsBlock extends StatefulWidget {
  const LinkedAccountsBlock({super.key, required this.user});

  final AppUser user;

  @override
  State<LinkedAccountsBlock> createState() => _LinkedAccountsBlockState();
}

class _LinkedAccountsBlockState extends State<LinkedAccountsBlock> {
  bool _working = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final auth = context.read<AuthProvider>();
      for (final id in widget.user.linkedAccountIds) {
        auth.ensureUserLoaded(id);
      }
    });
  }

  Future<void> _switchTo(String id) async {
    if (_working) return;
    setState(() => _working = true);
    final auth = context.read<AuthProvider>();
    final jobs = context.read<JobsProvider>();
    jobs.companyLogout();
    final ok = await auth.switchLinkedAccount(id);
    if (!mounted) return;
    setState(() => _working = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          ok
              ? 'Hesap değiştirildi. Çıkış yapmadan geçtin.'
              : (auth.error ?? 'Geçiş başarısız.'),
        ),
      ),
    );
    if (ok) context.go('/home');
  }

  Future<void> _linkOther() async {
    final emailCtrl = TextEditingController();
    final passCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Hesap bağla'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Diğer hesabın e-posta ve şifresi. İkisinde de çıkış yapmadan geçiş açılır.',
            ),
            const SizedBox(height: 12),
            TextField(
              controller: emailCtrl,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(labelText: 'E-posta'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: passCtrl,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Şifre'),
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
            child: const Text('Bağla'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _working = true);
    final auth = context.read<AuthProvider>();
    final linked = await auth.linkOwnedAccount(
      email: emailCtrl.text,
      password: passCtrl.text,
    );
    if (!mounted) return;
    setState(() => _working = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          linked ? 'Hesap bağlandı.' : (auth.error ?? 'Bağlama başarısız.'),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final ids = widget.user.linkedAccountIds
        .where((id) => id.isNotEmpty && id != widget.user.id)
        .toList();
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.border),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Bağlı hesaplar',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 4),
              Text(
                'Topluluk / firma hesapların arasında çıkış yapmadan geç.',
                style: TextStyle(
                  color: Colors.black.withValues(alpha: 0.6),
                  fontSize: 13,
                ),
              ),
              if (_working) const LinearProgressIndicator(),
              ...ids.map((id) {
                final u = auth.findUser(id);
                final title = u == null
                    ? id
                    : (u.username?.isNotEmpty == true
                        ? '@${u.username}'
                        : u.fullName.trim());
                final sub = u?.email ?? 'Bağlı hesap';
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const MtIcon(
                    MtIcons.community,
                    size: 20,
                    color: AppColors.navy,
                  ),
                  title: Text(
                    title.isEmpty ? 'Hesap' : title,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  subtitle: Text(sub),
                  trailing: const Icon(Icons.swap_horiz_rounded),
                  onTap: _working ? null : () => _switchTo(id),
                );
              }),
              TextButton.icon(
                onPressed: _working ? null : _linkOther,
                icon: const Icon(Icons.add_link_rounded),
                label: const Text('Başka hesap bağla'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
