import CoreGraphics
import Foundation

/// Type3 yazı tipindeki bir harfin resmi (1 bit, satır satır, her satır bayta yuvarlanmış; 1 = mürekkep).
public struct GlyphBitmap: Hashable, Sendable {
    public let width: Int
    public let height: Int
    /// Resmin harf kutusundaki yeri (taban çizgisi y = 0).
    public let offsetX: Int
    public let offsetY: Int
    public let bits: [UInt8]

    public init(width: Int, height: Int, offsetX: Int, offsetY: Int, bits: [UInt8]) {
        self.width = width
        self.height = height
        self.offsetX = offsetX
        self.offsetY = offsetY
        self.bits = bits
    }

    /// Resmin parmak izi (FNV-1a 64): aynı harf her ekstrede aynı piksellerle çizildiği için birebir eşleşir.
    public var fingerprint: String {
        var hash: UInt64 = 0xCBF2_9CE4_8422_2325
        func mix(_ byte: UInt8) {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01B3
        }
        for value in [width, height, offsetX, offsetY] {
            withUnsafeBytes(of: Int32(truncatingIfNeeded: value).littleEndian) { $0.forEach(mix) }
        }
        bits.forEach(mix)
        return String(format: "%016llx", hash)
    }

    public var bytesPerRow: Int { (width + 7) / 8 }

    public func isInk(x: Int, y: Int) -> Bool {
        guard x >= 0, y >= 0, x < width, y < height else { return false }
        return bits[y * bytesPerRow + x / 8] & (0x80 >> UInt8(x % 8)) != 0
    }
}

/// Sayfaya yerleştirilmiş bir harf.
public struct PlacedGlyph: Sendable {
    /// Type3 harf resmi; standart yazı tiplerinde nil.
    public let bitmap: GlyphBitmap?
    /// Sayfa koordinatı (pt, y yukarı doğru), taban çizgisi.
    public let x: Double
    public let y: Double
    /// Bir sonraki harfe kadar ilerleme (pt).
    public let advance: Double
    /// Yazı tipi boyutu (pt).
    public let size: Double
    /// Harf resminin 1 biriminin sayfadaki yüksekliği (pt).
    public let unitScale: Double
    /// PDF'teki yazı tipi adı ve harf kodu.
    public let font: String
    public let code: UInt8
}

/// PDF içerik akışını okuyup harfleri kodları, konumları ve (Type3 yazı tiplerinde) resimleriyle çıkarır.
/// Akbank ekstrelerinde harf adları anlamsız kodlardır ve ToUnicode tablosu yoktur; metin kodlardan ve harf resimlerinden çözülür.
public enum PDFGlyphExtractor {
    public static func pages(from data: Data) -> [[PlacedGlyph]] {
        guard let provider = CGDataProvider(data: data as CFData), let document = CGPDFDocument(provider) else { return [] }
        return (0..<document.numberOfPages).compactMap { index in
            document.page(at: index + 1).map(glyphs(on:))
        }
    }

    // MARK: İçerik akışı

    final class State {
        struct Graphics {
            var ctm = CGAffineTransform.identity
        }

        let stream: CGPDFContentStreamRef
        var graphics = Graphics()
        var stack: [Graphics] = []
        var textMatrix = CGAffineTransform.identity
        var lineMatrix = CGAffineTransform.identity
        var fontSize: Double = 1
        var horizontalScale: Double = 1
        var charSpacing: Double = 0
        var wordSpacing: Double = 0
        var leading: Double = 0
        var rise: Double = 0
        var font: Font?
        var fonts: [String: Font] = [:]
        var glyphs: [PlacedGlyph] = []

        init(stream: CGPDFContentStreamRef) { self.stream = stream }
    }

    final class Font {
        var bitmaps: [UInt8: GlyphBitmap] = [:]
        var advances: [UInt8: Double] = [:]
        var matrix = CGAffineTransform(a: 0.001, b: 0, c: 0, d: 0.001, tx: 0, ty: 0)
        var isType3 = false
        var defaultAdvance: Double = 500
        var name = ""
    }

    static func glyphs(on page: CGPDFPage) -> [PlacedGlyph] {
        let stream = CGPDFContentStreamCreateWithPage(page)
        let state = State(stream: stream)
        let table = CGPDFOperatorTableCreate()!
        register(table)
        let info = Unmanaged.passUnretained(state).toOpaque()
        let scanner = CGPDFScannerCreate(stream, table, info)
        CGPDFScannerScan(scanner)
        CGPDFScannerRelease(scanner)
        CGPDFContentStreamRelease(stream)
        CGPDFOperatorTableRelease(table)
        return state.glyphs
    }

    fileprivate static func state(_ info: UnsafeMutableRawPointer?) -> State {
        Unmanaged<State>.fromOpaque(info!).takeUnretainedValue()
    }

