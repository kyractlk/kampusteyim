import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_colors.dart';
import '../feedback/feedback_models.dart';

/// Admin · kullanıcı geri bildirimleri.
class AdminFeedbackTab extends StatefulWidget {
  const AdminFeedbackTab({super.key});

  @override
  State<AdminFeedbackTab> createState() => _AdminFeedbackTabState();
}

class _AdminFeedbackTabState extends State<AdminFeedbackTab> {
  List<UserFeedback> _items = [];
  bool _loading = true;
  String _filter = 'open';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      _items = await UserFeedback.loadForAdmin();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Yüklenemedi: $e')),
        );
      }
    }
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    final list = _filter == 'all'
        ? _items
        : _items.where((e) => e.status == _filter).toList();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  initialValue: _filter,
                  decoration: const InputDecoration(
                    labelText: 'Durum',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'open', child: Text('Açık')),
                    DropdownMenuItem(
                        value: 'reviewing', child: Text('İncelemede')),
                    DropdownMenuItem(value: 'done', child: Text('Tamam')),
                    DropdownMenuItem(value: 'all', child: Text('Tümü')),
                  ],
                  onChanged: (v) {
                    if (v == null) return;
                    setState(() => _filter = v);
                  },
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filledTonal(
                onPressed: _loading ? null : _load,
                icon: _loading
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.refresh),
              ),
            ],
          ),
        ),
        Expanded(
          child: _loading && _items.isEmpty
              ? const Center(child: CircularProgressIndicator())
              : list.isEmpty
                  ? const Center(child: Text('Geri bildirim yok'))
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                      itemCount: list.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 10),
                      itemBuilder: (context, i) {
                        final f = list[i];
                        return Material(
                          color: AppColors.surface,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                            side: BorderSide(
                              color: f.status == 'open'
                                  ? AppColors.cyan.withValues(alpha: 0.5)
                                  : AppColors.border,
                            ),
                          ),
                          child: ExpansionTile(
                            initiallyExpanded: false,
                            title: Text(
                              f.userName,
                              style:
                                  const TextStyle(fontWeight: FontWeight.w800),
                            ),
                            subtitle: Text(
                              '${f.status} · ${DateFormat('d MMM HH:mm', 'tr').format(f.createdAt)}\n${f.message}',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            childrenPadding:
                                const EdgeInsets.fromLTRB(16, 0, 16, 12),
                            children: [
                              Align(
                                alignment: Alignment.centerLeft,
                                child: Text(f.message),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                f.email,
                                style: const TextStyle(
                                  color: AppColors.textSecondary,
                                  fontSize: 12,
                                ),
                              ),
                              const SizedBox(height: 10),
                              Wrap(
                                spacing: 8,
                                children: [
                                  for (final s in [
                                    ('open', 'Açık'),
                                    ('reviewing', 'İncelemede'),
                                    ('done', 'Tamam'),
                                  ])
                                    OutlinedButton(
                                      onPressed: () async {
                                        await UserFeedback.updateStatus(
                                            f.id, s.$1);
                                        await _load();
                                      },
                                      child: Text(s.$2),
                                    ),
                                ],
                              ),
                            ],
                          ),
                        );
                      },
                    ),
        ),
      ],
    );
  }
}
