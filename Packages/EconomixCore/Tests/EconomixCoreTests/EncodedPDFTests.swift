import Foundation
import Testing
@testable import EconomixCore

/// ASCII çizimden harf resmi: "#" mürekkep. `baselineRow`: taban çizgisinin hemen üstündeki satır (0 = en üst).
func glyph(_ rows: [String], baselineRow: Int? = nil) -> GlyphBitmap {
    let width = rows.map(\.count).max() ?? 0
    let bytesPerRow = (width + 7) / 8
    var bits = [UInt8](repeating: 0, count: bytesPerRow * rows.count)
    for (y, row) in rows.enumerated() {
        for (x, char) in row.enumerated() where char == "#" {
            bits[y * bytesPerRow + x / 8] |= 0x80 >> UInt8(x % 8)
        }
    }
    let baseline = baselineRow ?? rows.count - 1
    return GlyphBitmap(width: width, height: rows.count, offsetX: 0, offsetY: baseline + 1 - rows.count, bits: bits)
}

private func box(width: Int, height: Int) -> [String] {
    (0..<height).map { y in
        String((0..<width).map { x in y == 0 || y == height - 1 || x == 0 || x == width - 1 ? "#" : "." })
    }
}

private func stem(_ height: Int, width: Int = 3) -> [String] { Array(repeating: String(repeating: "#", count: width), count: height) }
private let gap = ["...", "..."]

/// Akbank'ın ana bilgisayar çıktısını taklit eden PDF: Type3 bitmap yazı tipleri, EBCDIC kodlar, Unicode tablosu yok.
/// Türkçe harfler ayrı bir yazı tipinde, belgeye özel sırayla atanmış kodlarda durur. Her parça mutlak konumla yazılır.
enum EncodedPDFFixture {
    static let unit = 0.3  // 1 harf birimi = 0,3 pt (yazı tipi boyu 0,3, FontMatrix birim)

    static func make(_ pieces: [(text: String, x: Double, y: Double)]) -> Data {
        var base = Font(name: "C0000002_7")
        var turkish = Font(name: "C0000020_3")
        turkish.add(0x01, glyph(["........"]), advance: 0)
        let reverse = Dictionary(EBCDIC.table.enumerated().map { ($0.element, UInt8($0.offset)) }, uniquingKeysWith: { a, _ in a })

        var content = "BT\n"
        for piece in pieces {
            var x = piece.x
            var run: (font: String, codes: [UInt8], x: Double)?
            func flush() {
                guard let current = run, !current.codes.isEmpty else { return }
                let hex = current.codes.map { String(format: "%02X", $0) }.joined()
                content += String(format: "/%@ %.2f Tf 100.00 Tz 1 0 0 1 0 0 Tm %.3f %.3f Td [<%@>] TJ\n",
                                  current.font, unit, current.x, piece.y, hex)
                run = nil
            }
            for char in piece.text {
                let fontName: String, code: UInt8, advance: Double
                if char == "\u{200B}" {
                    // Akbank'taki gibi Türkçe yazı tipinin boş harfi, sıfır genişlikte
                    if run?.font != turkish.name { flush(); run = (turkish.name, [], x) }
                    run!.codes.append(0x01)
                    continue
                }
                if let shape = turkishShape(char) {
                    let assigned = turkish.code(for: char) ?? turkish.add(nil, shape, advance: Double(shape.width + 2))
                    turkish.chars[assigned] = char
                    (fontName, code, advance) = (turkish.name, assigned, turkish.advances[assigned]!)
                } else {
                    let ebcdic = reverse[char]!
                    if base.advances[ebcdic] == nil {
                        let bitmap = latinShape(char)
                        base.add(ebcdic, bitmap, advance: char == " " ? 10 : Double(bitmap.width + 2))
                    }
                    (fontName, code, advance) = (base.name, ebcdic, base.advances[ebcdic]!)
                }
                if run?.font != fontName { flush(); run = (fontName, [], x) }
                run!.codes.append(code)
                x += advance * unit
            }
            flush()
        }
        content += "ET\n"
        return PDFWriter.write(fonts: [base, turkish], content: content)
    }

