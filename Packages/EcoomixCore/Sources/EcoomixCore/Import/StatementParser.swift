import Foundation

public struct InstallmentMarker: Hashable, Sendable {
    public let current: Int
    public let total: Int

    public init(current: Int, total: Int) {
        self.current = current
        self.total = total
    }
}

public enum StatementRowKind: String, Sendable {
    /// Harcama (kartta) ya da para çıkışı (hesapta).
    case expense
    /// Kart iadesi.
    case refund
    /// Karta yapılan ödeme.
    case payment
    /// Hesaba giren para.
    case income
}

public struct StatementRow: Hashable, Sendable, Identifiable {
    public let lineNumber: Int
    public let date: Date
    public let description: String
    /// Her zaman pozitif; yönü `kind` belirler.
    public let amount: Money
    public let kind: StatementRowKind
    public let installment: InstallmentMarker?
    public let importHash: String

    public var id: Int { lineNumber }
}

public struct ColumnMap: Hashable, Sendable {
    public var date: Int
    public var description: Int
    public var amount: Int?
    public var debit: Int?
    public var credit: Int?
    public var installment: Int?

    public init(date: Int, description: Int, amount: Int? = nil, debit: Int? = nil, credit: Int? = nil,
                installment: Int? = nil) {
        self.date = date
        self.description = description
        self.amount = amount
        self.debit = debit
        self.credit = credit
        self.installment = installment
    }
}

public enum ExpenseSign: String, Sendable {
    /// Satırların çoğunluğunun işaretinden tahmin edilir.
    case auto
    /// Harcamalar pozitif (kart ekstreleri).
    case positive
    /// Harcamalar negatif (banka hesap dökümleri).
    case negative
}

public struct BankProfile: Hashable, Sendable, Identifiable {
    public let id: String
    public let name: String
    let keywords: [String]
    public let expenseSign: ExpenseSign

    public static let garanti = BankProfile(id: "garanti", name: "Garanti BBVA", keywords: ["GARANTI", "BONUS"], expenseSign: .auto)
    public static let yapikredi = BankProfile(id: "yapikredi", name: "Yapı Kredi",
                                              keywords: ["YAPI KREDI", "YAPIKREDI", "WORLD"], expenseSign: .auto)
    public static let akbank = BankProfile(id: "akbank", name: "Akbank", keywords: ["AKBANK", "AXESS"], expenseSign: .auto)
    public static let generic = BankProfile(id: "generic", name: "Diğer", keywords: [], expenseSign: .auto)

    public static let all: [BankProfile] = [.garanti, .yapikredi, .akbank, .generic]

    /// Dosya adından ya da ilk satırlardaki banka/kart adından tahmin eder.
    public static func detect(fileName: String, rows: [[String]]) -> BankProfile {
        let haystack = StatementParser.fold(fileName + " " + rows.prefix(15).flatMap { $0 }.joined(separator: " "))
        return all.first { profile in profile.keywords.contains { haystack.contains($0) } } ?? .generic
    }
}

public struct StatementParseResult: Sendable {
    public let rows: [StatementRow]
    public let skippedCount: Int
    public let headerIndex: Int
    public let columns: ColumnMap
    public let expensesArePositive: Bool
}

public enum StatementParser {
    public enum ParseError: Error, Equatable {
        case headerNotFound
        case noRows
    }

    /// Satır içinde geçerse atlanan özet satırları.
    private static let summaryKeywords = ["ONCEKI DONEM", "DEVREDEN", "TOPLAM", "ASGARI", "HESAP OZETI", "DONEM BORCU"]
    private static let paymentKeywords = ["ODEME", "TESEKKUR", "ODEMENIZ"]

    // MARK: Başlık

    public static func detectColumns(in rows: [[String]]) -> (headerIndex: Int, map: ColumnMap)? {
        for (index, row) in rows.prefix(40).enumerated() {
            let cells = row.map { fold($0) }
            func first(_ predicate: (String) -> Bool) -> Int? { cells.firstIndex(where: predicate) }

            let dateColumns = cells.indices.filter { cells[$0].contains("TARIH") && !cells[$0].contains("VALOR") }
            guard let date = dateColumns.first(where: { cells[$0].contains("ISLEM") }) ?? dateColumns.first else { continue }

            let description = first { $0.contains("ACIKLAMA") }
                ?? first { $0.contains("ISYERI") }
                ?? first { ($0 == "ISLEM" || $0.hasPrefix("ISLEM ") || $0 == "ISLEMLER") && !$0.contains("TARIH") && !$0.contains("TUTAR") }
            guard let description else { continue }

            let excluded = ["BONUS", "PUAN", "USD", "EUR", "DOVIZ", "CHIP", "MIL"]
            let amountColumns = cells.indices.filter { i in
                cells[i].contains("TUTAR") && !excluded.contains { cells[i].contains($0) }
            }
            let amount = amountColumns.first { cells[$0].contains("TL") } ?? amountColumns.first
            let debit = first { $0.contains("BORC") && !$0.contains("BAKIYE") }
            let credit = first { $0.contains("ALACAK") }
            guard amount != nil || (debit != nil && credit != nil) else { continue }

            let installment = first { $0.contains("TAKSIT") && !$0.contains("TUTAR") && !$0.contains("TARIH") }
            return (index, ColumnMap(date: date, description: description, amount: amount, debit: debit, credit: credit,
                                     installment: installment))
        }
        return nil
    }

