import CoreGraphics
import CoreText
import Foundation
import Testing
@testable import EconomixCore

/// Metni verilen konumlara çizen test PDF'i. Sütunlar ayrı ayrı çizildiği için PDF'in metin sırası satır sırası değildir.
func makePDF(_ items: [(String, CGFloat, CGFloat)]) -> Data {
    let data = NSMutableData()
    var box = CGRect(x: 0, y: 0, width: 595, height: 842)
    let context = CGContext(consumer: CGDataConsumer(data: data as CFMutableData)!, mediaBox: &box, nil)!
    context.beginPDFPage(nil)
    let font = CTFontCreateWithName("Helvetica" as CFString, 10, nil)
    for (text, x, y) in items {
        let attributed = NSAttributedString(string: text, attributes: [.init(kCTFontAttributeName as String): font])
        context.textPosition = CGPoint(x: x, y: y)
        CTLineDraw(CTLineCreateWithAttributedString(attributed), context)
    }
    context.endPDFPage()
    context.closePDF()
    return data as Data
}

@Suite("PDF ekstre")
struct PDFStatementTests {
    @Test("Sütun sütun yazılmış PDF'te satırlar konuma göre yeniden kurulur")
    func rebuildsVisualLines() throws {
        let pdf = makePDF([
            ("Garanti BBVA Bonus Ekstre", 40, 800),
            // Önce tarih sütunu, sonra açıklamalar, sonra tutarlar
            ("02.10.2026", 40, 700), ("06.10.2026", 40, 680),
            ("MIGROS SANAL MARKET", 120, 700), ("VATAN BILGISAYAR", 120, 680),
            ("2/6", 330, 680),
            ("1.234,56", 480, 700), ("2.500,00", 480, 680),
        ])
        let lines = try PDFTextReader.lines(from: pdf)
        #expect(lines.contains("02.10.2026 MIGROS SANAL MARKET 1.234,56"))
        #expect(lines.contains("06.10.2026 VATAN BILGISAYAR 2/6 2.500,00"))
        #expect(lines.first == "Garanti BBVA Bonus Ekstre")
    }

    @Test("PDF olmayan veri hata verir")
    func rejectsGarbage() {
        #expect(throws: PDFTextReader.ReadError.self) { try PDFTextReader.lines(from: Data("merhaba".utf8)) }
    }

