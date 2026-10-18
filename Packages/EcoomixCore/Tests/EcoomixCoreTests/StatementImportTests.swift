import Foundation
import Testing
@testable import EcoomixCore

@Suite("CSV okuma")
struct CSVReaderTests {
    @Test("Noktalı virgül, tırnak içi ayraç, BOM ve CRLF")
    func semicolon() {
        let text = "\u{FEFF}Tarih;Açıklama;Tutar\r\n01.10.2026;\"MIGROS; KADIKOY\";1.234,56\r\n"
        #expect(CSVReader.rows(from: text) == [["Tarih", "Açıklama", "Tutar"], ["01.10.2026", "MIGROS; KADIKOY", "1.234,56"]])
    }

    @Test("Virgül ayracı otomatik bulunur, çift tırnak kaçışı çözülür")
    func comma() {
        let text = "Date,Description,Amount\n2026-10-01,\"Ali \"\"Usta\"\" Kebap\",250.00\n"
        #expect(CSVReader.rows(from: text)[1] == ["2026-10-01", "Ali \"Usta\" Kebap", "250.00"])
    }

    @Test("Sekme ayracı")
    func tab() {
        #expect(CSVReader.rows(from: "a\tb\n1\t2")[1] == ["1", "2"])
    }
}

@Suite("Ekstre çözümleme")
struct StatementParserTests {
    /// Kart ekstresi: başta banka bilgileri, harcamalar pozitif, ödeme/iade negatif, bonus kolonu var.
    let cardRows: [[String]] = [
        ["Garanti BBVA Bonus Kart Ekstresi"],
        ["Kart No", "5400 **** **** 1234"],
        [],
        ["Tarih", "İşlem", "Etiket", "Bonus", "Tutar(TL)"],
        ["01.10.2026", "MIGROS KADIKOY ISTANBUL", "Market", "3,20", "1.234,56"],
        ["03.10.2026", "TEKNOSA TAKSIT 3/6", "Elektronik", "0", "2.000,00"],
        ["05.10.2026", "ÖDEMENİZ İÇİN TEŞEKKÜR EDERİZ", "", "", "-5.000,00"],
        ["07.10.2026", "ZARA IADE", "", "", "-299,90"],
        ["", "ÖNCEKİ DÖNEM BORCU", "", "", "4.000,00"],
        ["", "TOPLAM", "", "", "3.234,56"],
    ]

    @Test("Başlık satırı önsözün ardından bulunur, kolonlar eşlenir")
    func header() throws {
        let detected = try #require(StatementParser.detectColumns(in: cardRows))
        #expect(detected.headerIndex == 3)
        #expect(detected.map.date == 0)
        #expect(detected.map.description == 1)
        #expect(detected.map.amount == 4)
    }

    @Test("Harcama, taksit, ödeme ve iade satırları ayrılır; özet satırları atlanır")
    func parsesCardStatement() throws {
        let result = try StatementParser.parse(rows: cardRows, profile: .generic)
        #expect(result.rows.count == 4)
        let migros = result.rows[0]
        #expect(migros.date == d(2026, 10, 1))
        #expect(migros.amount == Money(minor: 123_456))
        #expect(migros.kind == .expense)
        #expect(result.rows[1].installment == InstallmentMarker(current: 3, total: 6))
        #expect(result.rows[2].kind == .payment)
        #expect(result.rows[2].amount == tl(5_000))
        #expect(result.rows[3].kind == .refund)
        #expect(result.skippedCount == 2)
    }

    @Test("Ayrı taksit kolonu okunur")
    func installmentColumn() throws {
        let rows = [["İşlem Tarihi", "Açıklama", "Taksit", "Tutar"],
                    ["02/10/2026", "VATAN BILGISAYAR", "2/12", "1.500,00"]]
        let result = try StatementParser.parse(rows: rows, profile: .generic)
        #expect(result.rows[0].installment == InstallmentMarker(current: 2, total: 12))
        #expect(result.rows[0].date == d(2026, 10, 2))
    }

    @Test("Borç/Alacak kolonlu banka hesabı dökümü: borç gider, alacak gelir")
    func debitCredit() throws {
        let rows = [["Tarih", "Açıklama", "Borç", "Alacak", "Bakiye"],
                    ["01.10.2026", "MAAS ODEMESI", "", "62.000,00", "70.000,00"],
                    ["05.10.2026", "KIRA", "18.000,00", "", "52.000,00"]]
        let result = try StatementParser.parse(rows: rows, profile: .generic)
        #expect(result.rows.map(\.kind) == [.income, .expense])
        #expect(result.rows.map(\.amount) == [tl(62_000), tl(18_000)])
    }

    @Test("Banka hesabında giderler negatifse işaret otomatik algılanır")
    func negativeExpenses() throws {
        let rows = [["Tarih", "Açıklama", "Tutar"],
                    ["01.10.2026", "A101", "-150,00"],
                    ["02.10.2026", "BIM", "-80,00"],
                    ["03.10.2026", "HAVALE GELEN", "1.000,00"]]
        let result = try StatementParser.parse(rows: rows, profile: .generic)
        #expect(result.rows.map(\.kind) == [.expense, .expense, .income])
    }