    // MARK: Satırlar

    /// - Parameter expenseSign: Hedef hesabın türünden gelen ipucu (banka dökümünde çıkışlar eksidir);
    ///   verilmezse profilinki kullanılır.
    public static func parse(rows: [[String]], profile: BankProfile,
                             columns: (headerIndex: Int, map: ColumnMap)? = nil,
                             expenseSign: ExpenseSign? = nil,
                             calendar: Calendar = FinanceCalendar.calendar) throws -> StatementParseResult {
        guard let detected = columns ?? detectColumns(in: rows) else { throw ParseError.headerNotFound }
        let map = detected.map

        struct Raw {
            let line: Int
            let date: Date
            let description: String
            let signed: Money
            let fromDebitCredit: Bool
            let installment: InstallmentMarker?
        }

        var raws: [Raw] = []
        var skipped = 0
        for (index, row) in rows.enumerated() where index > detected.headerIndex {
            guard row.contains(where: { !$0.isEmpty }) else { continue }
            func cell(_ i: Int?) -> String { i.flatMap { $0 < row.count ? row[$0] : nil } ?? "" }

            let description = cell(map.description).split(whereSeparator: \.isWhitespace).joined(separator: " ")
            let folded = fold(description)
            guard let date = parseDate(cell(map.date), calendar: calendar),
                  !summaryKeywords.contains(where: { folded.contains($0) }) else {
                skipped += 1
                continue
            }

            var signed: Money?
            var fromDebitCredit = false
            if let amountColumn = map.amount, let value = Money.parse(cell(amountColumn)) {
                signed = value
            } else if let debit = Money.parse(cell(map.debit)), debit.minor != 0 {
                signed = -debit.magnitude
                fromDebitCredit = true
            } else if let credit = Money.parse(cell(map.credit)), credit.minor != 0 {
                signed = credit.magnitude
                fromDebitCredit = true
            }
            guard let signed, signed.minor != 0 else {
                skipped += 1
                continue
            }

            let installment = parseInstallmentCell(cell(map.installment)) ?? installmentMarker(in: description)
            raws.append(Raw(line: index, date: date, description: description, signed: signed,
                            fromDebitCredit: fromDebitCredit, installment: installment))
        }
        guard !raws.isEmpty else { throw ParseError.noRows }

        let expensesPositive: Bool
        switch expenseSign ?? profile.expenseSign {
        case .positive: expensesPositive = true
        case .negative: expensesPositive = false
        case .auto:
            let amountRows = raws.filter { !$0.fromDebitCredit }
            // Negatif satırda ödeme/iade ifadesi varsa bu bir kart ekstresidir: harcamalar pozitiftir.
            let creditMarkers = paymentKeywords + ["IADE"]
            let hasCardCredits = amountRows.contains { raw in
                raw.signed.isNegative && creditMarkers.contains { fold(raw.description).contains($0) }
            }
            let positives = amountRows.filter { $0.signed.minor > 0 }.count
            expensesPositive = hasCardCredits || positives >= amountRows.count - positives
        }

        let parsed = raws.map { raw -> StatementRow in
            let kind: StatementRowKind
            if raw.fromDebitCredit {
                kind = raw.signed.isNegative ? .expense : .income
            } else if expensesPositive {
                if raw.signed.minor > 0 {
                    kind = .expense
                } else {
                    let folded = fold(raw.description)
                    kind = paymentKeywords.contains { folded.contains($0) } ? .payment : .refund
                }
            } else {
                kind = raw.signed.isNegative ? .expense : .income
            }
            let amount = raw.signed.magnitude
            return StatementRow(lineNumber: raw.line, date: raw.date, description: raw.description, amount: amount,
                                kind: kind, installment: raw.installment,
                                importHash: importHash(date: raw.date, amount: amount, description: raw.description,
                                                       calendar: calendar))
        }
        return StatementParseResult(rows: parsed, skippedCount: skipped, headerIndex: detected.headerIndex,
                                    columns: map, expensesArePositive: expensesPositive)
    }

    // MARK: Alanlar

