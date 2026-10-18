import SwiftUI
import SwiftData
import Charts
import EcoomixCore

struct DashboardView: View {
    @Environment(AppRouter.self) private var router
    @Query private var entries: [LedgerEntry]
    @Query(sort: \EntryCategory.sortOrder) private var categories: [EntryCategory]
    @Query private var plans: [InstallmentPlan]
    @Query private var recurring: [RecurringItem]
    @Query(filter: #Predicate<Account> { !$0.isArchived }, sort: \Account.sortOrder) private var accounts: [Account]

    @State private var month = YearMonth.current()

    var body: some View {
        let data = FinanceSnapshot(entries: entries, categories: categories, plans: plans, recurring: recurring)
        let period = DatePeriod(month: month)
        let summary = ReportBuilder.summary(data.transactions, in: period)
        let isCurrent = month == YearMonth.current()

        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    hero(summary: summary, isCurrent: isCurrent)
                    budgetsCard(data: data)
                    breakdownCard(data: data, period: period)
                    if isCurrent {
                        upcomingCard(data: data)
                        insightsCard(data: data)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
                .animation(.default, value: month)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle(month.title)
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button("Önceki ay", systemImage: "chevron.left") { month = month.adding(months: -1) }
                    Button("Sonraki ay", systemImage: "chevron.right") { month = month.adding(months: 1) }
                        .disabled(isCurrent)
                }
            }
            .navigationDestination(for: InsightsDestination.self) { _ in InsightsView() }
        }
    }

    // MARK: Bölümler

    private func hero(summary: PeriodSummary, isCurrent: Bool) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 4) {
                Text(isCurrent ? "Bu ay net" : "\(month.monthName) net").font(.subheadline).foregroundStyle(.secondary)
                Text(summary.net.formatted())
                    .font(.system(size: 38, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .foregroundStyle(summary.net.isNegative ? Color.expense : Color.primary)
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                if let rate = summary.savingsRate {
                    Text("Gelirinin \(TR.percent(rate))'i kaldı")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            HStack(alignment: .top) {
                StatTile(title: "Gelir", value: summary.income, tint: .income)
                StatTile(title: "Gider", value: summary.expense)
                VStack(alignment: .leading, spacing: 4) {
                    Text("İşlem").font(.caption).foregroundStyle(.secondary)
                    Text("\(summary.transactionCount)").font(.headline)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    @ViewBuilder
    private func budgetsCard(data: FinanceSnapshot) -> some View {
        let budgeted = data.categories.filter { $0.monthlyLimit != nil && !$0.isArchived }
        if !budgeted.isEmpty {
            Card("Bütçeler") {
                ForEach(budgeted) { category in
                    let spent = data.transactions
                        .filter { $0.kind == .expense && $0.categoryID == category.id.uuidString && month.contains($0.date) }
                        .map(\.amount).sum()
                    let status = BudgetEvaluator.evaluate(limit: category.monthlyLimit!, spent: spent, month: month, asOf: .now)
                    BudgetRow(category: category, status: status)
                }
            }
        }
    }

    @ViewBuilder
    private func breakdownCard(data: FinanceSnapshot, period: DatePeriod) -> some View {
        let totals = ReportBuilder.categoryTotals(data.transactions, kind: .expense, in: period)
        if !totals.isEmpty {
            Card("Harcama dağılımı", trailing: AnyView(
                Button("Raporlar") { router.tab = .reports }.font(.subheadline)
            )) {
                CategoryDonut(totals: totals, data: data)
            }
        }
    }

    @ViewBuilder
    private func upcomingCard(data: FinanceSnapshot) -> some View {
        let upcoming = UpcomingPayment.collect(cards: accounts, recurring: data.recurring, transactions: data.transactions)
        if !upcoming.isEmpty {
            Card("Yaklaşan ödemeler", trailing: AnyView(
                Text(upcoming.map(\.amount).sum().formatted(decimals: false))
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            )) {
                ForEach(upcoming.prefix(6)) { item in
                    HStack(spacing: 12) {
                        CategoryBadge(icon: item.icon, colorHex: item.colorHex, size: 32)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.title).font(.subheadline)
                            Text("\(TR.dayMonth(item.date)) · \(item.subtitle)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(item.amount.formatted())
                            .font(.subheadline.weight(.medium))
                            .monospacedDigit()
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func insightsCard(data: FinanceSnapshot) -> some View {
        let insights = data.insights().filter { $0.severity >= .suggestion }
        if !insights.isEmpty {
            Card("Öneriler", trailing: AnyView(
                NavigationLink("Tümü", value: InsightsDestination()).font(.subheadline)
            )) {
                ForEach(insights.prefix(3)) { insight in
                    InsightRow(insight: insight)
                    if insight.id != insights.prefix(3).last?.id { Divider() }
                }
            }
        }
    }
}

struct InsightsDestination: Hashable {}

struct BudgetRow: View {
    let category: EntryCategory
    let status: BudgetStatus

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                CategoryBadge(category: category, size: 24)
                Text(category.name).font(.subheadline)
                Spacer()
                Text("\(status.spent.formatted(decimals: false)) / \(status.limit.formatted(decimals: false))")
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            ProgressBar(ratio: status.ratio, tint: status.level.color)
            if status.level == .exceeded {
                Label("\((status.spent - status.limit).formatted(decimals: false)) aşıldı", systemImage: "exclamationmark.octagon.fill")
                    .font(.caption2)
                    .foregroundStyle(Color.expense)
            } else if status.projectedLevel == .exceeded {
                Label("Bu hızla ay sonu ~\(status.projected.formatted(decimals: false))", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption2)
                    .foregroundStyle(.orange)
            }
        }
    }
}

/// Kategori halka grafiği: ilk 5 kategori + "Diğer"; renk kategoriye aittir, lejant tutarlarla birlikte.
struct CategoryDonut: View {
    let totals: [CategoryTotal]
    let data: FinanceSnapshot
    @State private var selected: Double?

    private struct Slice: Identifiable {
        let id: String
        let name: String
        let amount: Money
        let share: Double
        let color: Color
        let icon: String
    }

    private var slices: [Slice] {
        let top = totals.prefix(5).map { total -> Slice in
            let category = data.category(id: total.categoryID)
            return Slice(id: total.categoryID ?? "none", name: category?.name ?? "Kategorisiz", amount: total.amount,
                         share: total.share, color: Color(hex: category?.colorHex ?? "#8E8E93"),
                         icon: category?.icon ?? "questionmark")
        }
        let rest = totals.dropFirst(5)
        guard !rest.isEmpty else { return top }
        return top + [Slice(id: "other", name: "Diğer (\(rest.count))", amount: rest.map(\.amount).sum(),
                            share: rest.map(\.share).reduce(0, +), color: ChartPalette.other, icon: "ellipsis")]
    }

    var body: some View {
        let slices = slices
        let total = totals.map(\.amount).sum()
        let active = selectedSlice(in: slices)

        HStack(alignment: .center, spacing: 16) {
            Chart(slices) { slice in
                SectorMark(angle: .value("Tutar", slice.amount.lira), innerRadius: .ratio(0.62), angularInset: 1.5)
                    .cornerRadius(3)
                    .foregroundStyle(slice.color)
                    .opacity(active == nil || active?.id == slice.id ? 1 : 0.35)
            }
            .chartAngleSelection(value: $selected)
            .chartBackground { _ in
                VStack(spacing: 0) {
                    Text(active?.name ?? "Toplam")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Text((active?.amount ?? total).formatted(decimals: false))
                        .font(.caption.weight(.bold))
                        .monospacedDigit()
                        .minimumScaleFactor(0.7)
                }
                .frame(width: 80)
            }
            .frame(width: 140, height: 140)

            VStack(alignment: .leading, spacing: 7) {
                ForEach(slices) { slice in
                    HStack(spacing: 6) {
                        Circle().fill(slice.color).frame(width: 8, height: 8)
                        Text(slice.name).font(.caption).lineLimit(1)
                        Spacer(minLength: 4)
                        Text(TR.percent(slice.share))
                            .font(.caption.weight(.medium))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private func selectedSlice(in slices: [Slice]) -> Slice? {
        guard let selected else { return nil }
        var cumulative = 0.0
        for slice in slices {
            cumulative += slice.amount.lira
            if selected <= cumulative { return slice }
        }
        return nil
    }
}

struct InsightRow: View {
    let insight: Insight

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(color)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 4) {
                Text(insight.title).font(.subheadline.weight(.semibold))
                Text(insight.message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let saving = insight.estimatedMonthlySaving, saving.minor > 0 {
                    Text("Olası tasarruf: ayda \(saving.formatted(decimals: false))")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(ChartPalette.single)
                }
            }
        }
    }

    private var icon: String {
        switch insight.severity {
        case .critical: "exclamationmark.octagon.fill"
        case .warning: "exclamationmark.triangle.fill"
        case .suggestion: "lightbulb.fill"
        case .info: "info.circle.fill"
        }
    }

    private var color: Color {
        switch insight.severity {
        case .critical: .expense
        case .warning: .orange
        case .suggestion: .yellow
        case .info: .blue
        }
    }
}
