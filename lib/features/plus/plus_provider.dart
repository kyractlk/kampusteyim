import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';

import 'plus_config.dart';

class PlusProvider extends ChangeNotifier {
  PlusProvider();

  PlusConfig _config = PlusConfig.defaults;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _sub;
  bool _bound = false;

  PlusConfig get config => _config;

  void bind() {
    if (_bound) return;
    _bound = true;
    _sub = FirebaseFirestore.instance
        .collection('app_config')
        .doc('kampusteyim_plus')
        .snapshots()
        .listen(
      (snap) {
        _config = PlusConfig.fromMap(snap.data());
        notifyListeners();
      },
      onError: (e) => debugPrint('[plus] config: $e'),
    );
  }

  Future<void> ensureConfigSeeded() async {
    final ref =
        FirebaseFirestore.instance.collection('app_config').doc('kampusteyim_plus');
    final snap = await ref.get();
    if (!snap.exists) {
      await ref.set(PlusConfig.defaults.toMap());
    }
  }

  Future<String?> startTrial() async {
    try {
      final callable = FirebaseFunctions.instanceFor(region: 'europe-west1')
          .httpsCallable('startPlusTrial');
      final res = await callable.call(<String, dynamic>{});
      final data = Map<String, dynamic>.from(res.data as Map? ?? {});
      if (data['ok'] == true) return null;
      return '${data['message'] ?? 'Deneme başlatılamadı'}';
    } on FirebaseFunctionsException catch (e) {
      return e.message ?? e.code;
    } catch (e) {
      debugPrint('[plus] trial: $e');
      return 'Deneme başlatılamadı';
    }
  }

  Future<String?> saveConfig(PlusConfig cfg) async {
    try {
      await FirebaseFirestore.instance
          .collection('app_config')
          .doc('kampusteyim_plus')
          .set(cfg.toMap(), SetOptions(merge: true));
      _config = cfg;
      notifyListeners();
      return null;
    } catch (e) {
      return '$e';
    }
  }

  Future<String?> adminGrantPlus({
    required String userId,
    required int days,
  }) async {
    try {
      final callable = FirebaseFunctions.instanceFor(region: 'europe-west1')
          .httpsCallable('adminSetPlus');
      await callable.call({
        'userId': userId,
        'action': 'grant',
        'days': days,
      });
      return null;
    } on FirebaseFunctionsException catch (e) {
      return e.message ?? e.code;
    } catch (e) {
      return '$e';
    }
  }

  Future<String?> adminRevokePlus({required String userId}) async {
    try {
      final callable = FirebaseFunctions.instanceFor(region: 'europe-west1')
          .httpsCallable('adminSetPlus');
      await callable.call({
        'userId': userId,
        'action': 'revoke',
      });
      return null;
    } on FirebaseFunctionsException catch (e) {
      return e.message ?? e.code;
    } catch (e) {
      return '$e';
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}
