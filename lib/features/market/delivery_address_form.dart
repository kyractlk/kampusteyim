import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/models.dart';
import '../auth/data/auth_provider.dart';

/// Teslimat adresi ekle / düzenle bottom sheet.
Future<DeliveryAddress?> showDeliveryAddressEditor(
  BuildContext context, {
  DeliveryAddress? initial,
  bool required = false,
  String title = 'Teslimat adresi',
}) async {
  final auth = context.read<AuthProvider>();
  final user = auth.user;
  final titleCtrl = TextEditingController(text: initial?.title ?? 'Ev');
  final nameCtrl = TextEditingController(
    text: initial?.fullName ?? user?.fullName ?? '',
  );
  final phoneCtrl = TextEditingController(
    text: initial?.phone ?? user?.phone ?? '',
  );
  final cityCtrl = TextEditingController(
    text: initial?.city ?? user?.city ?? '',
  );
  final districtCtrl = TextEditingController(text: initial?.district ?? '');
  final lineCtrl = TextEditingController(text: initial?.line1 ?? '');
  final postalCtrl = TextEditingController(text: initial?.postalCode ?? '');
  final formKey = GlobalKey<FormState>();

  final saved = await showModalBottomSheet<DeliveryAddress>(
    context: context,
    isScrollControlled: true,
    isDismissible: !required,
    enableDrag: !required,
    showDragHandle: true,
    builder: (ctx) {
      return Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 8,
          bottom: MediaQuery.viewInsetsOf(ctx).bottom + 16,
        ),
        child: Form(
          key: formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 18,
                  ),
                ),
                if (required)
                  const Padding(
                    padding: EdgeInsets.only(top: 6),
                    child: Text(
                      'Market siparişleri için bir teslimat adresi kaydetmen gerekiyor.',
                      style: TextStyle(color: Colors.black54, height: 1.35),
                    ),
                  ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: titleCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Adres başlığı (Ev, Yurt…)',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: nameCtrl,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                    labelText: 'Alıcı adı',
                    border: OutlineInputBorder(),
                  ),
                  validator: (v) =>
                      (v == null || v.trim().length < 2) ? 'Zorunlu' : null,
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: phoneCtrl,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(
                    labelText: 'Telefon',
                    border: OutlineInputBorder(),
                  ),
                  validator: (v) =>
                      (v == null || v.trim().length < 10) ? 'Geçersiz' : null,
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: cityCtrl,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                    labelText: 'Şehir',
                    border: OutlineInputBorder(),
                  ),
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'Zorunlu' : null,
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: districtCtrl,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                    labelText: 'İlçe',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: lineCtrl,
                  textCapitalization: TextCapitalization.sentences,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: 'Açık adres',
                    hintText: 'Mahalle, sokak, bina no, daire',
                    border: OutlineInputBorder(),
                  ),
                  validator: (v) =>
                      (v == null || v.trim().length < 5) ? 'Zorunlu' : null,
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: postalCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Posta kodu (opsiyonel)',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 14),
                FilledButton(
                  onPressed: () {
                    if (!(formKey.currentState?.validate() ?? false)) return;
                    Navigator.pop(
                      ctx,
                      DeliveryAddress(
                        id: initial?.id ??
                            DateTime.now().millisecondsSinceEpoch.toString(),
                        title: titleCtrl.text.trim().isEmpty
                            ? 'Adres'
                            : titleCtrl.text.trim(),
                        fullName: nameCtrl.text.trim(),
                        phone: phoneCtrl.text.trim(),
                        city: cityCtrl.text.trim(),
                        district: districtCtrl.text.trim(),
                        line1: lineCtrl.text.trim(),
                        postalCode: postalCtrl.text.trim(),
                        isDefault: initial?.isDefault ?? true,
                      ),
                    );
                  },
                  child: Text(initial == null ? 'Adresi kaydet' : 'Güncelle'),
                ),
                if (!required) ...[
                  const SizedBox(height: 6),
                  TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('Vazgeç'),
                  ),
                ],
              ],
            ),
          ),
        ),
      );
    },
  );

  titleCtrl.dispose();
  nameCtrl.dispose();
  phoneCtrl.dispose();
  cityCtrl.dispose();
  districtCtrl.dispose();
  lineCtrl.dispose();
  postalCtrl.dispose();
  return saved;
}
