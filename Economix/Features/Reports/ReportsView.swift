import SwiftUI
import SwiftData
import Charts
import EconomixCore

struct ReportsView: View {
    @Query private var entries: [LedgerEntry]
    @Query(sort: \EntryCategory.sortOrder) private var categories: [EntryCategory]

    @AppStorage("reportMode") private var modeRaw = ReportMode.cashFlow.rawValue
    @AppStorage("reportRange") private var rangeRaw = ReportRange.half.rawValue
    @AppStorage(MonthSettings.key) private var monthStartDay = 1
    /// İçinde bulunulan döneme uzaklık (0 = bu dönem). Özel aralıkta kullanılmaz; oklar tarihleri kaydırır.
    @State private var offset = 0
    @State private var customStart = FinanceCalendar.calendar.date(byAdding: .day, value: -29, to: .now)!
    @State private var customEnd = Date.now
    /// Kullanıcının seçtiği gruplama; aralığa uymuyorsa varsayılan kullanılır.
    @State private var granularityChoice: ReportGranularity?
    @State private var selectedDate: Date?

    private var mode: ReportMode { ReportMode(rawValue: modeRaw) ?? .cashFlow }
    private var range: ReportRange { ReportRange(rawValue: rangeRaw) ?? .half }
    private var rule: MonthRule { MonthRule(startDay: monthStartDay) }
    private var calendar: Calendar { FinanceCalendar.calendar }
    private var customPeriod: DatePeriod { DatePeriod(from: customStart, through: customEnd) }

    /// Seçili aralıkta `offset` adım uzaktaki dönem; özel aralıkta aynı uzunlukta kaydırılmış aralık.
    private func reportPeriod(offset: Int) -> DatePeriod {
        range.period(offset: offset, rule: rule) ?? customPeriod.shifted(by: offset)
    }

    /// Toplam aylık bütçe çizgisi. Yalnızca dönemde harcama yapılan her kategoride bütçe varsa anlamlı;
    /// yoksa bütçesiz harcamalar (ör. kira) toplamı bütçeyi olduğundan fazla aşmış gösterir.
    private func totalBudget(covering totals: [CategoryTotal]) -> Money? {
        let budgeted = categories.filter { !$0.isArchived && $0.monthlyLimit != nil }
        let ids = Set(budgeted.map(\.id.uuidString))
        guard !budgeted.isEmpty, totals.allSatisfy({ $0.categoryID.map(ids.contains) ?? false }) else { return nil }
        return budgeted.compactMap(\.monthlyLimit).sum()
    }

