import SwiftUI
import UIKit
import Charts
import EcoomixCore

/// Grafik renkleri — dataviz doğrulayıcısından geçmiş açık/koyu adımlar.
/// Metinler seri rengini değil birincil/ikincil metin rengini kullanır.
enum ChartPalette {
    /// Tek serili grafikler (taksit yükü, kategori trendi).
    static let single = Color(light: "#0E8F6B", dark: "#1FA676")
    static let income = Color(light: "#1BAF7A", dark: "#199E70")
    static let expense = Color(light: "#EB6834", dark: "#D95926")
    static let other = Color(light: "#A8A7A2", dark: "#6B6A66")
}

extension Color {
    init(light: String, dark: String) {
        self.init(uiColor: UIColor { traits in
            UIColor(Color(hex: traits.userInterfaceStyle == .dark ? dark : light))
        })
    }
}

enum ChartFormat {
    /// Eksen etiketi: 12500 → "12,5 B", 850 → "850"
    static func axis(_ lira: Double) -> String {
        let value = abs(lira)
        let sign = lira < 0 ? "-" : ""
        if value >= 1_000_000 { return sign + trimmed(value / 1_000_000) + " Mn" }
        if value >= 1_000 { return sign + trimmed(value / 1_000) + " B" }
        return sign + String(Int(value))
    }

    private static func trimmed(_ value: Double) -> String {
        let rounded = (value * 10).rounded() / 10
        return rounded == rounded.rounded()
            ? String(Int(rounded))
            : String(format: "%.1f", rounded).replacingOccurrences(of: ".", with: ",")
    }
}

enum ChartAxes {
    /// En fazla `maxCount` eşit aralıklı etiket konumu. Sağ kenara alanın `edgeFraction` kadarından yakın olanlar
    /// atlanır; orada etiket taşar ve kesilir ("26…").
    static func labelDates(_ dates: [Date], domain: ClosedRange<Date>, maxCount: Int, edgeFraction: Double = 0.08) -> [Date] {
        let step = max(1, Int((Double(dates.count) / Double(maxCount)).rounded(.up)))
        let width = domain.upperBound.timeIntervalSince(domain.lowerBound)
        let limit = domain.upperBound.addingTimeInterval(-width * edgeFraction)
        return stride(from: 0, to: dates.count, by: step).map { dates[$0] }.filter { $0 <= limit }
    }

    /// Çizginin üstündeki küçük etiket ("Ort. 2.589 ₺"); çubukların üstüne denk gelse de okunur.
    static func lineLabel(_ text: String) -> some View {
        Text(text)
            .font(.caption2)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 4)
            .background(Color(.secondarySystemGroupedBackground).opacity(0.85), in: .capsule)
    }

    /// Soldaki para ekseni: "12,5 B" etiketleri, silik ızgara.
    static func money() -> some AxisContent {
        AxisMarks(position: .leading) { value in
            AxisGridLine().foregroundStyle(Color.secondary.opacity(0.15))
            AxisValueLabel { Text(ChartFormat.axis(value.as(Double.self) ?? 0)) }
        }
    }
}

/// Seçili çubuğun üzerinde görünen küçük bilgi kutusu.
struct ChartCallout: View {
    let title: String
    let lines: [(String, String)]

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption.weight(.semibold))
            ForEach(lines, id: \.0) { line in
                HStack(spacing: 6) {
                    Text(line.0).foregroundStyle(.secondary)
                    Text(line.1).monospacedDigit()
                }
                .font(.caption2)
            }
        }
        .padding(8)
        .background(.regularMaterial, in: .rect(cornerRadius: 10))
    }
}