    @Test("İşlem satırları tarih, açıklama, taksit ve tutar kolonlarına ayrılır")
    func rowsFromLines() {
        let rows = PDFStatementLines.rows(from: [
            "Hesap Kesim Tarihi: 15.10.2026",
            "Dönem: 16.09.2026 - 15.10.2026",
            "02.10.2026 MIGROS SANAL MARKET ISTANBUL 3,20 1.234,56",
            "03/10/2026 03/10/2026 STARBUCKS NISANTASI 185,00 TL",
            "06.10.2026 VATAN BILGISAYAR 2/6 2.500,00",
            "12.10.2026 ÖDEMENİZ İÇİN TEŞEKKÜR EDERİZ - 5.000,00",
            "14 Eki 2026 ZARA IADE 299,90-",
            "Önceki dönem borcu 4.000,00",
            "02.10.2026 sadece tarih var",
        ])
        #expect(rows.first == ["Tarih", "Açıklama", "Taksit", "Tutar"])
        #expect(Array(rows.dropFirst()) == [
            ["02.10.2026", "MIGROS SANAL MARKET ISTANBUL", "", "1.234,56"],
            ["03.10.2026", "STARBUCKS NISANTASI", "", "185,00"],
            ["06.10.2026", "VATAN BILGISAYAR", "2/6", "2.500,00"],
            ["12.10.2026", "ÖDEMENİZ İÇİN TEŞEKKÜR EDERİZ", "", "-5.000,00"],
            ["14.10.2026", "ZARA IADE", "", "299,90-"],
        ])
    }

    @Test("PDF satırları mevcut çözümleyiciyle kart ekstresine dönüşür")
    func endToEnd() throws {
        let rows = PDFStatementLines.rows(from: [
            "02.10.2026 MIGROS SANAL MARKET 1.234,56",
            "06.10.2026 VATAN BILGISAYAR 2/6 2.500,00",
            "12.10.2026 ÖDEMENİZ İÇİN TEŞEKKÜR EDERİZ -5.000,00",
        ])
        let result = try StatementParser.parse(rows: rows, profile: .generic,
                                               columns: (headerIndex: 0, map: PDFStatementLines.columns))
        #expect(result.rows.map(\.kind) == [.expense, .expense, .payment])
        #expect(result.rows[1].installment == InstallmentMarker(current: 2, total: 6))
        #expect(result.rows[0].amount == Money(minor: 123_456))
    }

    @Test("Yazıyla ay adı içeren tarihler", arguments: [
        ("02 Ekim 2026", d(2026, 10, 2)), ("2 Eki 2026", d(2026, 10, 2)), ("02 EKİM 2026", d(2026, 10, 2)),
        ("15 Şubat 2027", d(2027, 2, 15)), ("1 Ağu 26", d(2026, 8, 1)),
    ])
    func turkishMonthDates(text: String, expected: Date) {
        #expect(StatementParser.parseDate(text) == expected)
    }

    @Test("Biçim örneği: rakamlar 9, harfler X olur; başlık kelimeleri ve ay adları korunur")
    func maskedStructure() {
        let masked = StatementStructure.masked(lines: [
            "02.10.2026 MIGROS Sanal 1.234,56 TL",
            "İşlem Tarihi Açıklama Taksit Tutar",
            "14 Eki 2026 ZARA IADE 299,90-",
        ])
        #expect(masked == [
            "99.99.9999 XXXXXX Xxxxx 9.999,99 TL",
            "İşlem Tarihi Açıklama Taksit Tutar",
            "99 Eki 9999 XXXX IADE 999,99-",
        ])
    }

    @Test("Biçim örneği: başlık kelimesine bitişik tutar, IBAN, kart no ve yer adları da gizlenir")
    func maskedStructureHidesAttachedValues() {
        let masked = StatementStructure.masked(lines: [
            "TUTAR:1.234,56 TOPLAM:12.345,67TL",
            "HESAP:TR330006100519786457841326",
            "KARTNO:5401231234561234",
            "ISLEM 15/10/2026 KARTAL OCAKBASI KASIMPASA",
            "İşlem Tarihi Taksitli Ödemeleri TOPLAMLARI",
        ])
        #expect(masked == [
            "TUTAR:9.999,99 TOPLAM:99.999,99TL",
            "HESAP:XX999999999999999999999999",
            "XXXXXX:9999999999999999",
            "ISLEM 99/99/9999 XXXXXX XXXXXXXX XXXXXXXXX",
            "İşlem Tarihi Taksitli Ödemeleri TOPLAMLARI",
        ])
    }
}

@Suite("Akbank Axess PDF düzeni")
struct AkbankLayoutTests {
    let lines = [
        "Hesap Kesim Tarihi 18/09/2026",
        "İşlem Tarihi Dönem içi işlemler Borç Tutarı (TL) Kalan Borç / Taksit Chip-para",
        "Önceki Dönem Hesap Özeti Bakiyesi 1,500.00",
        "02/09/2026 AKBANK Internet Subesi Odeme Tesekkurler 5,000.00(-)",
        "03/09/2026 abc_kadikoy_yemek 245.50",
        "05/09/2026 TEKNOSA/teknosa.com.tr (2,970.00 TL) 3/2.taksit 990.00 990.00x1",
        "06/09/2026 APPLE STORE/ISTANBUL (12,000.00 TL) 12/1.taksit 1,000.00 11000.00x11",
        "10/09/2026 MIGROS -Kullanilan chip-para 25.00()",
        "12/09/2026 MIGROS/ISTANBUL 1,234.56",
        "Genel Toplam 3,000.00 12,345.67 0.00",
    ]

