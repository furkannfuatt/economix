import SwiftUI
import SwiftData
import EconomixCore

struct SubscriptionsTab: View {
    @Query(sort: \RecurringItem.title) private var items: [RecurringItem]
    @State private var editing: RecurringItem?

    var body: some View {
        VStack(spacing: 16) { content }
            .sheet(item: $editing) { RecurringEditorView(item: $0) }
    }

    @ViewBuilder
    private var content: some View {
        let subscriptions = items.filter { $0.isSubscription }
        let others = items.filter { !$0.isSubscription }
        let activeSubs = subscriptions.filter { $0.isActive && $0.kind == .expense }
        let monthly = activeSubs.map(\.monthlyEquivalent).sum()

        if items.isEmpty {
            ContentUnavailableView {
                Label("Düzenli ödeme yok", systemImage: "repeat")
            } description: {
                Text("Netflix, Spotify gibi abonelikleri; maaş, kira gibi düzenli kalemleri ekle. Vadesi gelince işlem otomatik oluşur.")
            }
            .padding(.top, 40)
        } else {
            Card {
                HStack(alignment: .top) {
                    StatTile(title: "Aylık abonelik", value: monthly)
                    StatTile(title: "Yıllık karşılığı", value: activeSubs.map(\.yearlyEquivalent).sum())
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Aktif").font(.caption).foregroundStyle(.secondary)
                        Text("\(activeSubs.count)").font(.headline)
                    }
                }
            }

            if !subscriptions.isEmpty {
                Card("Abonelikler") { rows(subscriptions) }
            }
            if !others.isEmpty {
                Card("Diğer düzenli işlemler") { rows(others) }
            }
        }
    }

    @ViewBuilder
    private func rows(_ list: [RecurringItem]) -> some View {
        ForEach(list) { item in
            Button {
                editing = item
            } label: {
                RecurringRow(item: item)
            }
            .buttonStyle(.plain)
            if item.id != list.last?.id { Divider() }
        }
    }
}

struct RecurringRow: View {
    let item: RecurringItem

