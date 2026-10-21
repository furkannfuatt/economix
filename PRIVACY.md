# Economix Gizlilik Politikası

Son güncelleme: 21 Ekim 2026

Economix, kişisel gelir-gider, kredi kartı taksidi ve abonelik takibi için ücretsiz ve açık kaynaklı bir iPhone uygulamasıdır. Geliştirici hiçbir kişisel verini toplamaz, görmez ya da saklamaz.

## Verilerin nerede durur

- Girdiğin işlemler, hesaplar, kategoriler, bütçeler, taksit planları ve düzenli ödemeler **yalnızca cihazında** ve **kendi iCloud hesabının özel veritabanında** saklanır. Bu veritabanına yalnızca sen erişebilirsin; geliştiricinin erişimi yoktur.
- Uygulamanın ayarları (bütçe ayı başlangıcı, bildirim tercihleri gibi) yalnızca cihazında durur.
- İçe aktardığın ekstre dosyaları (PDF, Excel, CSV) cihazında okunur ve hiçbir yere gönderilmez.

## Toplanan veriler

Uygulama analiz, reklam ya da takip aracı içermez. Kullanım istatistiği, çökme raporu ya da reklam kimliği toplanmaz. Geliştiriciye hiçbir veri gönderilmez.

## İsteğe bağlı: Google Gemini

Yapay zekâ analizi ve otomatik kategorileme isteğe bağlıdır ve yalnızca:

1. kendi Google Gemini API anahtarını uygulamaya girersen,
2. uygulamanın gösterdiği izin penceresinde açıkça izin verirsen,
3. ve özelliği kendin başlatırsan çalışır.

Bu durumda şu bilgiler, senin anahtarınla doğrudan Google'ın Gemini hizmetine gönderilir:

- **Analizde:** son 6 ayın aylık gelir-gider toplamları, kategori toplamları, bütçeler, abonelik adları ve taksit yükü. Ayarlardan izin verirsen en çok harcadığın işyerlerinin adları ve toplamları ile bitmek üzere olan taksit planlarının adları.
- **Kategorilemede:** ekstredeki işyeri adları ve kategori adların.

İşlem notları, hesap adları ve kimlik bilgilerin gönderilmez. Gönderilen veriler Google'ın [Gemini API şartlarına](https://ai.google.dev/gemini-api/terms) tabidir; ücretsiz katmanda Google bu içeriği ürünlerini geliştirmek için kullanabilir. API anahtarın yalnızca cihazının Keychain'inde saklanır. İzni istediğin zaman Ayarlar > Yapay zekâ'dan geri alabilirsin.

## Face ID ve bildirimler

- Face ID kilidi isteğe bağlıdır. Kimlik doğrulaması iOS tarafından cihazda yapılır; uygulama yüz verine erişmez.
- Bildirimler (bütçe uyarıları, kart son ödeme günü, abonelik yenileme) cihazında oluşturulur; bir sunucudan gönderilmez.

## Yedek ve dışa aktarma dosyaları

"Yedekle" ve "CSV dışa aktar" özellikleri verilerini senin seçtiğin yere kaydettiğin bir dosyaya yazar. Bu dosyalar şifrelenmez; nerede saklayacağına sen karar verirsin. Uygulamanın paylaşım için hazırladığı geçici kopya, ekrandan çıkınca ve uygulama her açıldığında silinir.

## Verilerini silme

Uygulamayı silmek cihazdaki verileri siler. iCloud'daki kopyayı **Ayarlar > [adın] > iCloud > Saklama Alanını Yönet** bölümünden silebilirsin.

## Çocuklar

Uygulama çocuklara yönelik değildir ve kimseden bilerek kişisel veri toplamaz.

## İletişim

Soruların ve geri bildirimlerin için: [github.com/furkannfuatt/economix/issues](https://github.com/furkannfuatt/economix/issues)

---

# Economix Privacy Policy (English)

Economix is a free, open-source iPhone app for tracking personal income, expenses, credit-card installments and subscriptions. The developer does not collect, see or store any of your personal data.

- **Where your data lives:** only on your device and in your own private iCloud database, which only you can access. Imported statement files are read on the device and never uploaded.
- **No analytics, ads or tracking.** Nothing is sent to the developer.
- **Optional Google Gemini:** runs only if you enter your own Gemini API key, give explicit permission in the in-app consent dialog, and start the feature yourself. Monthly totals, category totals, budgets, subscription names, installment load (and, if you allow it, top merchant names and the names of installment plans that are about to end) for analysis, or merchant and category names for categorization are sent directly to Google under the [Gemini API terms](https://ai.google.dev/gemini-api/terms). Notes, account names and identity data are never sent. Your key stays in the device Keychain; you can revoke permission in Settings > Yapay zekâ.
- **Face ID and notifications** are handled on the device by iOS.
- **Backup and CSV export files** are written where you choose and are not encrypted. The temporary copy prepared for sharing is deleted when you leave the screen and on every app launch.
- **Deleting data:** delete the app, and remove the iCloud copy in Settings > [your name] > iCloud > Manage Storage.
- **Contact:** [github.com/furkannfuatt/economix/issues](https://github.com/furkannfuatt/economix/issues)
