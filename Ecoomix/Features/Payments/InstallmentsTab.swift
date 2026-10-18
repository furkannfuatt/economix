import SwiftUI
import SwiftData
import Charts
import EcoomixCore

struct InstallmentsTab: View {
    @Query(sort: \InstallmentPlan.purchaseDate, order: .reverse) private var plans: [InstallmentPlan]
    @State private var selectedDate: Date?
    @State private var showFinished = false

    var body: some View {
        let now = Date.now
        let progress = Dictionary(uniqueKeysWithValues: plans.map { ($0.id, $0.progress(asOf: now)) })
        let active = plans.filter { progress[$0.id]?.isFinished == false }
        let finished = plans.filter { progress[$0.id]?.isFinished != false }
        let outlook = InstallmentScheduler.outlook(
            plans: plans.map { PlanSchedule(id: $0.id.uuidString, title: $0.displayTitle, lines: $0.lines) },
            from: YearMonth.current(), monthCount: 12)
        let remainingTotal = active.compactMap { progress[$0.id]?.remainingAmount }.sum()

        if plans.isEmpty {
            ContentUnavailableView {
                Label("Taksitli alım yok", systemImage: "creditcard")
            } description: {
                Text("Kredi kartıyla gider eklerken taksit sayısını seçtiğinde planlar burada görünür.")
            }
            .padding(.top, 40)
        } else {
            Card {
                HStack(alignment: .top) {
                    StatTile(title: "Bu ay taksit", value: outlook.months.first?.amount ?? .zero)
                    StatTile(title: "Kalan toplam", value: remainingTotal)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Aktif plan").font(.caption).foregroundStyle(.secondary)
                        Text("\(active.count)").font(.headline)
                    }
                }
            }

            Card("Önümüzdeki 12 ay") {
                loadChart(outlook)
                if !outlook.reliefs.isEmpty {
                    Divider()
                    ForEach(outlook.reliefs, id: \.month) { relief in
                        HStack(alignment: .firstTextBaseline) {
                            Image(systemName: "arrow.down.right.circle.fill")
                                .foregroundStyle(ChartPalette.single)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("\(relief.month.title): \(relief.titles.joined(separator: ", ")) bitiyor")
                                    .font(.subheadline)
                                Text("Aylık yük \(relief.amount.formatted(decimals: false)) azalır")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }

            if !active.isEmpty {
                Card("Aktif taksitler") {
                    ForEach(active) { plan in
                        NavigationLink(value: plan) {
                            PlanRow(plan: plan, progress: progress[plan.id]!)
                        }
                        .buttonStyle(.plain)
                        if plan.id != active.last?.id { Divider() }
                    }
                }
            }

            if !finished.isEmpty {
                Card {
                    DisclosureGroup("Biten taksitler (\(finished.count))", isExpanded: $showFinished) {
                        ForEach(finished) { plan in
                            NavigationLink(value: plan) {
                                PlanRow(plan: plan, progress: progress[plan.id]!)
                            }
                            .buttonStyle(.plain)
                            .padding(.top, 8)
                        }
                    }
                }
            }
        }
    }

    private func loadChart(_ outlook: InstallmentOutlook) -> some View {
        let selected = selectedDate.flatMap { date in
            outlook.months.first { $0.month == YearMonth(date: date) }
        }
        return Chart(outlook.months, id: \.month) { item in
            BarMark(x: .value("Ay", item.month.start, unit: .month),
                    y: .value("Taksit", item.amount.lira))
                .cornerRadius(4)
                .foregroundStyle(ChartPalette.single.opacity(selected == nil || selected?.month == item.month ? 1 : 0.35))
            if let selected, selected.month == item.month {
                RuleMark(x: .value("Ay", item.month.start, unit: .month))
                    .foregroundStyle(.clear)
                    .annotation(position: .top, overflowResolution: .init(x: .fit, y: .disabled)) {
                        ChartCallout(title: item.month.title, lines: [("Taksit", item.amount.formatted())])
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
        .frame(height: 180)
    }
}

struct PlanRow: View {
    let plan: InstallmentPlan
    let progress: InstallmentProgress

    var body: some View {
        HStack(spacing: 12) {
            CategoryBadge(category: plan.category)
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    Text(plan.displayTitle).font(.body).lineLimit(1)
                    Spacer()
                    Text(plan.monthlyAmount.formatted(decimals: false) + "/ay")
                        .font(.subheadline.weight(.semibold))
                        .monospacedDigit()
                }
                ProgressBar(ratio: Double(progress.paidCount) / Double(max(progress.totalCount, 1)),
                            tint: ChartPalette.single)
                HStack {
                    Text("\(progress.paidCount)/\(progress.totalCount) ödendi")
                    Spacer()
                    if progress.isFinished {
                        Text("Tamamlandı")
                    } else {
                        Text("Kalan \(progress.remainingAmount.formatted(decimals: false))")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
            }
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .contentShape(.rect)
    }
}

extension InstallmentPlan {
    var displayTitle: String {
        if !title.isEmpty { return title }
        if !merchant.isEmpty { return merchant }
        return category?.name ?? "Taksitli alım"
    }
}
