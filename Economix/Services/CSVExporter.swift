import Foundation
import EconomixCore

/// Tüm işlemleri Excel'in Türkçe ayarlarıyla doğrudan açılan CSV'ye çevirir (BOM + noktalı virgül + ondalık virgül).
enum CSVExporter {
    static let header = ["Tarih", "Tür", "Tutar", "Kategori", "Hesap", "Hedef hesap", "İşyeri", "Not", "Taksit", "Kaynak"]

    static func csv(for entries: [LedgerEntry]) -> String {
        let lines = entries.sorted { $0.date < $1.date }.map { entry in
            [
                date(entry.date),
                entry.kind.title,
                amount(entry),
                neutralized(entry.category?.name ?? ""),
                neutralized(entry.account?.name ?? ""),
                neutralized(entry.toAccount?.name ?? ""),
                neutralized(entry.merchant),
                neutralized(entry.note),
                neutralized(entry.installmentLabel ?? ""),
                source(entry.source),
            ].map(escape).joined(separator: ";")
        }
        return "\u{FEFF}" + ([header.joined(separator: ";")] + lines).joined(separator: "\r\n") + "\r\n"
    }

    private static let filePrefix = "economix-islemler-"

    /// Paylaşım için geçici dosya: "economix-islemler-2026-10-18.csv". Cihaz kilitliyken okunamaz;
    /// önceki dışa aktarmalardan kalanlar önce silinir.
    static func writeTemporaryFile(for entries: [LedgerEntry]) throws -> URL {
        removeTemporaryFiles()
        let c = FinanceCalendar.calendar.dateComponents([.year, .month, .day], from: .now)
        let name = String(format: "\(filePrefix)%04d-%02d-%02d.csv", c.year!, c.month!, c.day!)
        let url = URL.temporaryDirectory.appending(path: name)
        try Data(csv(for: entries).utf8).write(to: url, options: [.atomic, .completeFileProtection])
        return url
    }

    /// Geçici klasördeki dışa aktarma dosyalarını siler.
    static func removeTemporaryFiles() {
        let directory = URL.temporaryDirectory
        let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        for name in names where name.hasPrefix(filePrefix) && name.hasSuffix(".csv") {
            try? FileManager.default.removeItem(at: directory.appending(path: name))
        }
    }

    private static func date(_ date: Date) -> String {
        let c = FinanceCalendar.calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%02d.%02d.%04d", c.day!, c.month!, c.year!)
    }

    private static func amount(_ entry: LedgerEntry) -> String {
        let minor = entry.amountMinor
        let text = "\(minor / 100)," + String(format: "%02d", minor % 100)
        return entry.kind == .expense || entry.kind == .investment ? "-" + text : text
    }

    private static func source(_ source: EntrySource) -> String {
        switch source {
        case .manual: "Elle"
        case .imported: "İçe aktarma"
        case .recurring: "Düzenli"
        case .installment: "Taksit"
        }
    }

    /// Excel ve benzerleri =, +, -, @ (ve sekme, satır başı) ile başlayan hücreyi formül sayar. İçe aktarılan
    /// bir işyeri adı ("=HYPERLINK(…)") dosya açılınca çalışmasın diye metin alanlarının başına ' eklenir.
    private static func neutralized(_ field: String) -> String {
        guard let first = field.unicodeScalars.first, "=+-@\t\r".unicodeScalars.contains(first) else { return field }
        return "'" + field
    }

    private static func escape(_ field: String) -> String {
        guard field.contains(where: { $0 == ";" || $0 == "\"" || $0.isNewline }) else { return field }
        return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}
