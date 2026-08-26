import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme/app_colors.dart';

FirebaseFunctions get _fn =>
    FirebaseFunctions.instanceFor(region: 'europe-west1');

/// Admin · Market ürünleri (Plus / merch / etkinlik bileti)
class AdminMarketProductsPanel extends StatefulWidget {
  const AdminMarketProductsPanel({super.key});

  @override
  State<AdminMarketProductsPanel> createState() =>
      _AdminMarketProductsPanelState();
}

class _AdminMarketProductsPanelState extends State<AdminMarketProductsPanel> {
  final _name = TextEditingController();
  final _amount = TextEditingController();
  final _stock = TextEditingController();
  final _plusDays = TextEditingController(text: '30');
  final _eventId = TextEditingController();
  final _tierLabel = TextEditingController(text: 'Bilet');
  String _type = 'plus';
  String? _editingId;
  bool _installmentsEnabled = true;
  bool _cashPriceInstallments = false;
  List<Map<String, dynamic>> _items = [];
  bool _loading = true;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _name.dispose();
    _amount.dispose();
    _stock.dispose();
    _plusDays.dispose();
    _eventId.dispose();
    _tierLabel.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final res = await _fn.httpsCallable('listMarketProducts').call();
      final data = Map<String, dynamic>.from(res.data as Map? ?? {});
      final list = (data['items'] as List? ?? const [])
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
      // Plus üstte
      list.sort((a, b) {
        final ap = a['type'] == 'plus' ? 0 : 1;
        final bp = b['type'] == 'plus' ? 0 : 1;
        if (ap != bp) return ap.compareTo(bp);
        return '${a['name']}'.compareTo('${b['name']}');
      });
      if (mounted) setState(() => _items = list);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ürünler yüklenemedi: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _fill(Map<String, dynamic> p) {
    setState(() {
      _editingId = '${p['id']}';
      _type = '${p['type'] ?? 'merch'}';
      _name.text = '${p['name'] ?? ''}';
      _amount.text = p['amount'] == null ? '' : '${p['amount']}';
      _stock.text = p['stock'] == null ? '' : '${p['stock']}';
      _plusDays.text = '${p['plusDays'] ?? 30}';
      _eventId.text = '${p['eventId'] ?? ''}';
      _tierLabel.text = '${p['tierLabel'] ?? 'Bilet'}';
      _installmentsEnabled = p['installmentsEnabled'] != false;
      _cashPriceInstallments = p['cashPriceInstallments'] == true;
    });
  }

  void _resetForm() {
    setState(() {
      _editingId = null;
      _type = 'merch';
      _name.clear();
      _amount.clear();
      _stock.clear();
      _plusDays.text = '30';
      _eventId.clear();
      _tierLabel.text = 'Bilet';
      _installmentsEnabled = true;
      _cashPriceInstallments = false;
    });
  }

