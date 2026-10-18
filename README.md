# Ecoomix

Kişisel gelir/gider, kredi kartı taksidi ve abonelik takibi için iPhone uygulaması (SwiftUI + SwiftData + iCloud).

- **Özet:** aylık net, bütçeler, kategori dağılımı, yaklaşan ödemeler, tasarruf önerileri
- **İşlemler:** hızlı ekleme; kredi kartında 2–24 taksit; arama ve filtre
- **Raporlar:** 1/3/6/12 aylık gelir-gider, tasarruf oranı, kategori trendi, en çok harcanan yerler. Taksitler için iki görünüm var: "Aylık yük" (taksitler aylara yayılır) ve "Satın alma" (alım ayında tek tutar).
- **Ödemeler:** taksit planları ve önümüzdeki 12 ayın yükü, abonelikler ve düzenli ödemeler, kart ekstre durumu
- **Bildirimler:** bütçe %80/%100, kart son ödeme, abonelik yenileme, aylık özet
- **Ekstre içe aktarma:** PDF, Excel (.xlsx) ve CSV. Garanti BBVA, Yapı Kredi ve Akbank profilleri; kolonlar tanınmazsa elle eşleme
- **Yapay zekâ analizi (isteğe bağlı):** Google Gemini ile kişisel tasarruf önerileri
- **Face ID kilidi, CSV dışa aktarma**

## Gereksinimler

