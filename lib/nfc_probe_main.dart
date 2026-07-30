import 'dart:async';
import 'dart:convert';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:crypto/crypto.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:nfc_manager/nfc_manager.dart';
import 'package:nfc_manager/nfc_manager_android.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'firebase_options.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  runApp(const NfcProbeApp());
}

class NfcProbeApp extends StatelessWidget {
  const NfcProbeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Kampüsteyim NFC Beta',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF2D1B4E),
          brightness: Brightness.light,
        ),
        useMaterial3: true,
      ),
      home: const NfcProbeScreen(),
    );
  }
}

class NfcProbeScreen extends StatefulWidget {
  const NfcProbeScreen({super.key});

  @override
  State<NfcProbeScreen> createState() => _NfcProbeScreenState();
}

class _NfcProbeScreenState extends State<NfcProbeScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();

  NfcAvailability? _availability;
  Map<String, dynamic>? _lastResult;
  String _status = 'Hazır';
  String? _serverLogId;
  bool _consent = false;
  bool _busy = false;
  bool _scanning = false;
  bool _obscure = true;

  User? get _user => FirebaseAuth.instance.currentUser;

  @override
  void initState() {
    super.initState();
    unawaited(_checkAvailability());
  }

  @override
  void dispose() {
    if (_scanning) {
      unawaited(NfcManager.instance.stopSession());
    }
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _checkAvailability() async {
    try {
      final availability = await NfcManager.instance.checkAvailability();
      if (!mounted) return;
      setState(() => _availability = availability);
    } catch (e) {
      if (!mounted) return;
      setState(() => _status = 'NFC kontrolü başarısız: $e');
    }
  }

  Future<void> _login() async {
    final email = _email.text.trim();
    final password = _password.text;
    if (email.isEmpty || password.isEmpty) return;
    setState(() {
      _busy = true;
      _status = 'Giriş yapılıyor…';
    });
    try {
      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
      if (!mounted) return;
      setState(() => _status = 'Admin girişi başarılı');
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      setState(() => _status = 'Giriş başarısız: ${e.message ?? e.code}');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _logout() async {
    await FirebaseAuth.instance.signOut();
    if (!mounted) return;
    setState(() {
      _status = 'Çıkış yapıldı';
      _serverLogId = null;
    });
  }

  Future<void> _startScan() async {
    if (_user == null || !_consent || _scanning) return;
    if (_availability != NfcAvailability.enabled) {
      setState(() => _status = 'Telefonda NFC kapalı veya desteklenmiyor.');
      return;
    }
    setState(() {
      _scanning = true;
      _status = 'Kartı telefonun NFC antenine yaklaştır…';
      _serverLogId = null;
    });
    try {
      await NfcManager.instance.startSession(
        pollingOptions: const {
          NfcPollingOption.iso14443,
          NfcPollingOption.iso15693,
          NfcPollingOption.iso18092,
        },
        onDiscovered: (tag) {
          unawaited(_handleTag(tag));
        },
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _scanning = false;
        _status = 'Tarama başlatılamadı: $e';
      });
    }
  }

  Future<void> _handleTag(NfcTag tag) async {
    try {
      final report = await _buildReport(tag);
      await NfcManager.instance.stopSession(alertMessageIos: 'Kart okundu.');
      if (!mounted) return;
      setState(() {
        _lastResult = report;
        _scanning = false;
        _status = 'Kart okundu; sunucuya güvenli şekilde gönderiliyor…';
      });

      final callable = FirebaseFunctions.instanceFor(
        region: 'europe-west1',
      ).httpsCallable('logNfcProbe');
      final response = await callable.call<Map<String, dynamic>>({
        'probe': report,
      });
      if (!mounted) return;
      setState(() {
        _serverLogId = '${response.data['logId'] ?? ''}';
        _status = 'Kart okundu ve sunucu loguna kaydedildi.';
      });
    } catch (e) {
      try {
        await NfcManager.instance.stopSession(errorMessageIos: 'Okuma hatası');
      } catch (_) {}
      if (!mounted) return;
      setState(() {
        _scanning = false;
        _status = 'Kart görüldü fakat işlem tamamlanamadı: $e';
      });
    }
  }

  Future<Map<String, dynamic>> _buildReport(NfcTag tag) async {
    final package = await PackageInfo.fromPlatform();
    final report = <String, dynamic>{
      'schemaVersion': 1,
      'capturedAt': DateTime.now().toUtc().toIso8601String(),
      'platform': 'android',
      'appVersion': '${package.version}+${package.buildNumber}',
      'readMode': 'metadata_and_public_ndef_only',
    };

    final android = NfcTagAndroid.from(tag);
    if (android == null) {
      report['error'] = 'Android tag verisi alınamadı';
      return report;
    }

    report['tag'] = {
      'idHex': _hex(android.id),
      'idSha256': sha256.convert(android.id).toString(),
      'idByteLength': android.id.length,
      'techList': android.techList,
    };

    final nfcA = NfcAAndroid.from(tag);
    if (nfcA != null) {
      report['nfcA'] = {
        'atqaHex': _hex(nfcA.atqa),
        'sak': nfcA.sak,
        'maxTransceiveLength': await nfcA.getMaxTransceiveLength(),
        'timeoutMs': await nfcA.getTimeout(),
      };
    }

    final isoDep = IsoDepAndroid.from(tag);
    if (isoDep != null) {
      report['isoDep'] = {
        'historicalBytesHex': _hexOrNull(isoDep.historicalBytes),
        'hiLayerResponseHex': _hexOrNull(isoDep.hiLayerResponse),
        'extendedLengthApduSupported': isoDep.isExtendedLengthApduSupported,
        'maxTransceiveLength': await isoDep.getMaxTransceiveLength(),
        'timeoutMs': await isoDep.getTimeout(),
      };
    }

    final classic = MifareClassicAndroid.from(tag);
    if (classic != null) {
      report['mifareClassic'] = {
        'type': classic.type.name,
        'sizeBytes': classic.size,
        'sectorCount': classic.sectorCount,
        'blockCount': classic.blockCount,
        'note': 'Anahtar denenmedi; korumalı sektörler okunmadı.',
      };
    }

    final ultralight = MifareUltralightAndroid.from(tag);
    if (ultralight != null) {
      report['mifareUltralight'] = {
        'type': ultralight.type.name,
        'maxTransceiveLength': await ultralight.getMaxTransceiveLength(),
        'timeoutMs': await ultralight.getTimeout(),
        'note': 'Ham sayfa okuması yapılmadı.',
      };
    }

    final ndef = NdefAndroid.from(tag);
    if (ndef != null) {
      final message = await ndef.getNdefMessage();
      report['ndef'] = {
        'type': ndef.type,
        'maxSize': ndef.maxSize,
        'isWritable': ndef.isWritable,
        'canMakeReadOnly': ndef.canMakeReadOnly,
        'records': [
          for (final record in message?.records ?? const [])
            {
              'tnf': record.typeNameFormat.name,
              'typeHex': _hex(record.type),
              'identifierHex': _hex(record.identifier),
              'payloadHex': _hex(record.payload),
              'payloadUtf8Preview': _utf8Preview(record.payload),
            },
        ],
      };
    } else {
      report['ndef'] = {'supported': false};
    }

    return report;
  }

  String _prettyJson() =>
      const JsonEncoder.withIndent('  ').convert(_lastResult ?? {});

  @override
  Widget build(BuildContext context) {
    final availabilityLabel = switch (_availability) {
      NfcAvailability.enabled => 'NFC açık',
      NfcAvailability.disabled => 'NFC kapalı',
      NfcAvailability.unsupported => 'NFC desteklenmiyor',
      null => 'NFC kontrol ediliyor',
    };

    return Scaffold(
      appBar: AppBar(
        title: const Text('Kampüsteyim NFC Beta'),
        actions: [
          if (_user != null)
            IconButton(
              tooltip: 'Çıkış',
              onPressed: _logout,
              icon: const Icon(Icons.logout),
            ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              color: const Color(0xFFFFF7E6),
              child: const Padding(
                padding: EdgeInsets.all(14),
                child: Text(
                  'BETA TESTİ: Bu araç kartı değiştirmez. Yalnız Android’in '
                  'karttan okuyabildiği kimlik, teknoloji bilgileri ve varsa '
                  'açık NDEF kayıtlarını gösterir. Korumalı öğrenci verileri '
                  'üniversite anahtarı olmadan okunamaz.',
                  style: TextStyle(height: 1.4),
                ),
              ),
            ),
            const SizedBox(height: 12),
            if (_user == null) ...[
              const Text(
                'Sunucu logu için admin girişi',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(
                  labelText: 'Admin e-posta',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.mail_outline),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _password,
                obscureText: _obscure,
                decoration: InputDecoration(
                  labelText: 'Şifre',
                  border: const OutlineInputBorder(),
                  prefixIcon: const Icon(Icons.lock_outline),
                  suffixIcon: IconButton(
                    onPressed: () => setState(() => _obscure = !_obscure),
                    icon: Icon(
                      _obscure ? Icons.visibility : Icons.visibility_off,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              FilledButton.icon(
                onPressed: _busy ? null : _login,
                icon: const Icon(Icons.login),
                label: const Text('Admin girişi yap'),
              ),
            ] else ...[
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const CircleAvatar(
                  child: Icon(Icons.admin_panel_settings),
                ),
                title: Text(_user?.email ?? _user!.uid),
                subtitle: const Text(
                  'Sunucu yalnız admin hesabını kabul eder.',
                ),
              ),
              CheckboxListTile(
                value: _consent,
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                title: const Text(
                  'Kart kimliği ve teknik NFC çıktısının beta analiz amacıyla '
                  'sunucuya kaydedilmesini kabul ediyorum.',
                ),
                onChanged: _scanning
                    ? null
                    : (value) => setState(() => _consent = value == true),
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 56,
                child: FilledButton.icon(
                  onPressed: (_consent && !_scanning) ? _startScan : null,
                  icon: _scanning
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2.5),
                        )
                      : const Icon(Icons.nfc, size: 28),
                  label: Text(
                    _scanning ? 'KARTI YAKLAŞTIR' : 'NFC KARTI OKUT',
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 14),
            Card(
              child: ListTile(
                leading: const Icon(Icons.info_outline),
                title: Text(_status),
                subtitle: Text(
                  '$availabilityLabel'
                  '${_serverLogId == null ? '' : '\nSunucu logu: $_serverLogId'}',
                ),
              ),
            ),
            if (_lastResult != null) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Okunan ham teknik çıktı',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'JSON kopyala',
                    onPressed: () async {
                      await Clipboard.setData(
                        ClipboardData(text: _prettyJson()),
                      );
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('JSON kopyalandı')),
                      );
                    },
                    icon: const Icon(Icons.copy),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF111827),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: SelectableText(
                  _prettyJson(),
                  style: const TextStyle(
                    color: Color(0xFFE5E7EB),
                    fontFamily: 'monospace',
                    fontSize: 12,
                    height: 1.35,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

String _hex(Uint8List bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join().toUpperCase();

String? _hexOrNull(Uint8List? bytes) => bytes == null ? null : _hex(bytes);

String _utf8Preview(Uint8List bytes) {
  if (bytes.isEmpty) return '';
  final decoded = utf8.decode(bytes, allowMalformed: true);
  return decoded
      .replaceAll(RegExp(r'[\u0000-\u0008\u000B\u000C\u000E-\u001F]'), '�')
      .substring(0, decoded.length.clamp(0, 240));
}
