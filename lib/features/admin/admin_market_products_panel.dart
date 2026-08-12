import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme/app_colors.dart';

FirebaseFunctions get _fn =>
    FirebaseFunctions.instanceFor(region: 'europe-west1');

/// Admin · Market ürünleri (merch / etkinlik bileti) + PayTR test modu
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
  final _eventId = TextEditingController();
  final _tierLabel = TextEditingController(text: 'Bilet');
  String _type = 'event_ticket';
  List<Map<String, dynamic>> _items = [];
  bool _loading = true;
  bool _busy = false;
  bool _paytrTest = false;
  bool _cfgBusy = false;

  @override
  void initState() {
    super.initState();
    _load();
    _loadPaytrTest();
  }

  @override
  void dispose() {
    _name.dispose();
    _amount.dispose();
    _stock.dispose();
    _eventId.dispose();
    _tierLabel.dispose();
    super.dispose();
  }

  Future<void> _loadPaytrTest() async {
    try {
      final res = await _fn.httpsCallable('getPaymentsAdmin').call();
      final data = Map<String, dynamic>.from(res.data as Map? ?? {});
      final cfg = Map<String, dynamic>.from(data['config'] as Map? ?? {});
      if (mounted) {
        setState(() => _paytrTest = cfg['paytrTestMode'] == true);
      }
    } catch (_) {}
  }

  Future<void> _setPaytrTest(bool v) async {
    setState(() {
      _paytrTest = v;
      _cfgBusy = true;
    });
    try {
      await _fn.httpsCallable('updatePaymentsConfig').call({
        'paytrTestMode': v,
        'activeProvider': 'paytr',
        'enabledProviders': ['paytr'],
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(v ? 'PayTR test modu açık' : 'PayTR canlı moda alındı'),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _paytrTest = !v);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ayar kaydedilemedi: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _cfgBusy = false);
    }
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

  Future<void> _save() async {
    setState(() => _busy = true);
    try {
      await _fn.httpsCallable('upsertMarketProduct').call({
        'type': _type,
        'name': _name.text.trim(),
        'amount': double.tryParse(_amount.text.replaceAll(',', '.')) ?? 0,
        'stock': int.tryParse(_stock.text.trim()),
        if (_type == 'event_ticket') ...{
          'eventId': _eventId.text.trim(),
          'tierLabel': _tierLabel.text.trim().isEmpty
              ? 'Bilet'
              : _tierLabel.text.trim(),
          'eventTitle': _name.text.trim(),
        },
      });
      _name.clear();
      _amount.clear();
      _stock.clear();
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
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Silinemedi: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Market ürünleri',
              style: TextStyle(fontWeight: FontWeight.w900, fontSize: 17),
            ),
            const SizedBox(height: 4),
            const Text(
              'Etkinlik bileti eklenince Market → Etkinlikler’de listelenir. Stok bitince veya tarih geçince “Stok bitti”.',
              style: TextStyle(color: Colors.black54, height: 1.35),
            ),
            const SizedBox(height: 10),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('PayTR test modu'),
              subtitle: Text(
                _paytrTest
                    ? 'Test — gerçek tahsilat yok'
                    : 'Canlı — gerçek kart ödemesi',
              ),
              value: _paytrTest,
              onChanged: _cfgBusy ? null : _setPaytrTest,
            ),
            const Divider(),
            DropdownButtonFormField<String>(
              initialValue: _type,
              decoration: const InputDecoration(labelText: 'Ürün tipi'),
              items: const [
                DropdownMenuItem(
                  value: 'event_ticket',
                  child: Text('Etkinlik bileti'),
                ),
                DropdownMenuItem(value: 'merch', child: Text('Merch')),
              ],
              onChanged: (v) {
                if (v != null) setState(() => _type = v);
              },
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _name,
              decoration: const InputDecoration(labelText: 'Ürün / bilet adı'),
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
                    decoration: const InputDecoration(labelText: 'Tutar (TL)'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _stock,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Stok'),
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
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _tierLabel,
                decoration: const InputDecoration(labelText: 'Bilet dilimi'),
              ),
            ],
            const SizedBox(height: 12),
            FilledButton(
              onPressed: _busy ? null : _save,
              child: Text(_busy ? 'Kaydediliyor…' : 'Ürün ekle / güncelle'),
            ),
            const SizedBox(height: 16),
            if (_loading)
              const Center(child: CircularProgressIndicator())
            else if (_items.isEmpty)
              const Text('Henüz market ürünü yok.', style: TextStyle(color: Colors.black54))
            else
              ..._items.map((p) {
                final soldOut = p['available'] == false;
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    '${p['name']}',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  subtitle: Text(
                    '${p['type']} · ${p['amount']} TL · '
                    '${soldOut ? (p['statusLabel'] ?? 'Stok bitti') : 'Kalan: ${p['remaining'] ?? '—'}'}',
                  ),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline, color: AppColors.crimson),
                    onPressed: () => _delete('${p['id']}'),
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }
}
