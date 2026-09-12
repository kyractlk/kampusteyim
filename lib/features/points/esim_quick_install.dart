import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';

/// GSMA LPA ile sistem eSIM kurulumunu açar (Quick Install).
///
/// iOS 17.4+: Apple Universal Link — carrier entitlement gerekmez.
/// Android: Play Services eSIM setup URL, yoksa ham LPA URI.
class EsimQuickInstall {
  EsimQuickInstall._();

  static Uri appleUri(String lpa) => Uri.https(
        'esimsetup.apple.com',
        '/esim_qrcode_provisioning',
        {'carddata': lpa},
      );

  static Uri androidUri(String lpa) => Uri.https(
        'esimsetup.android.com',
        '/esim_qrcode_provisioning',
        {'carddata': lpa},
      );

  static String? normalize(String? activationCode) {
    final lpa = (activationCode ?? '').trim();
    return lpa.isEmpty ? null : lpa;
  }

  /// Cihaz platformuna göre kurulum açar.
  static Future<bool> launch(String? activationCode) async {
    final lpa = normalize(activationCode);
    if (lpa == null) return false;

    if (kIsWeb) return launchApple(lpa);
    if (defaultTargetPlatform == TargetPlatform.iOS) return launchApple(lpa);
    if (defaultTargetPlatform == TargetPlatform.android) {
      return launchAndroid(lpa);
    }
    return launchApple(lpa);
  }

  static Future<bool> launchApple(String? activationCode) async {
    final lpa = normalize(activationCode);
    if (lpa == null) return false;
    return _tryLaunch(appleUri(lpa));
  }

  static Future<bool> launchAndroid(String? activationCode) async {
    final lpa = normalize(activationCode);
    if (lpa == null) return false;

    if (await _tryLaunch(androidUri(lpa))) return true;

    // Bazı OEM'ler ham LPA URI'sini doğrudan eSIM kurulumuna bağlar.
    try {
      return await launchUrl(
        Uri.parse(lpa),
        mode: LaunchMode.externalApplication,
      );
    } catch (_) {
      return false;
    }
  }

  static Future<bool> _tryLaunch(Uri uri) async {
    try {
      if (await canLaunchUrl(uri)) {
        return launchUrl(uri, mode: LaunchMode.externalApplication);
      }
      return launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      return false;
    }
  }
}
