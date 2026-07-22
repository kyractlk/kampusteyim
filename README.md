# KampüsteyimAPP

Kampüs sosyal ağı — Flutter ile **Android · iOS · Web**. Altyapı: **AYS Tech** · Firebase: `ayskampuss`.

Canlı web: https://ayskampuss.web.app

## Özellikler

### Hesap & güvenlik
- Öğrenci belgesi ile kayıt; admin onay kuyruğu
- Onay sonucu e-posta + push (iOS & Android)
- KVKK + pazarlama rızası
- Gizlilik: aramada gizle, gizli hesap, izleyici modu, engelleme

### Sosyal
- Akış, hikâyeler, takipçi/takip listeleri
- Duyurular, etkinlikler, çalışma odaları
- Staj / iş ilanları, CV-AI

### Operasyon
- Admin paneli, Guard moderasyonu, bakım modu

## Çalıştırma

```bash
flutter pub get
flutter run -d chrome
flutter run
```

## Firebase

**Project ID:** `ayskampuss` · Functions: `europe-west1`

```bash
firebase deploy --only "hosting,functions,firestore:rules,storage"
```

## Marka

- Uygulama adı: **KampüsteyimAPP**
- Logo: `assets/brand/kampus_app_logo.svg`
- AYS Tech altyapı olarak hafif gösterilir