    var body: some View {
        let period = reportPeriod(offset: offset)
        let txs = ReportBuilder.normalized(entries.map(\.snapshot), mode: mode)
        let summary = ReportBuilder.summary(txs, in: period)
        let options = ReportGranularity.options(for: period)
        let granularity = granularityChoice.flatMap { options.contains($0) ? $0 : nil } ?? ReportGranularity.preferred(for: period)
        let cumulative = ReportBuilder.cumulativeSpending(txs, in: period, asOf: .now)
        let previousCumulative = ReportBuilder.cumulativeSpending(txs, in: reportPeriod(offset: offset - 1))
        let pace = SpendingPace(current: cumulative, previous: previousCumulative, periodDays: period.dayCount())
        let months = range.monthCount == nil ? rule.months(in: period) : range.months(offset: offset, rule: rule)
        let categoryTotals = ReportBuilder.categoryTotals(txs, kind: .expense, in: period)

        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    Picker("Dönem", selection: $rangeRaw) {
                        ForEach(ReportRange.allCases, id: \.self) { Text($0.title).tag($0.rawValue) }
                    }
                    .pickerStyle(.segmented)

                    periodNavigator(period: period)

                    if range == .custom {
                        customRangePicker
                    }

                    summaryCard(summary, pace: pace, spentSoFar: cumulative.last?.amount ?? .zero, elapsedDays: cumulative.count)

                    Card("Harcama", trailing: options.count > 1 ? AnyView(granularityPicker(options, selection: granularity)) : nil) {
                        SpendingBarChart(buckets: ReportBuilder.spendingSeries(txs, in: period, by: granularity, rule: rule),
                                         granularity: granularity, rule: rule)
                    }

                    Card("Kümülatif harcama") {
                        CumulativeSpendingChart(current: cumulative, previous: previousCumulative, days: period.days(),
                                                budget: range == .month ? totalBudget(covering: categoryTotals) : nil)
                    }

                    if months.count > 1 && period.dayCount() >= 56 {
                        let monthly = ReportBuilder.monthlyTotals(txs, months: months, rule: rule, in: period)
                        Card("Gelir ve gider") { incomeExpenseChart(monthly) }
                        Card("Tasarruf oranı") { savingsRateChart(monthly) }
                    }

                    categoriesCard(categoryTotals)

                    // Haftalık aralıkta her gün bir kez geçer; günlük grafikle aynı olurdu.
                    if range != .week && period.dayCount() >= 14 {
                        Card("Haftanın günleri") {
                            WeekdayChart(days: ReportBuilder.weekdayAverages(txs, in: period, asOf: .now))
                        }
                    }

                    merchantsCard(txs: txs, period: period)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Raporlar")
            .navigationDestination(for: CategoryReportDestination.self) { destination in
                CategoryReportView(categoryID: destination.categoryID, period: period,
                                   periodTitle: navigatorTitles(period).title, mode: mode, rule: rule)
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
        .onChange(of: rangeRaw) {
            offset = 0
            granularityChoice = nil
        }
    }

    // MARK: Dönem

    private func periodNavigator(period: DatePeriod) -> some View {
        let titles = navigatorTitles(period)
        return HStack {
            Button("Önceki", systemImage: "chevron.left") { step(-1) }
                .labelStyle(.iconOnly)
            Spacer()
            VStack(spacing: 2) {
                Text(titles.title)
                    .font(.headline)
                Text(titles.caption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Sonraki", systemImage: "chevron.right") { step(1) }
                .labelStyle(.iconOnly)
                .disabled(!canStepForward)
        }
        .buttonStyle(.glass)
    }

    private var modeCaption: String {
        mode == .cashFlow ? "Taksitler aylara yayılmış" : "Taksitli alımlar alım ayında"
    }

    private func navigatorTitles(_ period: DatePeriod) -> (title: String, caption: String) {
        switch range {
        case .week:
            switch offset {
            case 0: return ("Bu hafta", period.shortTitle())
            case -1: return ("Geçen hafta", period.shortTitle())
            default: return (period.shortTitle(), modeCaption)
            }
        case .custom:
            return (period.shortTitle(), "\(period.dayCount()) gün · \(modeCaption)")
        case .month, .quarter, .half, .year:
            let months = range.months(offset: offset, rule: rule)
            let first = months.first!, last = months.last!
            return (months.count == 1 ? first.title : "\(first.shortTitle) \(first.year) – \(last.shortTitle) \(last.year)",
                    rule.isCalendarMonth ? modeCaption : rule.rangeTitle(of: first...last))
        }
    }

    private var canStepForward: Bool {
        range == .custom ? customPeriod.end <= calendar.startOfDay(for: .now) : offset < 0
    }

    private func step(_ direction: Int) {
        guard range == .custom else {
            offset = min(offset + direction, 0)
            return
        }
        // Özel aralık kendi uzunluğu kadar kayar; bugünü geçmez.
        let length = customPeriod.dayCount()
        let shiftedLast = calendar.date(byAdding: .day, value: length * direction - 1, to: customPeriod.end)!
        let last = min(shiftedLast, calendar.startOfDay(for: .now))
        customEnd = last
        customStart = calendar.date(byAdding: .day, value: -(length - 1), to: last)!
    }

    private var customRangePicker: some View {
        Card {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Başlangıç").font(.caption).foregroundStyle(.secondary)
                    DatePicker("Başlangıç", selection: $customStart, in: ...customEnd, displayedComponents: .date)
                        .labelsHidden()
                }
                Spacer()
                Image(systemName: "arrow.right").foregroundStyle(.secondary)
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    Text("Bitiş").font(.caption).foregroundStyle(.secondary)
                    DatePicker("Bitiş", selection: $customEnd, in: customStart...max(customStart, .now), displayedComponents: .date)
                        .labelsHidden()
                }
            }
        }
    }

    private func granularityPicker(_ options: [ReportGranularity], selection: ReportGranularity) -> some View {
        Picker("Gruplama", selection: Binding(get: { selection }, set: { value in granularityChoice = value })) {
            ForEach(options, id: \.self) { Text($0.title).tag($0) }
        }
        .pickerStyle(.segmented)
        .fixedSize()
    }

    // MARK: Özet

