import SwiftUI
import SwiftData
import EconomixCore

struct EntryEditorView: View {
    let request: EditorRequest

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(BudgetMonitor.self) private var budgetMonitor: BudgetMonitor?

    @Query(filter: #Predicate<EntryCategory> { !$0.isArchived }, sort: \EntryCategory.sortOrder)
    private var allCategories: [EntryCategory]
    @Query(filter: #Predicate<Account> { !$0.isArchived }, sort: \Account.sortOrder)
    private var accounts: [Account]

    @AppStorage("lastAccountID") private var lastAccountID = ""

    @State private var kind: TxKind = .expense
    @State private var amountText = ""
    @State private var category: EntryCategory?
    @State private var account: Account?
    @State private var toAccount: Account?
    @State private var date = Date.now
    @State private var merchant = ""
    @State private var note = ""
    @State private var installmentCount = 1
    @State private var error: String?
    @State private var loaded = false
    @State private var confirmDelete = false
    @FocusState private var amountFocused: Bool

    private static let installmentOptions = [1, 2, 3, 4, 5, 6, 8, 9, 10, 12, 18, 24]

    private var editing: LedgerEntry? { request.entry }
    private var isInstallmentEntry: Bool { editing?.installmentPlan != nil }
    private var amount: Money? { Money.parse(amountText).flatMap { $0.minor > 0 ? $0 : nil } }
    /// Yatırım bozma da yatırım kategorilerini kullanır (kategori varlık türüdür, yön işlem türündedir).
    private var categories: [EntryCategory] { allCategories.filter { $0.kind == kind.categoryKind } }

    /// Üstteki tür seçici: yatırım ve yatırım bozma aynı "Yatırım" sekmesinde, alttaki seçiciyle ayrılır.
    private static let mainKinds: [TxKind] = [.expense, .income, .investment, .transfer]

    private var canSplitIntoInstallments: Bool {
        editing == nil && kind == .expense && account?.isCreditCard == true
    }

    private var canSave: Bool {
        guard amount != nil else { return false }
        if kind == .transfer { return account != nil && toAccount != nil && account !== toAccount }
        return true
    }

    var body: some View {
        NavigationStack {
            Form {
                if !isInstallmentEntry {
                    Section {
                        Picker("Tür", selection: Binding(get: { kind.categoryKind }, set: { newKind in kind = newKind })) {
                            ForEach(Self.mainKinds, id: \.self) { Text($0.title).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets())
                        .listRowSeparator(.hidden)
                        if kind.categoryKind == .investment {
                            Picker("Yön", selection: $kind) {
                                Text("Yatırım yap").tag(TxKind.investment)
                                Text("Yatırımı boz").tag(TxKind.divestment)
                            }
                            .pickerStyle(.segmented)
                            .listRowBackground(Color.clear)
                            .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 0, trailing: 0))
                            .listRowSeparator(.hidden)
                        }
                    }
                }

                Section {
                    AmountField(text: $amountText, tint: tint, focused: $amountFocused)
                        .disabled(isInstallmentEntry)
                        .padding(.vertical, 8)
                    if let installment = editing?.installmentLabel {
                        Label("\(installment). Tutarı değiştirmek için taksit planını düzenle.",
                              systemImage: "info.circle")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                if kind != .transfer {
                    Section("Kategori") {
                        CategoryGrid(categories: categories, selection: $category)
                    }
                }

                Section {
                    if kind == .transfer {
                        accountPicker("Nereden", selection: $account)
                        accountPicker("Nereye", selection: $toAccount)
                    } else {
                        accountPicker(kind == .income || kind == .divestment ? "Hesap" : "Ödeme", selection: $account)
                    }
                    DatePicker("Tarih", selection: $date, displayedComponents: .date)
                        .disabled(isInstallmentEntry)
                    if kind != .transfer {
                        TextField(merchantPlaceholder,
                                  text: $merchant)
                            .textInputAutocapitalization(.words)
                            .onSubmit(suggestCategory)
                    }
                    TextField("Not", text: $note, axis: .vertical)
                }

                if canSplitIntoInstallments {
                    installmentSection
                }

                if editing != nil {
                    Section {
                        Button(isInstallmentEntry ? "Taksit planını sil" : "İşlemi sil", role: .destructive) {
                            confirmDelete = true
                        }
                    }
                }

                if let error {
                    Section { Text(error).foregroundStyle(.red) }
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(editing == nil ? "Yeni işlem" : "İşlemi düzenle")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Bitti") { amountFocused = false; hideKeyboard() }
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Vazgeç", systemImage: "xmark") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Kaydet", systemImage: "checkmark", action: save)
                        .disabled(!canSave)
                }
            }
            .confirmationDialog(isInstallmentEntry ? "Tüm taksitler silinecek." : "İşlem silinecek.",
                                isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Sil", role: .destructive, action: deleteEntry)
            }
            .onAppear(perform: load)
            .onChange(of: kind) { _, newKind in
                if category?.kind != newKind.categoryKind { category = nil }
                if newKind != .expense { installmentCount = 1 }
            }
            .onChange(of: account) { _, newAccount in
                if newAccount?.isCreditCard != true { installmentCount = 1 }
            }
        }
    }

    private var tint: Color {
        switch kind {
        case .expense: .primary
        case .income: .income
        case .investment, .divestment: .investment
        case .transfer: .transfer
        }
    }

    private var merchantPlaceholder: String {
        switch kind {
        case .income: "Kimden (ör. işveren)"
        case .investment: "Nereye (ör. Midas)"
        case .divestment: "Nereden (ör. Midas)"
        case .expense, .transfer: "Nereye (ör. Migros)"
        }
    }

    private var installmentSection: some View {
        Section {
            Picker("Taksit", selection: $installmentCount) {
                ForEach(Self.installmentOptions, id: \.self) { count in
                    Text(count == 1 ? "Tek çekim" : "\(count) taksit").tag(count)
                }
            }
            if installmentCount > 1, let amount {
                let parts = amount.split(into: installmentCount)
                LabeledContent("Aylık") {
                    Text("\(parts.last!.formatted()) × \(installmentCount)")
                        .monospacedDigit()
                }
                if let card = account {
                    let first = card.cycle.statement(containing: date)
                    LabeledContent("İlk ekstre", value: TR.dayMonth(first.closingDate))
                }
            }
        } header: {
            Text("Taksit")
        } footer: {
            if installmentCount > 1 {
                Text("Her ay bir taksit otomatik eklenir; kalan taksitleri Ödemeler sekmesinden izleyebilirsin.")
            }
        }
    }

    private func accountPicker(_ title: String, selection: Binding<Account?>) -> some View {
        Picker(title, selection: selection) {
            Text("Seçilmedi").tag(Account?.none)
            ForEach(accounts) { account in
                Label(account.name, systemImage: account.icon).tag(Account?.some(account))
            }
        }
    }

    // MARK: Eylemler

    private func load() {
        guard !loaded else { return }
        loaded = true
        if let entry = editing {
            kind = entry.kind
            amountText = entry.amount.inputString
            category = entry.category
            account = entry.account
            toAccount = entry.toAccount
            date = entry.date
            merchant = entry.merchant
            note = entry.note
        } else {
            kind = request.kind
            if let preset = request.presetAmount { amountText = preset.inputString }
            if let toID = request.presetToAccountID {
                toAccount = accounts.first { $0.id == toID }
                account = accounts.first { $0.type == .bank } ?? accounts.first { $0.id != toID }
            } else {
                account = accounts.first { $0.id.uuidString == lastAccountID } ?? accounts.first
            }
            amountFocused = request.presetAmount == nil
        }
    }

    private func suggestCategory() {
        guard category == nil else { return }
        if let learned = service.learnedCategory(for: merchant), learned.kind == kind.categoryKind {
            category = learned
        }
    }

    private var service: LedgerService {
        var service = LedgerService(context: context)
        service.onExpenseChange = { category, date in budgetMonitor?.check(category: category, date: date) }
        return service
    }

    private func save() {
        guard let amount else { return }
        let trimmedMerchant = merchant.trimmingCharacters(in: .whitespaces)
        do {
            if let entry = editing {
                if !isInstallmentEntry {
                    entry.kind = kind
                    entry.amount = amount
                    entry.date = date
                    entry.toAccount = kind == .transfer ? toAccount : nil
                }
                entry.category = kind == .transfer ? nil : category
                entry.account = account
                entry.merchant = trimmedMerchant
                entry.note = note
                try service.save(entry)
            } else if canSplitIntoInstallments && installmentCount > 1 {
                try service.addInstallmentPurchase(total: amount, count: installmentCount, purchaseDate: date,
                                                   category: category, account: account,
                                                   merchant: trimmedMerchant, title: note)
            } else {
                try service.addEntry(amount: amount, kind: kind, date: date, category: category, account: account,
                                     toAccount: toAccount, merchant: trimmedMerchant, note: note)
            }
            if let category, !trimmedMerchant.isEmpty {
                try service.learnCategory(merchant: trimmedMerchant, category: category)
            }
            if let account { lastAccountID = account.id.uuidString }
            dismiss()
        } catch {
            self.error = "Kaydedilemedi: \(error.localizedDescription)"
        }
    }

    private func deleteEntry() {
        guard let entry = editing else { return }
        do {
            if let plan = entry.installmentPlan {
                try service.deletePlan(plan)
            } else {
                try service.delete(entry)
            }
            dismiss()
        } catch {
            self.error = "Silinemedi: \(error.localizedDescription)"
        }
    }
}

/// Kategori seçim ızgarası.
struct CategoryGrid: View {
    let categories: [EntryCategory]
    @Binding var selection: EntryCategory?

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 4)

    var body: some View {
        if categories.isEmpty {
            Text("Ayarlar > Kategoriler'den kategori ekleyebilirsin.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        } else {
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(categories) { category in
                    let selected = selection === category
                    Button {
                        selection = selected ? nil : category
                    } label: {
                        VStack(spacing: 6) {
                            CategoryBadge(category: category, size: 44)
                                .overlay {
                                    Circle()
                                        .strokeBorder(Color.primary, lineWidth: selected ? 2.5 : 0)
                                        .padding(-4)
                                }
                                .opacity(selection == nil || selected ? 1 : 0.45)
                            Text(category.name)
                                .font(.caption2)
                                .lineLimit(1)
                                .foregroundStyle(selected ? .primary : .secondary)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
            .padding(.vertical, 6)
        }
    }
}
