import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_colors.dart';
import '../legal/legal_consent_models.dart';

/// Admin · KVKK ve pazarlama metinleri.
class AdminLegalTab extends StatefulWidget {
  const AdminLegalTab({super.key, this.editorName});

  final String? editorName;

  @override
  State<AdminLegalTab> createState() => _AdminLegalTabState();
}

class _AdminLegalTabState extends State<AdminLegalTab> {
  final _kvkkTitle = TextEditingController();
  final _kvkkBody = TextEditingController();
  final _marketingTitle = TextEditingController();
  final _marketingBody = TextEditingController();
  bool _loading = true;
  bool _saving = false;
  DateTime? _updatedAt;
  String? _updatedBy;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _kvkkTitle.dispose();
    _kvkkBody.dispose();
    _marketingTitle.dispose();
    _marketingBody.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final t = await LegalConsentTexts.load();
    _kvkkTitle.text = t.kvkkTitle;
    _kvkkBody.text = t.kvkkBody;
    _marketingTitle.text = t.marketingTitle;
    _marketingBody.text = t.marketingBody;
    _updatedAt = t.updatedAt;
    _updatedBy = t.updatedBy;
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final texts = LegalConsentTexts(
        kvkkTitle: _kvkkTitle.text.trim(),
        kvkkBody: _kvkkBody.text.trim(),
        marketingTitle: _marketingTitle.text.trim(),
        marketingBody: _marketingBody.text.trim(),
      );
      await LegalConsentTexts.save(texts, by: widget.editorName);
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Yasal metinler kaydedildi')),
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

  Future<void> _resetDefaults() async {
    final d = LegalConsentTexts.defaults;
    setState(() {
      _kvkkTitle.text = d.kvkkTitle;
      _kvkkBody.text = d.kvkkBody;
      _marketingTitle.text = d.marketingTitle;
      _marketingBody.text = d.marketingBody;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      children: [
        const Text(
          'Kayıt ekranındaki zorunlu onay metinleri',
          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
        ),
        const SizedBox(height: 4),
        Text(
          _updatedAt == null
              ? 'Henüz kaydedilmedi · varsayılan metinler kullanılıyor'
              : 'Son güncelleme: ${DateFormat('d MMM yyyy HH:mm', 'tr').format(_updatedAt!)}'
                  '${_updatedBy != null ? ' · $_updatedBy' : ''}',
          style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _kvkkTitle,
          decoration: const InputDecoration(
            labelText: 'KVKK başlık',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _kvkkBody,
          minLines: 8,
          maxLines: 14,
          decoration: const InputDecoration(
            labelText: 'KVKK metin',
            alignLabelWithHint: true,
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 20),
        TextField(
          controller: _marketingTitle,
          decoration: const InputDecoration(
            labelText: 'Pazarlama başlık',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _marketingBody,
          minLines: 6,
          maxLines: 12,
          decoration: const InputDecoration(
            labelText: 'Pazarlama / ticari iletişim metin',
            alignLabelWithHint: true,
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            OutlinedButton(
              onPressed: _saving ? null : _resetDefaults,
              child: const Text('Varsayılana doldur'),
            ),
            const Spacer(),
            FilledButton(
              onPressed: _saving ? null : _save,
              child: Text(_saving ? 'Kaydediliyor…' : 'Kaydet'),
            ),
          ],
        ),
      ],
    );
  }
}