    private func summaryCard(_ summary: PeriodSummary, pace: SpendingPace?, spentSoFar: Money, elapsedDays: Int) -> some View {
        let change = pace?.change
        return Card {
            HStack(alignment: .top) {
                StatTile(title: "Gelir", value: summary.income, tint: .income)
                StatTile(title: "Gider", value: summary.expense,
                         caption: change.map { changeText($0) },
                         captionTint: change.map { $0 > 0.005 ? Color.expense : $0 < -0.005 ? Color.income : .secondary } ?? .secondary)
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
            if elapsedDays > 0 {
                Text(averagesText(summary, spentSoFar: spentSoFar, elapsedDays: elapsedDays))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// "Öncekinden ▲ %12": devam eden dönemde önceki dönemin aynı gününe kadarki harcamayla kıyas.
    private func changeText(_ change: Double) -> String {
        let percent = Int((abs(change) * 100).rounded())
        if percent == 0 { return "Öncekiyle aynı" }
        return "Öncekinden \(change > 0 ? "▲" : "▼") %\(percent)"
    }

    private func averagesText(_ summary: PeriodSummary, spentSoFar: Money, elapsedDays: Int) -> String {
        var parts = ["Günlük ortalama gider \(spentSoFar.scaled(numerator: 1, denominator: elapsedDays).formatted(decimals: false))"]
        if let count = range.monthCount, count > 1 {
            parts.append("aylık \(summary.expense.scaled(numerator: 1, denominator: count).formatted(decimals: false))")
        }
        return parts.joined(separator: " · ")
    }

    // MARK: Grafikler

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
            .chartYAxis { ChartAxes.money() }
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

    // MARK: Listeler

    @ViewBuilder
    private func categoriesCard(_ totals: [CategoryTotal]) -> some View {
        if !totals.isEmpty {
            let maxAmount = totals.first?.amount ?? .zero
            Card("Kategoriler") {
                CategoryDonut(totals: totals, categories: categories)
                Divider()
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

/// Tek kategorinin 12 aylık trendi ve seçili dönemdeki işlemleri.
struct CategoryReportView: View {
    let categoryID: String?
    let period: DatePeriod
    /// "Ekim 2026", "Bu hafta", "5–18 Eki"
    let periodTitle: String
    let mode: ReportMode
    var rule: MonthRule = .calendarMonths

    @Environment(AppRouter.self) private var router
    @Query private var entries: [LedgerEntry]
    @Query private var categories: [EntryCategory]
    @State private var selectedDate: Date?

    var body: some View {
        let category = categories.first { $0.id.uuidString == categoryID }
        let lastMonth = rule.month(containing: period.end.addingTimeInterval(-1))
        let months = (0..<12).map { lastMonth.adding(months: -11 + $0) }
        let txs = ReportBuilder.normalized(entries.map(\.snapshot), mode: mode)
        let trend = ReportBuilder.categoryTrend(txs, categoryID: categoryID, months: months, rule: rule)
        let nonZero = trend.filter { $0.amount.minor > 0 }
        let average = nonZero.isEmpty ? Money.zero : nonZero.map(\.amount).sum().scaled(numerator: 1, denominator: nonZero.count)
        let color = Color(hex: category?.colorHex ?? "#8E8E93")
        let selectedMonth = selectedDate.map { YearMonth(date: $0) }
        let periodEntries = entries
            .filter { $0.kind == .expense && $0.category?.id.uuidString == categoryID && period.contains($0.date) }
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
                                ChartAxes.lineLabel("Ort. \(average.formatted(decimals: false))")
                            }
                    }
                }
                .chartXSelection(value: $selectedDate)
                .chartXAxis {
                    AxisMarks(values: .stride(by: .month, count: 2)) { _ in
                        AxisValueLabel(format: .dateTime.month(.abbreviated), centered: true)
                    }
                }
                .chartYAxis { ChartAxes.money() }
                .frame(height: 200)
                .padding(.vertical, 8)
            } header: {
                Text("Son 12 ay")
            } footer: {
                if let limit = category?.monthlyLimit {
                    Text("Aylık bütçe: \(limit.formatted(decimals: false))")
                }
            }

            Section("\(periodTitle) işlemleri") {
                if periodEntries.isEmpty {
                    Text("Bu dönemde işlem yok").foregroundStyle(.secondary)
                }
                ForEach(periodEntries) { entry in
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
