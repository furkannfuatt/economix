import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import EcoomixCore

struct ImportView: View {
    private enum Stage {
        case start
        case mapping(rows: [[String]], fileName: String)
        case preview(profile: BankProfile, result: StatementParseResult)
        case done(ImportSummary)
    }

    @Environment(\.modelContext) private var context
    @Query(filter: #Predicate<Account> { !$0.isArchived }, sort: \Account.sortOrder) private var accounts: [Account]
    @State private var categories: [EntryCategory] = []

    @State private var stage: Stage = .start
    @State private var account: Account?
    @State private var showPicker = false
    @State private var candidates: [ImportCandidate] = []
    @State private var error: String?
    /// PDF okunduğunda paylaşılabilecek gizlenmiş biçim örneği (okuma sorunlarını gidermek için).
    @State private var structureSample: String?
    @State private var copiedSample = false
    @State private var readingPDF = false
    @State private var categorizing = false
    @State private var categoryMessage: String?
    @State private var categoryError: String?
    @State private var confirmRemoval = false
    @State private var removalMessage: String?

    private static let types: [UTType] = [.pdf, .commaSeparatedText, .tabSeparatedText, .plainText,
                                          UTType(filenameExtension: "xlsx"), UTType(filenameExtension: "xls")]
        .compactMap { $0 }

    var body: some View {
        Group {
            switch stage {
            case .start: startView
            case .mapping(let rows, let fileName):
                ColumnMappingView(rows: rows) { header, map in
                    parse(rows: rows, fileName: fileName, columns: (header, map))
                }
            case .preview(let profile, let result): previewView(profile: profile, result: result)
            case .done(let summary): doneView(summary)
            }
        }
        .navigationTitle("Ekstre içe aktar")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .fileImporter(isPresented: $showPicker, allowedContentTypes: Self.types) { result in
            switch result {
            case .success(let url): load(url)
            case .failure(let failure): error = failure.localizedDescription
            }
        }
        .onAppear {
            if account == nil { account = accounts.first { $0.isCreditCard } ?? accounts.first }
            #if DEBUG
            if let path = UserDefaults.standard.string(forKey: "importFile"), case .start = stage {
                load(URL(fileURLWithPath: path))
            }
            #endif
        }
    }

    // MARK: Başlangıç

    private var startView: some View {
        Form {
            Section {
                Picker("Hangi hesaba/karta?", selection: $account) {
                    ForEach(accounts) { Label($0.name, systemImage: $0.icon).tag(Account?.some($0)) }
                }
                Button("Dosya seç", systemImage: "doc.badge.plus") { showPicker = true }
                    .disabled(account == nil || readingPDF)
                if readingPDF {
                    HStack {
                        ProgressView()
                        Text("PDF okunuyor…").foregroundStyle(.secondary)
                    }
                }
            } footer: {
                Text(account?.isCreditCard == false
                     ? "Banka kartı harcamaları vadesiz hesap dökümünde görünür; bankanın hesap hareketleri dökümünü (CSV/.xlsx) seç. Banka hesaplarına ve banka kartlarına elle girdiğin kayıtlar otomatik eşleştirilir."
                     : "Bankanın uygulamasından ya da internet şubesinden indirdiğin PDF, Excel (.xlsx) veya CSV ekstresini seç. Bu karta elle girdiğin kayıtlar otomatik eşleştirilir. Dosya cihazında işlenir, hiçbir yere gönderilmez.")
            }

            if let account, let imported, !imported.isEmpty {
                Section {
                    Button("Önceki içe aktarımı sil", systemImage: "trash", role: .destructive) { confirmRemoval = true }
                        .tint(.red)
                } header: {
                    Text("Baştan aktarmak için")
                } footer: {
                    Text(Self.removalText(imported, accountName: account.name))
                }
            }
            if let removalMessage {
                Section {
                    Label(removalMessage, systemImage: "checkmark.circle")
                        .foregroundStyle(ChartPalette.single)
                }
            }

            Section("Desteklenenler") {
                Label("PDF, Excel (.xlsx) ve CSV ekstreler", systemImage: "doc.text")
                Label("Garanti BBVA (Bonus), Yapı Kredi (World), Akbank (Axess)", systemImage: "building.columns")
                Label("Kolonları tanınmayan dosyalar için elle eşleme", systemImage: "tablecells")
                Label("Taksitler plana bağlanır, aynı satır iki kez eklenmez", systemImage: "checkmark.shield")
            }
            .font(.subheadline)

            if let error {
                Section {
                    Text(error).foregroundStyle(.red)
                    structureShareLink
                }
            }
        }
        // Alttaki "İşlem ekle" çubuğu son satırları örtmesin.
        .contentMargins(.bottom, 90, for: .scrollContent)
        .confirmationDialog("Önceki içe aktarım silinsin mi?", isPresented: $confirmRemoval, titleVisibility: .visible) {
            Button("Sil ve öğrenilen kategorileri unut", role: .destructive) { removeImported(forgetLearned: true) }
            Button("Yalnızca kayıtları sil", role: .destructive) { removeImported(forgetLearned: false) }
            Button("Vazgeç", role: .cancel) {}
        } message: {
            Text("Geri alınamaz; iCloud'daki kopyadan da silinir. Öğrenilen kategorileri unutursan ekstre yeni sözlükle baştan kategorilenir; o işyerleri için elle seçtiklerin de unutulur.")
        }
    }

    /// Seçili hesaba daha önce içe aktarılanlar.
    private var imported: ImportedRecords? {
        account.flatMap { try? ImportService(context: context).importedRecords(for: $0) }
    }

    static func removalText(_ records: ImportedRecords, accountName: String) -> String {
        var removed: [String] = []
        if records.entries > 0 { removed.append("\(records.entries) işlem") }
        if records.plans > 0 { removed.append("\(records.plans) taksit planı") }
        var text = removed.isEmpty ? "" : "\(accountName) için ekstreden eklenen \(removed.joined(separator: " ve ")) silinir. "
        if records.linked > 0 {
            text += "Elle girdiğin \(records.linked) kayıt kalır; yalnızca ekstreyle eşleşmesi kaldırılır. "
        }
        return text + "Ardından ekstreyi yeniden seçebilirsin."
    }

    private func removeImported(forgetLearned: Bool) {
        guard let account, let records = imported else { return }
        do {
            try ImportService(context: context).removeImported(for: account, forgetLearned: forgetLearned)
            var parts = ["\(records.entries) işlem", "\(records.plans) taksit planı"]
            if forgetLearned, records.rules > 0 { parts.append("\(records.rules) öğrenilmiş kategori") }
            removalMessage = "Silindi: " + parts.joined(separator: ", ") + ". Şimdi ekstreyi yeniden seçebilirsin."
        } catch {
            self.error = "Silinemedi: \(error.localizedDescription)"
        }
    }

    @ViewBuilder
    private var structureShareLink: some View {
        if let structureSample {
            Button("Biçim örneğini kopyala (gizlenmiş)", systemImage: "doc.on.doc") {
                UIPasteboard.general.string = structureSample
                copiedSample = true
            }
            if copiedSample {
                Label("Kopyalandı; sohbete yapıştırabilirsin.", systemImage: "checkmark.circle")
                    .font(.caption)
                    .foregroundStyle(ChartPalette.single)
            }
            ShareLink(item: structureSample, subject: Text("Ecoomix ekstre biçim örneği")) {
                Label("Biçim örneğini paylaş (gizlenmiş)", systemImage: "square.and.arrow.up")
            }
            Text("Harcamaların görünmez: rakamlar 9, harfler X olur; yalnızca \"Tarih, Tutar, Taksit\" gibi başlıklar kalır. Bunu gönderirsen okuyucu senin bankana göre ayarlanabilir.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: Önizleme

    private func previewView(profile: BankProfile, result: StatementParseResult) -> some View {
        let included = candidates.filter(\.include)
        let expenseTotal = included.filter { $0.row.kind == .expense && $0.category?.kind != .investment }
            .map(\.row.amount).sum()

        return List {
            Section {
                LabeledContent("Banka", value: profile.name)
                LabeledContent("Okunan satır", value: "\(result.rows.count)")
                if result.skippedCount > 0 {
                    LabeledContent("Atlanan özet satırı", value: "\(result.skippedCount)")
                }
                LabeledContent("Eklenecek harcama", value: expenseTotal.formatted())
            } footer: {
                Text(result.expensesArePositive
                     ? "Harcamalar pozitif, ödeme ve iadeler negatif olarak algılandı."
                     : "Para çıkışları negatif, girişler pozitif olarak algılandı.")
            }

            categorySection

            if structureSample != nil {
                Section {
                    structureShareLink
                } header: {
                    Text("Eksik ya da hatalı satır var mı?")
                }
            }

            candidateSection("Yeni", status: .new)
            candidateSection("Yeni taksit planı", status: .newInstallmentPlan,
                             footer: "Alım tarihi taksit sırasından geriye hesaplanır; kalan taksitler ileriye eklenir.")
            candidateSection("Muhtemel tekrar", status: .possibleDuplicate,
                             footer: "Elle girdiğin aynı tutarlı bir işlem var (±2 gün). Eklenmez; senin kaydın ekstreyle eşleştirilir.")
            candidateSection("Benzer tutar", status: .similarAmount,
                             footer: "Tutarı yakın (±5 ₺ ya da ±%2) elle girilmiş bir işlem var. İşyeri de tutuyorsa aynı alışveriş sayılır ve senin kaydının tutarı ekstredeki tutara düzeltilir; tutmuyorsa satır eklenir, gerekirse işaretini kaldır.")
            candidateSection("Mevcut taksit planında", status: .installmentKnown)
            candidateSection("Karta ödeme", status: .payment,
                             footer: "Ödemeleri genelde banka hesabından transfer olarak girersin; çift saymamak için kapalı.")
            candidateSection("Ödül / bonus", status: .reward,
                             footer: "Kampanya ödülleri, bonuslar ve chip-para/puan kullanımları harcama sayılmaz; karta ödeme gibi kapalı. İstersen açıp gelir olarak ekleyebilirsin.")
            candidateSection("Zaten eklenmiş", status: .duplicate)
        }
        .safeAreaInset(edge: .bottom) {
            Button {
                commit()
            } label: {
                Text("\(included.count) işlemi içe aktar")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.glassProminent)
            .controlSize(.large)
            .disabled(included.isEmpty)
            .padding()
        }
    }

    @ViewBuilder
    private func candidateSection(_ title: String, status: ImportCandidate.Status, footer: String? = nil) -> some View {
        let indices = candidates.indices.filter { candidates[$0].status == status }
        if !indices.isEmpty {
            Section {
                let expenseCategories = categories.filter { $0.kind == .expense || $0.kind == .investment }
                ForEach(indices, id: \.self) { index in
                    CandidateRow(candidate: $candidates[index], categories: expenseCategories) { category in
                        let others = ImportCandidate.applyCategory(category, at: index, in: &candidates)
                        categoryMessage = others > 0
                            ? "\(category?.name ?? "Kategori") aynı işyerinin \(others) satırına daha uygulandı." : nil
                    }
                }
            } header: {
                Text("\(title) (\(indices.count))")
            } footer: {
                if let footer { Text(footer) }
            }
        }
    }

    /// Kategorisiz gider satırları için toplu belirleme.
    @ViewBuilder
    private var categorySection: some View {
        let uncategorized = candidates.filter { $0.include && $0.row.kind == .expense && $0.category == nil }
        if !uncategorized.isEmpty || categoryMessage != nil {
            Section {
                if let categoryError {
                    Text(categoryError).font(.footnote).foregroundStyle(.red)
                }
                if let categoryMessage {
                    Label(categoryMessage, systemImage: "checkmark.circle")
                        .font(.subheadline)
                        .foregroundStyle(ChartPalette.single)
                }
                if !uncategorized.isEmpty {
                    if GeminiKeyProvider.current != nil {
                        Button {
                            Task { await categorizeWithGemini() }
                        } label: {
                            HStack {
                                Label(categorizing ? "Gemini belirliyor…" : "Kategorisiz \(uncategorized.count) satırı Gemini ile belirle",
                                      systemImage: "sparkles")
                                Spacer()
                                if categorizing { ProgressView() }
                            }
                        }
                        .disabled(categorizing)
                    } else {
                        NavigationLink {
                            AISettingsView()
                        } label: {
                            Label("Otomatik belirleme için Gemini anahtarı ekle", systemImage: "key.fill")
                        }
                    }
                }
            } header: {
                Text("Kategoriler")
            } footer: {
                Text("Bir satıra kategori seçince aynı işyerinin diğer satırları da alır; seçimlerin öğrenilir ve sonraki ekstrelerde otomatik gelir. Gemini'ye yalnızca işyeri adları ve kategori adların gönderilir; tutar ve tarih gönderilmez. Bir dakika kadar sürebilir.")
            }
        }
    }

    private func categorizeWithGemini() async {
        guard let key = GeminiKeyProvider.current else { return }
        categorizing = true
        categoryError = nil
        defer { categorizing = false }
        let targets = candidates.indices.filter {
            candidates[$0].include && candidates[$0].row.kind == .expense && candidates[$0].category == nil
        }
        let expenseCategories = categories.filter { $0.kind == .expense || $0.kind == .investment }
        do {
            let mapping = try await GeminiCategorizer(apiKey: key)
                .categorize(merchants: targets.map { candidates[$0].row.description }, categories: expenseCategories)
            var assigned = 0
            for index in targets {
                if let category = mapping[candidates[index].row.description] {
                    candidates[index].category = category
                    candidates[index].learnsCategory = true
                    assigned += 1
                }
            }
            let missing = targets.count - assigned
            categoryMessage = "Gemini \(assigned) satıra kategori atadı" + (missing > 0 ? "; \(missing) satırı sen seç." : ".")
        } catch {
            categoryMessage = nil
            categoryError = error.localizedDescription
        }
    }

    private func doneView(_ summary: ImportSummary) -> some View {
        ContentUnavailableView {
            Label("İçe aktarıldı", systemImage: "checkmark.circle.fill")
                .foregroundStyle(ChartPalette.single)
        } description: {
            Text(Self.summaryText(summary))
        } actions: {
            Button("Başka dosya") { stage = .start }
                .buttonStyle(.glass)
        }
    }

    // MARK: Eylemler

    private func load(_ url: URL) {
        error = nil
        structureSample = nil
        copiedSample = false
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        // Ekstreler birkaç MB'tır; çok büyük bir dosya belleği doldurup uygulamayı kilitlemesin.
        if let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size > ImportLimits.maxFileBytes {
            error = "Dosya çok büyük (en fazla \(ImportLimits.maxFileBytes / 1_048_576) MB). Bankanın ekstre dosyasını seç."
            return
        }
        do {
            let data = try Data(contentsOf: url)
            let rows: [[String]]
            switch url.pathExtension.lowercased() {
            case "pdf":
                loadPDF(data, fileName: url.lastPathComponent)
                return
            case "xlsx":
                rows = try XLSXReader.rows(from: data)
            case "xls":
                error = "Eski Excel (.xls) biçimi okunamıyor. Dosyayı Numbers'ta açıp Dosya > Dışa Aktar > CSV ya da Excel (.xlsx) olarak kaydet."
                return
            default:
                rows = CSVReader.rows(from: Self.decodeText(data))
            }
            parse(rows: rows, fileName: url.lastPathComponent, columns: nil)
        } catch XLSXReader.ReadError.tooLarge {
            error = "Excel dosyası bozuk ya da bir ekstre için fazla büyük (en fazla \(ImportLimits.maxRows) satır, \(ImportLimits.maxColumns) kolon)."
        } catch {
            self.error = "Dosya okunamadı: \(error.localizedDescription)"
        }
    }

    /// Önce PDF'in metin katmanı denenir; işlem satırı çıkmazsa metin harf kodlarından çözülür
    /// (Akbank'ın ana bilgisayar çıktısı PDF'leri). Görüntüden okuma yapılmaz.
    private func loadPDF(_ data: Data, fileName: String) {
        readingPDF = true
        Task {
            let outcome = await Task.detached(priority: .userInitiated) { () -> Result<[String], any Error> in
                Result { try PDFStatementText.lines(from: data) }
            }.value
            readingPDF = false
            switch outcome {
            case .success(let lines):
                structureSample = StatementStructure.masked(lines: lines).joined(separator: "\n")
                parse(rows: PDFStatementLines.rows(from: lines), fileName: fileName,
                      columns: (0, PDFStatementLines.columns))
            case .failure:
                error = "Bu PDF okunamadı. Bankanın uygulamasından ekstreyi Excel olarak almayı dene."
            }
        }
    }

    private func parse(rows: [[String]], fileName: String, columns: (Int, ColumnMap)?) {
        guard let account else { return }
        let profile = BankProfile.detect(fileName: fileName, rows: rows)
        do {
            let result = try StatementParser.parse(rows: rows, profile: profile,
                                                   columns: columns.map { (headerIndex: $0.0, map: $0.1) },
                                                   expenseSign: ImportService.expenseSign(for: account))
            candidates = try ImportService(context: context).prepare(result, account: account)
            categories = try context.fetch(FetchDescriptor<EntryCategory>(
                predicate: #Predicate { !$0.isArchived }, sortBy: [SortDescriptor(\.sortOrder)]))
            stage = .preview(profile: profile, result: result)
        } catch StatementParser.ParseError.headerNotFound {
            stage = .mapping(rows: rows, fileName: fileName)
        } catch StatementParser.ParseError.noRows {
            error = structureSample == nil
                ? "Dosyada işlem satırı bulunamadı."
                : "PDF okundu ama işlem satırı tanınamadı. Aşağıdaki gizlenmiş biçim örneğini paylaşırsan okuyucu bankana göre ayarlanabilir."
            stage = .start
        } catch {
            self.error = "Çözümlenemedi: \(error.localizedDescription)"
            stage = .start
        }
    }

    private func commit() {
        guard let account else { return }
        do {
            let summary = try ImportService(context: context).commit(candidates, account: account)
            stage = .done(summary)
        } catch {
            self.error = "İçe aktarılamadı: \(error.localizedDescription)"
        }
    }

    static func summaryText(_ summary: ImportSummary) -> String {
        var parts = ["\(summary.added) işlem eklendi"]
        if summary.plansCreated > 0 { parts.append("\(summary.plansCreated) taksit planı oluşturuldu") }
        if summary.linked > 0 { parts.append("\(summary.linked) satır elle girdiğin kayıtlarla eşleştirildi") }
        if summary.amountsCorrected > 0 { parts.append("\(summary.amountsCorrected) kaydın tutarı ekstreye göre düzeltildi") }
        if summary.skipped > 0 { parts.append("\(summary.skipped) satır atlandı") }
        return parts.joined(separator: ", ") + "."
    }

    /// UTF-8, olmazsa Türkçe Windows (1254), olmazsa Latin-1.
    static func decodeText(_ data: Data) -> String {
        if let text = String(data: data, encoding: .utf8) { return text }
        let turkish = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(
            CFStringEncoding(CFStringEncodings.windowsLatin5.rawValue)))
        return String(data: data, encoding: turkish) ?? String(decoding: data, as: UTF8.self)
    }
}

private struct CandidateRow: View {
    @Binding var candidate: ImportCandidate
    let categories: [EntryCategory]
    let onSelectCategory: (EntryCategory?) -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Button {
                candidate.include.toggle()
            } label: {
                Image(systemName: candidate.include ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(candidate.include ? ChartPalette.single : Color.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(candidate.include ? "Dahil" : "Hariç")

            VStack(alignment: .leading, spacing: 4) {
                Text(candidate.row.description).font(.subheadline).lineLimit(2)
                HStack(spacing: 6) {
                    Text(TR.shortDate(candidate.row.date))
                    if let marker = candidate.row.installment {
                        Text("· Taksit \(marker.current)/\(marker.total)")
                    }
                    if candidate.row.kind == .refund { Text("· İade") }
                    if candidate.row.kind == .reward { Text("· Ödül") }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                if let entry = candidate.matchedEntry {
                    MatchNote(candidate: candidate, entry: entry)
                }
                if candidate.row.kind == .expense {
                    Menu {
                        Button("Kategorisiz") { onSelectCategory(nil) }
                        ForEach(categories) { category in
                            Button(category.name, systemImage: category.icon) { onSelectCategory(category) }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: candidate.category?.icon ?? "questionmark.circle")
                            Text(candidate.category?.name ?? "Kategori seç")
                            Image(systemName: "chevron.up.chevron.down").font(.caption2)
                        }
                        .font(.caption)
                        .foregroundStyle(candidate.category.map { Color(hex: $0.colorHex) } ?? .secondary)
                    }
                }
            }
            Spacer(minLength: 4)
            Text(amountText)
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(candidate.row.kind == .expense ? Color.primary : Color.income)
        }
        .opacity(candidate.include ? 1 : 0.55)
    }

    private var amountText: String {
        let value = candidate.row.amount.formatted()
        return candidate.row.kind == .expense ? "-" + value : "+" + value
    }
}

/// Satırın eşleştiği kayıt: "Elle girdiğin: Migros · 2 Eki · 245,00 ₺".
private struct MatchNote: View {
    let candidate: ImportCandidate
    let entry: LedgerEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Label {
                Text("\(prefix): \(entry.displayTitle) · \(TR.dayMonth(entry.date)) · \(entry.amount.formatted())")
            } icon: {
                Image(systemName: icon)
            }
            if let difference = candidate.amountDifference {
                Text(candidate.include
                     ? "Fark \(difference.formatted()) · benzer olabilir, aynıysa işareti kaldır"
                     : "Fark \(difference.formatted()) · kaydının tutarı \(candidate.row.amount.formatted()) olarak düzeltilecek")
            }
        }
        .font(.caption)
        .foregroundStyle(candidate.status == .similarAmount && candidate.include ? Color.orange : Color.secondary)
    }

    private var prefix: String {
        candidate.status == .installmentKnown ? "Taksit planında" : "Elle girdiğin"
    }

    private var icon: String {
        switch candidate.status {
        case .installmentKnown: "calendar.badge.checkmark"
        case .similarAmount: "equal.circle"
        default: "link"
        }
    }
}

/// Başlığı tanınmayan dosyalar için kolonları elle seçme.
private struct ColumnMappingView: View {
    let rows: [[String]]
    let onContinue: (Int, ColumnMap) -> Void

    @State private var headerRow = 0
    @State private var dateColumn = 0
    @State private var descriptionColumn = 1
    @State private var amountColumn = 2

    private var columnCount: Int { rows.prefix(30).map(\.count).max() ?? 0 }

    var body: some View {
        Form {
            Section {
                Text("Dosyanın kolonları otomatik tanınamadı. İlk satırlara bakıp hangi kolonun ne olduğunu seç.")
                    .font(.subheadline)
            }
            Section("İlk satırlar") {
                ForEach(Array(rows.prefix(12).enumerated()), id: \.offset) { index, row in
                    Text("\(index + 1). " + row.joined(separator: " | "))
                        .font(.caption.monospaced())
                        .lineLimit(1)
                        .foregroundStyle(index == headerRow ? Color.accentColor : .primary)
                }
            }
            Section("Eşleme") {
                Picker("Başlık satırı", selection: $headerRow) {
                    Text("Başlık yok").tag(-1)
                    ForEach(0..<min(rows.count, 30), id: \.self) { Text("\($0 + 1). satır").tag($0) }
                }
                columnPicker("Tarih", selection: $dateColumn)
                columnPicker("Açıklama", selection: $descriptionColumn)
                columnPicker("Tutar", selection: $amountColumn)
            }
            Section {
                Button("Devam") {
                    onContinue(headerRow, ColumnMap(date: dateColumn, description: descriptionColumn, amount: amountColumn))
                }
            }
        }
    }

    private func columnPicker(_ title: String, selection: Binding<Int>) -> some View {
        Picker(title, selection: selection) {
            ForEach(0..<max(columnCount, 1), id: \.self) { column in
                Text(label(for: column)).tag(column)
            }
        }
    }

    private func label(for column: Int) -> String {
        let letter = String(UnicodeScalar(UInt8(65 + column % 26)))
        let sampleRow = headerRow >= 0 && headerRow < rows.count ? rows[headerRow] : rows.first ?? []
        let sample = column < sampleRow.count ? sampleRow[column] : ""
        return sample.isEmpty ? letter : "\(letter) · \(sample.prefix(18))"
    }
}