    @Test("Alacak satırları çoğunlukta olsa da ödeme/iade ifadesi kart ekstresi olduğunu gösterir")
    func cardWithMostlyCredits() throws {
        let rows = [["Tarih", "Açıklama", "Tutar"],
                    ["01.10.2026", "MIGROS", "300,00"],
                    ["05.10.2026", "ODEMENIZ ICIN TESEKKURLER", "-5.000,00"],
                    ["07.10.2026", "ZARA IADE", "-299,90"]]
        let result = try StatementParser.parse(rows: rows, profile: .generic)
        #expect(result.expensesArePositive)
        #expect(result.rows.map(\.kind) == [.expense, .payment, .refund])
    }

    @Test("Hesap türünden gelen işaret ipucu, eşit sayıda artı/eksi satırda tahminin önüne geçer")
    func expenseSignHint() throws {
        let rows = [["Tarih", "Açıklama", "Tutar"],
                    ["07.10.2026", "BIM MAGAZALARI", "-320,00"],
                    ["08.10.2026", "HAVALE GELEN", "1.000,00"]]
        let auto = try StatementParser.parse(rows: rows, profile: .generic)
        #expect(auto.rows.map(\.kind) == [.refund, .expense])
        let hinted = try StatementParser.parse(rows: rows, profile: .generic, expenseSign: .negative)
        #expect(!hinted.expensesArePositive)
        #expect(hinted.rows.map(\.kind) == [.expense, .income])
    }

    @Test("Başlık bulunamazsa elle eşleme için hata")
    func noHeader() {
        #expect(throws: StatementParser.ParseError.headerNotFound) {
            try StatementParser.parse(rows: [["x", "y"], ["1", "2"]], profile: .generic)
        }
    }

    @Test("Elle verilen kolon eşlemesiyle çözümleme")
    func manualMapping() throws {
        let rows = [["01.10.2026", "MIGROS", "100,00"]]
        let map = ColumnMap(date: 0, description: 1, amount: 2)
        let result = try StatementParser.parse(rows: rows, profile: .generic, columns: (headerIndex: -1, map: map))
        #expect(result.rows.first?.amount == tl(100))
    }

    @Test("Tarih biçimleri ve Excel seri numarası", arguments: [
        ("01.10.2026", d(2026, 10, 1)), ("1.10.2026", d(2026, 10, 1)), ("01/10/2026", d(2026, 10, 1)),
        ("2026-10-01", d(2026, 10, 1)), ("01.10.26", d(2026, 10, 1)), ("46296", d(2026, 10, 1)),
    ])
    func dates(text: String, expected: Date) {
        #expect(StatementParser.parseDate(text) == expected)
    }

    @Test("Taksit işaretleri açıklamadan çıkarılır", arguments: [
        ("TEKNOSA TAKSIT 3/6", InstallmentMarker(current: 3, total: 6)),
        ("APPLE STORE (2/12)", InstallmentMarker(current: 2, total: 12)),
        ("MEDIAMARKT 4/9 TK", InstallmentMarker(current: 4, total: 9)),
        ("Taksitli işlem 1/3", InstallmentMarker(current: 1, total: 3)),
    ])
    func installmentMarkers(text: String, expected: InstallmentMarker) {
        #expect(StatementParser.installmentMarker(in: text) == expected)
    }

    @Test("Tarih benzeri sayılar taksit sanılmaz", arguments: ["MIGROS 12/10/2026", "KAPI NO 5/1", "A101 7/45"])
    func notInstallment(text: String) {
        #expect(StatementParser.installmentMarker(in: text) == nil)
    }

    @Test("Tekrar kontrol hash'i büyük/küçük harf ve boşluktan bağımsız")
    func hash() {
        let a = StatementParser.importHash(date: d(2026, 10, 1), amount: tl(100), description: "Migros  Kadıköy")
        let b = StatementParser.importHash(date: d(2026, 10, 1), amount: tl(100), description: "MIGROS KADIKOY")
        #expect(a == b)
        #expect(a != StatementParser.importHash(date: d(2026, 10, 2), amount: tl(100), description: "MIGROS KADIKOY"))
    }

    @Test("Banka dosya adından ya da içerikten tahmin edilir")
    func detectsBank() {
        #expect(BankProfile.detect(fileName: "bonus_ekstre_ekim.csv", rows: []).id == "garanti")
        #expect(BankProfile.detect(fileName: "ekstre.xlsx", rows: [["YAPI KREDİ WORLD"]]).id == "yapikredi")
        #expect(BankProfile.detect(fileName: "Axess-hareketler.xlsx", rows: []).id == "akbank")
        #expect(BankProfile.detect(fileName: "x.csv", rows: [["foo"]]).id == "generic")
    }
}