    fileprivate static func popNumbers(_ scanner: CGPDFScannerRef, _ count: Int) -> [Double]? {
        var values: [Double] = []
        for _ in 0..<count {
            var value: CGPDFReal = 0
            guard CGPDFScannerPopNumber(scanner, &value) else { return nil }
            values.insert(Double(value), at: 0)
        }
        return values
    }

    private static func register(_ table: CGPDFOperatorTableRef) {
        CGPDFOperatorTableSetCallback(table, "q") { _, info in
            let s = PDFGlyphExtractor.state(info)
            s.stack.append(s.graphics)
        }
        CGPDFOperatorTableSetCallback(table, "Q") { _, info in
            let s = PDFGlyphExtractor.state(info)
            if let last = s.stack.popLast() { s.graphics = last }
        }
        CGPDFOperatorTableSetCallback(table, "cm") { scanner, info in
            guard let n = PDFGlyphExtractor.popNumbers(scanner, 6) else { return }
            let s = PDFGlyphExtractor.state(info)
            s.graphics.ctm = CGAffineTransform(a: n[0], b: n[1], c: n[2], d: n[3], tx: n[4], ty: n[5]).concatenating(s.graphics.ctm)
        }
        CGPDFOperatorTableSetCallback(table, "BT") { _, info in
            let s = PDFGlyphExtractor.state(info)
            s.textMatrix = .identity
            s.lineMatrix = .identity
        }
        CGPDFOperatorTableSetCallback(table, "Tf") { scanner, info in
            var size: CGPDFReal = 0
            var name: UnsafePointer<CChar>?
            guard CGPDFScannerPopNumber(scanner, &size), CGPDFScannerPopName(scanner, &name), let name else { return }
            let s = PDFGlyphExtractor.state(info)
            s.fontSize = Double(size)
            s.font = PDFGlyphExtractor.font(named: String(cString: name), in: s)
        }
        CGPDFOperatorTableSetCallback(table, "Tz") { scanner, info in
            if let n = PDFGlyphExtractor.popNumbers(scanner, 1) { PDFGlyphExtractor.state(info).horizontalScale = n[0] / 100 }
        }
        CGPDFOperatorTableSetCallback(table, "Tc") { scanner, info in
            if let n = PDFGlyphExtractor.popNumbers(scanner, 1) { PDFGlyphExtractor.state(info).charSpacing = n[0] }
        }
        CGPDFOperatorTableSetCallback(table, "Tw") { scanner, info in
            if let n = PDFGlyphExtractor.popNumbers(scanner, 1) { PDFGlyphExtractor.state(info).wordSpacing = n[0] }
        }
        CGPDFOperatorTableSetCallback(table, "TL") { scanner, info in
            if let n = PDFGlyphExtractor.popNumbers(scanner, 1) { PDFGlyphExtractor.state(info).leading = n[0] }
        }
        CGPDFOperatorTableSetCallback(table, "Ts") { scanner, info in
            if let n = PDFGlyphExtractor.popNumbers(scanner, 1) { PDFGlyphExtractor.state(info).rise = n[0] }
        }
        CGPDFOperatorTableSetCallback(table, "Tm") { scanner, info in
            guard let n = PDFGlyphExtractor.popNumbers(scanner, 6) else { return }
            let s = PDFGlyphExtractor.state(info)
            s.textMatrix = CGAffineTransform(a: n[0], b: n[1], c: n[2], d: n[3], tx: n[4], ty: n[5])
            s.lineMatrix = s.textMatrix
        }
        CGPDFOperatorTableSetCallback(table, "Td") { scanner, info in
            guard let n = PDFGlyphExtractor.popNumbers(scanner, 2) else { return }
            PDFGlyphExtractor.moveLine(PDFGlyphExtractor.state(info), n[0], n[1])
        }
        CGPDFOperatorTableSetCallback(table, "TD") { scanner, info in
            guard let n = PDFGlyphExtractor.popNumbers(scanner, 2) else { return }
            let s = PDFGlyphExtractor.state(info)
            s.leading = -n[1]
            PDFGlyphExtractor.moveLine(s, n[0], n[1])
        }
        CGPDFOperatorTableSetCallback(table, "T*") { _, info in
            let s = PDFGlyphExtractor.state(info)
            PDFGlyphExtractor.moveLine(s, 0, -s.leading)
        }
        CGPDFOperatorTableSetCallback(table, "Tj") { scanner, info in
            var string: CGPDFStringRef?
            guard CGPDFScannerPopString(scanner, &string), let string else { return }
            PDFGlyphExtractor.show(string, in: PDFGlyphExtractor.state(info))
        }
        CGPDFOperatorTableSetCallback(table, "'") { scanner, info in
            var string: CGPDFStringRef?
            guard CGPDFScannerPopString(scanner, &string), let string else { return }
            let s = PDFGlyphExtractor.state(info)
            PDFGlyphExtractor.moveLine(s, 0, -s.leading)
            PDFGlyphExtractor.show(string, in: s)
        }
        CGPDFOperatorTableSetCallback(table, "TJ") { scanner, info in
            var array: CGPDFArrayRef?
            guard CGPDFScannerPopArray(scanner, &array), let array else { return }
            let s = PDFGlyphExtractor.state(info)
            for index in 0..<CGPDFArrayGetCount(array) {
                var string: CGPDFStringRef?
                var number: CGPDFReal = 0
                if CGPDFArrayGetString(array, index, &string), let string {
                    PDFGlyphExtractor.show(string, in: s)
                } else if CGPDFArrayGetNumber(array, index, &number) {
                    let shift = -Double(number) / 1000 * s.fontSize * s.horizontalScale
                    s.textMatrix = CGAffineTransform(translationX: shift, y: 0).concatenating(s.textMatrix)
                }
            }
        }
    }

