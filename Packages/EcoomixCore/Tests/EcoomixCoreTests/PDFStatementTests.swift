import CoreGraphics
import CoreText
import Foundation
import Testing
@testable import EcoomixCore

/// Metni verilen konumlara çizen test PDF'i. Sütunlar ayrı ayrı çizildiği için PDF'in metin sırası satır sırası değildir.
private func makePDF(_ items: [(String, CGFloat, CGFloat)]) -> Data {
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
}
