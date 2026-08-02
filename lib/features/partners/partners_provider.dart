import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import 'package:image_picker/image_picker.dart';

import '../../core/storage/media_upload.dart';
import 'partner_models.dart';

class PartnersProvider extends ChangeNotifier {
  PartnersProvider() {
    _sub = FirebaseFirestore.instance
        .collection('partners')
        .orderBy('sortOrder')
        .snapshots()
        .listen(_onSnap, onError: (e) {
      debugPrint('[partners] stream: $e');
    });
  }

  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _sub;
  final List<BusinessPartner> _items = [];
  bool _busy = false;

  List<BusinessPartner> get items => List.unmodifiable(_items);
  bool get busy => _busy;

  void _onSnap(QuerySnapshot<Map<String, dynamic>> snap) {
    _items
      ..clear()
      ..addAll(snap.docs.map((d) => BusinessPartner.fromJson(d.id, d.data())));
    notifyListeners();
  }

  Future<String> uploadLogo(XFile file) async {
    return MediaUpload.uploadXFile(
      file: file,
      folder: 'partners',
      firstName: 'partner',
      lastName: 'logo',
      studentNo: 'brand',
      isVideo: false,
    );
  }

  Future<void> upsert({
    String? id,
    required String name,
    required String blurb,
    required String logoUrl,
    required String linkUrl,
    required double logoSize,
    int? sortOrder,
  }) async {
    if (name.trim().isEmpty) {
      throw StateError('İsim zorunlu');
    }
    _busy = true;
    notifyListeners();
    try {
      final col = FirebaseFirestore.instance.collection('partners');
      final order = sortOrder ??
          (_items.isEmpty
              ? 0
              : _items.map((e) => e.sortOrder).reduce((a, b) => a > b ? a : b) +
                  1);
      final data = BusinessPartner(
        id: id ?? '',
        name: name.trim(),
        blurb: blurb.trim(),
        logoUrl: logoUrl.trim(),
        linkUrl: linkUrl.trim(),
        logoSize: logoSize,
        sortOrder: order,
      ).toJson();
      if (id == null || id.isEmpty) {
        await col.add(data);
      } else {
        await col.doc(id).set(data, SetOptions(merge: true));
      }
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  Future<void> remove(String id) async {
    await FirebaseFirestore.instance.collection('partners').doc(id).delete();
  }

  Future<void> move(String id, {required bool up}) async {
    final i = _items.indexWhere((e) => e.id == id);
    if (i < 0) return;
    final j = up ? i - 1 : i + 1;
    if (j < 0 || j >= _items.length) return;
    final a = _items[i];
    final b = _items[j];
    final batch = FirebaseFirestore.instance.batch();
    batch.set(
      FirebaseFirestore.instance.collection('partners').doc(a.id),
      {'sortOrder': b.sortOrder},
      SetOptions(merge: true),
    );
    batch.set(
      FirebaseFirestore.instance.collection('partners').doc(b.id),
      {'sortOrder': a.sortOrder},
      SetOptions(merge: true),
    );
    await batch.commit();
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}
