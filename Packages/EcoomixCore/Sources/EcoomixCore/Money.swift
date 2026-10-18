import Foundation

/// Kuruş cinsinden tutar. Tüm hesaplar tamsayı üzerinde yapılır; kayan nokta hatası olmaz.
public struct Money: Hashable, Comparable, Sendable, Codable {
    public var minor: Int

    public init(minor: Int) {
        self.minor = minor
    }

    public static let zero = Money(minor: 0)

    public var isZero: Bool { minor == 0 }
    public var isNegative: Bool { minor < 0 }
    public var magnitude: Money { Money(minor: Swift.abs(minor)) }

    /// Lira cinsinden ondalık değer (grafikler için).
    public var lira: Double { Double(minor) / 100 }

    public static func + (lhs: Money, rhs: Money) -> Money { Money(minor: lhs.minor + rhs.minor) }
    public static func - (lhs: Money, rhs: Money) -> Money { Money(minor: lhs.minor - rhs.minor) }
    public static prefix func - (value: Money) -> Money { Money(minor: -value.minor) }
    public static func * (lhs: Money, rhs: Int) -> Money { Money(minor: lhs.minor * rhs) }
    public static func += (lhs: inout Money, rhs: Money) { lhs.minor += rhs.minor }
    public static func -= (lhs: inout Money, rhs: Money) { lhs.minor -= rhs.minor }
    public static func < (lhs: Money, rhs: Money) -> Bool { lhs.minor < rhs.minor }

    /// Oransal bölme; sonuç en yakın kuruşa yuvarlanır.
    public func scaled(numerator: Int, denominator: Int) -> Money {
        precondition(denominator != 0)
        let value = Double(minor) * Double(numerator) / Double(denominator)
        return Money(minor: Int(value.rounded(.toNearestOrAwayFromZero)))
    }

    /// Tutarı `count` parçaya böler; kuruş artığı ilk parçaya eklenir.
    public func split(into count: Int) -> [Money] {
        precondition(count > 0)
        let base = minor / count
        let remainder = minor - base * count
        return (0..<count).map { Money(minor: base + ($0 == 0 ? remainder : 0)) }
    }

    /// Bu tutarın `total` içindeki payı (0...1+). `total` sıfırsa 0.
    public func ratio(of total: Money) -> Double {
        total.minor == 0 ? 0 : Double(minor) / Double(total.minor)
    }
}

// MARK: - Biçimlendirme

extension Money {
    /// "1.234,56 ₺" biçiminde metin.
    public func formatted(decimals: Bool = true) -> String {
        let negative = minor < 0
        let absolute = Swift.abs(minor)
        var lira = absolute / 100
        let kurus = absolute % 100
        if !decimals, kurus >= 50 { lira += 1 }

        var body = Self.groupThousands(lira)
        if decimals {
            body += "," + (kurus < 10 ? "0\(kurus)" : "\(kurus)")
        }
        let showMinus = negative && (decimals ? absolute != 0 : (lira != 0))
        return (showMinus ? "-" : "") + body + " ₺"
    }

    private static func groupThousands(_ value: Int) -> String {
        let digits = Array(String(value))
        var result = ""
        for (index, digit) in digits.enumerated() {
            if index > 0, (digits.count - index) % 3 == 0 { result.append(".") }
            result.append(digit)
        }
        return result
    }
}

// MARK: - Metinden çözme

extension Money {
    /// Banka ekstrelerinde görülen tutar metinlerini çözer:
    /// "1.234,56", "1,234.56", "45,90-", "(150,00)", "1.250,00 TL", "₺ 99" …
    public static func parse(_ text: String) -> Money? {
        var s = text
            .replacingOccurrences(of: "TRY", with: "")
            .replacingOccurrences(of: "TL", with: "")
            .replacingOccurrences(of: "₺", with: "")
            .filter { !$0.isWhitespace }

        var negative = false
        if s.hasPrefix("("), s.hasSuffix(")") {
            negative = true
            s = String(s.dropFirst().dropLast())
        }
        if s.hasPrefix("-") {
            negative.toggle()
            s.removeFirst()
        } else if s.hasPrefix("+") {
            s.removeFirst()
        }
        if s.hasSuffix("-") {
            negative.toggle()
            s.removeLast()
        }

        guard !s.isEmpty, s.allSatisfy({ $0.isASCII && ($0.isNumber || $0 == "." || $0 == ",") }),
              s.contains(where: \.isNumber)
        else { return nil }

        guard let (integerPart, fractionPart) = splitNumber(s) else { return nil }
        guard let lira = Int(integerPart.isEmpty ? "0" : integerPart) else { return nil }

        var kurus = 0
        if !fractionPart.isEmpty {
            guard fractionPart.count <= 2, let f = Int(fractionPart) else { return nil }
            kurus = fractionPart.count == 1 ? f * 10 : f
        }
        let value = lira * 100 + kurus
        return Money(minor: negative ? -value : value)
    }

    /// Tam ve ondalık kısımları ayırır, binlik ayraçlarını doğrular.
    private static func splitNumber(_ s: String) -> (String, String)? {
        let commas = s.filter { $0 == "," }.count
        let dots = s.filter { $0 == "." }.count

        if commas > 0, dots > 0 {
            // Son görülen ayraç ondalıktır.
            let decimalSeparator: Character = s.lastIndex(of: ",")! > s.lastIndex(of: ".")! ? "," : "."
            let thousands: Character = decimalSeparator == "," ? "." : ","
            let parts = s.split(separator: decimalSeparator, omittingEmptySubsequences: false)
            guard parts.count == 2, !parts[1].contains(thousands) else { return nil }
            guard let integer = validatedThousands(String(parts[0]), separator: thousands) else { return nil }
            return (integer, String(parts[1]))
        }

        if commas == 0, dots == 0 { return (s, "") }

        let separator: Character = commas > 0 ? "," : "."
        let parts = s.split(separator: separator, omittingEmptySubsequences: false).map(String.init)
        if parts.count == 2 {
            // Tek ayraç: ardından tam 3 hane geliyorsa binlik, değilse ondalık.
            if parts[1].count == 3 { return (parts[0] + parts[1], "") }
            return (parts[0], parts[1])
        }
        // "1.234.56": OCR ondalık ayracı binlikle aynı okumuş; son 2 hane kuruştur.
        if parts.count > 2, parts.last?.count == 2,
           let integer = validatedThousands(parts.dropLast().joined(separator: String(separator)), separator: separator) {
            return (integer, parts.last!)
        }
        guard let integer = validatedThousands(s, separator: separator) else { return nil }
        return (integer, "")
    }

    private static func validatedThousands(_ s: String, separator: Character) -> String? {
        let groups = s.split(separator: separator, omittingEmptySubsequences: false)
        guard let first = groups.first, !first.isEmpty, first.count <= 3 || groups.count == 1 else { return nil }
        for group in groups.dropFirst() where group.count != 3 { return nil }
        return groups.joined()
    }
}

extension Sequence where Element == Money {
    public func sum() -> Money { reduce(.zero, +) }
}
