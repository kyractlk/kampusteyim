import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../../core/widgets/app_circle_logo.dart';
import '../auth/data/auth_provider.dart';
import '../maintenance/maintenance_provider.dart';
import 'admin_provider.dart';

/// Admin · AYS Tech planlı bakım paneli.
class AdminMaintenanceTab extends StatefulWidget {
  const AdminMaintenanceTab({
    super.key,
    required this.auth,
    required this.admin,
  });

  final AuthProvider auth;
  final AdminProvider admin;

  @override
  State<AdminMaintenanceTab> createState() => _AdminMaintenanceTabState();
}

class _AdminMaintenanceTabState extends State<AdminMaintenanceTab> {
  final _title = TextEditingController(text: 'Planlı bakım');
  final _message = TextEditingController(
    text:
        'KampüsteyimAPP şu an AYS Tech tarafından planlı bakıma alındı. Kısa süre içinde geri döneceğiz.',
  );
  DateTime? _start;
  DateTime? _end;
  bool _startNow = true;
  bool _autoActivate = true;
  bool _notifyOnStart = true;
  bool _hydrated = false;

  @override
  void dispose() {
    _title.dispose();
    _message.dispose();
    super.dispose();
  }

  void _hydrateFrom(MaintenanceProvider m) {
    if (_hydrated) return;
    final st = m.state;
    if (st.updatedAt == null && !st.active) return;
    _title.text = st.title;
    _message.text = st.message;
    _start = st.plannedStart;
    _end = st.plannedEnd;
    _autoActivate = st.autoActivate;
    _startNow = st.active;
    _hydrated = true;
  }

  Future<void> _pickDateTime({required bool isStart}) async {
    final now = DateTime.now();
    final initial = isStart
        ? (_start ?? now.add(const Duration(minutes: 5)))
        : (_end ?? now.add(const Duration(hours: 1)));
    final date = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: now.subtract(const Duration(days: 1)),
      lastDate: now.add(const Duration(days: 365)),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
    );
    if (time == null || !mounted) return;
    final dt = DateTime(date.year, date.month, date.day, time.hour, time.minute);
    setState(() {
      if (isStart) {
        _start = dt;
      } else {
        _end = dt;
      }
    });
  }

  String _fmt(DateTime? d) {
    if (d == null) return 'Seçilmedi';
    return DateFormat('dd.MM.yyyy HH:mm', 'tr').format(d.toLocal());
  }

  Future<void> _save({required bool activate}) async {
    final start = _start ?? DateTime.now();
    final end = _end ?? start.add(const Duration(hours: 1));
    if (end.isBefore(start)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Bitiş, başlangıçtan sonra olmalı')),
      );
      return;
    }
    try {
      await widget.admin.setMaintenance(
        title: _title.text.trim(),
        message: _message.text.trim(),
        plannedStart: start,
        plannedEnd: end,
        active: activate,
        autoActivate: _autoActivate,
        notifyOnStart: _notifyOnStart,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(widget.admin.status ?? 'Kaydedildi')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Hata: $e')),
      );
    }
  }

  Future<void> _endMaintenance() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Bakımı bitir?'),
        content: const Text(
          'Kullanıcılar uygulamaya döner. Abone olanlara push / e-posta gider.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Vazgeç'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Bitir ve haber ver'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await widget.admin.endMaintenance();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(widget.admin.status ?? 'Bakım bitti')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Hata: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final maint = context.watch<MaintenanceProvider>();
    final admin = widget.admin;
    _hydrateFrom(maint);
    final st = maint.state;

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
      children: [
        Row(
          children: [
            const AppCircleLogo(logo: AppLogo.ays, size: 44),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'AYS Tech Bakım',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: AppColors.navy,
                    ),
                  ),
                  Text(
                    st.active
                        ? 'Canlı · kullanıcılar bakım ekranında'
                        : 'Kapalı · uygulama açık',
                    style: TextStyle(
                      color: st.active ? AppColors.crimson : AppColors.lime,
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
            if (st.active)
              FilledButton.tonal(
                onPressed: admin.busy ? null : _endMaintenance,
                style: FilledButton.styleFrom(
                  foregroundColor: AppColors.crimson,
                ),
                child: const Text('Bakımı bitir'),
              ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          'Abone: ${st.subscriberCount} · Oturum: ${st.sessionId ?? '—'}',
          style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
        ),
        const SizedBox(height: 20),
        TextField(
          controller: _title,
          decoration: const InputDecoration(
            labelText: 'Başlık',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _message,
          minLines: 3,
          maxLines: 5,
          decoration: const InputDecoration(
            labelText: 'Mesaj',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 16),
        _DateTile(
          label: 'Planlanan başlangıç',
          value: _fmt(_start),
          onTap: () => _pickDateTime(isStart: true),
        ),
        const SizedBox(height: 8),
        _DateTile(
          label: 'Planlanan bitiş (geri sayım)',
          value: _fmt(_end),
          onTap: () => _pickDateTime(isStart: false),
        ),
        const SizedBox(height: 8),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Hemen başlat'),
          subtitle: const Text('Kaydetince bakım ekranı açılır'),
          value: _startNow,
          onChanged: (v) => setState(() => _startNow = v),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Otomatik başlat'),
          subtitle: const Text('Başlangıç saati gelince sunucu aktif eder'),
          value: _autoActivate,
          onChanged: (v) => setState(() => _autoActivate = v),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Başlarken herkese bildirim'),
          subtitle: const Text('Push + inbox (otomatik)'),
          value: _notifyOnStart,
          onChanged: (v) => setState(() => _notifyOnStart = v),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: admin.busy
                    ? null
                    : () => _save(activate: false),
                child: Text(admin.busy ? '…' : 'Sadece planla'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: FilledButton(
                onPressed: admin.busy
                    ? null
                    : () => _save(activate: _startNow),
                child: Text(
                  admin.busy
                      ? '…'
                      : (_startNow ? 'Kaydet / Başlat' : 'Planı kaydet'),
                ),
              ),
            ),
          ],
        ),
        if (admin.status != null) ...[
          const SizedBox(height: 12),
          Text(
            admin.status!,
            style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
          ),
        ],
        const SizedBox(height: 24),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.surfaceMuted,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.border),
          ),
          child: const Text(
            'Bakım açıkken normal kullanıcılar animasyonlu AYS ekranını görür. '
            'Admin / personel paneli çalışmaya devam eder. '
            'Bitirince abonelere e-posta ve push otomatik gider.',
            style: TextStyle(
              color: AppColors.textSecondary,
              fontSize: 13,
              height: 1.45,
            ),
          ),
        ),
      ],
    );
  }
}

class _DateTile extends StatelessWidget {
  const _DateTile({
    required this.label,
    required this.value,
    required this.onTap,
  });

  final String label;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: AppColors.border),
      ),
      title: Text(label, style: const TextStyle(fontSize: 13)),
      subtitle: Text(
        value,
        style: const TextStyle(
          fontWeight: FontWeight.w700,
          color: AppColors.navy,
        ),
      ),
      trailing: const Icon(Icons.event),
      onTap: onTap,
    );
  }
}
