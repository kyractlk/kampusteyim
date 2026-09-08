import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';

import '../../models/models.dart';
import '../auth/data/auth_provider.dart';
import 'admin_provider.dart';

Future<void> showAdminEditUserDialog({
  required BuildContext context,
  required AdminProvider admin,
  required AuthProvider auth,
  required AppUser user,
}) async {
  final saved = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => _AdminEditUserDialog(
      admin: admin,
      auth: auth,
      user: user,
    ),
  );
  if (saved == true && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '${user.fullName.trim().isEmpty ? user.email : user.fullName} güncellendi',
        ),
      ),
    );
  }
}

class _AdminEditUserDialog extends StatefulWidget {
  const _AdminEditUserDialog({
    required this.admin,
    required this.auth,
    required this.user,
  });

  final AdminProvider admin;
  final AuthProvider auth;
  final AppUser user;

  @override
  State<_AdminEditUserDialog> createState() => _AdminEditUserDialogState();
}

class _AdminEditUserDialogState extends State<_AdminEditUserDialog> {
  late final TextEditingController _first;
  late final TextEditingController _last;
  late final TextEditingController _username;
  late final TextEditingController _email;
  late final TextEditingController _phone;
  late final TextEditingController _studentNo;
  late final TextEditingController _city;
  late final TextEditingController _university;
  late final TextEditingController _faculty;
  late final TextEditingController _department;
  late final TextEditingController _bio;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final u = widget.user;
    _first = TextEditingController(text: u.firstName);
    _last = TextEditingController(text: u.lastName);
    _username = TextEditingController(
      text: (u.username ?? '').replaceFirst(RegExp(r'^@'), ''),
    );
    _email = TextEditingController(text: u.email);
    _phone = TextEditingController(text: u.phone);
    _studentNo = TextEditingController(text: u.studentNo);
    _city = TextEditingController(text: u.city);
    _university = TextEditingController(text: u.university);
    _faculty = TextEditingController(text: u.faculty);
    _department = TextEditingController(text: u.department);
    _bio = TextEditingController(text: u.bio);
  }

  @override
  void dispose() {
    _first.dispose();
    _last.dispose();
    _username.dispose();
    _email.dispose();
    _phone.dispose();
    _studentNo.dispose();
    _city.dispose();
    _university.dispose();
    _faculty.dispose();
    _department.dispose();
    _bio.dispose();
    super.dispose();
  }

  InputDecoration _dec(String label, {String? hint}) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      isDense: true,
      border: const OutlineInputBorder(),
    );
  }

  Future<void> _save() async {
    final first = _first.text.trim();
    if (first.isEmpty) {
      setState(() => _error = 'Ad / görünen ad zorunlu');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.admin.updateUserDetails(
        auth: widget.auth,
        user: widget.user,
        firstName: first,
        lastName: _last.text.trim(),
        username: _username.text.trim(),
        email: _email.text.trim(),
        phone: _phone.text.trim(),
        studentNo: _studentNo.text.trim(),
        city: _city.text.trim(),
        university: _university.text.trim(),
        faculty: _faculty.text.trim(),
        department: _department.text.trim(),
        bio: _bio.text.trim(),
      );
      if (!mounted) return;
      Navigator.pop(context, true);
    } on FirebaseFunctionsException catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = e.message ?? e.code;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = '$e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final u = widget.user;
    final nameLabel = (u.isCommunity || u.isCompany)
        ? 'Görünen ad'
        : 'Ad';
    return AlertDialog(
      title: const Text('Hesabı düzenle'),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                u.email,
                style: const TextStyle(fontSize: 13, height: 1.35),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _first,
                enabled: !_busy,
                textCapitalization: TextCapitalization.words,
                decoration: _dec(nameLabel),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _last,
                enabled: !_busy,
                textCapitalization: TextCapitalization.words,
                decoration: _dec('Soyad'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _username,
                enabled: !_busy,
                decoration: _dec('Kullanıcı adı', hint: 'ornek_ad'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _email,
                enabled: !_busy,
                keyboardType: TextInputType.emailAddress,
                decoration: _dec('E-posta'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _phone,
                enabled: !_busy,
                keyboardType: TextInputType.phone,
                decoration: _dec('Telefon'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _studentNo,
                enabled: !_busy,
                decoration: _dec('Öğrenci / hesap no'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _city,
                enabled: !_busy,
                decoration: _dec('Şehir'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _university,
                enabled: !_busy,
                decoration: _dec('Üniversite'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _faculty,
                enabled: !_busy,
                decoration: _dec('Fakülte'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _department,
                enabled: !_busy,
                decoration: _dec('Bölüm'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _bio,
                enabled: !_busy,
                maxLines: 3,
                decoration: _dec('Biyografi'),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(
                  _error!,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.error,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context, false),
          child: const Text('Vazgeç'),
        ),
        FilledButton(
          onPressed: _busy ? null : _save,
          child: _busy
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
