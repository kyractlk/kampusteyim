import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/storage/media_upload.dart';
import '../../core/theme/app_colors.dart';
import '../auth/data/auth_provider.dart';
import 'company_portal.dart';
import 'job_models.dart';
import 'jobs_provider.dart';

class CompanySettingsScreen extends StatefulWidget {
  const CompanySettingsScreen({super.key});

  @override
  State<CompanySettingsScreen> createState() => _CompanySettingsScreenState();
}

class _CompanySettingsScreenState extends State<CompanySettingsScreen> {
  late final TextEditingController _contact;
  late final TextEditingController _title;
  late final TextEditingController _email;
  late final TextEditingController _phone;
  late final TextEditingController _website;
  late final TextEditingController _address;
  late final TextEditingController _extra;
  String _logoUrl = '';
  bool _saving = false;
  bool _uploading = false;

  @override
  void initState() {
    super.initState();
    final c = context.read<JobsProvider>().company;
    final s = c?.mailSignature ?? const CompanyMailSignature();
    _logoUrl = s.logoUrl.isNotEmpty ? s.logoUrl : (c?.logoUrl ?? '');
    _contact = TextEditingController(
      text: s.contactName.isNotEmpty ? s.contactName : (c?.name ?? ''),
    );
    _title = TextEditingController(text: s.jobTitle);
    _email = TextEditingController(
      text: s.replyEmail.isNotEmpty ? s.replyEmail : (c?.email ?? ''),
    );
    _phone = TextEditingController(text: s.phone);
    _website = TextEditingController(text: s.website);
    _address = TextEditingController(text: s.address);
    _extra = TextEditingController(text: s.extraText);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await context.read<JobsProvider>().refreshCompanyProfile();
      if (!mounted) return;
      final fresh = context.read<JobsProvider>().company?.mailSignature;
      if (fresh == null) return;
      setState(() {
        if (fresh.logoUrl.isNotEmpty) _logoUrl = fresh.logoUrl;
        if (fresh.contactName.isNotEmpty) _contact.text = fresh.contactName;
        if (fresh.jobTitle.isNotEmpty) _title.text = fresh.jobTitle;
        if (fresh.replyEmail.isNotEmpty) _email.text = fresh.replyEmail;
        if (fresh.phone.isNotEmpty) _phone.text = fresh.phone;
        if (fresh.website.isNotEmpty) _website.text = fresh.website;
        if (fresh.address.isNotEmpty) _address.text = fresh.address;
        if (fresh.extraText.isNotEmpty) _extra.text = fresh.extraText;
      });
    });
  }

  @override
  void dispose() {
    _contact.dispose();
    _title.dispose();
    _email.dispose();
    _phone.dispose();
    _website.dispose();
    _address.dispose();
    _extra.dispose();
    super.dispose();
  }

  Future<void> _pickLogo() async {
    final auth = context.read<AuthProvider>();
    final jobs = context.read<JobsProvider>();
    final file = await MediaUpload.pickImage();
    if (file == null || !mounted) return;
    setState(() => _uploading = true);
    try {
      final url = await MediaUpload.uploadXFile(
        file: file,
        folder: 'company_logos/${jobs.company?.id ?? 'firma'}',
        firstName: auth.user?.firstName ?? 'firma',
        lastName: auth.user?.lastName ?? 'logo',
        studentNo: jobs.company?.id ?? 'co',
        isVideo: false,
      );
      if (!mounted) return;
      setState(() => _logoUrl = url);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Logo yüklenemedi: $e')),
      );
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _save() async {
    final jobs = context.read<JobsProvider>();
    final sig = CompanyMailSignature(
      logoUrl: _logoUrl.trim(),
      contactName: _contact.text.trim(),
      jobTitle: _title.text.trim(),
      replyEmail: _email.text.trim(),
      phone: _phone.text.trim(),
      website: _website.text.trim(),
      address: _address.text.trim(),
      extraText: _extra.text.trim(),
      configured: true,
    );
    if (!sig.isReady) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Logo, yetkili adı ve yanıt e-postası zorunlu.',
          ),
        ),
      );
      return;
    }
    setState(() => _saving = true);
    await jobs.saveMailSignature(sig);
    if (!mounted) return;
    setState(() => _saving = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(jobs.status ?? 'Kaydedildi')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final jobs = context.watch<JobsProvider>();
    if (jobs.company == null) {
      return const CompanyLoginScreen();
    }

    return CompanyPortalShell(
      child: Scaffold(
        appBar: AppBar(title: const Text('Firma ayarları · Mail imzası')),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.navy.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: AppColors.navy.withValues(alpha: 0.12),
                    ),
                  ),
                  child: const Text(
                    'Gmail’deki gibi kurumsal imzanızı ayarlayın. '
                    'Öğrenciye giden tüm mailler, teklifler ve ilan bildirimleri '
                    'firma logosu + bu imza ile HTML olarak gönderilir.',
                    style: TextStyle(height: 1.45),
                  ),
                ),
                const SizedBox(height: 18),
                Text(
                  'Firma logosu',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    CircleAvatar(
                      radius: 36,
                      backgroundColor: AppColors.surfaceMuted,
                      backgroundImage:
                          _logoUrl.isNotEmpty ? NetworkImage(_logoUrl) : null,
                      child: _logoUrl.isEmpty
                          ? const Icon(Icons.business, size: 32)
                          : null,
                    ),
                    const SizedBox(width: 16),
                    FilledButton.tonal(
                      onPressed: _uploading ? null : _pickLogo,
                      child: Text(_uploading ? 'Yükleniyor…' : 'Logo seç'),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                TextField(
                  controller: _contact,
                  decoration: const InputDecoration(
                    labelText: 'Yetkili adı soyadı *',
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _title,
                  decoration: const InputDecoration(
                    labelText: 'Ünvan',
                    hintText: 'ör. İK Uzmanı, Talent Lead',
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                    labelText: 'Yanıt e-postası *',
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _phone,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(labelText: 'Telefon'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _website,
                  keyboardType: TextInputType.url,
                  decoration: const InputDecoration(
                    labelText: 'Web sitesi',
                    hintText: 'https://',
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _address,
                  decoration: const InputDecoration(labelText: 'Adres'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _extra,
                  maxLines: 4,
                  decoration: const InputDecoration(
                    labelText: 'Ek imza metni',
                    hintText: 'Kapanış cümlesi, yasal uyarı vb.',
                  ),
                ),
                const SizedBox(height: 20),
                if (jobs.hasMailSignature)
                  const Padding(
                    padding: EdgeInsets.only(bottom: 12),
                    child: Row(
                      children: [
                        Icon(Icons.verified, color: AppColors.lime),
                        SizedBox(width: 8),
                        Text(
                          'İmza hazır — mail / teklif / ilan bildirimi açıldı',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ],
                    ),
                  ),
                FilledButton(
                  onPressed: _saving ? null : _save,
                  child: Text(_saving ? 'Kaydediliyor…' : 'İmzayı kaydet'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