  Future<void> _save() async {
    setState(() => _busy = true);
    try {
      await _fn.httpsCallable('upsertMarketProduct').call({
        if (_editingId != null) 'id': _editingId,
        'type': _type,
        'name': _name.text.trim(),
        'amount': double.tryParse(_amount.text.replaceAll(',', '.')) ?? 0,
        if (_type == 'plus') 'plusDays': int.tryParse(_plusDays.text.trim()) ?? 30,
        if (_type != 'plus') 'stock': int.tryParse(_stock.text.trim()),
        if (_type == 'event_ticket') ...{
          'eventId': _eventId.text.trim(),
          'tierLabel': _tierLabel.text.trim().isEmpty
              ? 'Bilet'
              : _tierLabel.text.trim(),
          'eventTitle': _name.text.trim(),
        },
        'installmentsEnabled': _installmentsEnabled,
        'cashPriceInstallments': _cashPriceInstallments,
      });
      _resetForm();
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Ürün kaydedildi')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Kayıt hatası: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete(String id) async {
    try {
      await _fn.httpsCallable('deleteMarketProduct').call({'id': id});
      if (_editingId == id) _resetForm();
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Silinemedi: $e')),
        );
      }
    }
  }

  String _typeLabel(String? t) => switch (t) {
        'plus' => 'Plus',
        'event_ticket' => 'Bilet',
        _ => 'Merch',
      };

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Market ürünleri',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w900,
              ),
        ),
        const SizedBox(height: 4),
        const Text(
          'KampüsteyimPlus, merch ve etkinlik biletleri. Plus fiyatı buradan da güncellenir.',
          style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
        ),
        const SizedBox(height: 16),
        Text(
          _editingId == null ? 'Yeni ürün' : 'Ürünü düzenle',
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w800,
              ),
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          key: ValueKey('type_$_type'),
          initialValue: _type,
          decoration: const InputDecoration(
            labelText: 'Ürün tipi',
            border: OutlineInputBorder(),
          ),
          items: const [
            DropdownMenuItem(
              value: 'plus',
              child: Text('KampüsteyimPlus'),
            ),
            DropdownMenuItem(
              value: 'event_ticket',
              child: Text('Etkinlik bileti'),
            ),
            DropdownMenuItem(value: 'merch', child: Text('Merch')),
          ],
          onChanged: _editingId == 'plus'
              ? null
              : (v) {
                  if (v != null) setState(() => _type = v);
                },
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _name,
          decoration: InputDecoration(
            labelText: _type == 'plus' ? 'Plus ürün adı' : 'Ürün / bilet adı',
            border: const OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _amount,
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                ],
                decoration: InputDecoration(
                  labelText: _type == 'plus' ? 'Aylık tutar (TL)' : 'Tutar (TL)',
                  helperText: _type == 'plus' ? '1/3/6/12 ay çarpılır' : null,
                  border: const OutlineInputBorder(),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _type == 'plus'
                  ? TextField(
                      controller: _plusDays,
                      keyboardType: TextInputType.number,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                      ],
                      decoration: const InputDecoration(
                        labelText: '1 ay = gün',
                        border: OutlineInputBorder(),
                      ),
                    )
                  : TextField(
                      controller: _stock,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Stok',
                        border: OutlineInputBorder(),
                      ),
                    ),
            ),
          ],
        ),
        if (_type == 'event_ticket') ...[
          const SizedBox(height: 8),
          TextField(
            controller: _eventId,
            decoration: const InputDecoration(
              labelText: 'Etkinlik ID',
              hintText: 'events/{id}',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _tierLabel,
            decoration: const InputDecoration(
              labelText: 'Bilet dilimi',
              border: OutlineInputBorder(),
            ),
          ),
        ],
        if (_type == 'plus' || _type == 'merch') ...[
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Taksit açık'),
            subtitle: const Text('Kapalıysa bu ürün peşin ödenir'),
            value: _installmentsEnabled,
            onChanged: (v) => setState(() => _installmentsEnabled = v),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Peşin fiyatına taksit'),
            subtitle: const Text(
              'PayTR panelindeki peşin fiyatına taksit seçenekleriyle uyumlu',
            ),
            value: _cashPriceInstallments,
            onChanged: _installmentsEnabled
                ? (v) => setState(() => _cashPriceInstallments = v)
                : null,
          ),
        ],
        const SizedBox(height: 12),
        FilledButton(
          onPressed: _busy ? null : _save,
          child: Text(
            _busy
                ? 'Kaydediliyor…'
                : (_editingId == null ? 'Ürün ekle' : 'Değişiklikleri kaydet'),
          ),
        ),
        if (_editingId != null)
          TextButton(
            onPressed: _resetForm,
            child: const Text('Yeni ürün moduna dön'),
          ),
        const SizedBox(height: 24),
        Row(
          children: [
            Text(
              'Kayıtlı ürünler',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
            ),
            const Spacer(),
            IconButton(
              tooltip: 'Yenile',
              onPressed: _loading ? null : _load,
              icon: const Icon(Icons.refresh, size: 20),
            ),
          ],
        ),
        const SizedBox(height: 4),
        if (_loading)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (_items.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Text(
              'Henüz market ürünü yok.',
              style: TextStyle(color: AppColors.textSecondary),
            ),
          )
        else
          ..._items.map((p) {
            final soldOut = p['available'] == false;
            final isPlus = p['type'] == 'plus';
            final selected = _editingId == '${p['id']}';
            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: selected ? AppColors.navy : AppColors.border,
                  width: selected ? 1.5 : 1,
                ),
                color: selected
                    ? AppColors.navy.withValues(alpha: 0.06)
                    : AppColors.surfaceMuted,
              ),
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                onTap: () => _fill(p),
                title: Text(
                  '${p['name']}',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                subtitle: Text(
                  isPlus
                      ? 'Plus · ${p['amount']} TL/ay · ${p['plusDays'] ?? 30} gün'
                      : '${_typeLabel('${p['type']}')} · ${p['amount']} TL · '
                          '${soldOut ? (p['statusLabel'] ?? 'Stok bitti') : 'Kalan: ${p['remaining'] ?? '—'}'}',
                  style: TextStyle(
                    color: soldOut ? AppColors.crimson : AppColors.textSecondary,
                    fontSize: 12.5,
                  ),
                ),
                trailing: isPlus
                    ? IconButton(
                        tooltip: 'Düzenle',
                        icon: const Icon(Icons.edit_outlined),
                        onPressed: () => _fill(p),
                      )
                    : IconButton(
                        icon: const Icon(
                          Icons.delete_outline,
                          color: AppColors.crimson,
                        ),
                        onPressed: () => _delete('${p['id']}'),
                      ),
              ),
            );
          }),
      ],
    );
  }
}
