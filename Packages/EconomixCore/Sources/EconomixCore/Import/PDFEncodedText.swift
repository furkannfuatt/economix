import Foundation

/// Ana bilgisayar (AFP) çıktısı PDF'lerin metnini harf kodlarından çözer (Akbank Axess).
/// Bu PDF'lerde harfler Type3 bitmap yazı tipleridir, kodlar EBCDIC'tir ve Unicode tablosu yoktur; PDFKit anlamsız metin verir.
/// Harfler sayfadaki konumlarına göre satırlara dizilir.
public enum PDFEncodedText {
    public static func lines(from data: Data) -> [String] {
        let pages = PDFGlyphExtractor.pages(from: data)
        guard isEBCDIC(pages.flatMap { $0 }) else { return [] }
        let turkishFonts = turkishFonts(in: pages.flatMap { $0 })
        return pages.flatMap { lines(on: $0, turkishFonts: turkishFonts) }
    }

    /// EBCDIC'te boşluk 0x40, rakamlar 0xF0–0xF9'dur; ASCII'de boşluk 0x20.
    static func isEBCDIC(_ glyphs: [PlacedGlyph]) -> Bool {
        let spaces = glyphs.filter { $0.code == EBCDIC.space }.count
        let asciiSpaces = glyphs.filter { $0.code == 0x20 }.count
        let digits = glyphs.filter { EBCDIC.digits.contains($0.code) }.count
        return spaces > asciiSpaces && digits > 0
    }

    /// Türkçe harf yazı tipi: boşluğu EBCDIC'teki gibi 0x40 ile yazmaz; harf sözlüğünde olan bir harf içerir,
    /// boşluğu başka bir koddadır ya da rakam içermez ve bütün harfleri Türkçe harf şekline uyar.
    static func turkishFonts(in glyphs: [PlacedGlyph]) -> Set<String> {
        let byFont = Dictionary(grouping: glyphs, by: \.font)
        return Set(byFont.compactMap { font, glyphs -> String? in
            let bitmaps = glyphs.compactMap(\.bitmap)
            guard !bitmaps.isEmpty, !glyphs.contains(where: { $0.code == EBCDIC.space }) else { return nil }
            if bitmaps.contains(where: TurkishGlyphs.isKnown) || bitmaps.contains(where: isBlank) { return font }
            let hasDigits = glyphs.contains { EBCDIC.digits.contains($0.code) }
            if !hasDigits, bitmaps.allSatisfy({ TurkishGlyphs.recognize($0) != nil }) { return font }
            return nil
        })
    }

    private static func isBlank(_ bitmap: GlyphBitmap) -> Bool { bitmap.bits.allSatisfy { $0 == 0 } }

    // MARK: Satırlar

    struct Item {
        let glyph: PlacedGlyph
        var character: Character?
        var isTurkishS = false

        var x: Double { glyph.x }
        var end: Double { glyph.x + glyph.advance }
        /// Mürekkebin taban çizgisinden yüksekliği (pt).
        var inkTop: Double? {
            guard let bitmap = glyph.bitmap,
                  let first = (0..<bitmap.height).first(where: { y in (0..<bitmap.width).contains { bitmap.isInk(x: $0, y: y) } })
            else { return nil }
            return Double(bitmap.offsetY + bitmap.height - first) * glyph.unitScale
        }
    }