    fileprivate static func moveLine(_ s: State, _ tx: Double, _ ty: Double) {
        s.lineMatrix = CGAffineTransform(translationX: tx, y: ty).concatenating(s.lineMatrix)
        s.textMatrix = s.lineMatrix
    }

    fileprivate static func show(_ string: CGPDFStringRef, in s: State) {
        guard let pointer = CGPDFStringGetBytePtr(string) else { return }
        let bytes = Array(UnsafeBufferPointer(start: pointer, count: CGPDFStringGetLength(string)))
        let font = s.font
        for code in bytes {
            let glyphAdvance = font.map { $0.advances[code] ?? $0.defaultAdvance } ?? 500
            let advanceInText = glyphAdvance * (font?.matrix.a ?? 0.001)
            let render = CGAffineTransform(a: s.fontSize * s.horizontalScale, b: 0, c: 0, d: s.fontSize, tx: 0, ty: s.rise)
                .concatenating(s.textMatrix).concatenating(s.graphics.ctm)
            let advance = (advanceInText * s.fontSize + s.charSpacing + (code == 32 ? s.wordSpacing : 0)) * s.horizontalScale
            let scale = (render.a * render.a + render.b * render.b).squareRoot() / max(s.horizontalScale, 0.0001)
            s.glyphs.append(PlacedGlyph(bitmap: font?.bitmaps[code], x: render.tx, y: render.ty,
                                        advance: advance * (scale / max(s.fontSize, 0.0001)), size: scale,
                                        unitScale: abs(font?.matrix.d ?? 0.001) * (render.c * render.c + render.d * render.d).squareRoot(),
                                        font: font?.name ?? "", code: code))
            s.textMatrix = CGAffineTransform(translationX: advance, y: 0).concatenating(s.textMatrix)
        }
    }

    // MARK: Yazı tipleri

    fileprivate static func font(named name: String, in s: State) -> Font? {
        if let cached = s.fonts[name] { return cached }
        guard let object = CGPDFContentStreamGetResource(s.stream, "Font", name) else { return nil }
        var dictionary: CGPDFDictionaryRef?
        guard CGPDFObjectGetValue(object, .dictionary, &dictionary), let dictionary else { return nil }
        let font = Font()
        font.name = name

        var subtype: UnsafePointer<CChar>?
        if CGPDFDictionaryGetName(dictionary, "Subtype", &subtype), let subtype { font.isType3 = String(cString: subtype) == "Type3" }

        var matrix: CGPDFArrayRef?
        if CGPDFDictionaryGetArray(dictionary, "FontMatrix", &matrix), let matrix, CGPDFArrayGetCount(matrix) == 6 {
            var v = [CGPDFReal](repeating: 0, count: 6)
            for i in 0..<6 { CGPDFArrayGetNumber(matrix, i, &v[i]) }
            font.matrix = CGAffineTransform(a: v[0], b: v[1], c: v[2], d: v[3], tx: v[4], ty: v[5])
        }

        var firstChar: CGPDFInteger = 0
        CGPDFDictionaryGetInteger(dictionary, "FirstChar", &firstChar)
        var widths: CGPDFArrayRef?
        if CGPDFDictionaryGetArray(dictionary, "Widths", &widths), let widths {
            for i in 0..<CGPDFArrayGetCount(widths) {
                var w: CGPDFReal = 0
                if CGPDFArrayGetNumber(widths, i, &w), let code = UInt8(exactly: Int(firstChar) + i) { font.advances[code] = Double(w) }
            }
        }

        guard font.isType3 else {
            s.fonts[name] = font
            return font
        }

        // Kod → harf adı (Encoding/Differences) → harf çizimi (CharProcs).
        var names: [UInt8: String] = [:]
        var encoding: CGPDFDictionaryRef?
        var differences: CGPDFArrayRef?
        if CGPDFDictionaryGetDictionary(dictionary, "Encoding", &encoding), let encoding,
           CGPDFDictionaryGetArray(encoding, "Differences", &differences), let differences {
            var code = 0
            for i in 0..<CGPDFArrayGetCount(differences) {
                var number: CGPDFInteger = 0
                var glyphName: UnsafePointer<CChar>?
                if CGPDFArrayGetInteger(differences, i, &number) {
                    code = Int(number)
                } else if CGPDFArrayGetName(differences, i, &glyphName), let glyphName {
                    if let byte = UInt8(exactly: code) { names[byte] = String(cString: glyphName) }
                    code += 1
                }
            }
        }
        var procs: CGPDFDictionaryRef?
        if CGPDFDictionaryGetDictionary(dictionary, "CharProcs", &procs), let procs {
            for (code, glyphName) in names {
                var stream: CGPDFStreamRef?
                guard CGPDFDictionaryGetStream(procs, glyphName, &stream), let stream else { continue }
                var format = CGPDFDataFormat.raw
                guard let data = CGPDFStreamCopyData(stream, &format) as Data? else { continue }
                let parsed = parseCharProc(Array(data))
                if let advance = parsed.advance { font.advances[code] = advance }
                font.bitmaps[code] = parsed.bitmap
            }
        }
        s.fonts[name] = font
        return font
    }

