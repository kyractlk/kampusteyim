import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

/// Admin’den düzenlenebilir KVKK + pazarlama metinleri.
class LegalConsentTexts {
  const LegalConsentTexts({
    required this.kvkkTitle,
    required this.kvkkBody,
    required this.marketingTitle,
    required this.marketingBody,
    this.updatedAt,
    this.updatedBy,
  });

  final String kvkkTitle;
  final String kvkkBody;
  final String marketingTitle;
  final String marketingBody;
  final DateTime? updatedAt;
  final String? updatedBy;

  static const defaults = LegalConsentTexts(
    kvkkTitle: 'Kişisel Verilerin Korunması Kanunu (KVKK) Aydınlatma Metni',
    kvkkBody: '''1. Veri Sorumlusu
6698 sayılı Kişisel Verilerin Korunması Kanunu (“KVKK”) uyarınca, KampüsteyimAPP mobil uygulaması ve ilişkili dijital hizmetler kapsamında kişisel verileriniz; veri sorumlusu sıfatıyla AYS Tech (bundan sonra “AYS Tech” veya “Şirket”) tarafından aşağıda açıklanan kapsamda işlenmektedir.

İletişim: Geri Bildirim / destek kanalları üzerinden KampüsteyimAPP uygulaması içinden veya AYS Tech resmi iletişim adreslerinden.

2. İşlenen Kişisel Veriler
Uygulama kullanımı kapsamında; kimlik (ad, soyad), iletişim (e-posta, telefon), öğrenci / üyelik bilgileri (öğrenci numarası, üniversite, fakülte, bölüm, şehir), hesap (kullanıcı adı, profil fotoğrafı, biyografi), işlem güvenliği (oturum, cihaz / bildirim token’ları), kullanıcı işlem (gönderi, yorum, beğeni, hikâye, şikayet, çalışma odası etkinlikleri), gizlilik tercihleri ve gerektiğinde pazarlama tercihleri işlenebilir.

e-Devlet öğrenci belgesi doğrulamasında: barkod ve T.C. kimlik numarası yalnızca anlık doğrulama için Türkiye.gov.tr’ye iletilir. Dönen PDF bellekte okunur; üniversite, fakülte, bölüm, öğrencilik durumu ve sınıf gibi eğitim / öğretim alanları çıkarılır. T.C. kimlik numarası, anne / baba adı, doğum yeri-tarihi ve ham PDF kalıcı olarak saklanmaz. Doğrulama kaydı, hesabınızdaki e-posta ve öğrenci numarası ile ilişkilendirilir.

3. Öğrenci Belgesi Doğrulama (hukuki değerlendirme)
KampüsteyimAPP doğrulanmış öğrenci kitlesine yönelik bir platformdur. Öğrenci olduğunu teyit etmek, sahte hesapları ve kampüs dışı kötüye kullanımı önlemek meşru bir amaçtır.

Yasal yaklaşımımız (veri minimizasyonu ile):
• Anlık doğrulama: barkod + T.C. yalnızca e-Devlet sorgusunda kullanılır; sonrasında T.C. ve ham belge silinir.
• Saklanan içerik: yalnızca eğitim / öğretim alanları + doğrulama zamanı + bağlı e-posta / öğrenci no.
• Saklanmayanlar: T.C. kimlik no (düz metin), anne/baba adı, doğum bilgileri, ham PDF / kart görüntüsü (e-Devlet başarılıysa).

Bu model KVKK m.4’teki “amaçla bağlantılı, sınırlı ve ölçülü olma” (veri minimizasyonu) ilkesine uygun tasarlanmıştır. Eğitim bilgisi “özel nitelikli kişisel veri” (KVKK m.6 sağlık / biyometrik vb.) kapsamında değildir; genel kişisel veridir.

Doğrulama başarısız olursa veya öğrenci kartı yüklenirse; yüklenen görüntü / PDF yalnızca admin incelemesi için işlenir ve onay sürecinin tamamlanmasına kadar tutulabilir.

4. Kişisel Verilerin İşlenme Amaçları
Üyelik oluşturma ve öğrenci doğrulama, kampüs sosyal ağı hizmetlerinin sunulması, içerik moderasyonu ve güvenlik (AYS Tech Guard dâhil), bildirim gönderimi, staj / CV / etkinlik / hikâye özelliklerinin işletilmesi, yasal yükümlülüklerin yerine getirilmesi, suiistimalin önlenmesi ve hizmet kalitesinin artırılması.

5. Hukuki Sebepler (KVKK m.5)
• m.5/2-c — Bir sözleşmenin kurulması veya ifasıyla doğrudan doğruya ilgili olması kaydıyla sözleşmenin taraflarına ait kişisel verilerin işlenmesinin gerekli olması (üyelik / öğrenci platform hizmetinin kurulması ve ifası).
• m.5/2-f — İlgili kişinin temel hak ve özgürlüklerine zarar vermemek kaydıyla, veri sorumlusunun meşru menfaatleri için veri işlenmesinin zorunlu olması (kampüs topluluğunun doğruluğu, sahte hesap / kötüye kullanım önleme, güvenlik).
• m.5/1 — Açık rıza: özellikle pazarlama iletişimi ve — manuel belge yükleme hâlinde — belge incelemesi için.
• Gerekli hallerde m.5/2-ç (hukuki yükümlülük) ve m.5/2-e (bir hakkın tesisi, kullanılması veya korunması).

Kaynak: https://www.kvkk.gov.tr/Icerik/4190/Kisisel-Verilerin-Islenme-Sartlari

6. Aktarım
Verileriniz; hizmet altyapısı için Firebase / Google Cloud gibi yurt içi-yurt dışı teknik hizmet sağlayıcılarına, yasal zorunluluk hâlinde yetkili kamu kurumlarına ve açık rızanız varsa pazarlama amaçlı AYS Tech ekosistem hizmetlerine aktarılabilir. e-Devlet doğrulama sorgusu Türkiye.gov.tr altyapısına yapılır. Aktarımlarda KVKK’ya uygun güvenlik önlemleri alınır.

7. Saklama
e-Devlet otomatik doğrulamasında ham PDF ve T.C. kimlik numarası doğrulama sonrası tutulmaz; yalnızca eğitim alanları ve doğrulama özeti hesap kaydıyla (e-posta / öğrenci no) ilişkilendirilir. Manuel yüklenen öğrenci kartı / belge görüntüleri, onay sürecinin tamamlanması ve olası itiraz süreleri boyunca; diğer veriler üyelik ve yasal saklama süreleri boyunca muhafaza edilir. Hesap silme taleplerinde KVKK’ya uygun silme/yok etme süreçleri işletilir.

8. Haklarınız
KVKK’nın 11. maddesi uyarınca; kişisel verilerinizin işlenip işlenmediğini öğrenme, işlenmişse bilgi talep etme, amaca uygun kullanılıp kullanılmadığını öğrenme, yurt içinde/yurt dışında aktarıldığı üçüncü kişileri bilme, eksik/yanlış işlenmişse düzeltilmesini isteme, KVKK’ya uygun silme/yok etme talep etme, otomatik sistemler vasıtasıyla analiz sonucu aleyhinize çıkan sonuca itiraz etme ve kanuna aykırı işleme nedeniyle zararın giderilmesini talep etme haklarınız vardır.

Taleplerinizi KampüsteyimAPP içindeki “Geri Bildirim” hattı veya hesap silme süreçleri üzerinden iletebilirsiniz. Başvurularınız yasal sürelerde sonuçlandırılır.

9. Onay
Bu aydınlatma metnini okuduğunuzu; kişisel verilerinizin (öğrenci doğrulama özeti dâhil) yukarıda belirtilen kapsam, amaç ve hukuki sebepler çerçevesinde işlenmesini kabul ettiğinizi beyan edersiniz.''',
    marketingTitle: 'Pazarlama İletişimi Açık Rıza Metni',
    marketingBody: '''6698 sayılı KVKK ve 6563 sayılı Elektronik Ticaretin Düzenlenmesi Hakkında Kanun ile ilgili ikincil mevzuat kapsamında; AYS Tech’in sunduğu ürün, hizmet, kampanya, etkinlik ve bilgilendirmelere ilişkin ticari elektronik ileti ve pazarlama iletişimi için açık rızanız alınmaktadır.

E-posta, uygulama içi bildirim (push), gerekirse SMS / diğer elektronik iletişim kanalları kullanılabilir.

Ad-soyad, e-posta, kullanıcı adı ve tercih ettiğiniz iletişim bilgileriniz; tanıtım, duyuru, kampanya, ürün/hizmet bilgilendirmesi ve AYS Tech ekosistemindeki uygulamalara ilişkin pazarlama amaçlarıyla işlenebilir.

Bu izin, geri alınana kadar geçerlidir. İstediğiniz zaman KampüsteyimAPP “Geri Bildirim” hattı, bildirim ayarları veya iletilerde yer alan ret imkânları üzerinden pazarlama iletişimini durdurabilirsiniz. Rızanın geri alınması, üyeliğinizi veya zorunlu hizmet bildirimlerini (ör. hesap onay sonucu) etkilemez.''',
  );

