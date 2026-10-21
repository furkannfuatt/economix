# App Store yayın rehberi

Economix ücretsizdir, uygulama içi satın alma ya da abonelik içermez. Bu dosya App Store Connect'e girilecek bilgileri ve yayın adımlarını toplar.

## 1. Sürümü hazırla (geliştirici)

- Simge saydamlık kanalı içermez (`scripts/make-icon.swift`).
- Gizlilik bildirimi: `Economix/Resources/PrivacyInfo.xcprivacy`.
- Gemini'ye veri gitmeden önce açık izin penceresi (`Economix/Features/AI/AIConsent.swift`).
- Ekran görüntüleri: `make appstore-screens` → `build/appstore/` (6,9 inç, 1320×2868). App Store Connect daha küçük ekranlar için bunları kendisi ölçekler.
- Arşiv ve yükleme: Xcode > Product > Archive > Distribute App > App Store Connect, ya da komut satırından `xcodebuild archive` + `-exportArchive`. Xcode, dağıtımda bildirim ve iCloud ortamını Production'a kendisi çevirir.

## 2. iCloud şemasını Production'a aktar (bir kez, yayından önce)

Mağaza ve TestFlight sürümleri iCloud'un **Production** ortamını kullanır; geliştirme sürümleri **Development**'ı.

