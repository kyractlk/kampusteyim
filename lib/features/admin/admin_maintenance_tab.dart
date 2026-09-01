import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../../core/widgets/app_circle_logo.dart';
import '../auth/data/auth_provider.dart';
import '../maintenance/maintenance_provider.dart';
import 'admin_provider.dart';
import 'admin_test_mode_panel.dart';

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
        const SizedBox(height: 24),
        const Divider(height: 32),
        AdminTestModePanel(admin: admin),
        const SizedBox(height: 28),
        const Divider(height: 32),
        const Text(
          'Planlı bakım',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w800,
            color: AppColors.navy,
          ),
        ),
        const SizedBox(height: 12),
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
        const SizedBox(height: 28),
        const _AppVersionGatePanel(),
      ],
    );
  }
}

class _AppVersionGatePanel extends StatefulWidget {
  const _AppVersionGatePanel();

  @override
  State<_AppVersionGatePanel> createState() => _AppVersionGatePanelState();
}

class _AppVersionGatePanelState extends State<_AppVersionGatePanel> {
  final _min = TextEditingController();
  final _title = TextEditingController(text: 'Güncelleme gerekli');
  final _message = TextEditingController(
    text:
        'KampüsteyimAPP’in yeni sürümü yayında. Devam etmek için uygulamayı mağazadan güncelle.',
  );
  final _iosOverride = TextEditingController();
  final _androidOverride = TextEditingController();
  bool _forceBelowMin = true;
  bool _softEnabled = true;
  bool _loading = true;
  bool _saving = false;
  String _iosStore = '—';
  String _androidStore = '—';
  String? _status;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _min.dispose();
    _title.dispose();
    _message.dispose();
    _iosOverride.dispose();
    _androidOverride.dispose();
    super.dispose();
  }

  Future<void> _load({bool refreshStore = false}) async {
    setState(() {
      _loading = true;
      _status = null;
    });
    try {
      final snap = await FirebaseFirestore.instance
          .collection('app_config')
          .doc('app_version')
          .get();
      final d = snap.data() ?? {};
      _min.text = '${d['minVersion'] ?? ''}';
      _title.text = '${d['title'] ?? _title.text}';
      _message.text = '${d['message'] ?? _message.text}';
      _iosOverride.text = '${d['latestIosOverride'] ?? ''}';
      _androidOverride.text = '${d['latestAndroidOverride'] ?? ''}';
      _forceBelowMin = d['forceBelowMin'] != false;
      _softEnabled = d['softUpdateEnabled'] != false;
      _iosStore = '${d['cachedIosVersion'] ?? '—'}';
      _androidStore = '${d['cachedAndroidVersion'] ?? '—'}';

      if (refreshStore || _iosStore == '—' || _iosStore.isEmpty) {
        final callable =
            FirebaseFunctions.instanceFor(region: 'europe-west1')
                .httpsCallable('updateAppVersionConfig');
        final res = await callable.call({'refreshStore': true});
        final data = Map<String, dynamic>.from(res.data as Map? ?? {});
        final store = Map<String, dynamic>.from(data['store'] as Map? ?? {});
        final cfg = Map<String, dynamic>.from(data['config'] as Map? ?? {});
        _iosStore = '${store['iosVersion'] ?? cfg['cachedIosVersion'] ?? _iosStore}';
        _androidStore =
            '${store['androidVersion'] ?? cfg['cachedAndroidVersion'] ?? _androidStore}';
        if (_iosStore.isEmpty) _iosStore = '—';
        if (_androidStore.isEmpty) _androidStore = '—';
      }
    } catch (e) {
      _status = 'Yüklenemedi: $e';
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _save({bool refreshStore = false}) async {
    setState(() {
      _saving = true;
      _status = null;
    });
    try {
      final callable = FirebaseFunctions.instanceFor(region: 'europe-west1')
          .httpsCallable('updateAppVersionConfig');
      final res = await callable.call({
        'minVersion': _min.text.trim(),
        'title': _title.text.trim(),
        'message': _message.text.trim(),
        'latestIosOverride': _iosOverride.text.trim(),
        'latestAndroidOverride': _androidOverride.text.trim(),
        'forceBelowMin': _forceBelowMin,
        'softUpdateEnabled': _softEnabled,
        'refreshStore': refreshStore,
      });
      final data = Map<String, dynamic>.from(res.data as Map? ?? {});
      final store = Map<String, dynamic>.from(data['store'] as Map? ?? {});
      _iosStore = '${store['iosVersion'] ?? _iosStore}';
      _androidStore = '${store['androidVersion'] ?? _androidStore}';
      if (_iosStore.isEmpty) _iosStore = '—';
      if (_androidStore.isEmpty) _androidStore = '—';
      _status = refreshStore
          ? 'Kaydedildi · mağaza sürümleri yenilendi'
          : 'Sürüm kapısı kaydedildi';
    } catch (e) {
      _status = 'Kaydedilemedi: $e';
    }
    if (mounted) setState(() => _saving = false);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Uygulama sürümü',
          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
        ),
        const SizedBox(height: 6),
        const Text(
          'App Store / Play sürümleri otomatik okunur. Minimum sürümün altındaki '
          'kullanıcılar uygulamayı kullanamaz ve mağazaya yönlendirilir. '
          'Mağazada daha yeni sürüm varsa soft uyarı çıkar.',
          style: TextStyle(
            fontSize: 12.5,
            color: AppColors.textSecondary,
            height: 1.4,
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            _chip('App Store', _iosStore),
            _chip('Play Store', _androidStore),
          ],
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _min,
          decoration: const InputDecoration(
            labelText: 'Zorunlu minimum sürüm',
            hintText: 'örn. 1.0.32',
            helperText: 'Bu sürümün altı → tam ekran “güncelle” kilidi',
          ),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _title,
          decoration: const InputDecoration(labelText: 'Başlık'),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _message,
          maxLines: 3,
          decoration: const InputDecoration(labelText: 'Mesaj'),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _iosOverride,
          decoration: const InputDecoration(
            labelText: 'iOS sürüm override (opsiyonel)',
            hintText: 'Boş bırak → App Store’dan oku',
          ),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _androidOverride,
          decoration: const InputDecoration(
            labelText: 'Android sürüm override (opsiyonel)',
            hintText: 'Boş bırak → Play’den oku / cache',
          ),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Minimum altını zorla'),
          subtitle: const Text('minVersion altındaki kullanıcılar kilitlenir'),
          value: _forceBelowMin,
          onChanged: (v) => setState(() => _forceBelowMin = v),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Soft güncelleme uyarısı'),
          subtitle: const Text('Mağazada daha yeni sürüm varsa alt banner'),
          value: _softEnabled,
          onChanged: (v) => setState(() => _softEnabled = v),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _saving ? null : () => _save(refreshStore: true),
                icon: const Icon(Icons.storefront_outlined, size: 18),
                label: const Text('Mağazadan yenile'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: FilledButton(
                onPressed: _saving ? null : () => _save(),
                child: Text(_saving ? '…' : 'Kaydet'),
              ),
            ),
          ],
        ),
        if (_status != null) ...[
          const SizedBox(height: 10),
          Text(
            _status!,
            style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
          ),
        ],
      ],
    );
  }

  Widget _chip(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.surfaceMuted,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 2),
          Text(
            value.isEmpty ? '—' : value,
            style: const TextStyle(
              fontWeight: FontWeight.w800,
              color: AppColors.navy,
            ),
          ),
        ],
      ),
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
