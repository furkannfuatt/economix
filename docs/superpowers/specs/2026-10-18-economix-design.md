# Economix — Kişisel Gelir/Gider ve Taksit Takip Uygulaması (iOS)

## Bağlam

Kullanıcı yalnızca kendi iPhone'unda kullanacağı detaylı bir finans uygulaması istiyor:
- Geriye dönük harcamaları ve kategori dağılımını görmek
- Gelir/gider dengesini izlemek
- Kredi kartı taksitlerini takip etmek (kaç taksit kaldı, aylık yük ne)
- "Neyden tasarruf etmeliyim" sorusuna somut cevap almak

Proje klasörü boş, yani sıfırdan başlıyoruz.
Ortam: Xcode 26.5, Swift 6.3, iOS 26.5 simülatörü, XcodeGen (`~/.local/bin/xcodegen`) kurulu. Ücretli Apple Developer hesabı mevcut (takım kimliği `Config/Secrets.xcconfig` içinde).

### Kullanıcının verdiği kararlar
| Konu | Karar |
|---|---|
| Platform | Native iOS: SwiftUI + SwiftData + Swift Charts, **iOS 26 hedefli** |
| Veri | SwiftData + **CloudKit (iCloud otomatik senkron)** |
| Borç türleri | Kredi kartı taksitleri, abonelikler/düzenli ödemeler |
| Ek özellikler | Kart hesap kesim takibi, bütçe limiti + bildirim, ekstre içe aktarma, AI tasarruf analizi |
| Bankalar | Garanti BBVA (Bonus), Yapı Kredi (World), Akbank (Axess) |

---

## Mimari

**İki katman:**
1. **`EconomixCore`** (yerel Swift Package): Saf iş mantığı, UI ve SwiftData bağımlılığı yok. Değer tipleri (struct snapshot) üzerinde çalışır, `swift test` ile macOS'ta saniyeler içinde test edilir (Swift Testing, TDD).
2. **`Economix`** (iOS app target): SwiftData modelleri, servisler (Core'u SwiftData'ya bağlayan katman) ve SwiftUI ekranları.

Proje dosyası **XcodeGen** (`project.yml`) ile üretilir. `.xcodeproj` git'e girmez, CLI'dan tekrar üretilebilir.

- Bundle ID: `com.furkanfuat.economix` · iCloud container: `iCloud.com.furkanfuat.ecoomix` (uygulamanın eski yazımı; veriler orada olduğu için değiştirilmedi)
- Capabilities: iCloud (CloudKit), Push Notifications + Background Modes → Remote notifications (CloudKit senkronu sessiz push ile çalışır)
- Bağımlılık: yalnızca **CoreXLSX** (SPM, .xlsx okumak için). Gerisi Apple framework'leri.
- Takvim: `Europe/Istanbul`, Gregoryen, hafta pazartesi başlar. Para formatı `tr_TR` ("1.234,56 ₺").

### Klasör yapısı
```
economix/
  project.yml
  docs/superpowers/specs/2026-10-18-economix-design.md   (bu planın spec kopyası)
  Packages/EconomixCore/
    Sources/EconomixCore/
      Money.swift                 // kuruş (Int) tabanlı tutar + TL format/parse
      StatementCycle.swift        // hesap kesim / son ödeme hesabı
      InstallmentScheduler.swift  // taksit takvimi üretimi
      RecurrenceEngine.swift      // abonelik/düzenli işlem vade tarihleri
      ReportBuilder.swift         // dönem, kategori, trend, işyeri toplamları
      BudgetEvaluator.swift       // limit, oran, ay sonu tahmini
      SavingsAnalyzer.swift       // kural tabanlı tasarruf önerileri
      AIPayloadBuilder.swift      // AI'ya gidecek özet JSON
      Import/ CSVReader, XLSXReader, BankProfiles, StatementParser, MerchantCategorizer
    Tests/EconomixCoreTests/  (+ Fixtures/ anonimleştirilmiş ekstre örnekleri)
  Economix/
    App/        EconomixApp, ModelContainerFactory, AppLock (Face ID)
    Models/     Account, Category, Transaction, InstallmentPlan, RecurringItem, MerchantRule, AIAnalysis
    Services/   TransactionService, RecurringGenerator, NotificationScheduler, ImportService,
                AIAdvisor, KeychainStore, SeedService, CSVExporter
    Features/   Dashboard/, Transactions/, Reports/, Payments/, Settings/, Import/
    Resources/  Assets.xcassets
  EconomixTests/ (SwiftData entegrasyon testleri, in-memory container)
```