  factory LegalConsentTexts.fromMap(Map<String, dynamic>? m) {
    if (m == null || m.isEmpty) return defaults;
    final rawBody = '${m['kvkkBody'] ?? ''}'.trim();
    // Eski Firestore metni yeni dayanakları içermiyorsa kod varsayılanına dön.
    final kvkkBody = rawBody.isEmpty || !rawBody.contains('m.5/2-c')
        ? defaults.kvkkBody
        : rawBody;
    return LegalConsentTexts(
      kvkkTitle: '${m['kvkkTitle'] ?? defaults.kvkkTitle}'.trim().isEmpty
          ? defaults.kvkkTitle
          : '${m['kvkkTitle']}'.trim(),
      kvkkBody: kvkkBody,
      marketingTitle:
          '${m['marketingTitle'] ?? defaults.marketingTitle}'.trim().isEmpty
              ? defaults.marketingTitle
              : '${m['marketingTitle']}'.trim(),
      marketingBody:
          '${m['marketingBody'] ?? defaults.marketingBody}'.trim().isEmpty
              ? defaults.marketingBody
              : '${m['marketingBody']}'.trim(),
      updatedAt: DateTime.tryParse('${m['updatedAt'] ?? ''}'),
      updatedBy: m['updatedBy'] as String?,
    );
  }

  Map<String, dynamic> toMap() => {
        'kvkkTitle': kvkkTitle,
        'kvkkBody': kvkkBody,
        'marketingTitle': marketingTitle,
        'marketingBody': marketingBody,
        'updatedAt': updatedAt?.toIso8601String(),
        'updatedBy': updatedBy,
      };

  static Future<LegalConsentTexts> load() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('app_config')
          .doc('legal_consent')
          .get();
      if (!doc.exists) return defaults;
      return LegalConsentTexts.fromMap(doc.data());
    } catch (e) {
      debugPrint('[legal] load: $e');
      return defaults;
    }
  }

  static Future<void> save(LegalConsentTexts texts, {String? by}) async {
    final now = DateTime.now();
    final payload = texts.toMap()
      ..['updatedAt'] = now.toIso8601String()
      ..['updatedBy'] = by;
    await FirebaseFirestore.instance
        .collection('app_config')
        .doc('legal_consent')
        .set(payload, SetOptions(merge: true));
  }
}
