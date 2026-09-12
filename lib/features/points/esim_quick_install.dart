import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';

/// GSMA LPA ile sistem eSIM kurulumunu açar (Quick Install).
///
/// iOS 17.4+: Apple Universal Link — carrier entitlement gerekmez.
/// Android: Play Services eSIM setup URL, yoksa ham LPA intent.
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

  static Future<bool> launch(String? activationCode) async {
    final lpa = (activationCode ?? '').trim();
    if (lpa.isEmpty) return false;

    if (kIsWeb) {
      return launchUrl(
        appleUri(lpa),
        mode: LaunchMode.externalApplication,
      );
    }

    if (defaultTargetPlatform == TargetPlatform.iOS) {
      return launchUrl(appleUri(lpa), mode: LaunchMode.externalApplication);
    }

    if (defaultTargetPlatform == TargetPlatform.android) {
      try {
        final ok = await launchUrl(
          androidUri(lpa),
          mode: LaunchMode.externalApplication,
        );
        if (ok) return true;
      } catch (_) {}
      return launchUrl(
        Uri.parse(lpa),
        mode: LaunchMode.externalApplication,
      );
    }

    return launchUrl(appleUri(lpa), mode: LaunchMode.externalApplication);
  }
}