    /// "01.10.2026", "1/10/26", "2026-10-01", "01.10.2026 14:23", "02 Ekim 2026" ya da Excel seri numarası.
    public static func parseDate(_ text: String, calendar: Calendar = FinanceCalendar.calendar) -> Date? {
        let words = text.trimmingCharacters(in: .whitespaces).split(separator: " ").map(String.init)
        if words.count >= 3, let day = Int(words[0]), let month = monthNumber(words[1]), var year = Int(words[2]) {
            if year < 100 { year += 2000 }
            guard (1...31).contains(day), (2000...2100).contains(year),
                  let date = calendar.date(from: DateComponents(year: year, month: month, day: day)),
                  calendar.component(.day, from: date) == day else { return nil }
            return date
        }
        let token = words.first ?? ""
        guard !token.isEmpty else { return nil }

        if let serial = Double(token), serial > 20_000, serial < 80_000 {
            let base = calendar.date(from: DateComponents(year: 1899, month: 12, day: 30))!
            return calendar.date(byAdding: .day, value: Int(serial), to: base)
        }

        let parts = token.split(whereSeparator: { $0 == "." || $0 == "/" || $0 == "-" }).compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        var (day, month, year) = (parts[0], parts[1], parts[2])
        if parts[0] > 999 { (year, month, day) = (parts[0], parts[1], parts[2]) }
        if year < 100 { year += 2000 }
        guard (1...12).contains(month), (1...31).contains(day), (2000...2100).contains(year) else { return nil }
        let components = DateComponents(year: year, month: month, day: day)
        guard let date = calendar.date(from: components),
              calendar.component(.day, from: date) == day else { return nil }
        return date
    }

    private static let monthPrefixes = ["OCA", "SUB", "MAR", "NIS", "MAY", "HAZ", "TEM", "AGU", "EYL", "EKI", "KAS", "ARA"]

    /// "Ekim", "Eki", "EKİM", "Şubat" → ay numarası
    static func monthNumber(_ word: String) -> Int? {
        let folded = fold(word).filter(\.isLetter)
        guard folded.count >= 3 else { return nil }
        return monthPrefixes.firstIndex(of: String(folded.prefix(3))).map { $0 + 1 }
    }

    private static let keywordPattern = try! NSRegularExpression(
        pattern: #"(?:TAKSIT\w*|\bTKS?\b)\D{0,15}?\b(\d{1,2})\s*/\s*(\d{1,2})\b(?!\s*/\s*\d)"#)
    /// "4/9 TK" ya da Akbank'ın "3/2.taksit" (toplam/kaçıncı) yazımı.
    private static let trailingKeywordPattern = try! NSRegularExpression(
        pattern: #"\b(\d{1,2})\s*/\s*(\d{1,2})[.\s]*(?:TAKSIT|TKS?)\b"#)
    private static let parenthesizedPattern = try! NSRegularExpression(pattern: #"\((\d{1,2})\s*/\s*(\d{1,2})\)"#)

    /// Açıklamadaki "TAKSIT 3/6", "(2/12)", "4/9 TK" gibi işaretler. Tarih benzeri sayılar elenir.
    public static func installmentMarker(in text: String) -> InstallmentMarker? {
        let folded = fold(text)
        let range = NSRange(folded.startIndex..., in: folded)
        for pattern in [keywordPattern, trailingKeywordPattern, parenthesizedPattern] {
            guard let match = pattern.firstMatch(in: folded, range: range),
                  let first = Range(match.range(at: 1), in: folded), let second = Range(match.range(at: 2), in: folded),
                  var current = Int(folded[first]), var total = Int(folded[second]) else { continue }
            // Sonda "taksit" geçen yazımda büyük sayı toplamdır (Akbank: "12/1.taksit" = 12 taksitin 1.'si).
            if pattern === trailingKeywordPattern, current > total { swap(&current, &total) }
            if let marker = validMarker(current, total) { return marker }
        }
        return nil
    }

    private static func parseInstallmentCell(_ text: String) -> InstallmentMarker? {
        let numbers = text.split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) }
        guard numbers.count == 2 else { return nil }
        return validMarker(numbers[0], numbers[1])
    }

    private static func validMarker(_ current: Int, _ total: Int) -> InstallmentMarker? {
        guard (2...36).contains(total), (1...total).contains(current) else { return nil }
        return InstallmentMarker(current: current, total: total)
    }

    /// Aynı satırın ikinci kez içe aktarılmasını yakalamak için anahtar.
    public static func importHash(date: Date, amount: Money, description: String,
                                  calendar: Calendar = FinanceCalendar.calendar) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        let day = String(format: "%04d-%02d-%02d", c.year!, c.month!, c.day!)
        return "\(day)|\(amount.minor)|\(MerchantNormalizer.normalize(description))"
    }

    /// Türkçe karakterleri katlayıp büyük harfe çevirir; noktalama korunur.
    static func fold(_ text: String) -> String {
        text.folding(options: .diacriticInsensitive, locale: nil).uppercased(with: Locale(identifier: "en_US_POSIX"))
    }
}
