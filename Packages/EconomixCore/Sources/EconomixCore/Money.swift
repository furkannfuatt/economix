import Foundation

/// Kuruş cinsinden tutar. Tüm hesaplar tamsayı üzerinde yapılır; kayan nokta hatası olmaz.
public struct Money: Hashable, Comparable, Sendable, Codable {
    public var minor: Int

    public init(minor: Int) {
        self.minor = minor
    }

    public static let zero = Money(minor: 0)

    /// Metinden kabul edilen en büyük tutar: 10 milyar TL. Üstü yazım ya da dosya hatasıdır.
    public static let maxMagnitude = Money(minor: 1_000_000_000_000)

    public var isZero: Bool { minor == 0 }
    public var isNegative: Bool { minor < 0 }
    public var magnitude: Money { Money(minor: Int(clamping: minor.magnitude)) }

    /// Lira cinsinden ondalık değer (grafikler için).
    public var lira: Double { Double(minor) / 100 }

    // Aritmetik taşmada çökmek yerine ±Int.max'a doyar: bozuk ya da dev bir kayıt uygulamayı her açılışta
    // çökertmesin. Int.min kullanılmaz; böylece işaret değiştirme ve mutlak değer de güvenli kalır.
    private static func saturated(_ result: (partialValue: Int, overflow: Bool), positive: Bool) -> Money {
        guard !result.overflow, result.partialValue != .min else { return Money(minor: positive ? .max : -.max) }
        return Money(minor: result.partialValue)
    }

    public static func + (lhs: Money, rhs: Money) -> Money {
        saturated(lhs.minor.addingReportingOverflow(rhs.minor), positive: rhs.minor > 0)
    }
    public static func - (lhs: Money, rhs: Money) -> Money {
        saturated(lhs.minor.subtractingReportingOverflow(rhs.minor), positive: rhs.minor < 0)
    }
    public static prefix func - (value: Money) -> Money { Money(minor: 0) - value }
    public static func * (lhs: Money, rhs: Int) -> Money {
        saturated(lhs.minor.multipliedReportingOverflow(by: rhs), positive: (lhs.minor < 0) == (rhs < 0))
    }
    public static func += (lhs: inout Money, rhs: Money) { lhs = lhs + rhs }
    public static func -= (lhs: inout Money, rhs: Money) { lhs = lhs - rhs }
    public static func < (lhs: Money, rhs: Money) -> Bool { lhs.minor < rhs.minor }

    /// Oransal bölme; sonuç en yakın kuruşa yuvarlanır (Int aralığı dışına çıkarsa sınırlanır).
    public func scaled(numerator: Int, denominator: Int) -> Money {
        precondition(denominator != 0)
        let value = (Double(minor) * Double(numerator) / Double(denominator)).rounded(.toNearestOrAwayFromZero)
        guard value.isFinite else { return Money(minor: value < 0 ? -.max : .max) }
        return Money(minor: Int(exactly: value) ?? (value < 0 ? -.max : .max))
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
        let absolute = magnitude.minor
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
        // 12 haneden uzun tam kısım zaten sınırın üstünde; çevirmeden reddedilir (taşma olmaz).
        guard integerPart.count <= 12, let lira = Int(integerPart.isEmpty ? "0" : integerPart) else { return nil }

        var kurus = 0
        if !fractionPart.isEmpty {
            guard fractionPart.count <= 2, let f = Int(fractionPart) else { return nil }
            kurus = fractionPart.count == 1 ? f * 10 : f
        }
        let value = lira * 100 + kurus
        guard value <= maxMagnitude.minor else { return nil }
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