    var body: some View {
        HStack(spacing: 12) {
            CategoryBadge(category: item.category)
                .opacity(item.isActive ? 1 : 0.4)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .foregroundStyle(item.isActive ? .primary : .secondary)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                AmountText(amount: item.amount, kind: item.kind, font: .subheadline)
                Text(item.frequency.title)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .contentShape(.rect)
    }

    private var subtitle: String {
        guard item.isActive else { return "Duraklatıldı" }
        guard let next = item.nextDate() else { return "Sona erdi" }
        let days = FinanceCalendar.calendar.dateComponents([.day], from: FinanceCalendar.calendar.startOfDay(for: .now),
                                                           to: next).day ?? 0
        let when = days == 0 ? "bugün" : days == 1 ? "yarın" : "\(days) gün sonra"
        return "Sonraki: \(TR.dayMonth(next)) (\(when))" + (item.account.map { " · \($0.name)" } ?? "")
    }
}

struct RecurringEditorView: View {
    let item: RecurringItem?

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(filter: #Predicate<EntryCategory> { !$0.isArchived }, sort: \EntryCategory.sortOrder)
    private var allCategories: [EntryCategory]
    @Query(filter: #Predicate<Account> { !$0.isArchived }, sort: \Account.sortOrder)
    private var accounts: [Account]

    @State private var title = ""
    @State private var amountText = ""
    @State private var kind: TxKind = .expense
    @State private var isSubscription = true
    @State private var frequency: Frequency = .monthly
    @State private var dayOfMonth = FinanceCalendar.calendar.component(.day, from: .now)
    @State private var startDate = Date.now
    @State private var hasEndDate = false
    @State private var endDate = Date.now
    @State private var category: EntryCategory?
    @State private var account: Account?
    @State private var isActive = true
    @State private var includePast = false
    @State private var loaded = false
    @State private var confirmDelete = false
    @State private var error: String?

    private var amount: Money? { Money.parse(amountText).flatMap { $0.minor > 0 ? $0 : nil } }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Tür", selection: $kind) {
                        Text("Gider").tag(TxKind.expense)
                        Text("Gelir").tag(TxKind.income)
                        Text("Yatırım").tag(TxKind.investment)
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                }

                Section {
                    TextField(kind == .income ? "Ad (ör. Maaş)" : "Ad (ör. Netflix)", text: $title)
                    TextField("Tutar", text: $amountText)
                        .keyboardType(.decimalPad)
                    if kind == .expense {
                        Toggle("Abonelik", isOn: $isSubscription)
                    }
                }

                Section("Ne zaman") {
                    Picker("Sıklık", selection: $frequency) {
                        ForEach(Frequency.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    if frequency != .weekly {
                        Picker("Ayın günü", selection: $dayOfMonth) {
                            ForEach(1...31, id: \.self) { Text("\($0)").tag($0) }
                        }
                    }
                    DatePicker("Başlangıç", selection: $startDate, displayedComponents: .date)
                    Toggle("Bitiş tarihi", isOn: $hasEndDate)
                    if hasEndDate {
                        DatePicker("Bitiş", selection: $endDate, displayedComponents: .date)
                    }
                    if item == nil {
                        Toggle("Geçmiş ödemeleri de ekle", isOn: $includePast)
                    }
                }

                Section("Kategori") {
                    CategoryGrid(categories: allCategories.filter { $0.kind == kind }, selection: $category)
                }

                Section {
                    Picker("Hesap", selection: $account) {
                        Text("Seçilmedi").tag(Account?.none)
                        ForEach(accounts) { Text($0.name).tag(Account?.some($0)) }
                    }
                    if item != nil {
                        Toggle("Aktif", isOn: $isActive)
                    }
                } footer: {
                    if frequency == .yearly {
                        Text("Yıllık ödemelerde ay, başlangıç tarihinin ayıdır.")
                    }
                }

                if item != nil {
                    Section {
                        Button("Sil", role: .destructive) { confirmDelete = true }
                    } footer: {
                        Text("Daha önce oluşan işlemler geçmişte kalır.")
                    }
                }

                if let error {
                    Section { Text(error).foregroundStyle(.red) }
                }
            }
            .navigationTitle(item == nil ? "Düzenli ödeme" : "Düzenle")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Vazgeç", systemImage: "xmark") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Kaydet", systemImage: "checkmark", action: save)
                        .disabled(amount == nil || title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .confirmationDialog("Düzenli ödeme silinecek.", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Sil", role: .destructive) {
                    if let item { context.delete(item) }
                    try? context.save()
                    dismiss()
                }
            }
            .onChange(of: kind) { _, newKind in
                if category?.kind != newKind { category = nil }
                if newKind == .income { isSubscription = false }
            }
            .onAppear(perform: load)
        }
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        guard let item else {
            account = accounts.first { $0.isCreditCard } ?? accounts.first
            category = allCategories.first { $0.seedKey == "abonelik" }
            return
        }
        title = item.title
        amountText = item.amount.inputString
        kind = item.kind
        isSubscription = item.isSubscription
        frequency = item.frequency
        dayOfMonth = item.dayOfMonth
        startDate = item.startDate
        hasEndDate = item.endDate != nil
        endDate = item.endDate ?? .now
        category = item.category
        account = item.account
        isActive = item.isActive
    }

    private func save() {
        guard let amount else { return }
        let calendar = FinanceCalendar.calendar
        let target: RecurringItem
        if let item {
            target = item
        } else {
            target = RecurringItem(title: title, amount: amount, kind: kind, frequency: frequency,
                                   dayOfMonth: dayOfMonth, startDate: startDate, isSubscription: isSubscription)
            context.insert(target)
        }
        target.title = title.trimmingCharacters(in: .whitespaces)
        target.amount = amount
        target.kind = kind
        target.isSubscription = kind == .expense && isSubscription
        target.frequency = frequency
        target.dayOfMonth = frequency == .weekly ? calendar.component(.day, from: startDate) : dayOfMonth
        target.startDate = calendar.startOfDay(for: startDate)
        target.endDate = hasEndDate ? calendar.startOfDay(for: endDate) : nil
        target.category = category
        target.account = account
        target.isActive = isActive
        if item == nil && !includePast { target.skipPastOccurrences() }
        do {
            try context.save()
            try RecurringGenerator(context: context).run()
            dismiss()
        } catch {
            self.error = "Kaydedilemedi: \(error.localizedDescription)"
        }
    }
}
