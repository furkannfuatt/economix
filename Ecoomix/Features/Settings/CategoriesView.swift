import SwiftUI
import SwiftData
import EcoomixCore

struct CategoriesView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \EntryCategory.sortOrder) private var categories: [EntryCategory]
    @State private var kind: TxKind = .expense
    @State private var editing: CategoryEditRequest?

    private var visible: [EntryCategory] { categories.filter { $0.kind == kind } }

    var body: some View {
        List {
            Section {
                Picker("Tür", selection: $kind) {
                    Text("Gider").tag(TxKind.expense)
                    Text("Gelir").tag(TxKind.income)
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
            }

            Section {
                ForEach(visible) { category in
                    Button {
                        editing = CategoryEditRequest(category: category, kind: kind)
                    } label: {
                        HStack(spacing: 12) {
                            CategoryBadge(category: category)
                            Text(category.name)
                                .foregroundStyle(category.isArchived ? .secondary : .primary)
                            Spacer()
                            if let limit = category.monthlyLimit {
                                Text("Bütçe \(limit.formatted(decimals: false))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                }
                .onMove(perform: move)
            } footer: {
                if kind == .expense {
                    Text("Bir kategoriye aylık bütçe koyarsan %80 ve %100'e ulaştığında bildirim alırsın.")
                }
            }
        }
        .navigationTitle("Kategoriler")
        .toolbar {
            EditButton()
            Button("Ekle", systemImage: "plus") { editing = CategoryEditRequest(kind: kind) }
        }
        .sheet(item: $editing) { request in
            CategoryEditView(request: request)
        }
    }

    private func move(from source: IndexSet, to destination: Int) {
        var ordered = visible
        ordered.move(fromOffsets: source, toOffset: destination)
        for (index, category) in ordered.enumerated() { category.sortOrder = index }
        try? context.save()
    }
}

struct CategoryEditRequest: Identifiable {
    let id = UUID()
    var category: EntryCategory?
    var kind: TxKind
}

struct CategoryEditView: View {
    let request: CategoryEditRequest

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var categories: [EntryCategory]

    @State private var name = ""
    @State private var icon = "tag.fill"
    @State private var colorHex = Palette.colors[0]
    @State private var limitText = ""
    @State private var isArchived = false
    @State private var loaded = false
    @State private var confirmDelete = false

    private var kind: TxKind { request.category?.kind ?? request.kind }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        CategoryBadge(icon: icon, colorHex: colorHex, size: 44)
                        TextField("Kategori adı", text: $name)
                            .font(.title3)
                    }
                }

                if kind == .expense {
                    Section {
                        TextField("Aylık bütçe (boş = limitsiz)", text: $limitText)
                            .keyboardType(.decimalPad)
                    } header: {
                        Text("Bütçe")
                    }
                }

                Section("Renk") {
                    ColorPalettePicker(selection: $colorHex)
                }

                Section("Simge") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: 14) {
                        ForEach(Palette.categoryIcons, id: \.self) { symbol in
                            Image(systemName: symbol)
                                .font(.title3)
                                .frame(width: 40, height: 40)
                                .foregroundStyle(symbol == icon ? .white : .primary)
                                .background(symbol == icon ? Color(hex: colorHex) : Color.secondary.opacity(0.12),
                                            in: .circle)
                                .onTapGesture { icon = symbol }
                        }
                    }
                    .padding(.vertical, 6)
                }

                if request.category != nil {
                    Section {
                        Toggle("Arşivle", isOn: $isArchived)
                        Button("Kategoriyi sil", role: .destructive) { confirmDelete = true }
                    } footer: {
                        Text("Silinen kategorinin işlemleri “Kategorisiz” olur.")
                    }
                }
            }
            .navigationTitle(request.category == nil ? "Yeni kategori" : "Kategoriyi düzenle")
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
            .confirmationDialog("Kategori silinecek.", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Sil", role: .destructive) {
                    if let category = request.category {
                        context.delete(category)
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
        guard let category = request.category else { return }
        name = category.name
        icon = category.icon
        colorHex = category.colorHex
        limitText = category.monthlyLimit?.inputString ?? ""
        isArchived = category.isArchived
    }

    private func save() {
        let category = request.category ?? EntryCategory(name: name, icon: icon, colorHex: colorHex, kind: kind)
        if request.category == nil {
            category.sortOrder = (categories.map(\.sortOrder).max() ?? 0) + 1
            context.insert(category)
        }
        category.name = name.trimmingCharacters(in: .whitespaces)
        category.icon = icon
        category.colorHex = colorHex
        category.monthlyLimit = Money.parse(limitText).flatMap { $0.minor > 0 ? $0 : nil }
        category.isArchived = isArchived
        try? context.save()
        dismiss()
    }
}
