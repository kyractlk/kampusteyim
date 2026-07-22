import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../auth/data/auth_provider.dart';

/// Çift onaylı hesap silme: 1) uyarı 2) e-posta kodu.
class AccountDeleteScreen extends StatefulWidget {
  const AccountDeleteScreen({super.key});

  @override
  State<AccountDeleteScreen> createState() => _AccountDeleteScreenState();
}

class _AccountDeleteScreenState extends State<AccountDeleteScreen> {
  final _code = TextEditingController();
  bool _busy = false;
  bool _codeSent = false;
  String? _hint;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<bool> _firstConfirm() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Hesabını silmek istiyor musun?'),
        content: const Text(
          'Bu işlem geri alınamaz. Profilin, oturumun ve kişisel verilerin '
          'silinir. Paylaşımların “silinmiş hesap” olarak kalabilir.\n\n'
          'Devam edersen e-postana doğrulama kodu gönderilir.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Vazgeç'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.crimson),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Evet, devam et'),
          ),
        ],
      ),
    );
    return ok == true;
  }

  Future<void> _sendCode() async {
    if (!await _firstConfirm()) return;
    setState(() => _busy = true);
    try {
      final callable = FirebaseFunctions.instanceFor(region: 'europe-west1')
          .httpsCallable('requestAccountDeletion');
      final res = await callable.call();
      final map = Map<String, dynamic>.from(res.data as Map);
      setState(() {
        _codeSent = true;
        _hint = map['emailHint'] as String? ??
            'Kod e-posta adresine gönderildi.';
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_hint!)),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Kod gönderilemedi: $e')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _confirmDelete() async {
    final code = _code.text.trim();
    if (code.length < 4) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('E-postadaki kodu gir')),
      );
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Son onay'),
        content: const Text(
          'Hesabın kalıcı olarak silinecek. Emin misin?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Vazgeç'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.crimson),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Hesabımı sil'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    setState(() => _busy = true);
    try {
      final callable = FirebaseFunctions.instanceFor(region: 'europe-west1')
          .httpsCallable('confirmAccountDeletion');
      await callable.call({'code': code});
      if (!mounted) return;
      await context.read<AuthProvider>().signOut();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Hesabın silindi')),
      );
      context.go('/login');
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Silinemedi: $e')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthProvider>().user;
    return Scaffold(
      appBar: AppBar(title: const Text('Hesabı sil')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Icon(Icons.warning_amber_rounded,
              size: 48, color: AppColors.crimson),
          const SizedBox(height: 12),
          Text(
            user?.email ?? '',
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          const Text(
            'Hesap silme işlemi için e-posta adresine tek kullanımlık kod '
            'gönderilir. Kod 15 dakika geçerlidir.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.textSecondary, height: 1.4),
          ),
          const SizedBox(height: 24),
          if (!_codeSent)
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.crimson,
                minimumSize: const Size.fromHeight(48),
              ),
              onPressed: _busy ? null : _sendCode,
              child: Text(_busy ? 'Gönderiliyor…' : 'Doğrulama kodu gönder'),
            )
          else ...[
            if (_hint != null)
              Text(_hint!, style: const TextStyle(color: AppColors.textSecondary)),
            const SizedBox(height: 12),
            TextField(
              controller: _code,
              textCapitalization: TextCapitalization.characters,
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9]')),
              ],
              decoration: const InputDecoration(
                labelText: 'E-posta kodu',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.crimson,
                minimumSize: const Size.fromHeight(48),
              ),
              onPressed: _busy ? null : _confirmDelete,
              child: Text(_busy ? 'Siliniyor…' : 'Kodu doğrula ve sil'),
            ),
            TextButton(
              onPressed: _busy ? null : _sendCode,
              child: const Text('Kodu tekrar gönder'),
            ),
          ],
        ],
      ),
    );
  }
}
