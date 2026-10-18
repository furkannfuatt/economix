import Foundation
import CoreXLSX

/// İlk çalışma sayfasını metin hücreli satırlara çevirir; boş hücre ve satırlarla kolon/satır hizası korunur.
public enum XLSXReader {
    public enum ReadError: Error {
        case noWorksheet
    }

    public static func rows(from data: Data) throws -> [[String]] {
        let file = try XLSXFile(data: data)
        let sharedStrings = try file.parseSharedStrings()
        guard let workbook = try file.parseWorkbooks().first,
              let path = try file.parseWorksheetPathsAndNames(workbook: workbook).first?.path
        else { throw ReadError.noWorksheet }

        let worksheet = try file.parseWorksheet(at: path)
        var result: [[String]] = []
        for row in worksheet.data?.rows ?? [] {
            // Atlanan satırlar boş satır olarak eklenir (r numaraları 1'den başlar).
            while result.count < Int(row.reference) - 1 { result.append([]) }

            var cells: [String] = []
            for cell in row.cells {
                let column = columnIndex(cell.reference.column.value)
                while cells.count < column { cells.append("") }
                let raw = sharedStrings.flatMap { cell.stringValue($0) } ?? cell.inlineString?.text ?? cell.value ?? ""
                cells.append(normalizedNumber(raw).trimmingCharacters(in: .whitespacesAndNewlines))
            }
            while cells.last?.isEmpty == true { cells.removeLast() }
            result.append(cells)
        }
        return result
    }

    /// "A" → 0, "C" → 2, "AA" → 26
    static func columnIndex(_ letters: String) -> Int {
        letters.unicodeScalars.reduce(0) { $0 * 26 + Int($1.value) - 64 } - 1
    }

    /// Excel'in kayan nokta artığını ("1234.5599999999999") iki haneye yuvarlar.
    private static func normalizedNumber(_ text: String) -> String {
        guard let fraction = text.split(separator: ".").dropFirst().first, fraction.count > 2,
              fraction.allSatisfy(\.isNumber), let value = Double(text) else { return text }
        let rounded = (value * 100).rounded() / 100
        var formatted = String(format: "%.2f", rounded)
        while formatted.hasSuffix("0") { formatted.removeLast() }
        if formatted.hasSuffix(".") { formatted.removeLast() }
        return formatted
    }
}
