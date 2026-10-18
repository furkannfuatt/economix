import Foundation
import PDFKit

/// PDF ekstreden görsel satırları çıkarır. Metin parçaları sayfadaki konumlarına göre gruplanır;
/// böylece metni sütun sütun saklayan PDF'lerde de satırlar doğru kurulur.
public enum PDFTextReader {
    public enum ReadError: Error {
        case notPDF
        case noText
    }

    public static func lines(from data: Data) throws -> [String] {
        guard let document = PDFDocument(data: data) else { throw ReadError.notPDF }
        var result: [String] = []
        for index in 0..<document.pageCount {
            if let page = document.page(at: index) { result += lines(on: page) }
        }
        guard !result.isEmpty else { throw ReadError.noText }
        return result
    }

    /// PDFKit'in satır seçimleri her metin parçasını konumuyla verir (karakter indeksleri `page.string` ile
    /// hizalı olmadığından karakter düzeyinde konum kullanılmaz). Parçalar yüksekliğe göre satırlara toplanır.
    static func lines(on page: PDFPage) -> [String] {
        guard let selection = page.selection(for: page.bounds(for: .mediaBox)) else { return [] }
        let pieces: [(text: String, rect: CGRect)] = selection.selectionsByLine().compactMap { line in
            let text = (line.string ?? "").split(whereSeparator: \.isNewline).joined(separator: " ")
                .trimmingCharacters(in: .whitespaces)
            let rect = line.bounds(for: page)
            return text.isEmpty || rect.isNull ? nil : (text, rect)
        }

        // PDF koordinatlarında y yukarı doğru artar: yukarıdan aşağıya sırala, aynı yükseklikteki parçaları birleştir.
        var rows: [(midY: CGFloat, pieces: [(text: String, rect: CGRect)])] = []
        for piece in pieces.sorted(by: { $0.rect.midY > $1.rect.midY }) {
            let tolerance = max(2, piece.rect.height * 0.5)
            if let last = rows.last, abs(last.midY - piece.rect.midY) <= tolerance {
                rows[rows.count - 1].pieces.append(piece)
            } else {
                rows.append((piece.rect.midY, [piece]))
            }
        }
        return rows.map { row in
            row.pieces.sorted { $0.rect.minX < $1.rect.minX }.map(\.text).joined(separator: " ")
        }
    }
}

/// PDF satırlarından işlem satırlarını seçip kolonlara ayırır: tarihle başlayan ve tutarla biten satırlar.
public enum PDFStatementLines {
    public static let header = ["Tarih", "Açıklama", "Taksit", "Tutar"]
    public static let columns = ColumnMap(date: 0, description: 1, amount: 3, installment: 2)

    public static func rows(from lines: [String], calendar: Calendar = FinanceCalendar.calendar) -> [[String]] {
        [header] + lines.compactMap { row(from: $0, calendar: calendar) }
    }