---

## Veri Modeli (SwiftData, CloudKit uyumlu)

**CloudKit kuralları (zorunlu):** Her property'nin varsayılan değeri olacak ya da optional olacak, `@Attribute(.unique)` kullanılmayacak, tüm ilişkiler optional olacak ve inverse'leri tanımlanacak. Enum'lar `xxxRaw: String` olarak saklanır (predicate dostu). Tutarlar **kuruş cinsinden `Int`** (Decimal yerine; CloudKit ve predicate sorunsuz).

| Model | Alanlar |
|---|---|
| `Account` | name, typeRaw (`cash`/`bank`/`creditCard`), icon, colorHex, openingBalanceMinor, **statementDay** (hesap kesim günü), **dueOffsetDays** (varsayılan 10), creditLimitMinor?, isArchived |
| `Category` | name, icon (SF Symbol), colorHex, kindRaw (`expense`/`income`), **monthlyLimitMinor?** (bütçe), sortOrder, seedKey? |
| `Transaction` | amountMinor (her zaman pozitif), kindRaw (`expense`/`income`/`transfer`), date, merchant, note, account?, toAccount? (transfer), category?, installmentPlan?, installmentIndex?, recurringItem?, sourceRaw (`manual`/`import`/`recurring`/`installment`), importHash?, createdAt |
| `InstallmentPlan` | title, merchant, totalMinor, count, purchaseDate, account? (kart), category?, closedEarlyAt?, transactions? |
| `RecurringItem` | title, amountMinor, kindRaw, frequencyRaw (`weekly`/`monthly`/`yearly`), dayOfMonth, startDate, endDate?, **isSubscription**, isActive, lastGeneratedDate?, account?, category? |
| `MerchantRule` | pattern (normalize edilmiş işyeri adı), category?. Kullanıcı bir işlemin kategorisini düzeltince otomatik öğrenilir. |
| `AIAnalysis` | createdAt, periodStart, periodEnd, model, resultJSON. Geçmiş analizleri tekrar görmek için saklanır. |

**Kritik iş kuralları:**
- **Kart borcu ödemesi = `transfer`** (banka hesabı → kart). Gider sayılmaz; aksi halde harcama iki kez sayılır.
- **Taksit:** Plan oluşturulunca `count` adet `Transaction` üretilir. Tutar `total / count`, kuruş artığı ilk taksite eklenir. i. taksitin tarihi = satın alma + i ay. Plan düzenlenirse yalnızca gelecekteki taksitler yeniden üretilir. "Erken kapat" kalan taksitleri tek işlemde birleştirir.
- **Raporlarda iki görünüm:** Varsayılan *"Aylık yük"* (taksitler aylara yayılır, ekstreyle uyumlu) ve *"Satın alma"* (taksitli alım tek tutar olarak alım ayında görünür). Raporlar ekranında bu ikisi arasında geçiş yapılır.
- **Hesap kesim:** Alım günü ≤ kesim günü ise ekstre o ay kesilir, değilse bir sonraki ay. Kesim günü ayın gün sayısını aşarsa ayın son gününe çekilir (ör. 31 → Şubat 28/29). Son ödeme = kesim + dueOffsetDays. Kart ekranında üç tutar görünür: "Dönem içi borç", "Son ekstre / ödenecek" ve "Gelecek ekstrelere düşecek taksitler".
- **Düzenli işlemler:** Uygulama öne geldiğinde `RecurringGenerator`, `lastGeneratedDate`'ten bugüne kadar kaçırılan vadeleri üretir. Maaş, kira ve abonelikler bu yolla otomatik eklenir. Fiyat değişikliği yalnızca gelecekteki işlemleri etkiler.
- **Varsayılan kategoriler / CloudKit çakışması:** Yeniden kurulumda iCloud'dan gelen verilerle varsayılanlar çift oluşmasın diye, varsayılan kategoriler onboarding'de butonla yüklenir ve her açılışta `seedKey` üzerinden tekilleştirme çalışır.
  - Gider: Market, Yemek & Kafe, Ulaşım/Yakıt, Kira, Faturalar, Abonelikler, Giyim, Sağlık, Eğitim, Eğlence, Elektronik, Ev & Yaşam, Kişisel Bakım, Hediye, Seyahat, Diğer
  - Gelir: Maaş, Burs, Ek Gelir, Freelance, Diğer · Yatırım: Yatırım. Yatırım sekmesinde "Yatırım yap" (gider sayılmaz, kalandan düşülür) ve "Yatırımı boz" (gelir sayılmaz, kalana eklenir)