    @Test("Satırlar kolonlara ayrılır: İngiliz usulü tutar, (-) alacak, kalan taksit kolonu atılır")
    func rows() {
        let rows = Array(PDFStatementLines.rows(from: lines).dropFirst())
        #expect(rows == [
            ["02.09.2026", "AKBANK Internet Subesi Odeme Tesekkurler", "", "-5,000.00"],
            ["03.09.2026", "abc_kadikoy_yemek", "", "245.50"],
            ["05.09.2026", "TEKNOSA/teknosa.com.tr (2,970.00 TL) 3/2.taksit", "", "990.00"],
            ["06.09.2026", "APPLE STORE/ISTANBUL (12,000.00 TL) 12/1.taksit", "", "1,000.00"],
            ["10.09.2026", "MIGROS -Kullanilan chip-para", "", "-25.00"],
            ["12.09.2026", "MIGROS/ISTANBUL", "", "1,234.56"],
        ])
    }

    @Test("Uçtan uca: ödeme, chip-para, harcama ve toplam/kaçıncı sıralı taksitler")
    func endToEnd() throws {
        let result = try StatementParser.parse(rows: PDFStatementLines.rows(from: lines), profile: .akbank,
                                               columns: (headerIndex: 0, map: PDFStatementLines.columns))
        #expect(result.rows.map(\.kind) == [.payment, .expense, .expense, .expense, .reward, .expense])
        #expect(result.rows[0].amount == tl(5_000))
        #expect(result.rows[2].installment == InstallmentMarker(current: 2, total: 3))
        #expect(result.rows[2].amount == Money(minor: 99_000))
        #expect(result.rows[3].installment == InstallmentMarker(current: 1, total: 12))
        #expect(result.rows[5].amount == Money(minor: 123_456))
    }

    @Test("Taksit yazımları", arguments: [
        ("TEKNOSA (2,970.00 TL) 3/2.taksit", InstallmentMarker(current: 2, total: 3)),
        ("APPLE (12,000.00 TL) 12/1.taksit", InstallmentMarker(current: 1, total: 12)),
        ("X 3/3.taksit", InstallmentMarker(current: 3, total: 3)),
        ("MEDIAMARKT 4/9 TK", InstallmentMarker(current: 4, total: 9)),
    ])
    func installmentStyles(text: String, expected: InstallmentMarker) {
        #expect(StatementParser.installmentMarker(in: text) == expected)
    }
}

@Suite("Ödül ve bonus satırları")
struct RewardRowTests {
    @Test("Kampanya ödülü, bonus, puan ve chip-para alacakları ödül sayılır; iade ve ödeme ayrı kalır")
    func rewards() throws {
        let rows = [["Tarih", "Açıklama", "Tutar"],
                    ["01.09.2026", "MIGROS", "500,00"],
                    ["02.09.2026", "İLK HARCAMANIZA 100 TL ÖDÜL", "-100,00"],
                    ["03.09.2026", "MIGROS -Kullanılan chip-para", "-25,00"],
                    ["04.09.2026", "BONUS FLAŞ KAMPANYASI", "-30,00"],
                    ["05.09.2026", "ZARA IADE", "-299,90"],
                    ["06.09.2026", "ÖDEMENİZ İÇİN TEŞEKKÜR EDERİZ", "-5.000,00"],
                    ["07.09.2026", "WORLDPUAN KAZANIM", "-12,00"],
                    ["08.09.2026", "HOŞGELDİN HEDİYESİ", "-50,00"],
                    ["09.09.2026", "BOYNER", "-80,00"]]
        let result = try StatementParser.parse(rows: rows, profile: .generic)
        #expect(result.rows.map(\.kind) == [.expense, .reward, .reward, .reward, .refund, .payment, .reward, .reward, .refund])
    }

    @Test("İşaretsiz yazılan chip-para kazanımı da ödüldür; adında bonus/hediye geçen gerçek alışveriş harcama kalır")
    func positiveRewards() throws {
        let rows = [["Tarih", "Açıklama", "Tutar"],
                    ["01.09.2026", "ODEMENIZ ICIN TESEKKURLER", "-1.000,00"],
                    ["02.09.2026", "ilk_harcamaya_ödül", "150,00"],
                    ["03.09.2026", "AXESS CHIP-PARA KAZANIMI", "12,00"],
                    ["04.09.2026", "HEDIYE DUNYASI", "80,00"],
                    ["05.09.2026", "BONUS MARKET", "45,00"],
                    ["06.09.2026", "KAMPANYA OUTLET", "60,00"]]
        let result = try StatementParser.parse(rows: rows, profile: .generic)
        #expect(result.rows.map(\.kind) == [.payment, .reward, .reward, .expense, .expense, .expense])
    }
}

