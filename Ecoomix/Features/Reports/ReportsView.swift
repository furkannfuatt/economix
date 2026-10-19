import SwiftUI
import SwiftData
import Charts
import EcoomixCore

enum ReportSpan: Int, CaseIterable, Identifiable {
    case month = 1, quarter = 3, half = 6, year = 12

    var id: Int { rawValue }
    var title: String {
        switch self {
        case .month: "Ay"
        case .quarter: "3 Ay"
        case .half: "6 Ay"
        case .year: "Yıl"
        }
    }
}

struct ReportsView: View {
    @Query private var entries: [LedgerEntry]
    @Query(sort: \EntryCategory.sortOrder) private var categories: [EntryCategory]

    @AppStorage("reportMode") private var modeRaw = ReportMode.cashFlow.rawValue
    @AppStorage(MonthSettings.key) private var monthStartDay = 1
    @State private var span: ReportSpan = .half
    /// Son ayın içinde bulunulan döneme uzaklığı (0 = bu dönem).
    @State private var anchorOffset = 0
    @State private var selectedDate: Date?

    private var mode: ReportMode { ReportMode(rawValue: modeRaw) ?? .cashFlow }
    private var rule: MonthRule { MonthRule(startDay: monthStartDay) }
    private var anchor: YearMonth { rule.current().adding(months: anchorOffset) }

