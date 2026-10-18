import SwiftUI
import SwiftData
import EcoomixCore

struct PlanDetailView: View {
    let plan: InstallmentPlan

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var editing = false
    @State private var closingEarly = false
    @State private var confirmDelete = false
    @State private var closeDate = Date.now

    var body: some View {
        let now = Date.now
        let progress = plan.progress(asOf: now)
        List {
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 12) {
                        CategoryBadge(category: plan.category, size: 48)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(plan.displayTitle).font(.title3.weight(.semibold))
                            Text([plan.merchant, plan.account?.name ?? ""].filter { !$0.isEmpty }.joined(separator: " · "))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    ProgressBar(ratio: Double(progress.paidCount) / Double(max(progress.totalCount, 1)),
                                tint: ChartPalette.single)
                    HStack(alignment: .top) {
                        StatTile(title: "Toplam", value: plan.total)
                        StatTile(title: "Ödenen", value: progress.paidAmount)
                        StatTile(title: "Kalan", value: progress.remainingAmount)
                    }
                    if let last = progress.lastMonth {
                        Text(progress.isFinished ? "Tamamlandı." : "Son taksit \(last.title). \(progress.remainingCount) taksit kaldı.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }

            Section("Taksitler") {
                ForEach(plan.sortedEntries) { entry in
                    let paid = entry.date <= now
                    HStack {
                        Image(systemName: paid ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(paid ? ChartPalette.single : Color.secondary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(entry.installmentLabel ?? "")
                            Text(dueText(for: entry))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(entry.amount.formatted())
                            .monospacedDigit()
                            .foregroundStyle(paid ? .secondary : .primary)
                    }
                }
            }
        }
        .navigationTitle("Taksit planı")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            Menu {
                Button("Düzenle", systemImage: "pencil") { editing = true }
                if !progress.isFinished {
                    Button("Erken kapat", systemImage: "checkmark.seal") { closingEarly = true }
                }
                Button("Planı sil", systemImage: "trash", role: .destructive) { confirmDelete = true }
            } label: {
                Label("İşlemler", systemImage: "ellipsis")
            }
        }
        .sheet(isPresented: $editing) {
            PlanEditView(plan: plan)
        }
        .sheet(isPresented: $closingEarly) {
            NavigationStack {
                Form {
                    Section {
                        DatePicker("Kapama tarihi", selection: $closeDate, displayedComponents: .date)
                    } footer: {
                        Text("Bu tarihten sonraki \(plan.progress(asOf: closeDate).remainingCount) taksit (\(plan.progress(asOf: closeDate).remainingAmount.formatted())) tek seferde bu tarihe yazılır.")
                    }
                }
                .navigationTitle("Erken kapat")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Vazgeç", systemImage: "xmark") { closingEarly = false }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Kapat", systemImage: "checkmark") {
                            try? LedgerService(context: context).closeEarly(plan, on: closeDate)
                            closingEarly = false
                        }
                    }
                }
            }
            .presentationDetents([.medium])
        }
        .confirmationDialog("Plan ve tüm taksitleri silinecek.", isPresented: $confirmDelete,
                            titleVisibility: .visible) {
            Button("Sil", role: .destructive) {
                try? LedgerService(context: context).deletePlan(plan)
                dismiss()
            }
        }
    }

    private func dueText(for entry: LedgerEntry) -> String {
        guard let card = plan.account, card.isCreditCard else { return TR.shortDate(entry.date) }
        let statement = card.cycle.statement(containing: entry.date)
        return "\(TR.shortDate(entry.date)) · son ödeme \(TR.dayMonth(statement.dueDate))"
    }
}

struct PlanEditView: View {
    let plan: InstallmentPlan

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(filter: #Predicate<EntryCategory> { !$0.isArchived }, sort: \EntryCategory.sortOrder)
    private var allCategories: [EntryCategory]
    @Query(filter: #Predicate<Account> { !$0.isArchived }, sort: \Account.sortOrder)
    private var accounts: [Account]

    @State private var title = ""
    @State private var merchant = ""
    @State private var totalText = ""
    @State private var count = 1
    @State private var purchaseDate = Date.now
    @State private var category: EntryCategory?
    @State private var account: Account?
    @State private var loaded = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                if let error {
                    Section { Text(error).foregroundStyle(.red) }
                }
                Section {
                    TextField("Ürün / açıklama", text: $title)
                    TextField("İşyeri", text: $merchant)
                    TextField("Toplam tutar", text: $totalText)
                        .keyboardType(.decimalPad)
                    Picker("Taksit sayısı", selection: $count) {
                        ForEach(1...36, id: \.self) { Text("\($0)").tag($0) }
                    }
                    DatePicker("Alım tarihi", selection: $purchaseDate, displayedComponents: .date)
                    Picker("Kart", selection: $account) {
                        Text("Seçilmedi").tag(Account?.none)
                        ForEach(accounts) { Text($0.name).tag(Account?.some($0)) }
                    }
                } footer: {
                    Text("Tutar, taksit sayısı veya tarih değişirse taksitler yeniden hesaplanır.")
                }
                Section("Kategori") {
                    CategoryGrid(categories: allCategories.filter { $0.kind == .expense }, selection: $category)
                }
            }
            .navigationTitle("Planı düzenle")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Vazgeç", systemImage: "xmark") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Kaydet", systemImage: "checkmark", action: save)
                        .disabled(Money.parse(totalText).map { $0.minor <= 0 } ?? true)
                }
            }
            .onAppear {
                guard !loaded else { return }
                loaded = true
                title = plan.title
                merchant = plan.merchant
                totalText = plan.total.inputString
                count = plan.count
                purchaseDate = plan.purchaseDate
                category = plan.category
                account = plan.account
            }
        }
    }

    private func save() {
        guard let total = Money.parse(totalText) else { return }
        let service = LedgerService(context: context)
        plan.title = title
        plan.merchant = merchant
        plan.category = category
        plan.account = account
        do {
            let calendar = FinanceCalendar.calendar
            let scheduleChanged = total != plan.total || count != plan.count
                || !calendar.isDate(purchaseDate, inSameDayAs: plan.purchaseDate)
            if scheduleChanged {
                try service.updatePlan(plan, total: total, count: count, purchaseDate: purchaseDate)
            }
            try service.propagateDetails(of: plan)
            dismiss()
        } catch {
            self.error = "Kaydedilemedi: \(error.localizedDescription)"
        }
    }
}