1. [icloud.developer.apple.com](https://icloud.developer.apple.com) > CloudKit Console > `iCloud.com.furkanfuat.ecoomix`.
2. **Schema** > **Deploy Schema Changes…** > Development → Production > **Deploy**.

Şema değişmedikçe bu adım tekrarlanmaz. Yeni bir model alanı eklenirse yayından önce yeniden deploy edilir.

## 3. Verilerini mağaza sürümüne taşı

Apple, Development ile Production arasında veri taşımaz. Geliştirme sürümündeki veriler mağaza sürümünde kendiliğinden görünmez.

1. Geliştirme sürümünde **Ayarlar > Yedekle ve geri yükle > Yedek dosyasını kaydet** ile dosyayı Dosyalar'a (ör. iCloud Drive) kaydet.
2. TestFlight ya da App Store sürümünü kur.
3. Veriler görünmüyorsa: ilk açılış ekranında **Yedekten geri yükle**'ye, ya da Ayarlar > Yedekle ve geri yükle > Yedek dosyası seç'e dokunup dosyayı seç.

Geri yükleme mevcut verilerin yerine geçer; çift kayıt oluşmaz. Gemini anahtarını, Gemini iznini ve Face ID kilidini yeniden ver.

## 4. App Store Connect kaydı

appstoreconnect.apple.com > Uygulamalar > **+** > Yeni Uygulama:

| Alan | Değer |
|---|---|
| Platform | iOS |
| Ad | Economix |
| Birincil dil | Türkçe |
| Paket kimliği | `com.furkanfuat.economix` |
| SKU | `economix-ios` |
| Kullanıcı erişimi | Tam erişim |

Ad başka bir uygulamada kullanılıyorsa (ör. "Economix: Bütçe ve Taksit") gibi bir varyant seç.

## 5. Mağaza bilgileri

**Alt başlık** (en fazla 30 karakter):
Bütçe, taksit ve abonelik

**Promosyon metni** (en fazla 170 karakter):
Harcamalarını, kredi kartı taksitlerini ve aboneliklerini tek yerde izle. Reklamsız, ücretsiz ve açık kaynak; verilerin yalnızca senin iCloud hesabında.

**Açıklama:**

Economix; gelirini, giderini, kredi kartı taksitlerini ve aboneliklerini tek yerde takip etmen için ücretsiz ve açık kaynaklı bir uygulamadır. Reklam, abonelik ya da uygulama içi satın alma yoktur. Verilerin yalnızca cihazında ve kendi iCloud hesabında durur.

ÖZET VE BÜTÇELER
• Ayın neti, gelir ve gider bir bakışta
• Kategori bütçeleri ve "bu hızla ay sonu" tahmini
• Bütçe ayını maaş gününe göre başlat (ör. her ayın 23'ü)

RAPORLAR
• Hafta, ay, 3 ay, 6 ay, yıl ya da seçtiğin tarih aralığı
• Günlük, haftalık ve aylık harcama grafikleri, tutar dökümüyle
• Kümülatif harcama: önceki dönemin aynı günüyle kıyas
• Kategori dağılımı, haftanın günlerine göre harcama, en çok harcadığın yerler
• Taksitler için "aylık yük" ve "satın alma" görünümleri

TAKSİT VE ABONELİKLER
• Kredi kartı taksit planları, kalan tutar ve biten taksitler
• Önümüzdeki 12 ayın taksit yükü
• Abonelik ve düzenli ödemelerin aylık ve yıllık maliyeti
• Kart hesap kesimi ve son ödeme günü hatırlatmaları

EKSTRE İÇE AKTARMA
• Kart ekstreni PDF, Excel ya da CSV olarak içe aktar
• Elle girdiğin harcamalarla otomatik eşleştirme, çift kayıt yok
• Kategoriler işyerine göre öğrenilir

TASARRUF ÖNERİLERİ
• Bütçe aşımı, artan harcamalar ve benzer abonelikler için öneriler
• İsteğe bağlı: kendi Google Gemini anahtarınla, açık iznin alınarak yapay zekâ analizi

GİZLİLİK VE GÜVENLİK
• Hesap açmak gerekmez, veri toplanmaz
• Face ID kilidi
• Tüm verilerini tek dosyaya yedekle, geri yükle; Excel için CSV dışa aktar

Açık kaynak: github.com/furkannfuatt/economix

**Anahtar kelimeler** (en fazla 100 karakter, virgülle):
bütçe,harcama,gider,gelir,taksit,kredi kartı,abonelik,ekstre,tasarruf,para,finans,hesap

**Destek URL'si:** https://github.com/furkannfuatt/economix/issues
**Pazarlama URL'si:** https://github.com/furkannfuatt/economix
**Gizlilik politikası URL'si:** https://github.com/furkannfuatt/economix/blob/main/PRIVACY.md

**Kategori:** Finans (birincil)
**Fiyat:** Ücretsiz (0 ₺), uygulama içi satın alma yok
**Telif hakkı:** 2026 Furkan Fuat
**Yaş derecelendirmesi:** Anketteki tüm sorulara "Yok" → 4+

## 6. Uygulama gizliliği formu

App Store Connect > Uygulama Gizliliği. `PrivacyInfo.xcprivacy` ile tutarlı:

- **Veri topluyor musunuz?** Evet. Yalnızca isteğe bağlı Gemini özelliği için.
- **Veri türü:** Finansal Bilgiler > Diğer Finansal Bilgiler
  - Kullanım amacı: Uygulama İşlevselliği
  - Kullanıcı kimliğiyle ilişkilendiriliyor mu? Hayır
  - İzleme (tracking) için kullanılıyor mu? Hayır
- Diğer tüm veri türleri: toplanmıyor.

Gemini kullanılmadıkça hiçbir veri cihazdan çıkmaz. iCloud'daki veriler kullanıcının kendi özel veritabanındadır; Apple'ın tanımına göre geliştirici tarafından toplanmış sayılmaz.

## 7. İnceleme bilgileri (App Review notları, İngilizce)

- **Oturum açma gerekli mi?** Hayır.
- **Notlar:**

```
Economix is a free, open-source personal finance tracker (Turkish UI). No account, no in-app purchases, no ads, no analytics.

How to test:
1. On first launch tap "Başla" (Start) to create default categories.
2. Add transactions with the "İşlem ekle" (Add transaction) button at the bottom.
3. Reports (Raporlar), Payments (Ödemeler: installments, subscriptions, cards) and Settings (Ayarlar) work without any setup.
4. Statement import (Ayarlar > Ekstre içe aktar) accepts PDF/XLSX/CSV card statements from Turkish banks. A sample file:
   https://github.com/furkannfuatt/economix/blob/main/EconomixUITests/Fixtures/garanti-ornek.csv

Optional AI feature: "Gemini" analysis/categorization only works if the user enters their own Google Gemini API key (Ayarlar > Yapay zekâ). Before any data is sent, the app shows an explicit consent dialog describing exactly what is sent; the user can revoke it in settings. The app is fully functional without it.

Data is stored on device and in the user's private CloudKit database. Face ID lock is optional.
```

## 8. TestFlight ve gönderim

1. Yüklenen sürüm App Store Connect > TestFlight'ta görünür (işlenmesi 10–30 dk sürer).
2. Kendini iç test kullanıcısı olarak ekle, TestFlight uygulamasından kur, 3. adımdaki veri taşımayı dene.
3. Her şey yolundaysa: App Store sekmesi > sürüm 1.0 > yapıyı seç > **İncelemeye Gönder**. İnceleme genelde 1–2 gün sürer.
