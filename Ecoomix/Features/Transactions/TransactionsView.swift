import SwiftUI
import SwiftData
import EcoomixCore

struct EntryFilter: Equatable {
    var kind: TxKind?
    var categoryID: UUID?
    var accountID: UUID?
    var month: YearMonth?

    var isActive: Bool { kind != nil || categoryID != nil || accountID != nil || month != nil }

    func matches(_ entry: LedgerEntry, search: String, rule: MonthRule = .calendarMonths) -> Bool {
        if let kind, entry.kind != kind { return false }
        if let categoryID, entry.category?.id != categoryID { return false }
        if let accountID, entry.account?.id != accountID, entry.toAccount?.id != accountID { return false }
        if let month, !rule.period(of: month).contains(entry.date) { return false }
        guard !search.isEmpty else { return true }
        let haystack = [entry.merchant, entry.note, entry.category?.name ?? "", entry.installmentPlan?.title ?? ""]
            .joined(separator: " ")
        return haystack.localizedStandardContains(search)
    }
}

struct TransactionsView: View {
    @Environment(AppRouter.self) private var router
    @Query(sort: \LedgerEntry.date, order: .reverse) private var entries: [LedgerEntry]
    @Query(sort: \EntryCategory.sortOrder) private var categories: [EntryCategory]
    @Query(sort: \Account.sortOrder) private var accounts: [Account]

    @AppStorage(MonthSettings.key) private var monthStartDay = 1
    @State private var search = ""
    @State private var filter = EntryFilter()
    @State private var showPlanned = false

    private struct DayGroup: Identifiable {
        let id: Date
        let entries: [LedgerEntry]
        var net: Money {
            entries.reduce(.zero) { total, entry in
                switch entry.kind {
                case .income: total + entry.amount
                case .expense: total - entry.amount
                case .transfer: total
                }
            }
        }
    }

    private var filtered: [LedgerEntry] {
        entries.filter { filter.matches($0, search: search, rule: MonthRule(startDay: monthStartDay)) }
    }

    private var planned: [LedgerEntry] {
        let now = Date.now
        return filtered.filter { $0.date > now }.reversed()
    }

    private var days: [DayGroup] {
        let calendar = FinanceCalendar.calendar
        let now = Date.now
        let past = filtered.filter { $0.date <= now }
        let grouped = Dictionary(grouping: past) { calendar.startOfDay(for: $0.date) }
        return grouped.keys.sorted(by: >).map { DayGroup(id: $0, entries: grouped[$0]!) }
    }

    var body: some View {
        NavigationStack {
            List {
                if filter.isActive {
                    Section {
                        filterSummary
                    }
                }

                if !planned.isEmpty {
                    Section {
                        DisclosureGroup(isExpanded: $showPlanned) {
                            ForEach(planned) { entry in
                                row(entry)
                            }
                        } label: {
                            Label("Planlanan \(planned.count) işlem", systemImage: "calendar.badge.clock")
                                .font(.subheadline.weight(.medium))
                        }
                    } footer: {
                        Text("Gelecek tarihli taksitler. Tarihi gelince listeye düşer.")
                    }
                }

                ForEach(days) { day in
                    Section {
                        ForEach(day.entries) { entry in
                            row(entry)
                        }
                    } header: {
                        HStack {
                            Text(TR.dayHeader(day.id))
                            Spacer()
                            Text(day.net.formatted())
                                .monospacedDigit()
                        }
                    }
                }
            }
            .overlay {
                if entries.isEmpty {
                    ContentUnavailableView {
                        Label("Henüz işlem yok", systemImage: "tray")
                    } description: {
                        Text("Aşağıdaki “İşlem ekle” ile ilk harcamanı ya da gelirini gir.")
                    }
                } else if days.isEmpty && planned.isEmpty {
                    ContentUnavailableView.search(text: search)
                }
            }
            .searchable(text: $search, prompt: "İşyeri, not veya kategori")
            .navigationTitle("İşlemler")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    filterMenu
                }
            }
        }
    }

    private func row(_ entry: LedgerEntry) -> some View {
        Button {
            router.editor = EditorRequest(entry: entry)
        } label: {
            EntryRow(entry: entry)
        }
        .buttonStyle(.plain)
    }

    private var filterSummary: some View {
        HStack {
            Label("\(filtered.count) işlem", systemImage: "line.3.horizontal.decrease.circle.fill")
                .foregroundStyle(.tint)
            Spacer()
            let summary = ReportBuilder.summary(filtered.map(\.snapshot),
                                                in: DatePeriod(start: .distantPast, end: .distantFuture))
            Text(summary.net.formatted())
                .monospacedDigit()
                .foregroundStyle(.secondary)
            Button("Temizle") { filter = EntryFilter() }
                .buttonStyle(.borderless)
        }
        .font(.subheadline)
    }

    private var filterMenu: some View {
        Menu {
            Picker("Tür", selection: $filter.kind) {
                Text("Tümü").tag(TxKind?.none)
                ForEach(TxKind.allCases, id: \.self) { Text($0.title).tag(TxKind?.some($0)) }
            }
            Picker("Ay", selection: $filter.month) {
                Text("Tüm zamanlar").tag(YearMonth?.none)
                ForEach(recentMonths, id: \.self) { Text($0.title).tag(YearMonth?.some($0)) }
            }
            .pickerStyle(.menu)
            Picker("Kategori", selection: $filter.categoryID) {
                Text("Tüm kategoriler").tag(UUID?.none)
                ForEach(categories) { Label($0.name, systemImage: $0.icon).tag(UUID?.some($0.id)) }
            }
            .pickerStyle(.menu)
            Picker("Hesap", selection: $filter.accountID) {
                Text("Tüm hesaplar").tag(UUID?.none)
                ForEach(accounts) { Label($0.name, systemImage: $0.icon).tag(UUID?.some($0.id)) }
            }
            .pickerStyle(.menu)
            if filter.isActive {
                Button("Filtreyi temizle", systemImage: "xmark.circle", role: .destructive) { filter = EntryFilter() }
            }
        } label: {
            Label("Filtrele", systemImage: filter.isActive
                  ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
        }
    }

    private var recentMonths: [YearMonth] {
        let current = MonthRule(startDay: monthStartDay).current()
        return (0..<24).map { current.adding(months: -$0) }
    }
}

struct EntryRow: View {
    let entry: LedgerEntry

    var body: some View {
        HStack(spacing: 12) {
            if entry.kind == .transfer {
                CategoryBadge(icon: "arrow.left.arrow.right", colorHex: "#5A78F2")
            } else {
                CategoryBadge(category: entry.category)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.displayTitle)
                    .font(.body)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            AmountText(amount: entry.amount, kind: entry.kind)
        }
        .contentShape(.rect)
    }

    private var subtitle: String {
        var parts: [String] = []
        if entry.kind == .transfer {
            parts.append("\(entry.account?.name ?? "?") → \(entry.toAccount?.name ?? "?")")
        } else {
            if let name = entry.category?.name, name != entry.displayTitle { parts.append(name) }
            if let account = entry.account?.name { parts.append(account) }
        }
        if let label = entry.installmentLabel { parts.append(label) }
        if entry.source == .recurring { parts.append("Otomatik") }
        return parts.joined(separator: " · ")
    }
}
