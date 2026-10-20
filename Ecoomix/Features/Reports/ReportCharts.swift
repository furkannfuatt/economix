import SwiftUI
import Charts
import EcoomixCore

/// Zamana göre gider: gün, hafta ya da bütçe ayı çubukları, ortalama çizgisi, en yüksek dönem ve döküm listesi.
/// Çubuklar kovanın gerçek süresini kaplar; dönem sınırında kırpılan hafta/ay daha dar görünür.
struct SpendingBarChart: View {
    let buckets: [SpendingBucket]
    let granularity: ReportGranularity
    let rule: MonthRule
    var now: Date = .now

    @State private var selectedDate: Date?
    @State private var showsBreakdown = false

    var body: some View {
        let elapsed = buckets.filter { $0.period.start <= now }
        let total = elapsed.map(\.amount).sum()
        let average = elapsed.count > 1 && total.minor > 0 ? total.scaled(numerator: 1, denominator: elapsed.count) : nil
        let selected = selectedDate.flatMap { date in buckets.first { $0.period.contains(date) } }
        let peak = elapsed.max { $0.amount < $1.amount }.flatMap { $0.amount.minor > 0 ? $0 : nil }

        VStack(alignment: .leading, spacing: 12) {
            Chart {
                ForEach(buckets, id: \.period.start) { bucket in
                    let span = barSpan(bucket.period)
                    RectangleMark(xStart: .value("Başlangıç", span.lowerBound), xEnd: .value("Bitiş", span.upperBound),
                                  yStart: .value("Sıfır", 0.0), yEnd: .value("Gider", bucket.amount.lira))
                        .cornerRadius(3)
                        .foregroundStyle(ChartPalette.expense.opacity(selected == nil || selected == bucket ? 1 : 0.35))
                }
                if let average {
                    RuleMark(y: .value("Ortalama", average.lira))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                        .foregroundStyle(Color.secondary)
                        .annotation(position: .top, alignment: .trailing) {
                            ChartAxes.lineLabel("Ort. \(average.formatted(decimals: false))")
                        }
                }
                if let selected {
                    RuleMark(x: .value("Seçili", midpoint(selected.period)))
                        .foregroundStyle(.clear)
                        .annotation(position: .top, overflowResolution: .init(x: .fit, y: .disabled)) {
                            ChartCallout(title: title(of: selected), lines: [
                                ("Gider", selected.amount.formatted()),
                                ("İşlem", "\(selected.count)"),
                            ])
                        }
                }
            }
            .chartXScale(domain: buckets.first!.period.start...buckets.last!.period.end)
            .chartXSelection(value: $selectedDate)
            .chartXAxis {
                AxisMarks(values: axisDates) { value in
                    AxisValueLabel {
                        if let date = value.as(Date.self) { Text(axisLabel(date)) }
                    }
                }
            }
            .chartYAxis { ChartAxes.money() }
            .frame(height: 190)

            if let peak {
                Label("En yüksek \(unitName): \(shortTitle(of: peak)) · \(peak.amount.formatted(decimals: false))",
                      systemImage: "arrow.up.to.line")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if !elapsed.isEmpty {
                DisclosureGroup(isExpanded: $showsBreakdown) {
                    VStack(spacing: 10) {
                        ForEach(elapsed.reversed(), id: \.period.start) { bucket in
                            HStack {
                                Text(title(of: bucket)).font(.subheadline)
                                Spacer()
                                if bucket.count > 0 {
                                    Text("\(bucket.count) işlem")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Text(bucket.amount.formatted(decimals: false))
                                    .font(.subheadline.weight(.medium))
                                    .monospacedDigit()
                                    .foregroundStyle(bucket.amount.isZero ? .secondary : .primary)
                                    .frame(minWidth: 80, alignment: .trailing)
                            }
                        }
                    }
                    .padding(.top, 8)
                } label: {
                    Text("Dökümü göster").font(.subheadline)
                }
            }
        }
    }

    /// Çubuğun kapladığı süre: kova, çubuklar arasında boşluk kalsın diye iki yandan %12 içeride.
    private func barSpan(_ period: DatePeriod) -> ClosedRange<Date> {
        let inset = period.end.timeIntervalSince(period.start) * 0.12
        return period.start.addingTimeInterval(inset)...period.end.addingTimeInterval(-inset)
    }

    private func midpoint(_ period: DatePeriod) -> Date {
        period.start.addingTimeInterval(period.end.timeIntervalSince(period.start) / 2)
    }

    /// En fazla 6 etiket, kovanın ortasında. Ay adları kısa; sağ kenarda da sığar.
    private var axisDates: [Date] {
        ChartAxes.labelDates(buckets.map { midpoint($0.period) },
                             domain: buckets.first!.period.start...buckets.last!.period.end,
                             maxCount: 6, edgeFraction: granularity == .month ? 0 : 0.12)
    }

    private var spansMonths: Bool {
        guard let first = buckets.first, let last = buckets.last else { return false }
        return YearMonth(date: first.period.start) != YearMonth(date: last.period.start)
    }

    private func axisLabel(_ date: Date) -> String {
        guard let bucket = buckets.first(where: { $0.period.contains(date) }) else { return "" }
        let start = bucket.period.start
        switch granularity {
        case .day: return spansMonths ? TR.dayShortMonth(start) : "\(FinanceCalendar.calendar.component(.day, from: start))"
        case .week: return TR.dayShortMonth(start)
        case .month: return rule.month(containing: start).shortTitle
        }
    }

    private var unitName: String {
        switch granularity {
        case .day: "gün"
        case .week: "hafta"
        case .month: "ay"
        }
    }

    /// Bilgi kutusu ve döküm satırı: "18 Ekim Cumartesi", "13–19 Eki", "Ekim 2026" / "Kasım · 23 Eki – 22 Kas".
    private func title(of bucket: SpendingBucket) -> String {
        switch granularity {
        case .day: TR.dayHeader(bucket.period.start)
        case .week, .month: shortTitle(of: bucket)
        }
    }

    private func shortTitle(of bucket: SpendingBucket) -> String {
        switch granularity {
        case .day:
            return TR.dayMonth(bucket.period.start)
        case .week:
            return bucket.period.shortTitle()
        case .month:
            let month = rule.month(containing: bucket.period.start)
            return rule.isCalendarMonth && bucket.period == rule.period(of: month)
                ? month.title
                : "\(month.monthName) · \(bucket.period.shortTitle())"
        }
    }
}

/// Dönem içinde biriken gider: bu dönem (bugüne kadar) ve aynı güne hizalanmış önceki dönem; ayda bütçe çizgisi.
struct CumulativeSpendingChart: View {
    /// Bu dönem, bugüne kadar.
    let current: [DayAmount]
    /// Önceki dönemin tamamı.
    let previous: [DayAmount]
    /// Bu dönemin günleri (x ekseni).
    let days: [Date]
    var budget: Money?

    @State private var selectedDate: Date?

    private static let currentName = "Bu dönem"
    private static let previousName = "Önceki dönem"

    private struct Point: Identifiable {
        let series: String
        let day: Date
        let amount: Money
        var id: String { "\(series)-\(day.timeIntervalSinceReferenceDate)" }
    }

    var body: some View {
        // Önceki dönem gün sırasıyla bu dönemin tarihlerine yerleşir (1. gün → 1. gün).
        // Önceki dönemde hiç harcama yoksa (veri başlamadan önce) sıfırda düz çizgi çizilmez.
        let hasPrevious = (previous.last?.amount.minor ?? 0) > 0
        let previousPoints = hasPrevious ? zip(days, previous).map { Point(series: Self.previousName, day: $0, amount: $1.amount) } : []
        let currentPoints = current.map { Point(series: Self.currentName, day: $0.day, amount: $0.amount) }
        let selectedIndex = selectedDate.flatMap { date in days.lastIndex { $0 <= date } }
        let pace = hasPrevious ? SpendingPace(current: current, previous: previous, periodDays: days.count) : nil

        VStack(alignment: .leading, spacing: 10) {
            Chart {
                ForEach(previousPoints + currentPoints) { point in
                    LineMark(x: .value("Gün", point.day), y: .value("Tutar", point.amount.lira),
                             series: .value("Seri", point.series))
                        .foregroundStyle(by: .value("Seri", point.series))
                        .lineStyle(point.series == Self.currentName
                                   ? StrokeStyle(lineWidth: 2, lineCap: .round)
                                   : StrokeStyle(lineWidth: 2, lineCap: .round, dash: [4, 4]))
                }
                if let budget, budget.minor > 0 {
                    RuleMark(y: .value("Bütçe", budget.lira))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [2, 3]))
                        .foregroundStyle(Color.secondary)
                        .annotation(position: .top, alignment: .leading) {
                            ChartAxes.lineLabel("Bütçe \(budget.formatted(decimals: false))")
                        }
                }
                if let selectedIndex {
                    let day = days[selectedIndex]
                    RuleMark(x: .value("Gün", day))
                        .lineStyle(StrokeStyle(lineWidth: 1))
                        .foregroundStyle(Color.secondary.opacity(0.4))
                        .annotation(position: .top, overflowResolution: .init(x: .fit, y: .disabled)) {
                            ChartCallout(title: "\(TR.dayMonth(day)) · \(selectedIndex + 1). gün",
                                         lines: calloutLines(at: selectedIndex))
                        }
                    if selectedIndex < current.count {
                        PointMark(x: .value("Gün", day), y: .value("Tutar", current[selectedIndex].amount.lira))
                            .symbolSize(50)
                            .foregroundStyle(ChartPalette.expense)
                    }
                }
            }
            .chartForegroundStyleScale([Self.currentName: ChartPalette.expense, Self.previousName: ChartPalette.other])
            .chartLegend(position: .top, alignment: .leading, spacing: 14)
            .chartLegend(hasPrevious ? .visible : .hidden)
            .chartXScale(domain: days.first!...days.last!)
            .chartXSelection(value: $selectedDate)
            .chartXAxis {
                AxisMarks(values: axisDays) { value in
                    AxisValueLabel {
                        if let date = value.as(Date.self) { Text(TR.dayShortMonth(date)) }
                    }
                }
            }
            .chartYAxis { ChartAxes.money() }
            .frame(height: 210)

            if let pace {
                Text(pace.isPartial
                     ? "Bugüne kadar \(pace.current.formatted(decimals: false)) · önceki dönemin aynı gününde \(pace.previous.formatted(decimals: false))"
                     : "Bu dönem \(pace.current.formatted(decimals: false)) · önceki dönem \(pace.previous.formatted(decimals: false))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if let spent = current.last {
                Text("Bugüne kadar \(spent.amount.formatted(decimals: false)) · önceki dönemde kayıt yok")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var axisDays: [Date] {
        ChartAxes.labelDates(days, domain: days.first!...days.last!, maxCount: 5)
    }

    private func calloutLines(at index: Int) -> [(String, String)] {
        var lines: [(String, String)] = []
        if index < current.count { lines.append((Self.currentName, current[index].amount.formatted(decimals: false))) }
        if index < previous.count { lines.append((Self.previousName, previous[index].amount.formatted(decimals: false))) }
        return lines
    }
}

/// Pazartesiden pazara gün başına ortalama gider; en yüksek gün doğrudan etiketlenir.
struct WeekdayChart: View {
    let days: [WeekdayAverage]

    @State private var selectedName: String?

    var body: some View {
        let peak = days.max { $0.average < $1.average }.flatMap { $0.average.minor > 0 ? $0 : nil }
        let active = selectedName.flatMap { name in days.first { $0.shortTitle == name } }

        VStack(alignment: .leading, spacing: 10) {
            Chart(days, id: \.index) { day in
                BarMark(x: .value("Gün", day.shortTitle), y: .value("Ortalama", day.average.lira), width: .ratio(0.6))
                    .cornerRadius(3)
                    .foregroundStyle(ChartPalette.expense.opacity(active == nil || active == day ? 1 : 0.35))
                    .annotation(position: .top) {
                        if active == nil, day == peak {
                            Text(day.average.formatted(decimals: false))
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                    }
                if active == day {
                    RuleMark(x: .value("Gün", day.shortTitle))
                        .foregroundStyle(.clear)
                        .annotation(position: .top, overflowResolution: .init(x: .fit, y: .disabled)) {
                            ChartCallout(title: day.title, lines: [
                                ("Ortalama", day.average.formatted(decimals: false)),
                                ("Toplam", day.total.formatted(decimals: false)),
                                ("Gün sayısı", "\(day.dayCount)"),
                            ])
                        }
                }
            }
            .chartXSelection(value: $selectedName)
            .chartXAxis { AxisMarks { AxisValueLabel() } }
            .chartYAxis { ChartAxes.money() }
            .frame(height: 170)

            Text("Her hafta günü için dönemdeki ortalama harcama")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
