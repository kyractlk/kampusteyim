import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import 'test_mode_models.dart';

/// Canlı test modu durumu (`app_config/test_mode`).
class TestModeProvider extends ChangeNotifier {
  TestModeProvider() {
    _bind();
  }

  TestModeState state = TestModeState.empty;
  bool loading = true;

  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _sub;

  bool get isActive => state.active;

  void _bind() {
    try {
      _sub = FirebaseFirestore.instance
          .collection('app_config')
          .doc('test_mode')
          .snapshots()
          .listen(
        (snap) {
          state = TestModeState.fromMap(snap.data());
          loading = false;
          notifyListeners();
        },
        onError: (e) {
          debugPrint('[testMode] listen: $e');
          loading = false;
          notifyListeners();
        },
      );
    } catch (e) {
      debugPrint('[testMode] bind: $e');
      loading = false;
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}