    /// "wx 0 llx lly urx ury d1 q W 0 0 H tx ty cm BI /W w /H h /BPC 1 /IM true /D [1 0] ID <veri> EI Q"
    static func parseCharProc(_ bytes: [UInt8]) -> (advance: Double?, bitmap: GlyphBitmap?) {
        guard let idRange = find([0x49, 0x44], in: bytes, after: 0, delimited: true) else {  // "ID"
            return (leadingNumbers(bytes, before: "d1").first, nil)
        }
        let header = String(decoding: bytes[..<idRange.lowerBound], as: UTF8.self)
        let advance = leadingNumbers(Array(header.utf8), before: "d1").first
        let cm = leadingNumbers(Array(header.utf8), before: "cm")
        func value(_ key: String) -> Int? {
            guard let range = header.range(of: "/" + key + " ") else { return nil }
            return Int(header[range.upperBound...].prefix { $0.isNumber })
        }
        guard let width = value("W") ?? value("Width"), let height = value("H") ?? value("Height"), width > 0, height > 0
        else { return (advance, nil) }
        let decodeInverted = header.contains("/D [1 0]") || header.contains("/Decode [1 0]")
        let start = idRange.upperBound + 1  // "ID" sonrası tek boşluk
        let length = (width + 7) / 8 * height
        guard start + length <= bytes.count else { return (advance, nil) }
        var bits = Array(bytes[start..<start + length])
        // Görüntü maskesinde varsayılan Decode [0 1]: 0 = boya. Mürekkebi 1 olarak tutmak için ters çevrilir.
        if !decodeInverted { bits = bits.map { ~$0 } }
        let offsetX = cm.count >= 6 ? Int(cm[4].rounded()) : 0
        let offsetY = cm.count >= 6 ? Int(cm[5].rounded()) : 0
        return (advance, GlyphBitmap(width: width, height: height, offsetX: offsetX, offsetY: offsetY, bits: bits))
    }

    /// `operator` adının hemen önündeki sayılar.
    private static func leadingNumbers(_ bytes: [UInt8], before operatorName: String) -> [Double] {
        let text = String(decoding: bytes, as: UTF8.self)
        guard let range = text.range(of: " " + operatorName) ?? text.range(of: operatorName) else { return [] }
        let words = text[..<range.lowerBound].split(whereSeparator: \.isWhitespace)
        var numbers: [Double] = []
        for word in words.reversed() {
            guard let number = Double(word) else { break }
            numbers.insert(number, at: 0)
        }
        return numbers
    }

    private static func find(_ needle: [UInt8], in bytes: [UInt8], after start: Int, delimited: Bool) -> Range<Int>? {
        guard bytes.count >= needle.count else { return nil }
        var index = start
        while index + needle.count <= bytes.count {
            if Array(bytes[index..<index + needle.count]) == needle {
                // "/D [1 0]ID" gibi ayraçla bitişik yazımlar da olur
                let before = index == 0 || isWhitespace(bytes[index - 1]) || [0x5D, 0x29, 0x3E].contains(bytes[index - 1])
                let after = index + needle.count >= bytes.count || isWhitespace(bytes[index + needle.count])
                if !delimited || (before && after) { return index..<index + needle.count }
            }
            index += 1
        }
        return nil
    }

    private static func isWhitespace(_ byte: UInt8) -> Bool { [0x20, 0x0A, 0x0D, 0x09, 0x0C, 0x00].contains(byte) }
}