- Xcode 26.5+, iOS 26 cihaz/simülatör
- [XcodeGen](https://github.com/yonaskolb/XcodeGen). `Makefile`, `~/.local/share/xcodegen-dist/bin/xcodegen` yolunu kullanır. Farklı bir kurulum için: `make XCODEGEN=xcodegen …`
- Ücretli Apple Developer hesabı (takım `TAKIM_KIMLIGI`; iCloud/CloudKit için gerekli)

## Komutlar

| Komut | Ne yapar |
|---|---|
| `make generate` | `project.yml`'dan `Ecoomix.xcodeproj` üretir (proje dosyası git'te tutulmaz) |
| `make core-test` | Saf iş mantığı testleri (`Packages/EcoomixCore`, macOS'ta saniyeler sürer) |
| `make test` | SwiftData entegrasyon testleri (simülatör) |
| `make gemini-live` | Uygulamanın gerçek Gemini isteklerini (analiz ve kategori) `Config/Secrets.xcconfig`'teki anahtarla dener |
| `scripts/check-gemini.sh` | Anahtarı ve istek biçimini küçük bir istekle hızlıca dener (anahtar yazdırılmaz) |
| `make demo` | Simülatörde 12 aylık demo veriyle açar (ayrı yerel dosya, iCloud'a gitmez) |
| `make screens` | Demo veriyle ekranları gezip `build/screens/` altına görüntü kaydeder |
| `make device UDID=…` | Kabloyla bağlı iPhone'a kurar |

## iPhone'a kurulum

1. iPhone'u kabloyla Mac'e bağla ve "Bu bilgisayara güven" de.
2. iPhone'da **Ayarlar > Gizlilik ve Güvenlik > Geliştirici Modu**'nu aç (telefon yeniden başlar).
3. İlk kurulumda bir kez `open Ecoomix.xcodeproj` ile projeyi aç. **Ecoomix** hedefinde **Signing & Capabilities** sekmesinde takımın seçili olduğunu ve iCloud container'ının (`iCloud.com.furkanfuat.ecoomix`) işaretli olduğunu kontrol et. Xcode, App ID'yi ve container'ı geliştirici hesabında oluşturur.
4. Cihaz kimliğini bul: `xcrun devicectl list devices`
5. Kur: `make device UDID=<cihaz-id>`

Ücretli hesapla kurulan uygulama 1 yıl geçerlidir. Süre dolunca 5. adımı tekrarlaman yeterli; veriler iCloud'da olduğu için kaybolmaz.

### iCloud notları

- Xcode'dan kurulan sürüm CloudKit **Development** ortamını kullanır.
- İleride TestFlight/App Store'a geçersen önce [CloudKit Console](https://icloud.developer.apple.com) üzerinden şemayı **Production**'a deploy et.
- Telefon değişirse ya da uygulama silinip yeniden kurulursa veriler iCloud'dan geri gelir. Varsayılan kategorilerin iki kez oluşması açılışta otomatik birleştirilir.

## Ekstre içe aktarma

1. Bankanın uygulamasından ya da internet şubesinden kart ekstresini **PDF**, **Excel (.xlsx)** ya da **CSV** olarak indir.
2. **Ayarlar > Ekstre içe aktar**'a gir, ilgili kartı seç ve dosyayı seç.
3. Önizlemede satırları kontrol et ve **İçe aktar**'a bas.
   - **Zaten eklenmiş:** daha önce içe aktarılan satırlar.
   - **Muhtemel tekrar:** aynı hesapta, ±2 gün içinde, aynı tutarla elle girdiğin bir işlem var. Eklenmez; senin kaydın ekstreyle eşleştirilir.
   - **Benzer tutar:** tutar ±5 ₺ ya da ±%2 yakın (ör. 245 ₺ girdin, ekstrede 245,28 ₺). İşyeri adı da tutuyorsa aynı alışveriş sayılır, eklenmez ve senin kaydının tutarı ekstredeki kuruşlu tutara düzeltilir. Tutmuyorsa satır eklenir ama "benzer olabilir" notuyla gösterilir; aynıysa işaretini kaldır.
   - Her elle girdiğin kayıt en fazla bir ekstre satırıyla eşleşir; önce tam tutar, sonra en küçük fark aranır. Her satırın altında hangi kaydınla eşleştiği yazar.
   - "TAKSİT 3/6" gibi satırlar mevcut plana bağlanır. Plan yoksa alım tarihi geriye hesaplanarak yeni plan oluşturulur.
   - Karta yapılan ödemeler varsayılan olarak kapalıdır; iadeler gelir olarak eklenir.

**Kategoriler** şu sırayla belirlenir:
1. Senin daha önceki seçimlerin. Aynı markanın başka şube ya da şehir yazımı da tanınır ("MIGROS KADIKÖY" için seçtiğin kategori "MIGROS SANAL MARKET İSTANBUL"a da gelir).
2. Yaygın Türk zincirleri ve "PASTANESİ, KASAP, ECZANESİ, OTOPARKI, KIRTASİYE" gibi genel kelimeler.
3. Önizlemede bir satıra kategori seçince, aynı işyerinin kategorisiz diğer satırları da onu alır.
4. Kalan kategorisiz satırlar için **Gemini ile belirle** düğmesi. Gemini'ye yalnızca işyeri adları ve kategori adların gider; tutar ve tarih gitmez. Gemini emin değilse satırı boş bırakır.

İçe aktarılan her kategori seçimi öğrenilir; sonraki ekstrelerde otomatik gelir.

**Banka kartı (debit):** Ayarlar > Hesaplar ve kartlar > + menüsünde her banka için kredi kartı ve banka kartı şablonu var. Banka kartı harcamaları vadesiz hesap dökümünde görünür. Bu dökümü içe aktarırken bir banka hesabı ya da banka kartı seç; eşleştirme tüm banka hesaplarına ve banka kartlarına elle girdiğin kayıtlara bakar. Kredi kartı ekstresi ise yalnızca o kartın kayıtlarıyla karşılaştırılır.

Eski `.xls` biçimi okunamaz. Dosyayı Numbers'ta açıp CSV ya da .xlsx olarak dışa aktar.

**PDF ekstreler:** Tarihle başlayıp tutarla biten satırlar işlem sayılır. Satırlar sayfadaki konuma göre kurulduğu için sütunlu PDF'ler de okunur. Taksit kolonu ("3/6") ve bonus/puan kolonu ayırt edilir. Taranmış (yalnızca görüntü olan) PDF'ler okunamaz. Okumada sorun olursa önizlemedeki **Biçim örneğini paylaş** düğmesi gizlenmiş bir örnek üretir: rakamlar 9'a, harfler X'e döner, yalnızca başlık kelimeleri kalır. Okuyucu bu örnekle bankana göre ayarlanabilir.

> Banka profilleri yaygın kolon adlarına göre yazıldı ("Tarih", "İşlem/Açıklama", "Tutar", "Taksit", "Borç/Alacak"). Gerçek bir ekstre düzgün okunmazsa elle eşleme ekranı devreye girer. Kolon düzeni belli olan bir örnek dosyayla profil kesinleştirilebilir (`Packages/EcoomixCore/Tests/EcoomixCoreTests/Fixtures`).

## Yapay zekâ analizi (Google Gemini)

Anahtarı [aistudio.google.com](https://aistudio.google.com) > **Get API key** üzerinden al. İki yoldan biriyle ver:

1. **Dosya (önerilen):** `Config/Secrets.xcconfig` içinde `GEMINI_API_KEY = AIza…` satırını doldur, sonra `make device UDID=…` ile yeniden kur. Bu dosya `.gitignore`'da; git'e girmez. İlk `make generate` onu `Config/Secrets.example.xcconfig` şablonundan oluşturur.
2. **Uygulama içinden:** **Ayarlar > Yapay zekâ** alanına yaz. Yalnızca bu cihazın Keychain'inde saklanır ve dosyadaki anahtardan önce gelir.

Dosya yolunda anahtar uygulama paketine gömülür. Uygulama yalnızca senin telefonunda olduğu için risk düşük; yine de Google Cloud Console'da anahtarı **Generative Language API** ve **iOS uygulaması `com.furkanfuat.ecoomix`** ile sınırlaman önerilir (uygulama `X-Ios-Bundle-Identifier` başlığını gönderir).

- Analiz yalnızca **Öneriler > Son 6 ayı analiz et** düğmesiyle çalışır. Model düşünerek yanıt verdiği için 1–2 dakika sürebilir.
- Model: `gemini-3.8-flash` (varsayılan) ya da `gemini-4-argon`. Ayarlar'dan seçilir.
- **Gönderilenler:** aylık gelir/gider toplamları, kategori × ay toplamları, bütçeler, abonelik adları ve tutarları, taksit yükü, kural tabanlı bulgular.
- **Gönderilmeyenler:** işlem notları ve tek tek işlemler. İşyeri adları yalnızca ayarlardan izin verilirse gönderilir.
- Ücretsiz katmanda Google gönderilen içeriği ürün geliştirmede kullanabilir. Bunu istemiyorsan AI Studio'da faturalandırmayı aç.

## Mimari

```
Packages/EcoomixCore   Saf Swift: para, takvim, kesim döngüsü, taksit, düzenli işlem, rapor,
                       bütçe, tasarruf analizi, AI özeti, CSV/XLSX ekstre çözümleme (+ testler)
Ecoomix/Models         SwiftData modelleri (CloudKit kurallarına uygun)
Ecoomix/Services       LedgerService, RecurringGenerator, ImportService, BudgetMonitor,
                       NotificationScheduler, GeminiAdvisor, CSVExporter, SeedService
Config                 Secrets.example.xcconfig (şablon); Secrets.xcconfig git'e girmez
Ecoomix/Features       SwiftUI ekranları
EcoomixTests           SwiftData entegrasyon testleri (bellek içi)
EcoomixUITests         Ekran görüntüsü ve içe aktarma akışı testleri
```

Tasarım dokümanı: `docs/superpowers/specs/2026-10-18-ecoomix-design.md`