@Suite("İşyeri kategorisi tahmini")
struct MerchantCategorizerTests {
    @Test("Bilinen işyerleri varsayılan kategorilere eşlenir", arguments: [
        ("MIGROS KADIKOY ISTANBUL", "market"),
        ("ŞOK MARKET 1234", "market"),
        ("NETFLIX.COM", "abonelik"),
        ("OPET PETROLCULUK", "ulasim"),
        ("TRENDYOL YEMEK", "yemek"),
        ("ENERJISA ISTANBUL", "fatura"),
        ("PEGASUS HAVA", "seyahat"),
        ("ECZANE AYDIN", "saglik"),
    ])
    func known(merchant: String, key: String) {
        #expect(MerchantCategorizer.suggestedSeedKey(for: merchant) == key)
    }

    @Test("Belirsiz işyeri tahmin edilmez")
    func unknown() {
        #expect(MerchantCategorizer.suggestedSeedKey(for: "TRENDYOL") == nil)
        #expect(MerchantCategorizer.suggestedSeedKey(for: "ABC LTD STI") == nil)
    }
}

@Suite("Marka anahtarı")
struct BrandKeyTests {
    @Test("Şube, şehir, şirket eki ve ödeme aracısı ayıklanır", arguments: [
        ("MIGROS SANAL MARKET ISTANBUL TR", "MIGROS"),
        ("Migros Kadıköy", "MIGROS"),
        ("IYZICO/TRENDYOL", "TRENDYOL"),
        ("PAYPAL *STEAM GAMES", "STEAM"),
        ("A101 MAGAZALARI 1234", "A101"),
        ("YEMEKSEPETI.COM", "YEMEKSEPETI"),
        ("ŞOK MARKETLER TİC. A.Ş.", "SOK"),
        ("PAYTR*ABC TEKSTIL LTD STI", "ABC TEKSTIL"),
    ])
    func brandKey(text: String, expected: String) {
        #expect(MerchantNormalizer.brandKey(text) == expected)
    }

    @Test("Boş ya da yalnızca ek içeren metin boş anahtar verir")
    func empty() {
        #expect(MerchantNormalizer.brandKey("  ") == "")
        #expect(MerchantNormalizer.brandKey("LTD STI") == "")
    }
}

@Suite("Genişletilmiş kategori sözlüğü")
struct ExtendedCategorizerTests {
    @Test("Genel kelime kökleri tanınır", arguments: [
        ("AYDIN PASTANESI", "yemek"),
        ("KASAP ALI", "market"),
        ("YILDIZ MANAV", "market"),
        ("ABC TEKSTIL LTD STI", "giyim"),
        ("OZ KIRTASIYE", "egitim"),
        ("MERKEZ OTOPARKI", "ulasim"),
        ("SELIN KUAFOR", "bakim"),
        ("CINAR ECZANESI", "saglik"),
        ("GUNES MOBILYA", "ev"),
        ("ILHAN FIRINI", "yemek"),
        ("abc_kadikoy_yemek", "yemek"),
        ("AYSE TEYZE EV YEMEKLERI", "yemek"),
    ])
    func genericStems(text: String, key: String) {
        #expect(MerchantCategorizer.suggestedSeedKey(for: text) == key)
    }

    @Test("Yaygın zincirler", arguments: [
        ("FILE MARKET", "market"), ("HAKMAR EXPRESS", "market"), ("GETIR", "market"),
        ("POPEYES ATASEHIR", "yemek"), ("SIMIT SARAYI", "yemek"), ("TAVUK DUNYASI", "yemek"),
        ("PETROL OFISI", "ulasim"), ("BITAKSI", "ulasim"), ("TURKCELL FATURA", "fatura"),
        ("WATSONS", "bakim"), ("GRATIS", "bakim"), ("DECATHLON", "giyim"), ("KOCTAS", "ev"),
        ("TEKNOSA", "elektronik"), ("PEGASUS", "seyahat"), ("BILETIX", "eglence"),
    ])
    func chains(text: String, key: String) {
        #expect(MerchantCategorizer.suggestedSeedKey(for: text) == key)
    }

    @Test("Taksit yazısı taksi sanılmaz", arguments: [
        ("HEPSIPAY/HEPSIBU (1,500.00 TL) 3/3.taksit", nil),
        ("HEPSIBURADA TAKSITLI SATIS", nil),
        ("SARI TAKSI", "ulasim"),
        ("TAKSICI MEHMET", "ulasim"),
    ] as [(String, String?)])
    func installmentIsNotTaxi(text: String, key: String?) {
        #expect(MerchantCategorizer.suggestedSeedKey(for: text) == key)
    }

    @Test("Belirsiz pazaryerleri hâlâ tahmin edilmez", arguments: ["TRENDYOL", "HEPSIBURADA", "AMAZON", "N11"])
    func ambiguous(text: String) {
        #expect(MerchantCategorizer.suggestedSeedKey(for: text) == nil)
    }
}
