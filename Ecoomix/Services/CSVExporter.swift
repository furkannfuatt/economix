import Foundation
import EcoomixCore

/// Tüm işlemleri Excel'in Türkçe ayarlarıyla doğrudan açılan CSV'ye çevirir (BOM + noktalı virgül + ondalık virgül).
enum CSVExporter {
    static let header = ["Tarih", "Tür", "Tutar", "Kategori", "Hesap", "Hedef hesap", "İşyeri", "Not", "Taksit", "Kaynak"]

    static func csv(for entries: [LedgerEntry]) -> String {
        let lines = entries.sorted { $0.date < $1.date }.map { entry in
            [
                date(entry.date),
                entry.kind.title,
                amount(entry),
                entry.category?.name ?? "",
                entry.account?.name ?? "",
                entry.toAccount?.name ?? "",
                entry.merchant,
                entry.note,
                entry.installmentLabel ?? "",
                source(entry.source),
            ].map(escape).joined(separator: ";")
        }
        return "\u{FEFF}" + ([header.joined(separator: ";")] + lines).joined(separator: "\r\n") + "\r\n"
    }

    /// Paylaşım için geçici dosya: "ecoomix-islemler-2026-10-18.csv"
    static func writeTemporaryFile(for entries: [LedgerEntry]) throws -> URL {
        let c = FinanceCalendar.calendar.dateComponents([.year, .month, .day], from: .now)
        let name = String(format: "ecoomix-islemler-%04d-%02d-%02d.csv", c.year!, c.month!, c.day!)
        let url = URL.temporaryDirectory.appending(path: name)
        try csv(for: entries).write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private static func date(_ date: Date) -> String {
        let c = FinanceCalendar.calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%02d.%02d.%04d", c.day!, c.month!, c.year!)
    }

    private static func amount(_ entry: LedgerEntry) -> String {
        let minor = entry.amountMinor
        let text = "\(minor / 100)," + String(format: "%02d", minor % 100)
        return entry.kind == .expense ? "-" + text : text
    }

    private static func source(_ source: EntrySource) -> String {
        switch source {
        case .manual: "Elle"
        case .imported: "İçe aktarma"
        case .recurring: "Düzenli"
        case .installment: "Taksit"
        }
    }

    private static func escape(_ field: String) -> String {
        guard field.contains(where: { $0 == ";" || $0 == "\"" || $0.isNewline }) else { return field }
        return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}
