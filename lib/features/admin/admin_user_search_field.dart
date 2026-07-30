import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../../models/models.dart';
import '../auth/data/auth_provider.dart';

/// Admin kullanici secimi: ad, e-posta, @handle veya uid ile ara.
class AdminUserSearchField extends StatefulWidget {
  const AdminUserSearchField({
    super.key,
    required this.controller,
    this.labelText = 'Kullanici ara (ad / e-posta / @handle / uid)',
    this.hintText = 'Ornek: Acme, info@firma.com',
    this.filter,
    this.onSelected,
  });

  /// Secilen kullanicinin doc id'si buraya yazilir.
  final TextEditingController controller;
  final String labelText;
  final String hintText;
  final bool Function(AppUser user)? filter;
  final ValueChanged<AppUser>? onSelected;

  @override
  State<AdminUserSearchField> createState() => _AdminUserSearchFieldState();
}

class _AdminUserSearchFieldState extends State<AdminUserSearchField> {
  final _queryCtrl = TextEditingController();
  AppUser? _selected;

  @override
  void dispose() {
    _queryCtrl.dispose();
    super.dispose();
  }

  List<AppUser> _hits(AuthProvider auth) {
    final q = _queryCtrl.text.trim();
    if (q.isEmpty) return const [];
    final ql = q.toLowerCase();
    final list = <AppUser>[
      ...auth.searchUsers(q),
      ...auth.directory.where(
        (u) =>
            u.id.toLowerCase() == ql || u.id.toLowerCase().contains(ql),
      ),
    ];
    final seen = <String>{};
    final out = <AppUser>[];
    for (final u in list) {
      if (!seen.add(u.id)) continue;
      if (widget.filter != null && !widget.filter!(u)) continue;
      out.add(u);
      if (out.length >= 25) break;
    }
    return out;
  }

  void _pick(AppUser u) {
    setState(() {
      _selected = u;
      _queryCtrl.clear();
      widget.controller.text = u.id;
    });
    widget.onSelected?.call(u);
    FocusScope.of(context).unfocus();
  }

  void _clear() {
    setState(() {
      _selected = null;
      widget.controller.clear();
      _queryCtrl.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final hits = _hits(auth);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _queryCtrl,
          decoration: InputDecoration(
            labelText: widget.labelText,
            hintText: widget.hintText,
            border: const OutlineInputBorder(),
            suffixIcon: _queryCtrl.text.isEmpty
                ? const Icon(Icons.search)
                : IconButton(
                    icon: const Icon(Icons.clear),
                    onPressed: () {
                      _queryCtrl.clear();
                      setState(() {});
                    },
                  ),
          ),
          onChanged: (_) => setState(() {}),
        ),
        if (_selected != null) ...[
          const SizedBox(height: 8),
          Material(
            color: AppColors.surface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: const BorderSide(color: AppColors.border),
            ),
            child: ListTile(
              dense: true,
              title: Text(
                _selected!.fullName,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              subtitle: Text(
                '${_selected!.email}\n${_selected!.id}',
                style: const TextStyle(fontSize: 12),
              ),
              isThreeLine: true,
              trailing: IconButton(
                tooltip: 'Temizle',
                icon: const Icon(Icons.close),
                onPressed: _clear,
              ),
            ),
          ),
        ] else if (widget.controller.text.trim().isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(
            'Secili id: ${widget.controller.text.trim()}',
            style: const TextStyle(
              fontSize: 12,
              color: AppColors.textSecondary,
            ),
          ),
        ],
        if (_queryCtrl.text.trim().isNotEmpty) ...[
          const SizedBox(height: 6),
          if (hits.isEmpty)
            const Text(
              'Sonuc yok. Ad, e-posta veya uid deneyin.',
              style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
            )
          else
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 220),
              child: Material(
                color: AppColors.surface,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: const BorderSide(color: AppColors.border),
                ),
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: hits.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, i) {
                    final u = hits[i];
                    final role = u.isCompany
                        ? 'firma'
                        : u.isCommunity
                            ? 'topluluk'
                            : 'kullanici';
                    return ListTile(
                      dense: true,
                      title: Text(u.fullName),
                      subtitle: Text('${u.email} · $role'),
                      onTap: () => _pick(u),
                    );
                  },
                ),
              ),
            ),
        ],
      ],
    );
  }
}