    private static let numericDate = try! NSRegularExpression(pattern: #"^\d{1,2}[./-]\d{1,2}[./-]\d{2,4}$"#)
    /// "1.234,56", "1,234.56", "245.50", "299,90-", "5,000.00(-)", "25.00()"
    private static let money = try! NSRegularExpression(
        pattern: #"^-?\(?(\d{1,3}([.,]\d{3})+|\d+)[.,]\d{2}\)?(-|\(-\)|\(\+\)|\(\))?$"#)
    /// Akbank'ın "kalan taksit" kolonu: "990.00x1"
    private static let remainingInstallments = try! NSRegularExpression(pattern: #"^\d[\d.,]*x\d+$"#)
    private static let installment = try! NSRegularExpression(pattern: #"^(\d{1,2})/(\d{1,2})$"#)

    static func row(from line: String, calendar: Calendar) -> [String]? {
        var tokens = line.split(whereSeparator: \.isWhitespace).map(String.init)
        guard let first = leadingDate(tokens, calendar: calendar) else { return nil }
        tokens.removeFirst(first.consumed)
        // Valör/kayıt tarihi gibi ikinci bir tarih varsa atılır.
        if let second = leadingDate(tokens, calendar: calendar) { tokens.removeFirst(second.consumed) }

        // Sondan: para birimi işaretleri ve tutarlar (bonus/puan kolonu varsa son tutar asıl tutardır).
        var amounts: [String] = []
        var pendingCredit = false
        while let last = tokens.last {
            if ["TL", "₺", "TRY"].contains(last.uppercased()) {
                tokens.removeLast()
            } else if amounts.isEmpty, matches(remainingInstallments, last) {
                tokens.removeLast()
            } else if amounts.isEmpty, ["(-)", "()"].contains(last) {
                pendingCredit = true
                tokens.removeLast()
            } else if matches(money, last) {
                amounts.insert(normalizedAmount(last, credit: pendingCredit && amounts.isEmpty), at: 0)
                tokens.removeLast()
            } else if (last == "-" || last == "+"), !amounts.isEmpty {
                if last == "-" { amounts[0] = "-" + amounts[0] }
                tokens.removeLast()
            } else {
                break
            }
        }
        guard let amount = amounts.last else { return nil }

        var installmentText = ""
        if let last = tokens.last, isInstallment(last) {
            installmentText = last
            tokens.removeLast()
        }
        let description = tokens.joined(separator: " ")
        guard !description.isEmpty else { return nil }
        return [first.normalized, description, installmentText, amount]
    }

    /// "5,000.00(-)" / "25.00()" → "-5,000.00" / "-25.00"; "(+)" atılır.
    private static func normalizedAmount(_ token: String, credit: Bool) -> String {
        var text = token
        var negative = credit
        for suffix in ["(-)", "()"] where text.hasSuffix(suffix) {
            text.removeLast(suffix.count)
            negative = true
        }
        if text.hasSuffix("(+)") { text.removeLast(3) }
        return negative && !text.hasPrefix("-") ? "-" + text : text
    }

    private static func leadingDate(_ tokens: [String], calendar: Calendar) -> (normalized: String, consumed: Int)? {
        guard let first = tokens.first else { return nil }
        if matches(numericDate, first), let date = StatementParser.parseDate(first, calendar: calendar) {
            return (format(date, calendar), 1)
        }
        if tokens.count >= 3, first.count <= 2, first.allSatisfy(\.isNumber),
           let date = StatementParser.parseDate(tokens[0...2].joined(separator: " "), calendar: calendar) {
            return (format(date, calendar), 3)
        }
        return nil
    }

    private static func isInstallment(_ token: String) -> Bool {
        let range = NSRange(token.startIndex..., in: token)
        guard let match = installment.firstMatch(in: token, range: range),
              let current = Int(token[Range(match.range(at: 1), in: token)!]),
              let total = Int(token[Range(match.range(at: 2), in: token)!]) else { return false }
        return (2...36).contains(total) && (1...total).contains(current)
    }

    private static func matches(_ regex: NSRegularExpression, _ text: String) -> Bool {
        regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
    }

    private static func format(_ date: Date, _ calendar: Calendar) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%02d.%02d.%04d", c.day!, c.month!, c.year!)
    }
}

/// Okuma sorunlarında paylaşılacak gizlenmiş biçim örneği: rakamlar 9, harfler X/x olur;
/// yalnızca ekstre başlık kelimeleri ve ay adları korunur.
public enum StatementStructure {
    private static let exactKeywords: Set<String> = [
        "TL", "TRY", "NO", "SON", "OCA", "SUB", "MAR", "NIS", "MAY", "HAZ", "TEM", "AGU", "EYL", "EKI", "KAS", "ARA",
    ]
    private static let prefixKeywords = [
        "TARIH", "ISLEM", "ACIKLAMA", "TUTAR", "TAKSIT", "BONUS", "PUAN", "ODEME", "IADE", "TOPLAM", "DONEM",
        "BORC", "ALACAK", "ASGARI", "KESIM", "HESAP", "EKSTRE", "ONCEKI", "DEVREDEN", "VALOR", "ISYERI", "KART",
        "OCAK", "SUBAT", "MART", "NISAN", "MAYIS", "HAZIRAN", "TEMMUZ", "AGUSTOS", "EYLUL", "EKIM", "KASIM", "ARALIK",
    ]

    public static func masked(lines: [String], limit: Int = 120) -> [String] {
        lines.prefix(limit).map { line in
            line.split(separator: " ", omittingEmptySubsequences: false).map { token in
                isKeyword(String(token)) ? String(token) : mask(String(token))
            }
            .joined(separator: " ")
        }
    }

    private static func isKeyword(_ token: String) -> Bool {
        let letters = StatementParser.fold(token).filter(\.isLetter)
        guard !letters.isEmpty else { return false }
        return exactKeywords.contains(letters) || prefixKeywords.contains { letters.hasPrefix($0) }
    }

    private static func mask(_ token: String) -> String {
        String(token.map { character -> Character in
            if character.isNumber { return "9" }
            if character.isLetter { return character.isUppercase ? "X" : "x" }
            return character
        })
    }
}