    /// Türkçe ek harflerin yapay çizimleri (gerçek ekstredekilerden farklı; sözlükte yoklar, şekilden tanınmalılar).
    static func turkishShape(_ char: Character) -> GlyphBitmap? {
        switch char {
        case "ı": glyph(stem(16))
        case "İ": glyph(stem(3) + gap + stem(22))
        case "ş": glyph(box(width: 10, height: 16) + ["..........", "....###...", "...###...."], baselineRow: 15)
        case "Ş": glyph(box(width: 12, height: 22) + ["............", ".....###....", "....###....."], baselineRow: 21)
        case "ğ": glyph(["..########", "..########"] + ["..........", ".........."] + box(width: 10, height: 22), baselineRow: 19)
        case "Ğ": glyph(["...######...", "...######..."] + ["............", "............"] + box(width: 12, height: 22))
        default: nil
        }
    }

    /// Latin harfler: küçük harfler x yüksekliğinde (16), büyük harf/rakam/uzun harfler 22 satır.
    static func latinShape(_ char: Character) -> GlyphBitmap {
        if char == " " { return glyph(["........"]) }
        if char.isLowercase, "acemnorsuvwxz".contains(char) { return glyph(box(width: 10, height: 16)) }
        if "gjpqy".contains(char) { return glyph(box(width: 10, height: 22), baselineRow: 15) }
        if ".,:;-_'".contains(char) { return glyph(box(width: 4, height: 4)) }
        return glyph(box(width: char.isUppercase ? 14 : 10, height: 22))
    }

    struct Font {
        let name: String
        var bitmaps: [UInt8: GlyphBitmap] = [:]
        var advances: [UInt8: Double] = [:]
        var chars: [UInt8: Character] = [:]
        var nextCode: UInt8 = 0xA5

        init(name: String) { self.name = name }

        func code(for char: Character) -> UInt8? { chars.first { $0.value == char }?.key }

        @discardableResult
        mutating func add(_ code: UInt8?, _ bitmap: GlyphBitmap, advance: Double) -> UInt8 {
            let assigned = code ?? nextCode
            if code == nil { nextCode += 1 }
            bitmaps[assigned] = bitmap
            advances[assigned] = advance
            return assigned
        }
    }

