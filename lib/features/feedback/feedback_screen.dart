import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../../core/utils/auth_gate.dart';
import '../auth/data/auth_provider.dart';
import 'feedback_models.dart';

/// Profil → geri bildirim formu.
class FeedbackScreen extends StatefulWidget {
  const FeedbackScreen({super.key});

  @override
  State<FeedbackScreen> createState() => _FeedbackScreenState();
}

class _FeedbackScreenState extends State<FeedbackScreen> {
  final _ctrl = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final auth = context.read<AuthProvider>();
    final user = auth.user;
    if (user == null) {
      AuthGate.requireAuth(context, message: 'Geri bildirim için giriş yap.');
      return;
    }
    final text = _ctrl.text.trim();
    if (text.length < 8) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Biraz daha detay yaz (en az 8 karakter)')),
      );
      return;
    }
    setState(() => _busy = true);
    try {
      await UserFeedback.submit(
        userId: user.id,
        userName: user.fullName,
        email: user.email,
        message: text,
      );
      if (!mounted) return;
      _ctrl.clear();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Teşekkürler · geri bildirimin admin paneline iletildi'),
        ),
      );
      context.pop();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Gönderilemedi: $e')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Geri bildirim')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text(
            'Öneri, hata veya isteklerini yaz. AYS Tech / admin ekibi inceler.',
            style: TextStyle(color: AppColors.textSecondary, height: 1.4),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _ctrl,
            minLines: 5,
            maxLines: 10,
            maxLength: 2000,
            decoration: const InputDecoration(
              labelText: 'Mesajın',
              alignLabelWithHint: true,
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: _busy ? null : _send,
            child: Text(_busy ? 'Gönderiliyor…' : 'Gönder'),
          ),
        ],
      ),
    );
  }
}
