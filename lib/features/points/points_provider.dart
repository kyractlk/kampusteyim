import 'package:flutter/foundation.dart';

import 'points_models.dart';

class PointsProvider extends ChangeNotifier {
  PointsConfig config = const PointsConfig();
  int balance = 0;
  int spinsLeft = 0;
  int spinsUsedThisWeek = 0;
  String weekKey = '';
  List<PointsCatalogItem> catalog = [];
  List<UserReward> rewards = [];
  bool loading = false;
  String? error;

  bool get enabled => config.enabled;
  bool get silSupurEnabled => config.silSupur.enabled;

  bool get isSilSupurDay {
    final wd = DateTime.now().weekday % 7; // Dart: Mon=1..Sun=7 → convert
    // Istanbul approx: device local; admin weekday 0=Sun
    final now = DateTime.now();
    final dartWd = now.weekday; // Mon=1
    final sun0 = dartWd % 7; // Sun=0 if Sunday=7 → 0
    return sun0 == config.silSupur.weekday;
  }

  Future<void> refresh() async {
    loading = true;
    error = null;
    notifyListeners();
    try {
      final data = await PointsService.getConfig();
      final cfgMap = Map<String, dynamic>.from(data['config'] as Map? ?? {});
      config = PointsConfig.fromMap(cfgMap);
      balance = (num.tryParse('${data['balance']}') ?? 0).round();
      spinsLeft = (num.tryParse('${data['spinsLeft']}') ?? 0).round();
      spinsUsedThisWeek =
          (num.tryParse('${data['spinsUsedThisWeek']}') ?? 0).round();
      weekKey = '${data['weekKey'] ?? ''}';
      catalog = await PointsService.listCatalog();
    } catch (e) {
      error = '$e';
      debugPrint('[points] refresh: $e');
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  Future<void> loadRewards() async {
    try {
      rewards = await PointsService.listRewards();
      notifyListeners();
    } catch (e) {
      debugPrint('[points] rewards: $e');
    }
  }

  Future<Map<String, dynamic>> redeem(String id) async {
    final res = await PointsService.redeem(id);
    await refresh();
    await loadRewards();
    return res;
  }

  Future<Map<String, dynamic>> spin() async {
    final res = await PointsService.playSilSupur();
    await refresh();
    await loadRewards();
    return res;
  }

  Future<UserReward> refreshReward(String id) async {
    final r = await PointsService.refreshEsim(id);
    final i = rewards.indexWhere((e) => e.id == id);
    if (i >= 0) {
      rewards[i] = r;
    } else {
      rewards.insert(0, r);
    }
    notifyListeners();
    return r;
  }
}