    /// En küçük PDF yazıcı: katalog, sayfa, iki Type3 yazı tipi, içerik ve harf çizimleri.
    enum PDFWriter {
        static func write(fonts: [Font], content: String) -> Data {
            var objects: [Data] = []
            func reserve() -> Int { objects.append(Data()); return objects.count }
            let catalog = reserve(), pages = reserve(), page = reserve(), contents = reserve()
            let fontIDs = fonts.map { _ in reserve() }

            for (font, id) in zip(fonts, fontIDs) {
                let codes = font.bitmaps.keys.sorted()
                var procs = ""
                for code in codes {
                    let bitmap = font.bitmaps[code]!
                    var stream = Data(String(format: "%.0f 0 0 %d %d %d d1 q %d 0 0 %d %d %d cm BI /W %d /H %d /BPC 1 /IM true /D [1 0] ID ",
                                             font.advances[code]!, bitmap.offsetY, bitmap.width, bitmap.offsetY + bitmap.height,
                                             bitmap.width, bitmap.height, bitmap.offsetX, bitmap.offsetY, bitmap.width, bitmap.height).utf8)
                    stream.append(contentsOf: bitmap.bits)
                    stream.append(Data(" EI Q".utf8))
                    let procID = reserve()
                    objects[procID - 1] = streamObject(stream)
                    procs += String(format: "/C%02x %d 0 R ", code, procID)
                }
                let first = Int(codes.first ?? 0), last = Int(codes.last ?? 0)
                let widths = (first...last).map { code in font.advances[UInt8(code)].map { String(format: "%.0f", $0) } ?? "0" }
                let differences = codes.map { String(format: "%d /C%02x", $0, $0) }.joined(separator: " ")
                objects[id - 1] = Data("""
                << /Type /Font /Subtype /Type3 /FontBBox [0 -20 40 80] /FontMatrix [1 0 0 1 0 0] \
                /CharProcs << \(procs)>> /Encoding << /Type /Encoding /Differences [\(differences)] >> \
                /FirstChar \(first) /LastChar \(last) /Widths [\(widths.joined(separator: " "))] /Resources << >> >>
                """.utf8)
            }
            let fontRefs = zip(fonts, fontIDs).map { "/\($0.name) \($1) 0 R" }.joined(separator: " ")
            objects[catalog - 1] = Data("<< /Type /Catalog /Pages \(pages) 0 R >>".utf8)
            objects[pages - 1] = Data("<< /Type /Pages /Kids [\(page) 0 R] /Count 1 >>".utf8)
            objects[page - 1] = Data("""
            << /Type /Page /Parent \(pages) 0 R /MediaBox [0 0 595 842] /Resources << /Font << \(fontRefs) >> >> /Contents \(contents) 0 R >>
            """.utf8)
            objects[contents - 1] = streamObject(Data(content.utf8))

            var pdf = Data("%PDF-1.4\n".utf8)
            var offsets: [Int] = []
            for (index, body) in objects.enumerated() {
                offsets.append(pdf.count)
                pdf.append(Data("\(index + 1) 0 obj\n".utf8))
                pdf.append(body)
                pdf.append(Data("\nendobj\n".utf8))
            }
            let xref = pdf.count
            pdf.append(Data("xref\n0 \(objects.count + 1)\n0000000000 65535 f \n".utf8))
            for offset in offsets { pdf.append(Data(String(format: "%010d 00000 n \n", offset).utf8)) }
            pdf.append(Data("trailer\n<< /Size \(objects.count + 1) /Root \(catalog) 0 R >>\nstartxref\n\(xref)\n%%EOF\n".utf8))
            return pdf
        }

        private static func streamObject(_ data: Data) -> Data {
            var object = Data("<< /Length \(data.count) >>\nstream\n".utf8)
            object.append(data)
            object.append(Data("\nendstream".utf8))
            return object
        }
    }
}

@Suite("EBCDIC kodlu PDF (Akbank)")
struct EncodedPDFTests {
    @Test("EBCDIC rakam, harf, işaret ve Latin-1 Türkçe harfleri")
    func ebcdic() {
        #expect(EBCDIC.decode([0xF0, 0xF2, 0x61, 0xF0, 0xF9, 0x40, 0xC1, 0x81, 0x6B, 0x4B, 0x4D, 0x60, 0x5D]) == "02/09 Aa,.(-)")
        #expect(EBCDIC.decode([0x48, 0x68, 0xCC, 0xEC, 0xDC, 0xFC, 0x6D, 0x5E]) == "çÇöÖüÜ_;")
    }

    @Test("Ek Türkçe harfler şeklinden tanınır", arguments: Array("ıİğĞ"))
    func shapes(letter: Character) {
        #expect(TurkishGlyphs.recognize(EncodedPDFFixture.turkishShape(letter)!) == .character(letter))
    }

    @Test("Çengelli s şeklinden tanınır; büyük/küçük harf komşulara göre belirlenir")
    func sCedilla() {
        #expect(TurkishGlyphs.recognize(EncodedPDFFixture.turkishShape("ş")!) == .sCedilla)
        #expect(TurkishGlyphs.recognize(EncodedPDFFixture.turkishShape("Ş")!) == .sCedilla)
        #expect(TurkishGlyphs.recognize(glyph(["........"])) == .blank)
    }