---

## Ekranlar (TabView, iOS 26 Liquid Glass)

1. **Özet:** Bu ayın gelir, gider ve neti. Bütçe ilerleme çubukları, kategori donut grafiği (SectorMark), yaklaşan ödemeler (kart son ödeme günleri, abonelik yenilemeleri, bu ayın taksitleri) ve en önemli 3 tasarruf önerisi kartı.
2. **İşlemler:** Günlere göre gruplu liste, arama ve filtreler (kategori, hesap, tür, tarih aralığı). Kaydırarak düzenleme/silme.
   - **Hızlı ekle** sheet'i: büyük tutar alanı, gider/gelir/transfer seçimi, kategori ızgarası, hesap, tarih ve not.
   - Hesap kredi kartıysa **"Taksit: Tek çekim / 2…12"** seçicisi çıkar ve "aylık X ₺ × N" önizlemesi gösterilir.
3. **Raporlar:**
   - Dönem seçici: ay / 3 ay / 6 ay / yıl / özel
   - Gelir–gider aylık bar grafiği ve tasarruf oranı çizgisi
   - Kategori dağılımı, seçilen kategorinin aylara göre trendi
   - En çok harcama yapılan işyerleri
   - "Aylık yük ↔ Satın alma" görünüm geçişi
4. **Ödemeler:**
   - *Taksitler:* aktif planlar (kalan taksit, kalan tutar, bitiş ayı) ve gelecek 12 ayın taksit yükü grafiği ("Mart'ta 3 taksit bitiyor → aylık +4.200 ₺ rahatlama").
   - *Abonelikler:* liste, aylık ve yıllık toplam maliyet.
   - *Kartlar:* her kart için dönem borcu, son ödeme tarihi ve limit kullanımı.
5. **Ayarlar:** Hesaplar/kartlar (kesim günü, son ödeme ofseti), kategoriler ve bütçe limitleri, ekstre içe aktarma, AI ayarları (API anahtarı, işyeri adlarını gönderme izni), bildirim tercihleri, Face ID kilidi, CSV dışa aktarma.

---

## Özellik Detayları

### Bütçe + bildirimler (`NotificationScheduler`, yerel bildirim; sunucu yok)
- İşlem kaydedildiğinde kategori ay içinde **%80 veya %100** eşiğini geçtiyse anında bildirim gönderilir. Aynı eşik için tekrar bildirim gitmez; ay/kategori/eşik bazında `UserDefaults`'ta işaretlenir.
- Kart son ödeme günlerinden 2 gün önce saat 09:00'da hatırlatma.
- Abonelik yenilemesinden 1 gün önce hatırlatma.
- Her ayın 1'inde geçen ayın özeti.
- `BudgetEvaluator` ay sonu tahmini yapar: harcanan / geçen gün × ayın gün sayısı.

### Kural tabanlı tasarruf analizi (`SavingsAnalyzer`, çevrimdışı ve ücretsiz)
Her kural şu yapıda bir `Insight` döndürür: `severity`, `title`, `message`, `estimatedMonthlySavingMinor?`. Eşikler tek bir `InsightThresholds` dosyasında tutulur.
1. Gidişata göre bütçeyi aşacak kategoriler
2. Kategori artışı: bu ay, son 3 ay ortalamasının %25'inden ve 500 ₺'den fazla üstündeyse
3. Abonelik yükü: aylık/yıllık toplam ve aynı kategorideki mükerrer abonelikler (ör. iki müzik servisi)
4. Taksit yükü: gelecek ayın taksitleri ortalama gelirin %25'ini aşıyorsa uyarı, ayrıca hangi ay ne kadar rahatlama olacağı
5. Sık küçük harcamalar: ayda 10'dan fazla, tanesi 300 ₺ altı (kafe, yemek uygulaması vb.) → aylık toplam ve yıllık projeksiyon
6. Tasarruf oranı: (gelir − gider) / gelir. Hedef %20, altındaysa uyarı.

