import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme/app_colors.dart';

/// CV-AI kullanıcı başı günlük kota — 0 = sınırsız (ileride rate limit).
class AdminCvAiLimitsTab extends StatefulWidget {
  const AdminCvAiLimitsTab({super.key});

  @override
  State<AdminCvAiLimitsTab> createState() => _AdminCvAiLimitsTabState();
}

class _AdminCvAiLimitsTabState extends State<AdminCvAiLimitsTab> {
  final _limit = TextEditingController(text: '0');
  bool _enabled = true;
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _limit.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('app_config')
          .doc('cv_ai_limits')
          .get();
      final d = doc.data() ?? {};
      _enabled = d['enabled'] != false;
      final n = d['perUserDailyLimit'];
      _limit.text = '${n is num ? n.toInt() : 0}';
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final n = int.tryParse(_limit.text.trim()) ?? 0;
    try {
      await FirebaseFirestore.instance.collection('app_config').doc('cv_ai_limits').set(
        {
          'enabled': _enabled,
          'perUserDailyLimit': n < 0 ? 0 : n,
          'updatedAt': DateTime.now().toIso8601String(),
          'note': '0 = sınırsız. Pozitif sayı = user başı günlük CV-AI üretimi.',
        },
        SetOptions(merge: true),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('CV-AI limitleri kaydedildi')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Kayıt hatası: $e')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text(
          'CV-AI kullanım limitleri',
          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
        ),
        const SizedBox(height: 6),
        const Text(
          'İleride OpenAI rate limit’e takılmamak için kullanıcı başına '
          'günlük CV üretimi kısıtlanabilir. Şu an 0 = sınırsız.',
          style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
        ),
        const SizedBox(height: 16),
        SwitchListTile(
          title: const Text('Limit sistemi açık'),
          subtitle: const Text('Kapalıysa kota kontrolü yapılmaz'),
          value: _enabled,
          onChanged: (v) => setState(() => _enabled = v),
        ),
        TextField(
          controller: _limit,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: const InputDecoration(
            labelText: 'User başı günlük limit',
            helperText: '0 = sınırsız',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Kaydet'),
        ),
      ],
    );
  }
}