    static let statement: [(text: String, x: Double, y: Double)] = [
        ("Hesap Kesim Tarihi 18/09/2026", 40, 800),
        ("İşlem Tarihi", 40, 760), ("Dönem içi işlemler", 110, 760), ("Borç Tutarı (TL)", 380, 760),
        ("Kalan Borç / Taksit", 460, 760),
        ("02/09/2026", 40, 740), ("AKBANK Internet Subesi Odeme Tesekkurler", 110, 740), ("5,000.00(-)", 380, 740.4),
        ("05/09/2026", 40, 725), ("HEPSİBURADA/İSTANBUL (2,970.00 TL) 3/2.taksit", 110, 725), ("990.00", 380, 725),
        ("990.00x1", 460, 725),
        ("10/09/2026", 40, 710), ("ŞOK MARKET KADIKÖY", 110, 710), ("245.50", 380, 709.7),
        ("12/09/2026", 40, 695), ("DOĞAN KIRTASİYE", 110, 695), ("89.90", 380, 695),
        ("13/09/2026", 40, 680), ("ilk_harcamaya_ödül", 110, 680), ("150.00", 520, 680),
        ("Ödemeniz için teşekkür ederiz. Ağustos ayı yaptı\u{200B}ğ\u{200B}ınız", 40, 650),
    ]

    @Test("Type3/EBCDIC PDF metni konumlarına göre satırlara çözülür")
    func decodesLines() {
        let lines = PDFEncodedText.lines(from: EncodedPDFFixture.make(Self.statement))
        #expect(lines == [
            "Hesap Kesim Tarihi 18/09/2026",
            "İşlem Tarihi Dönem içi işlemler Borç Tutarı (TL) Kalan Borç / Taksit",
            "02/09/2026 AKBANK Internet Subesi Odeme Tesekkurler 5,000.00(-)",
            "05/09/2026 HEPSİBURADA/İSTANBUL (2,970.00 TL) 3/2.taksit 990.00 990.00x1",
            "10/09/2026 ŞOK MARKET KADIKÖY 245.50",
            "12/09/2026 DOĞAN KIRTASİYE 89.90",
            "13/09/2026 ilk_harcamaya_ödül 150.00",
            "Ödemeniz için teşekkür ederiz. Ağustos ayı yaptığınız",
        ])
    }

    @Test("PDFKit'in okuyamadığı Akbank PDF'i kodlarından okunur ve işlem satırlarına ayrılır")
    func statementText() throws {
        let pdf = EncodedPDFFixture.make(Self.statement)
        let lines = try PDFStatementText.lines(from: pdf)
        let result = try StatementParser.parse(rows: PDFStatementLines.rows(from: lines), profile: .akbank,
                                               columns: (headerIndex: 0, map: PDFStatementLines.columns))
        #expect(result.rows.map(\.kind) == [.payment, .expense, .expense, .expense, .reward])
        #expect(result.rows.map(\.description) == [
            "AKBANK Internet Subesi Odeme Tesekkurler", "HEPSİBURADA/İSTANBUL (2,970.00 TL) 3/2.taksit",
            "ŞOK MARKET KADIKÖY", "DOĞAN KIRTASİYE", "ilk_harcamaya_ödül",
        ])
        #expect(result.rows[1].installment == InstallmentMarker(current: 2, total: 3))
        #expect(result.rows.map(\.amount) == [tl(5_000), tl(990), Money(minor: 24_550), Money(minor: 8_990), tl(150)])
    }

    @Test("Metni okunabilen PDF'lerde PDFKit satırları kullanılır")
    func plainPDF() throws {
        let pdf = makePDF([("02.10.2026", 40, 700), ("MIGROS SANAL MARKET", 120, 700), ("1.234,56", 480, 700)])
        #expect(PDFEncodedText.lines(from: pdf).isEmpty, "EBCDIC olmayan PDF bu yoldan çözülmemeli")
        #expect(try PDFStatementText.lines(from: pdf) == ["02.10.2026 MIGROS SANAL MARKET 1.234,56"])
    }

    /// UI testindeki örnek dosyayı yazar: make fixtures
    @Test(.enabled(if: ProcessInfo.processInfo.environment["AKBANK_FIXTURE_OUT"] != nil))
    func writeUIFixture() throws {
        let url = URL(fileURLWithPath: ProcessInfo.processInfo.environment["AKBANK_FIXTURE_OUT"]!)
        try EncodedPDFFixture.make(Self.statement).write(to: url)
    }
}
