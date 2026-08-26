import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme/app_colors.dart';
import 'admin_user_search_field.dart';

FirebaseFunctions get _fn =>
    FirebaseFunctions.instanceFor(region: 'europe-west1');

/// Admin · Market kampanya kodları / üye çekleri
class AdminMarketCampaignsPanel extends StatefulWidget {
  const AdminMarketCampaignsPanel({super.key});

  @override
  State<AdminMarketCampaignsPanel> createState() =>
      _AdminMarketCampaignsPanelState();
}

class _AdminMarketCampaignsPanelState extends State<AdminMarketCampaignsPanel> {
  final _code = TextEditingController();
  final _label = TextEditingController();
  final _value = TextEditingController(text: '20');
  final _maxUses = TextEditingController();
  final _maxPerUser = TextEditingController(text: '1');
  final _minAmount = TextEditingController();
  final _assignUid = TextEditingController();
  String _type = 'percent';
  final Set<String> _applies = {'plus', 'merch'};
  List<Map<String, dynamic>> _items = [];
  String? _selectedId;
  bool _loading = true;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final c in [
      _code,
      _label,
      _value,
      _maxUses,
      _maxPerUser,
      _minAmount,
      _assignUid,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final res = await _fn.httpsCallable('listMarketCampaigns').call();
      final data = Map<String, dynamic>.from(res.data as Map? ?? {});
      final list = (data['items'] as List? ?? const [])
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
      if (mounted) setState(() => _items = list);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Kampanyalar yüklenemedi: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    setState(() => _busy = true);
    try {
      await _fn.httpsCallable('upsertMarketCampaign').call({
        if (_selectedId != null) 'id': _selectedId,
        'code': _code.text.trim(),
        'label': _label.text.trim(),
        'type': _type,
        'value': double.tryParse(_value.text.trim().replaceAll(',', '.')) ?? 0,
        'appliesTo': _applies.toList(),
        'maxUses': _maxUses.text.trim().isEmpty
            ? null
            : int.tryParse(_maxUses.text.trim()),
        'maxUsesPerUser': int.tryParse(_maxPerUser.text.trim()) ?? 1,
        'minAmount':
            double.tryParse(_minAmount.text.trim().replaceAll(',', '.')) ?? 0,
        'active': true,
      });
      _selectedId = null;
      _code.clear();
      _label.clear();
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Kampanya kaydedildi')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Kaydedilemedi: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _assign({required bool remove}) async {
    final id = _selectedId;
    final uid = _assignUid.text.trim();
    if (id == null || uid.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Önce listeden kampanya seç ve üye uid gir')),
      );
      return;
    }
    setState(() => _busy = true);
    try {
      await _fn.httpsCallable('assignMarketCampaign').call({
        'campaignId': id,
        'uid': uid,
        'remove': remove,
      });
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(remove ? 'Üyeden çek kaldırıldı' : 'Üyeye çek tanımlandı'),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$e')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _edit(Map<String, dynamic> c) {
    setState(() {
      _selectedId = '${c['id']}';
      _code.text = '${c['code'] ?? ''}';
      _label.text = '${c['label'] ?? ''}';
      _type = '${c['type'] ?? 'percent'}';
      _value.text = '${c['value'] ?? ''}';
      _maxUses.text = c['maxUses'] == null ? '' : '${c['maxUses']}';
      _maxPerUser.text = '${c['maxUsesPerUser'] ?? 1}';
      _minAmount.text = '${c['minAmount'] ?? ''}';
      _applies
        ..clear()
        ..addAll(
          ((c['appliesTo'] as List?) ?? const ['plus', 'merch'])
              .map((e) => '$e'),
        );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Market · Kampanya kodları & üye çekleri',
          style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
        ),
        const SizedBox(height: 4),
        const Text(
          'Genel kod (atanmamış) herkes girebilir. Üyeye tanımlı çekler '
          'uygulamada “Kodlarım”da görünür. Kişi / toplam limit koyabilirsin.',
          style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _code,
          textCapitalization: TextCapitalization.characters,
          decoration: const InputDecoration(
            labelText: 'Kod (örn. KAMPUS20)',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _label,
          decoration: const InputDecoration(
            labelText: 'Etiket',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: DropdownButtonFormField<String>(
                value: _type,
                decoration: const InputDecoration(
                  labelText: 'Tip',
                  border: OutlineInputBorder(),
                ),
                items: const [
                  DropdownMenuItem(value: 'percent', child: Text('% indirim')),
                  DropdownMenuItem(value: 'fixed', child: Text('Sabit TL')),
                ],
                onChanged: (v) => setState(() => _type = v ?? 'percent'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: _value,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: _type == 'fixed' ? 'TL' : 'Yüzde',
                  border: const OutlineInputBorder(),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          children: [
            for (final p in ['plus', 'merch'])
              FilterChip(
                label: Text(p == 'plus' ? 'Plus' : 'Merch'),
                selected: _applies.contains(p),
                onSelected: (v) => setState(() {
                  if (v) {
                    _applies.add(p);
                  } else {
                    _applies.remove(p);
                  }
                }),
              ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _maxUses,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(
                  labelText: 'Toplam limit (boş=∞)',
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: _maxPerUser,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(
                  labelText: 'Kişi başı',
                  border: OutlineInputBorder(),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _minAmount,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'Min. tutar (TL)',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 10),
        FilledButton(
          onPressed: _busy ? null : _save,
          child: Text(_selectedId == null ? 'Kampanya oluştur' : 'Kampanyayı güncelle'),
        ),
        if (_selectedId != null)
          TextButton(
            onPressed: () => setState(() {
              _selectedId = null;
              _code.clear();
              _label.clear();
            }),
            child: const Text('Yeni kayıt moduna dön'),
          ),
        const Divider(height: 28),
        const Text(
          'Üyeye çek tanımla',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 4),
        const Text(
          'Kampanyayı listeden veya aşağıdaki menüden seç, üyeyi ara, tanımla.',
          style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary),
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          initialValue: _items.any((c) => '${c['id']}' == _selectedId)
              ? _selectedId
              : null,
          decoration: const InputDecoration(
            labelText: 'Kampanya seç',
            border: OutlineInputBorder(),
          ),
          items: [
            for (final c in _items)
              DropdownMenuItem(
                value: '${c['id']}',
                child: Text(
                  '${c['code']} · ${c['label']}',
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
          onChanged: (v) {
            if (v == null) return;
            Map<String, dynamic>? found;
            for (final c in _items) {
              if ('${c['id']}' == v) {
                found = c;
                break;
              }
            }
            if (found != null) _edit(found);
          },
        ),
        const SizedBox(height: 8),
        AdminUserSearchField(
          controller: _assignUid,
          labelText: 'Üye ara / uid',
          hintText: 'Seçilen kampanyaya atanır',
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: FilledButton.tonal(
                onPressed: _busy ? null : () => _assign(remove: false),
                child: const Text('Çek tanımla'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton(
                onPressed: _busy ? null : () => _assign(remove: true),
                child: const Text('Kaldır'),
              ),
            ),
          ],
        ),
        const Divider(height: 28),
        Row(
          children: [
            const Text(
              'Kayıtlı kampanyalar',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
            const Spacer(),
            IconButton(onPressed: _load, icon: const Icon(Icons.refresh)),
          ],
        ),
        if (_loading)
          const Padding(
            padding: EdgeInsets.all(16),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (_items.isEmpty)
          const Text('Henüz kampanya yok', style: TextStyle(color: AppColors.textSecondary))
        else
          ..._items.map((c) {
            final selected = _selectedId == '${c['id']}';
            return Card(
              color: selected ? AppColors.surfaceMuted : null,
              child: ListTile(
                title: Text(
                  '${c['code']} · ${c['label']}',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                subtitle: Text(
                  '${c['type'] == 'fixed' ? '${c['value']} TL' : '%${c['value']}'} · '
                  'kullanım ${c['usedCount']}/${c['maxUses'] ?? '∞'} · '
                  '${(c['appliesTo'] as List? ?? const []).join(', ')}'
                  '${c['assignedOnly'] == true ? ' · atanmış' : ' · genel'}',
                ),
                trailing: Switch(
                  value: c['active'] != false,
                  onChanged: (v) async {
                    await _fn.httpsCallable('setMarketCampaignActive').call({
                      'campaignId': c['id'],
                      'active': v,
                    });
                    await _load();
                  },
                ),
                onTap: () => _edit(c),
              ),
            );
          }),
      ],
    );
  }
}