    var body: some View {
        let months = (0..<span.rawValue).map { anchor.adding(months: -(span.rawValue - 1) + $0) }
        let period = rule.period(of: months.first!...months.last!)
        let txs = ReportBuilder.normalized(entries.map(\.snapshot), mode: mode)
        let summary = ReportBuilder.summary(txs, in: period)
        let monthly = ReportBuilder.monthlyTotals(txs, months: months, rule: rule)

        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    Picker("Dönem", selection: $span) {
                        ForEach(ReportSpan.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)

                    periodNavigator(months: months)

                    Card {
                        HStack(alignment: .top) {
                            StatTile(title: "Gelir", value: summary.income, tint: .income)
                            StatTile(title: "Gider", value: summary.expense)
                            StatTile(title: "Net", value: summary.net,
                                     tint: summary.net.isNegative ? .expense : .primary,
                                     caption: summary.savingsRate.map { "Tasarruf \(TR.percent($0))" })
                        }
                        if !summary.investment.isZero {
                            Label("Yatırıma ayrılan \(summary.investment.formatted(decimals: false)) (gider ve nete dahil değil)",
                                  systemImage: "chart.line.uptrend.xyaxis")
                                .font(.caption)
                                .foregroundStyle(Color.investment)
                        }
                        if span.rawValue > 1 {
                            Text("Aylık ortalama gider \(summary.expense.scaled(numerator: 1, denominator: span.rawValue).formatted(decimals: false))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    if span == .month {
                        Card("Günlük harcama") { dailyChart(txs: txs, month: anchor) }
                    } else {
                        Card("Gelir ve gider") { incomeExpenseChart(monthly) }
                        Card("Tasarruf oranı") { savingsRateChart(monthly) }
                    }

                    categoriesCard(txs: txs, period: period, months: months)
                    merchantsCard(txs: txs, period: period)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Raporlar")
            .navigationDestination(for: CategoryReportDestination.self) { destination in
                CategoryReportView(categoryID: destination.categoryID, anchor: anchor, mode: mode, rule: rule)
            }
            .toolbar {
                Menu {
                    Picker("Görünüm", selection: $modeRaw) {
                        ForEach(ReportMode.allCases, id: \.self) { Text($0.title).tag($0.rawValue) }
                    }
                } label: {
                    Label(mode.title, systemImage: "slider.horizontal.3")
                }
            }
        }
    }

    private func periodNavigator(months: [YearMonth]) -> some View {
        HStack {
            Button("Önceki", systemImage: "chevron.left") { anchorOffset -= span.rawValue }
                .labelStyle(.iconOnly)
            Spacer()
            VStack(spacing: 2) {
                Text(months.count == 1 ? months[0].title : "\(months.first!.shortTitle) \(months.first!.year) – \(months.last!.shortTitle) \(months.last!.year)")
                    .font(.headline)
                Text(rule.isCalendarMonth
                     ? (mode == .cashFlow ? "Taksitler aylara yayılmış" : "Taksitli alımlar alım ayında")
                     : rule.rangeTitle(of: months.first!...months.last!))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Sonraki", systemImage: "chevron.right") {
                anchorOffset = min(anchorOffset + span.rawValue, 0)
            }
            .labelStyle(.iconOnly)
            .disabled(anchorOffset >= 0)
        }
        .buttonStyle(.glass)
    }

    // MARK: Grafikler

    private func dailyChart(txs: [TxSnapshot], month: YearMonth) -> some View {
        let calendar = FinanceCalendar.calendar
        var byDay: [Date: Money] = [:]
        for tx in txs where tx.kind == .expense && rule.period(of: month).contains(tx.date) {
            byDay[calendar.startOfDay(for: tx.date), default: .zero] += tx.amount
        }
        let days = rule.days(of: month)
        let selectedDay = selectedDate.map { calendar.startOfDay(for: $0) }

        return Chart(days, id: \.self) { day in
            BarMark(x: .value("Gün", day, unit: .day), y: .value("Gider", (byDay[day] ?? .zero).lira))
                .cornerRadius(3)
                .foregroundStyle(ChartPalette.expense.opacity(selectedDay == nil || selectedDay == day ? 1 : 0.35))
            if selectedDay == day {
                RuleMark(x: .value("Gün", day, unit: .day))
                    .foregroundStyle(.clear)
                    .annotation(position: .top, overflowResolution: .init(x: .fit, y: .disabled)) {
                        ChartCallout(title: TR.dayMonth(day), lines: [("Gider", (byDay[day] ?? .zero).formatted())])
                    }
            }
        }
        .chartXSelection(value: $selectedDate)
        .chartXAxis {
            AxisMarks(values: .stride(by: .day, count: 7)) { _ in
                AxisValueLabel(format: .dateTime.day())
            }
        }
        .chartYAxis { moneyAxis }
        .frame(height: 180)
    }

    private struct SeriesPoint: Identifiable {
        let month: YearMonth
        let series: String
        let amount: Money
        var id: String { "\(month)-\(series)" }
    }

    private func incomeExpenseChart(_ monthly: [MonthlyTotals]) -> some View {
        let points = monthly.flatMap {
            [SeriesPoint(month: $0.month, series: "Gelir", amount: $0.income),
             SeriesPoint(month: $0.month, series: "Gider", amount: $0.expense)]
        }
        let selectedMonth = selectedDate.map { YearMonth(date: $0) }

        return VStack(alignment: .leading, spacing: 10) {
            Chart(points) { point in
                BarMark(x: .value("Ay", point.month.start, unit: .month),
                        y: .value("Tutar", point.amount.lira), width: .ratio(0.85))
                    .position(by: .value("Seri", point.series))
                    .cornerRadius(3)
                    .foregroundStyle(by: .value("Seri", point.series))
                    .opacity(selectedMonth == nil || selectedMonth == point.month ? 1 : 0.35)
                if let selectedMonth, selectedMonth == point.month, point.series == "Gelir",
                   let totals = monthly.first(where: { $0.month == selectedMonth }) {
                    RuleMark(x: .value("Ay", point.month.start, unit: .month))
                        .foregroundStyle(.clear)
                        .annotation(position: .top, overflowResolution: .init(x: .fit, y: .disabled)) {
                            ChartCallout(title: totals.month.title, lines: [
                                ("Gelir", totals.income.formatted(decimals: false)),
                                ("Gider", totals.expense.formatted(decimals: false)),
                                ("Net", totals.net.formatted(decimals: false)),
                            ])
                        }
                }
            }
            .chartForegroundStyleScale(["Gelir": ChartPalette.income, "Gider": ChartPalette.expense])
            .chartLegend(position: .top, alignment: .leading, spacing: 14)
            .chartXSelection(value: $selectedDate)
            .chartXAxis {
                AxisMarks(values: .stride(by: .month, count: monthly.count > 6 ? 2 : 1)) { _ in
                    AxisValueLabel(format: .dateTime.month(.abbreviated), centered: true)
                }
            }
            .chartYAxis { moneyAxis }
            .frame(height: 200)
        }
    }

    private func savingsRateChart(_ monthly: [MonthlyTotals]) -> some View {
        let points = monthly.compactMap { totals -> (YearMonth, Double)? in
            guard totals.income.minor > 0 else { return nil }
            return (totals.month, totals.net.ratio(of: totals.income) * 100)
        }
        return Chart {
            RuleMark(y: .value("Hedef", InsightThresholds.savingsRateTarget * 100))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                .foregroundStyle(Color.secondary)
                .annotation(position: .top, alignment: .leading) {
                    Text("Hedef %20").font(.caption2).foregroundStyle(.secondary)
                }
            ForEach(points, id: \.0) { month, rate in
                LineMark(x: .value("Ay", month.start, unit: .month), y: .value("Oran", rate))
                    .lineStyle(StrokeStyle(lineWidth: 2))
                    .foregroundStyle(ChartPalette.single)
                PointMark(x: .value("Ay", month.start, unit: .month), y: .value("Oran", rate))
                    .symbolSize(40)
                    .foregroundStyle(ChartPalette.single)
            }
            if let last = points.last {
                PointMark(x: .value("Ay", last.0.start, unit: .month), y: .value("Oran", last.1))
                    .opacity(0)
                    .annotation(position: .top) {
                        Text("%\(Int(last.1.rounded()))").font(.caption2.weight(.semibold))
                    }
            }
        }
        .chartXAxis {
            AxisMarks(values: .stride(by: .month, count: monthly.count > 6 ? 2 : 1)) { _ in
                AxisValueLabel(format: .dateTime.month(.abbreviated), centered: true)
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading) { value in
                AxisGridLine().foregroundStyle(Color.secondary.opacity(0.15))
                AxisValueLabel { Text("%\(Int(value.as(Double.self) ?? 0))") }
            }
        }
        .frame(height: 150)
    }

    private var moneyAxis: some AxisContent {
        AxisMarks(position: .leading) { value in
            AxisGridLine().foregroundStyle(Color.secondary.opacity(0.15))
            AxisValueLabel { Text(ChartFormat.axis(value.as(Double.self) ?? 0)) }
        }
    }

    // MARK: Listeler

    @ViewBuilder
    private func categoriesCard(txs: [TxSnapshot], period: DatePeriod, months: [YearMonth]) -> some View {
        let totals = ReportBuilder.categoryTotals(txs, kind: .expense, in: period)
        if !totals.isEmpty {
            let maxAmount = totals.first?.amount ?? .zero
            Card("Kategoriler") {
                ForEach(totals, id: \.categoryID) { total in
                    let category = categories.first { $0.id.uuidString == total.categoryID }
                    NavigationLink(value: CategoryReportDestination(categoryID: total.categoryID)) {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                CategoryBadge(category: category, size: 28)
                                Text(category?.name ?? "Kategorisiz").font(.subheadline)
                                Spacer()
                                VStack(alignment: .trailing, spacing: 0) {
                                    Text(total.amount.formatted(decimals: false))
                                        .font(.subheadline.weight(.semibold))
                                        .monospacedDigit()
                                    Text("\(TR.percent(total.share)) · \(total.count) işlem")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            ProgressBar(ratio: total.amount.ratio(of: maxAmount),
                                        tint: Color(hex: category?.colorHex ?? "#8E8E93"))
                        }
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    @ViewBuilder
    private func merchantsCard(txs: [TxSnapshot], period: DatePeriod) -> some View {
        let merchants = ReportBuilder.topMerchants(txs, in: period, limit: 10)
        if !merchants.isEmpty {
            Card("En çok harcadığın yerler") {
                ForEach(Array(merchants.enumerated()), id: \.element.key) { index, merchant in
                    HStack {
                        Text("\(index + 1)")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.secondary)
                            .frame(width: 20)
                        Text(merchant.name).font(.subheadline).lineLimit(1)
                        Spacer()
                        Text("\(merchant.count)×")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(merchant.amount.formatted(decimals: false))
                            .font(.subheadline.weight(.medium))
                            .monospacedDigit()
                            .frame(minWidth: 80, alignment: .trailing)
                    }
                }
            }
        }
    }
}

struct CategoryReportDestination: Hashable {
    let categoryID: String?
}

/// Tek kategorinin 12 aylık trendi ve dönemdeki işlemleri.
struct CategoryReportView: View {
    let categoryID: String?
    let anchor: YearMonth
    let mode: ReportMode
    var rule: MonthRule = .calendarMonths

    @Environment(AppRouter.self) private var router
    @Query private var entries: [LedgerEntry]
    @Query private var categories: [EntryCategory]
    @State private var selectedDate: Date?

    var body: some View {
        let category = categories.first { $0.id.uuidString == categoryID }
        let months = (0..<12).map { anchor.adding(months: -11 + $0) }
        let txs = ReportBuilder.normalized(entries.map(\.snapshot), mode: mode)
        let trend = ReportBuilder.categoryTrend(txs, categoryID: categoryID, months: months, rule: rule)
        let nonZero = trend.filter { $0.amount.minor > 0 }
        let average = nonZero.isEmpty ? Money.zero : nonZero.map(\.amount).sum().scaled(numerator: 1, denominator: nonZero.count)
        let color = Color(hex: category?.colorHex ?? "#8E8E93")
        let selectedMonth = selectedDate.map { YearMonth(date: $0) }
        let monthEntries = entries
            .filter { $0.kind == .expense && $0.category?.id.uuidString == categoryID && rule.period(of: anchor).contains($0.date) }
            .sorted { $0.date > $1.date }

        List {
            Section {
                Chart {
                    ForEach(trend, id: \.month) { item in
                        BarMark(x: .value("Ay", item.month.start, unit: .month), y: .value("Tutar", item.amount.lira))
                            .cornerRadius(3)
                            .foregroundStyle(color.opacity(selectedMonth == nil || selectedMonth == item.month ? 1 : 0.35))
                        if selectedMonth == item.month {
                            RuleMark(x: .value("Ay", item.month.start, unit: .month))
                                .foregroundStyle(.clear)
                                .annotation(position: .top, overflowResolution: .init(x: .fit, y: .disabled)) {
                                    ChartCallout(title: item.month.title, lines: [("Harcama", item.amount.formatted())])
                                }
                        }
                    }
                    if average.minor > 0 {
                        RuleMark(y: .value("Ortalama", average.lira))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                            .foregroundStyle(Color.secondary)
                            .annotation(position: .top, alignment: .leading) {
                                Text("Ort. \(average.formatted(decimals: false))").font(.caption2).foregroundStyle(.secondary)
                            }
                    }
                }
                .chartXSelection(value: $selectedDate)
                .chartXAxis {
                    AxisMarks(values: .stride(by: .month, count: 2)) { _ in
                        AxisValueLabel(format: .dateTime.month(.abbreviated), centered: true)
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading) { value in
                        AxisGridLine().foregroundStyle(Color.secondary.opacity(0.15))
                        AxisValueLabel { Text(ChartFormat.axis(value.as(Double.self) ?? 0)) }
                    }
                }
                .frame(height: 200)
                .padding(.vertical, 8)
            } header: {
                Text("Son 12 ay")
            } footer: {
                if let limit = category?.monthlyLimit {
                    Text("Aylık bütçe: \(limit.formatted(decimals: false))")
                }
            }

            Section("\(anchor.title) işlemleri") {
                if monthEntries.isEmpty {
                    Text("Bu ay işlem yok").foregroundStyle(.secondary)
                }
                ForEach(monthEntries) { entry in
                    Button {
                        router.editor = EditorRequest(entry: entry)
                    } label: {
                        EntryRow(entry: entry)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .navigationTitle(category?.name ?? "Kategorisiz")
    }
}
