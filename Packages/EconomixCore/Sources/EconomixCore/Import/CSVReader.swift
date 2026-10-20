import Foundation

/// Banka CSV dışa aktarımları için hafif okuyucu: ayraç otomatik (; , sekme), tırnak, BOM, CRLF.
public enum CSVReader {
    public static func rows(from text: String) -> [[String]] {
        var source = text
        if source.hasPrefix("\u{FEFF}") { source.removeFirst() }
        let delimiter = detectDelimiter(in: source)

        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var inQuotes = false
        var iterator = Array(source).makeIterator()
        var pending: Character? = nil

        func endField() {
            row.append(field.trimmingCharacters(in: .whitespaces))
            field = ""
        }
        func endRow() {
            endField()
            if !(row.count == 1 && row[0].isEmpty) { rows.append(row) }
            row = []
        }

        while let char = pending ?? iterator.next() {
            pending = nil
            if inQuotes {
                if char == "\"" {
                    let next = iterator.next()
                    if next == "\"" {
                        field.append("\"")
                    } else {
                        inQuotes = false
                        pending = next
                    }
                } else {
                    field.append(char)
                }
                continue
            }
            switch char {
            case "\"" where field.isEmpty: inQuotes = true
            case delimiter: endField()
            case "\r\n", "\n", "\r": endRow()
            default: field.append(char)
            }
        }
        if !field.isEmpty || !row.isEmpty { endRow() }
        return rows
    }

    static func detectDelimiter(in text: String) -> Character {
        let firstLine = text.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
        var counts: [Character: Int] = [";": 0, ",": 0, "\t": 0]
        var inQuotes = false
        for char in firstLine {
            if char == "\"" { inQuotes.toggle() }
            if !inQuotes, counts[char] != nil { counts[char]! += 1 }
        }
        // Eşitlikte noktalı virgül: Türk bankaları ondalıkta virgül kullandığı için ; ayraç tercih eder.
        let best = counts.max { a, b in a.value != b.value ? a.value < b.value : a.key != ";" }
        return (best?.value ?? 0) > 0 ? best!.key : ";"
    }
}