### AI tasarruf analizi (`GeminiAdvisor`, Google Gemini)
- URLSession ile `POST https://generativelanguage.googleapis.com/v1beta/models/{model}:generateContent`.
  - Başlıklar: `x-goog-api-key` (anahtar URL'de değil), `X-Ios-Bundle-Identifier: com.furkanfuat.economix`.
- Gövde: `systemInstruction`, `contents` (özet JSON), `generationConfig { responseMimeType: application/json, responseJsonSchema, maxOutputTokens }`. (Belgedeki `responseFormat.text.mimeType` biçimi canlı API'de 400 verdiği için kullanılmıyor.)
- Model: `gemini-3.8-flash` varsayılan, `gemini-4-argon` seçilebilir (Ayarlar).
- Yanıt: `candidates[0].content.parts` (düşünce parçaları atlanır, kod bloğu ayıklanır); `promptFeedback.blockReason` ve `finishReason` (SAFETY vb. → engellendi, MAX_TOKENS → kesildi) içerikten önce kontrol edilir.
- Anahtar: yalnızca uygulamada girilen (Keychain, bu cihaz). Uygulama paketine gömülmez; `Config/Secrets.xcconfig` içindeki değer yalnızca `make gemini-live` ve `scripts/check-gemini.sh` içindir.
- Gönderilen veri ve tetikleme kuralları değişmedi (yalnızca toplulaştırılmış veri, yalnızca düğmeyle).

### Ekstre içe aktarma (`StatementParser` + `ImportService`)
1. Dosyalar uygulamasından `.csv` veya `.xlsx` seçilir. Eski `.xls` gelirse "Numbers'ta açıp CSV/XLSX olarak dışa aktar" yönlendirmesi gösterilir.
2. İlk 30 satırda başlık satırı aranır ("Tarih", "İşlem Tarihi", "Açıklama", "Tutar" vb.). Banka profili (Garanti / Yapı Kredi / Akbank) otomatik tahmin edilir.
3. Profil şunları belirler: kolon eşlemesi, tarih formatı (`dd.MM.yyyy` / `dd/MM/yyyy`), tutar parse kuralı ("1.234,56", eksi/artı işareti, ayrı borç/alacak kolonları), taksit tespiti ("Taksit 3/6" kolonu ya da açıklamadaki `(\d+)/(\d+)` kalıbı), atlanacak satırlar (puan/bonus kazanımı, devreden bakiye, ara toplamlar).
4. **Önizleme ekranı:**
   - Her satır için önerilen kategori gelir: önce `MerchantRule`, sonra yerleşik anahtar kelime sözlüğü (MİGROS, A101, BİM, ŞOK → Market; OPET, SHELL → Yakıt; NETFLIX, SPOTIFY → Abonelik; YEMEKSEPETİ, GETİR → Yemek…).
   - **Mükerrer** satırlar işaretlenir: `importHash` (tarih + tutar + normalize açıklama) eşleşmesi, ya da aynı tutarla ±2 gün içindeki elle girilmiş işlem.
   - Taksit satırları: eşleşen bir plan varsa ona bağlanır, yoksa "Taksit planı oluştur" seçeneği çıkar ve kalan taksitler ileriye üretilir.
5. Onaylanınca işlemler eklenir.
- **Fallback:** Profil tutmazsa "Elle eşle" ekranında kolonlar seçilir ve özel profil olarak kaydedilir.
- **Gereken girdi:** Profilleri kesinleştirmek için her bankadan bir **örnek ekstre** (CSV/XLSX, isim ve kart numarası maskelenmiş olabilir) gerekiyor. Bunlar anonimleştirilip test fixture'ı yapılacak. Faz 6'ya gelince kullanıcıdan istenecek.

### Diğer
- **Face ID kilidi** (`LocalAuthentication`): İsteğe bağlı. Uygulama arka plana geçince ekran bulanıklaşır.
- **CSV dışa aktarma**: Tüm işlemler `ShareLink` ile Excel'e veya Dosyalar'a aktarılır. iCloud yedeğinin yanında ikinci bir güvence.
- **DEBUG demo verisi**: `-demoData` launch argümanıyla 12 aylık gerçekçi sahte veri yüklenir. Grafikleri simülatörde görsel olarak doğrulamak için kullanılır.

---

## Uygulama Fazları (her faz kendi içinde doğrulanır)

| Faz | İçerik | Doğrulama |
|---|---|---|
| 0 | `git init`, spec'i `docs/`'a kopyala, `project.yml`, Core paketi, boş app iskeleti, `.gitignore` | `xcodegen generate` + simülatörde boş uygulama açılıyor |
| 1 | Core (TDD): Money, StatementCycle, InstallmentScheduler, RecurrenceEngine, ReportBuilder, BudgetEvaluator | `swift test` yeşil. Ay sonu, şubat, 31 çekme, kuruş artığı gibi kenar durumlar test edilmiş |
| 2 | SwiftData modelleri, CloudKit container, seed/tekilleştirme, hesaplar, kategoriler, Hızlı Ekle, İşlemler listesi/filtre | In-memory container entegrasyon testleri ve simülatör ekran görüntüsü |
| 3 | Taksit planları, kart kesim ekranı, abonelikler, RecurringGenerator → Ödemeler sekmesi | Taksitli alım → 6 ayın listesi doğru. Kaçırılan abonelik vadeleri üretiliyor |
| 4 | Özet ve Raporlar (Swift Charts), iki görünüm modu | Demo veriyle ekran görüntüleri, toplamlar Core testleriyle tutarlı |
| 5 | Bütçe limitleri, bildirimler (eşik, son ödeme, abonelik, aylık özet) | Simülatörde eşik geçince bildirim düşüyor |
| 6 | Ekstre içe aktarma (3 banka profili + elle eşleme) | Kullanıcının örnek ekstreleriyle fixture testleri ve önizleme ekranı |
| 7 | SavingsAnalyzer (kurallar) ve AIAdvisor | Kural testleri. Kullanıcı onayıyla tek bir gerçek API çağrısı |
| 8 | Face ID, CSV dışa aktarma, iPhone'a kurulum | Cihazda çalışıyor, CloudKit Console'da (Development) kayıtlar görünüyor |

---

## Doğrulama (uçtan uca)

- **Birim testleri:** `cd Packages/EconomixCore && swift test`
- **Derleme ve testler:**
  - `xcodegen generate`
  - `xcodebuild -scheme Economix -destination 'platform=iOS Simulator,name=<iPhone 17 vb., simctl list ile seçilecek>' build test`
- **Görsel kontrol:** `xcrun simctl install/launch` (`-demoData` ile) ve `xcrun simctl io booted screenshot`. Ekran görüntüleri incelenerek her sekme kontrol edilir.
- **Cihaz:**
  - iPhone kabloyla bağlanır, Ayarlar > Gizlilik ve Güvenlik > Geliştirici Modu açılır.
  - Kurulum: `xcodebuild -destination 'platform=iOS,id=<udid>' -allowProvisioningUpdates` (takım kimliği `Config/Secrets.xcconfig` > `DEVELOPMENT_TEAM`)
  - İlk seferde iCloud container'ın Xcode'da oluşturulması için bir kez Signing & Capabilities ekranının açılması gerekebilir.
- **iCloud:** Doğrudan Xcode'dan kurulan sürüm CloudKit **Development** ortamını kullanır. İleride TestFlight'a geçilirse şemanın CloudKit Console'da Production'a deploy edilmesi gerekir; bu not README'ye yazılacak.

## Kapsam dışı (v1)
Widget, Siri/Kestirmeler, çoklu para birimi, yatırım/portföy takibi, banka kredisi, kişisel borç/alacak, PDF ekstre okuma. Mimari bunların sonradan eklenmesine engel değil.
