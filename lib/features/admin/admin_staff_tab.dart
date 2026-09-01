import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/icons/mt_icons.dart';
import '../../core/theme/app_colors.dart';
import '../auth/data/auth_provider.dart';
import 'admin_provider.dart';

/// Personel / admin hesap yönetimi — oluştur + liste.
class AdminStaffTab extends StatefulWidget {
  const AdminStaffTab({super.key});

  @override
  State<AdminStaffTab> createState() => _AdminStaffTabState();
}

class _AdminStaffTabState extends State<AdminStaffTab> {
  final _first = TextEditingController();
  final _last = TextEditingController();
  final _email = TextEditingController();
  String? _roleId;
  bool _busy = false;
  String? _error;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final admin = context.read<AdminProvider>();
    final list = admin.roles.where((r) => !r.isSuper).toList();
    _roleId ??= list.isEmpty ? null : list.first.id;
  }

  @override
  void dispose() {
    _first.dispose();
    _last.dispose();
    _email.dispose();
    super.dispose();
  }

  Future<String?> _pickRole(AdminProvider admin) {
    final roles = admin.roles.where((r) => !r.isSuper).toList();
    return showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Rol seç'),
        children: [
          for (final r in roles)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, r.id),
              child: Text('${r.name} · ${r.permissions.length} yetki'),
            ),
        ],
      ),
    );
  }

  Future<void> _create() async {
    final auth = context.read<AuthProvider>();
    final admin = context.read<AdminProvider>();
    if (_first.text.trim().isEmpty ||
        _email.text.trim().isEmpty ||
        _roleId == null) {
      setState(() => _error = 'Ad, e-posta ve rol gerekli');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await admin.createAdminAccount(
        auth: auth,
        firstName: _first.text,
        lastName: _last.text,
        email: _email.text,
        roleId: _roleId!,
      );
      if (!mounted) return;
      _first.clear();
      _last.clear();
      _email.clear();
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(admin.status ?? 'Admin oluşturuldu')),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = admin.status ?? '$e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final admin = context.watch<AdminProvider>();
    final staff = admin.staffMembers(auth);
    final assignable = admin.roles.where((r) => !r.isSuper).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Adminler',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
              ),
              const SizedBox(height: 4),
              Text(
                'Personel hesabı aç, rol ata. Süper admin buradan oluşturulmaz.',
                style: TextStyle(
                  fontSize: 12.5,
                  color: AppColors.textSecondary.withValues(alpha: 0.95),
                  height: 1.35,
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
                    const Row(
                      children: [
                        Icon(Icons.badge_outlined, color: AppColors.navy),
                        SizedBox(width: 10),
                        Text(
                          'Yeni personel',
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 15,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _first,
                            textCapitalization: TextCapitalization.words,
                            decoration: const InputDecoration(
                              labelText: 'Ad *',
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: TextField(
                            controller: _last,
                            textCapitalization: TextCapitalization.words,
                            decoration: const InputDecoration(
                              labelText: 'Soyad',
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _email,
                      keyboardType: TextInputType.emailAddress,
                      decoration: const InputDecoration(
                        labelText: 'E-posta *',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.mail_outline),
                      ),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      // ignore: deprecated_member_use
                      value: assignable.any((r) => r.id == _roleId)
                          ? _roleId
                          : (assignable.isNotEmpty ? assignable.first.id : null),
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Rol *',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.security_outlined),
                      ),
                      items: [
                        for (final r in assignable)
                          DropdownMenuItem(
                            value: r.id,
                            child: Text(
                              '${r.name} (${r.permissions.length} yetki)',
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                      onChanged: (v) => setState(() => _roleId = v),
                    ),
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
                      onPressed: _busy ? null : _create,
                      icon: _busy
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const MtIcon(
                              MtIcons.admin,
                              size: 18,
                              color: Colors.white,
                            ),
                      label: Text(
                        _busy ? 'Oluşturuluyor…' : 'Admin oluştur ve rol ata',
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'Mevcut adminler (${staff.length})',
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 15,
                ),
              ),
              const SizedBox(height: 10),
              if (staff.isEmpty)
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: const Text(
                    'Henüz personel yok.',
                    style: TextStyle(color: AppColors.textSecondary),
                  ),
                )
              else
                ...staff.map((u) {
                  final role = admin.roleById(u.staffRoleId);
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Material(
                      color: AppColors.surface,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                        side: const BorderSide(color: AppColors.border),
                      ),
                      child: ListTile(
                        contentPadding: const EdgeInsets.fromLTRB(14, 6, 6, 6),
                        title: Text(
                          u.fullName,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        subtitle: Text(
                          '${u.email}\n${role?.name ?? 'rol yok'}'
                          '${u.isSuperAdmin ? ' · süper' : ''}',
                        ),
                        isThreeLine: true,
                        trailing: u.isSuperAdmin
                            ? const Chip(
                                label: Text('Süper'),
                                visualDensity: VisualDensity.compact,
                              )
                            : PopupMenuButton<String>(
                                onSelected: (v) async {
                                  if (v == 'revoke') {
                                    await admin.revokeStaffAccess(
                                      auth: auth,
                                      userId: u.id,
                                    );
                                  } else if (v == 'role') {
                                    final id = await _pickRole(admin);
                                    if (id != null) {
                                      await admin.assignStaffRole(
                                        auth: auth,
                                        userId: u.id,
                                        roleId: id,
                                      );
                                    }
                                  }
                                },
                                itemBuilder: (_) => const [
                                  PopupMenuItem(
                                    value: 'role',
                                    child: Text('Rol değiştir'),
                                  ),
                                  PopupMenuItem(
                                    value: 'revoke',
                                    child: Text('Adminliği kaldır'),
                                  ),
                                ],
                              ),
                      ),
                    ),
                  );
                }),
            ],
          ),
        ),
      ],
    );
  }
}
