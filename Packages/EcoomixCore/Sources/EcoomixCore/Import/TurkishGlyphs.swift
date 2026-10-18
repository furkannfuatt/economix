import Foundation

/// Akbank ekstrelerinde EBCDIC tablosunda olmayan Türkçe harfler (ı İ ş Ş ğ Ğ) ayrı bir Type3 yazı tipinde durur.
/// Bu yazı tipindeki kodlar belgeden belgeye değişebildiği için harf, resminden tanınır:
/// önce gerçek ekstreden öğrenilmiş harf sözlüğüne, yoksa harfin şekline bakılır.
public enum TurkishGlyphs {
    public enum Recognition: Equatable, Sendable {
        case character(Character)
        /// ş ya da Ş: şekilleri aynıdır, büyük/küçük harf komşu harflerin boyuna bakılarak anlaşılır.
        case sCedilla
        /// Boş resim. Bu yazı tipinde harflerin arasına sıfır genişlikte konur; boşluk değildir.
        case blank
    }

    public static func recognize(_ bitmap: GlyphBitmap) -> Recognition? {
        if let character = known[bitmap.fingerprint] { return .character(character) }
        return shape(of: bitmap)
    }

    /// Harf sözlüğünde var mı? (Boşluk sözlükte yoktur; boş resim her yazı tipinde aynıdır.)
    public static func isKnown(_ bitmap: GlyphBitmap) -> Bool { known[bitmap.fingerprint] != nil }

    /// Şekil kuralları: tek çubuk ı; üstünde nokta olan çubuk İ; üstünde çizgi olan geniş harf ğ (taban çizgisinin altına iner) ya da Ğ;
    /// altında çengel olan geniş harf ş/Ş.
    static func shape(of bitmap: GlyphBitmap) -> Recognition? {
        let inkRows = (0..<bitmap.height).filter { y in (0..<bitmap.width).contains { bitmap.isInk(x: $0, y: y) } }
        guard let bottom = inkRows.last else { return .blank }

        var segments: [ClosedRange<Int>] = []
        for y in inkRows {
            if let last = segments.last, last.upperBound == y - 1 {
                segments[segments.count - 1] = last.lowerBound...y
            } else {
                segments.append(y...y)
            }
        }
        func isNarrow(_ rows: ClosedRange<Int>) -> Bool {
            let columns = (0..<bitmap.width).filter { x in rows.contains { bitmap.isInk(x: x, y: $0) } }
            guard let first = columns.first, let last = columns.last else { return false }
            return Double(last - first + 1) <= Double(rows.count) * 0.45
        }
        // Taban çizgisinin hemen üstündeki satır; altına inen mürekkep kuyruktur.
        let baselineRow = bitmap.height + bitmap.offsetY - 1
        let descends = bottom > baselineRow + max(1, inkRows.count / 12)

        switch segments.count {
        case 1:
            return isNarrow(segments[0]) ? .character("ı") : nil
        case 2:
            let (upper, lower) = (segments[0], segments[1])
            if upper.count < lower.count {
                if isNarrow(lower) { return .character("İ") }
                return .character(descends ? "ğ" : "Ğ")
            }
            return .sCedilla
        default:
            return nil
        }
    }

    /// Gerçek Akbank ekstresinden öğrenilmiş harf resimleri (parmak izi → harf). Harfin resmi yazı tipi ve boyuna göre sabittir;
    /// büyük/küçük harf, harfin üst ucu aynı satırdaki komşu harflerle karşılaştırılarak belirlendi.
    static let known: [String: Character] = [
        "dd7049d20b376962": "ı", "a2696f4af0789de3": "ı", "e29a351bc69c3906": "ı", "588acc03dc090adf": "ı",
        "4f99c49b75141f85": "ı", "51a069cbef9e4a21": "ı", "69efb0c8e1dfa9af": "ı", "b68918326be71719": "ı",
        "b82f2c3bd8112b70": "İ", "0c08a13ab75bf4f7": "İ", "c5caafaeb9efa8b8": "İ", "e7464b4edeee67ca": "İ",
        "d30a3379c6d8da37": "İ",
        "b2780f12e9ea4f26": "ş", "a3948eae9251e2c2": "ş", "9d7d06b614b25838": "ş", "98576b9f1821e71b": "ş",
        "9ee716c172e93317": "ş",
        "c885b4497f97ea5b": "Ş", "75cb9220e3143eb7": "Ş", "49112798ade8db8f": "Ş", "23095f55ada8819d": "Ş",
        "e7d4aa52e30f48b9": "ğ", "d945bb84038961db": "ğ", "1bc9af67456b0d53": "ğ", "33c659d052dd71b4": "ğ",
        "7cdb0003ae47dfc1": "Ğ",
    ]
}