    static func lines(on page: [PlacedGlyph], turkishFonts: Set<String>) -> [String] {
        let items = page.map { glyph -> Item in
            guard turkishFonts.contains(glyph.font) else {
                let character = EBCDIC.character(glyph.code)
                return Item(glyph: glyph, character: character == "\u{A0}" ? " " : (isControl(character) ? nil : character))
            }
            switch glyph.bitmap.flatMap(TurkishGlyphs.recognize) {
            case .character(let character): return Item(glyph: glyph, character: character)
            case .sCedilla: return Item(glyph: glyph, character: "ş", isTurkishS: true)
            // Kelime arası boşluk, harfler arasındaki açıklıktan anlaşılır.
            case .blank: return Item(glyph: glyph, character: nil)
            case nil: return Item(glyph: glyph, character: "?")
            }
        }

        // Yukarıdan aşağıya: taban çizgileri birbirine yakın harfler aynı satırdır.
        var rows: [[Item]] = []
        var rowY = Double.infinity
        for item in items.sorted(by: { $0.glyph.y > $1.glyph.y }) {
            if let last = rows.indices.last, abs(rowY - item.glyph.y) <= 1.5 {
                rows[last].append(item)
            } else {
                rows.append([item])
                rowY = item.glyph.y
            }
        }
        return rows.compactMap { row in
            let text = text(of: resolveCase(row.sorted { $0.x < $1.x }))
            return text.isEmpty ? nil : text
        }
    }

    /// ş/Ş: harfin üst ucu yakındaki küçük harflerin (x yüksekliği) belirgin üstündeyse ya da büyük harflerle aynı boydaysa büyük harftir.
    static func resolveCase(_ row: [Item]) -> [Item] {
        var row = row
        for index in row.indices where row[index].isTurkishS {
            guard let top = row[index].inkTop else { continue }
            let scale = row[index].glyph.unitScale
            let neighbours = row.indices
                .filter { $0 != index && abs($0 - index) <= 8 && abs(row[$0].glyph.unitScale - scale) < scale * 0.01 }
                .sorted { abs($0 - index) < abs($1 - index) }
            for neighbour in neighbours {
                guard let character = row[neighbour].character, let neighbourTop = row[neighbour].inkTop else { continue }
                if xHeightLetters.contains(character) {
                    if top > neighbourTop * 1.15 { row[index].character = "Ş" }
                    break
                }
                if capitalLetters.contains(character) {
                    if top > neighbourTop * 0.86 { row[index].character = "Ş" }
                    break
                }
            }
        }
        return row
    }

    private static let xHeightLetters = Set("acemnorsuvwxzçıüö")
    private static let capitalLetters = Set("ABCDEFGHIJKLMNOPQRSTUVWXYZÇ")

    /// Harfleri birleştirir; arada boşluk kadar açıklık varsa (sütunlar ayrı parçalar halinde yazılır) boşluk koyar.
    static func text(of row: [Item]) -> String {
        let advances = row.filter { $0.character != " " }.map(\.glyph.advance).sorted()
        let median = advances.isEmpty ? 1 : advances[advances.count / 2]
        let gapThreshold = max(0.8, median * 0.35)
        var text = ""
        var previous: Item?
        for item in row {
            guard let character = item.character else { continue }
            if let previous {
                // Kalın yazı için aynı harfin hafif kaydırılıp tekrar basılması
                if character == previous.character, item.x - previous.x < previous.glyph.advance * 0.3 { continue }
                if item.x - previous.end > gapThreshold, text.last != " " { text.append(" ") }
            }
            if character == " ", text.last == " " || text.isEmpty { previous = item; continue }
            text.append(character)
            previous = item
        }
        return text.trimmingCharacters(in: .whitespaces)
    }

    private static func isControl(_ character: Character) -> Bool {
        character.unicodeScalars.allSatisfy { $0.properties.generalCategory == .control }
    }
}

/// Ekstre PDF'inin satırları: önce PDFKit'in metni, işlem satırı çıkmazsa harf kodlarından çözülen metin (Akbank).
public enum PDFStatementText {
    public static func lines(from data: Data) throws -> [String] {
        var textLines: [String] = []
        do {
            textLines = try PDFTextReader.lines(from: data)
        } catch PDFTextReader.ReadError.notPDF {
            throw PDFTextReader.ReadError.notPDF
        } catch {}
        if PDFStatementLines.rows(from: textLines).count > 1 { return textLines }

        let decoded = PDFEncodedText.lines(from: data)
        if PDFStatementLines.rows(from: decoded).count > 1 { return decoded }
        if !textLines.isEmpty { return textLines }
        if !decoded.isEmpty { return decoded }
        throw PDFTextReader.ReadError.noText
    }
}
