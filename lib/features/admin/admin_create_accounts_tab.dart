import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../../data/campus_catalog.dart';
import '../auth/data/auth_provider.dart';
import 'admin_permissions.dart';
import 'admin_provider.dart';

/// Firma / topluluk hesabı açma — sade hub + tek form.
class AdminCreateAccountsTab extends StatefulWidget {
  const AdminCreateAccountsTab({super.key});

  @override
  State<AdminCreateAccountsTab> createState() => _AdminCreateAccountsTabState();
}

class _AdminCreateAccountsTabState extends State<AdminCreateAccountsTab> {
  String _kind = 'company'; // company | community
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _pass = TextEditingController();
  bool _autoPass = true;
  bool _busy = false;
  String? _error;

  CampusCatalog? _catalog;
  String? _city;
  String? _university;

  @override
  void initState() {
    super.initState();
    CampusCatalog.load().then((c) {
      if (!mounted) return;
      setState(() {
        _catalog = c;
        _city = c.cities.contains('Gaziantep')
            ? 'Gaziantep'
            : (c.cities.isNotEmpty ? c.cities.first : null);
        final unis = c.universitiesForCity(_city);
        _university = unis.isNotEmpty ? unis.first : null;
      });
    });
  }

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _pass.dispose();
    super.dispose();
  }

  void _switchKind(String kind) {
    if (_kind == kind) return;
    setState(() {
      _kind = kind;
      _error = null;
      _name.clear();
      _email.clear();
      _pass.clear();
      _autoPass = true;
    });
  }

  Future<void> _submit() async {
    final auth = context.read<AuthProvider>();
    final admin = context.read<AdminProvider>();
    final me = auth.user;
    if (me == null) return;

    final isCompany = _kind == 'company';
    if (isCompany && !admin.can(me, AdminPermission.createCompany)) return;
    if (!isCompany && !admin.can(me, AdminPermission.createCommunity)) return;

    final name = _name.text.trim();
    final email = _email.text.trim();
    if (name.isEmpty || email.isEmpty || !email.contains('@')) {
      setState(() => _error = 'Ad ve geçerli e-posta gerekli');
      return;
    }
    if (!_autoPass && _pass.text.trim().length < 6) {
      setState(() => _error = 'Şifre en az 6 karakter olmalı');
      return;
    }
    if (!isCompany && (_city == null || _city!.trim().isEmpty)) {
      setState(() => _error = 'Topluluk için şehir seç');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await admin.createManagedAccount(
        auth: auth,
        displayName: name,
        email: email,
        kind: _kind,
        password: _autoPass ? null : _pass.text.trim(),
        city: _city,
        university: isCompany ? '—' : (_university ?? ''),
      );
      if (!mounted) return;
      _name.clear();
      _email.clear();
      _pass.clear();
      setState(() {
        _busy = false;
        _autoPass = true;
      });
      await _showCreds(
        title: isCompany ? 'Firma hesabı hazır' : 'Topluluk hesabı hazır',
        email: result.user.email,
        password: result.password,
        kindLabel: isCompany ? 'Firma paneli' : 'Topluluk hesabı',
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = admin.status ?? '$e';
      });
    }
  }

  Future<void> _showCreds({
    required String title,
    required String email,
    required String password,
    required String kindLabel,
  }) async {
    final blob = 'E-posta: $email\nGeçici şifre: $password';
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '$kindLabel oluşturuldu. Bilgileri güvenli kanaldan ilet.',
              style: const TextStyle(
                color: AppColors.textSecondary,
                height: 1.35,
              ),
            ),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.surfaceMuted,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.border),
              ),
              child: SelectableText(
                blob,
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  height: 1.45,
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: blob));
              if (ctx.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Panoya kopyalandı')),
                );
              }
            },
            child: const Text('Kopyala'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Tamam'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final admin = context.watch<AdminProvider>();
    final me = auth.user;
    if (me == null) {
      return const Center(child: Text('Giriş gerekli'));
    }

    final canCompany = admin.can(me, AdminPermission.createCompany);
    final canCommunity = admin.can(me, AdminPermission.createCommunity);
    if (!canCompany && !canCommunity) {
      return const Center(child: Text('Hesap açma yetkin yok'));
    }

    // Yetki yoksa diğer türe düş
    if (_kind == 'company' && !canCompany && canCommunity) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _kind = 'community');
      });
    } else if (_kind == 'community' && !canCommunity && canCompany) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _kind = 'company');
      });
    }

    final isCompany = _kind == 'company';
    final unis = _catalog?.universitiesForCity(_city) ?? const <String>[];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Hesap aç',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
              ),
              const SizedBox(height: 4),
              const Text(
                'Firma veya üniversite topluluğu için Auth + profil oluştur. '
                'Geçici şifre otomatik üretilebilir; e-postaya da gider.',
                style: TextStyle(
                  fontSize: 12.5,
                  color: AppColors.textSecondary,
                  height: 1.35,
                ),
              ),
              const SizedBox(height: 12),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    if (canCompany)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                          avatar: Icon(
                            Icons.business_outlined,
                            size: 16,
                            color: _kind == 'company'
                                ? AppColors.navy
                                : AppColors.textSecondary,
                          ),
                          label: const Text('Firma'),
                          selected: _kind == 'company',
                          onSelected: (_) => _switchKind('company'),
                        ),
                      ),
                    if (canCommunity)
                      ChoiceChip(
                        avatar: Icon(
                          Icons.groups_outlined,
                          size: 16,
                          color: _kind == 'community'
                              ? AppColors.navy
                              : AppColors.textSecondary,
                        ),
                        label: const Text('Topluluk'),
                        selected: _kind == 'community',
                        onSelected: (_) => _switchKind('community'),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
            children: [
              Container(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 18),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.border),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: AppColors.cyan.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(
                            isCompany
                                ? Icons.business_outlined
                                : Icons.groups_outlined,
                            color: AppColors.navy,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                isCompany
                                    ? 'Yeni firma hesabı'
                                    : 'Yeni topluluk hesabı',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 15,
                                ),
                              ),
                              Text(
                                isCompany
                                    ? 'İş ilanı ve firma paneli erişimi'
                                    : 'Gold rozetli resmi kulüp / topluluk',
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: AppColors.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _name,
                      textCapitalization: TextCapitalization.words,
                      decoration: InputDecoration(
                        labelText: isCompany ? 'Firma adı *' : 'Topluluk adı *',
                        hintText: isCompany
                            ? 'Örn. AYS Tech'
                            : 'Örn. Mühendislik Topluluğu',
                        border: const OutlineInputBorder(),
                        prefixIcon: Icon(
                          isCompany
                              ? Icons.apartment_outlined
                              : Icons.diversity_3_outlined,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _email,
                      keyboardType: TextInputType.emailAddress,
                      autocorrect: false,
                      decoration: const InputDecoration(
                        labelText: 'E-posta *',
                        hintText: 'giris@ornek.com',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.mail_outline),
                      ),
                    ),
                    if (!isCompany) ...[
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        // ignore: deprecated_member_use
                        value: _city != null &&
                                (_catalog?.cities.contains(_city) ?? false)
                            ? _city
                            : null,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'Şehir *',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.location_city_outlined),
                        ),
                        items: [
                          for (final c in _catalog?.cities ?? const <String>[])
                            DropdownMenuItem(value: c, child: Text(c)),
                        ],
                        onChanged: (v) => setState(() {
                          _city = v;
                          final u = _catalog?.universitiesForCity(v) ?? [];
                          _university = u.isNotEmpty ? u.first : null;
                        }),
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        // ignore: deprecated_member_use
                        value: _university != null && unis.contains(_university)
                            ? _university
                            : (unis.isNotEmpty ? unis.first : null),
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'Üniversite',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.school_outlined),
                        ),
                        items: [
                          for (final u in unis)
                            DropdownMenuItem(
                              value: u,
                              child: Text(u, overflow: TextOverflow.ellipsis),
                            ),
                        ],
                        onChanged: (v) => setState(() => _university = v),
                      ),
                    ] else ...[
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        // ignore: deprecated_member_use
                        value: _city != null &&
                                (_catalog?.cities.contains(_city) ?? false)
                            ? _city
                            : null,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'Şehir',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.location_city_outlined),
                        ),
                        items: [
                          for (final c in _catalog?.cities ?? const <String>[])
                            DropdownMenuItem(value: c, child: Text(c)),
                        ],
                        onChanged: (v) => setState(() => _city = v),
                      ),
                    ],
                    const SizedBox(height: 8),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Otomatik geçici şifre'),
                      subtitle: const Text(
                        'Açıkken güvenli şifre üretilir ve e-postaya gider',
                      ),
                      value: _autoPass,
                      onChanged: _busy
                          ? null
                          : (v) => setState(() {
                                _autoPass = v;
                                if (v) _pass.clear();
                              }),
                    ),
                    if (!_autoPass) ...[
                      const SizedBox(height: 4),
                      TextField(
                        controller: _pass,
                        obscureText: true,
                        decoration: const InputDecoration(
                          labelText: 'Şifre (min. 6)',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.lock_outline),
                        ),
                      ),
                    ],
                    if (_error != null) ...[
                      const SizedBox(height: 10),
                      Text(
                        _error!,
                        style: const TextStyle(
                          color: AppColors.crimson,
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                    ],
                    const SizedBox(height: 14),
                    FilledButton.icon(
                      onPressed: _busy ? null : _submit,
                      icon: _busy
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.person_add_alt_1_outlined),
                      label: Text(
                        _busy
                            ? 'Oluşturuluyor…'
                            : (isCompany
                                ? 'Firma hesabını aç'
                                : 'Topluluk hesabını aç'),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              Text(
                isCompany
                    ? 'Aynı e-posta ile ikinci hesap açılamaz. Firma /firma panelinden giriş yapar.'
                    : 'Topluluk hesabına gold rozet verilir. Kampüs feed’inde üniversitesine göre öne çıkar.',
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
