import SwiftUI
import SwiftData
import EcoomixCore

struct AccountsView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Account.sortOrder) private var accounts: [Account]
    @State private var editing: AccountEditRequest?

    var body: some View {
        List {
            ForEach(AccountType.allCases) { type in
                let group = accounts.filter { $0.type == type }
                if !group.isEmpty {
                    Section(type.title) {
                        ForEach(group) { account in
                            Button {
                                editing = AccountEditRequest(account: account)
                            } label: {
                                AccountRow(account: account)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
        .navigationTitle("Hesaplar ve kartlar")
        .toolbar {
            Menu {
                Button("Yeni hesap", systemImage: "plus") { editing = AccountEditRequest() }
                Section("Kredi kartı şablonları") {
                    ForEach(CardPreset.all.filter { $0.type == .creditCard }) { preset in
                        Button(preset.name, systemImage: AccountType.creditCard.defaultIcon) {
                            editing = AccountEditRequest(preset: preset)
                        }
                    }
                }
                Section("Banka kartı şablonları") {
                    ForEach(CardPreset.all.filter { $0.type == .debitCard }) { preset in
                        Button(preset.name, systemImage: AccountType.debitCard.defaultIcon) {
                            editing = AccountEditRequest(preset: preset)
                        }
                    }
                }
            } label: {
                Label("Ekle", systemImage: "plus")
            }
        }
        .sheet(item: $editing) { request in
            AccountEditView(request: request)
        }
    }
}

struct AccountRow: View {
    let account: Account

    var body: some View {
        HStack(spacing: 12) {
            CategoryBadge(icon: account.icon, colorHex: account.colorHex)
            VStack(alignment: .leading, spacing: 2) {
                Text(account.name)
                if account.isCreditCard {
                    Text("Kesim: her ayın \(account.statementDay). günü · Son ödeme +\(account.dueOffsetDays) gün")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if account.isArchived {
                Text("Arşiv").font(.caption).foregroundStyle(.secondary)
            }
        }
        .contentShape(.rect)
    }
}

struct CardPreset: Identifiable {
    let id: String
    let name: String
    let colorHex: String
    let type: AccountType

    static let all = [
        CardPreset(id: "bonus", name: "Garanti BBVA Bonus", colorHex: "#0E8F6B", type: .creditCard),
        CardPreset(id: "world", name: "Yapı Kredi World", colorHex: "#5856D6", type: .creditCard),
        CardPreset(id: "axess", name: "Akbank Axess", colorHex: "#FF3B30", type: .creditCard),
        CardPreset(id: "garanti-debit", name: "Garanti BBVA Banka Kartı", colorHex: "#30A46C", type: .debitCard),
        CardPreset(id: "yapikredi-debit", name: "Yapı Kredi Banka Kartı", colorHex: "#AF52DE", type: .debitCard),
        CardPreset(id: "akbank-debit", name: "Akbank Banka Kartı", colorHex: "#FF6482", type: .debitCard),
    ]
}

struct AccountEditRequest: Identifiable {
    let id = UUID()
    var account: Account?
    var preset: CardPreset?
}

struct AccountEditView: View {
    let request: AccountEditRequest

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var accounts: [Account]

    @State private var name = ""
    @State private var type: AccountType = .bank
    @State private var colorHex = Palette.colors[4]
    @State private var openingBalance = ""
    @State private var statementDay = 15
    @State private var dueOffsetDays = 10
    @State private var creditLimit = ""
    @State private var isArchived = false
    @State private var loaded = false
    @State private var confirmDelete = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        CategoryBadge(icon: type.defaultIcon, colorHex: colorHex, size: 44)
                        TextField("Hesap adı", text: $name)
                            .font(.title3)
                    }
                    Picker("Tür", selection: $type) {
                        ForEach(AccountType.allCases) { Text($0.title).tag($0) }
                    }
                }

                Section("Renk") {
                    ColorPalettePicker(selection: $colorHex)
                }

                if type == .creditCard {
                    Section {
                        Picker("Hesap kesim günü", selection: $statementDay) {
                            ForEach(1...31, id: \.self) { Text("\($0)").tag($0) }
                        }
                        Stepper("Son ödeme: kesimden \(dueOffsetDays) gün sonra",
                                value: $dueOffsetDays, in: 1...30)
                        TextField("Kart limiti (isteğe bağlı)", text: $creditLimit)
                            .keyboardType(.decimalPad)
                    } header: {
                        Text("Kart ayarları")
                    } footer: {
                        Text("Kesim gününden sonraki harcamalar bir sonraki ekstreye düşer. Ekstrendeki tarihlere göre ayarla.")
                    }
                } else if type == .debitCard {
                    Section {
                        Label("Harcamalar doğrudan vadesiz hesaptan çekilir", systemImage: "info.circle")
                            .font(.subheadline)
                    } footer: {
                        Text("Banka kartında taksit ve ekstre olmaz. Harcamaları ay sonunda bankanın vadesiz hesap dökümüyle içe aktarabilirsin.")
                    }
                } else {
                    Section {
                        TextField("Açılış bakiyesi", text: $openingBalance)
                            .keyboardType(.decimalPad)
                    } footer: {
                        Text("Takibe başladığın gündeki bakiye. Bakiye hesabı bu tutardan başlar.")
                    }
                }

                if request.account != nil {
                    Section {
                        Toggle("Arşivle (yeni işlemlerde gösterme)", isOn: $isArchived)
                        Button("Hesabı sil", role: .destructive) { confirmDelete = true }
                    } footer: {
                        Text("Silinen hesabın işlemleri silinmez, hesapsız kalır.")
                    }
                }
            }
            .navigationTitle(request.account == nil ? "Yeni hesap" : "Hesabı düzenle")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Vazgeç", systemImage: "xmark") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Kaydet", systemImage: "checkmark", action: save)
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .confirmationDialog("Hesap silinecek.", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Sil", role: .destructive) {
                    if let account = request.account {
                        context.delete(account)
                        try? context.save()
                    }
                    dismiss()
                }
            }
            .onAppear(perform: load)
        }
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        if let account = request.account {
            name = account.name
            type = account.type
            colorHex = account.colorHex
            openingBalance = account.openingBalanceMinor == 0 ? "" : account.openingBalance.inputString
            statementDay = account.statementDay
            dueOffsetDays = account.dueOffsetDays
            creditLimit = account.creditLimit?.inputString ?? ""
            isArchived = account.isArchived
        } else if let preset = request.preset {
            name = preset.name
            type = preset.type
            colorHex = preset.colorHex
        }
    }

    private func save() {
        let account = request.account ?? Account(name: name, type: type)
        if request.account == nil {
            account.sortOrder = (accounts.map(\.sortOrder).max() ?? 0) + 1
            context.insert(account)
        }
        account.name = name.trimmingCharacters(in: .whitespaces)
        account.type = type
        account.icon = type.defaultIcon
        account.colorHex = colorHex
        account.openingBalanceMinor = Money.parse(openingBalance)?.minor ?? 0
        account.statementDay = statementDay
        account.dueOffsetDays = dueOffsetDays
        account.creditLimitMinor = Money.parse(creditLimit)?.minor
        account.isArchived = isArchived
        try? context.save()
        dismiss()
    }
}

struct ColorPalettePicker: View {
    @Binding var selection: String

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: 12) {
            ForEach(Palette.colors, id: \.self) { hex in
                Circle()
                    .fill(Color(hex: hex).gradient)
                    .frame(width: 34, height: 34)
                    .overlay {
                        if hex == selection {
                            Image(systemName: "checkmark")
                                .font(.caption.bold())
                                .foregroundStyle(.white)
                        }
                    }
                    .onTapGesture { selection = hex }
                    .accessibilityAddTraits(hex == selection ? .isSelected : [])
            }
        }
        .padding(.vertical, 6)
    }
}
