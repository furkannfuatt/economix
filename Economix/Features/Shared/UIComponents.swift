import SwiftUI
import EconomixCore

// MARK: - Renk

extension Color {
    init(hex: String) {
        let cleaned = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var value: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&value)
        let r, g, b: Double
        if cleaned.count == 6 {
            r = Double((value >> 16) & 0xFF) / 255
            g = Double((value >> 8) & 0xFF) / 255
            b = Double(value & 0xFF) / 255
        } else {
            r = 0.56; g = 0.56; b = 0.58
        }
        self.init(red: r, green: g, blue: b)
    }

    static let expense = Color(red: 0.90, green: 0.28, blue: 0.30)
    static let income = Color(red: 0.19, green: 0.64, blue: 0.42)
    static let transfer = Color(red: 0.35, green: 0.47, blue: 0.95)
    static let investment = Color(red: 0.62, green: 0.40, blue: 0.93)
}

enum Palette {
    static let colors = [
        "#34C759", "#30A46C", "#0E8F6B", "#32ADE6", "#0A84FF", "#5856D6", "#AF52DE", "#BF5AF2",
        "#FF2D55", "#FF375F", "#FF3B30", "#FF6482", "#FF9500", "#FF9F0A", "#FFB800", "#A2845E",
        "#64D2FF", "#8E8E93",
    ]

    static let categoryIcons = [
        "cart.fill", "basket.fill", "fork.knife", "cup.and.saucer.fill", "takeoutbag.and.cup.and.straw.fill",
        "car.fill", "fuelpump.fill", "bus.fill", "tram.fill", "airplane", "house.fill", "sofa.fill",
        "bolt.fill", "drop.fill", "flame.fill", "wifi", "phone.fill", "play.rectangle.fill", "music.note",
        "tshirt.fill", "bag.fill", "cross.case.fill", "pills.fill", "heart.fill", "book.fill",
        "graduationcap.fill", "gamecontroller.fill", "film.fill", "ticket.fill", "iphone", "laptopcomputer",
        "headphones", "sparkles", "scissors", "gift.fill", "pawprint.fill", "figure.run", "dumbbell.fill",
        "wrench.and.screwdriver.fill", "banknote.fill", "creditcard.fill", "building.columns.fill",
        "chart.line.uptrend.xyaxis", "plus.circle.fill", "briefcase.fill", "person.2.fill", "ellipsis.circle.fill",
    ]
}

// MARK: - Biçimlendirme

enum TR {
    static let locale = Locale(identifier: "tr_TR")

    private static func style(_ base: Date.FormatStyle) -> Date.FormatStyle {
        var s = base
        s.locale = locale
        s.calendar = FinanceCalendar.calendar
        s.timeZone = FinanceCalendar.calendar.timeZone
        return s
    }

    /// "18 Ekim Cumartesi"
    static func dayHeader(_ date: Date) -> String {
        date.formatted(style(.dateTime.day().month(.wide).weekday(.wide)))
    }

    /// "18 Eki 2026"
    static func shortDate(_ date: Date) -> String {
        date.formatted(style(.dateTime.day().month(.abbreviated).year()))
    }

    /// "18 Ekim"
    static func dayMonth(_ date: Date) -> String {
        date.formatted(style(.dateTime.day().month(.wide)))
    }

    /// "18 Eki"
    static func dayShortMonth(_ date: Date) -> String {
        date.formatted(style(.dateTime.day().month(.abbreviated)))
    }

    static func percent(_ value: Double) -> String {
        "%" + String(Int((value * 100).rounded()))
    }
}

extension Money {
    /// Düzenleme alanı için gruplamasız metin: "1234,56"
    var inputString: String {
        let absolute = abs(minor)
        let kurus = absolute % 100
        let base = "\(absolute / 100)"
        return kurus == 0 ? base : base + "," + (kurus < 10 ? "0\(kurus)" : "\(kurus)")
    }
}

// MARK: - Bileşenler

func hideKeyboard() {
    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
}

struct CategoryBadge: View {
    let icon: String
    let colorHex: String
    var size: CGFloat = 36

    init(icon: String, colorHex: String, size: CGFloat = 36) {
        self.icon = icon
        self.colorHex = colorHex
        self.size = size
    }

    init(category: EntryCategory?, size: CGFloat = 36) {
        self.init(icon: category?.icon ?? "questionmark", colorHex: category?.colorHex ?? "#8E8E93", size: size)
    }

    var body: some View {
        Image(systemName: icon)
            .font(.system(size: size * 0.45, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(Color(hex: colorHex).gradient, in: .circle)
    }
}

/// İşaretli ve renkli tutar: gider "-1.234,56 ₺", gelir "+…", transfer nötr.
struct AmountText: View {
    let amount: Money
    let kind: TxKind
    var font: Font = .body

    var body: some View {
        Text(text)
            .font(font.weight(.semibold))
            .monospacedDigit()
            .foregroundStyle(color)
    }

    private var text: String {
        switch kind {
        case .expense, .investment: "-" + amount.formatted()
        case .income, .divestment: "+" + amount.formatted()
        case .transfer: amount.formatted()
        }
    }

    private var color: Color {
        switch kind {
        case .expense: .primary
        case .income: .income
        case .investment, .divestment: .investment
        case .transfer: .secondary
        }
    }
}

/// Büyük tutar giriş alanı.
struct AmountField: View {
    @Binding var text: String
    var tint: Color = .primary
    @FocusState.Binding var focused: Bool

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            TextField("0", text: $text)
                .keyboardType(.decimalPad)
                .font(.system(size: 46, weight: .bold, design: .rounded))
                .multilineTextAlignment(.center)
                .foregroundStyle(tint)
                .focused($focused)
                .fixedSize()
            Text("₺")
                .font(.system(size: 30, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .contentShape(.rect)
        .onTapGesture { focused = true }
    }
}

/// Başlık + değer satırı (özet kartları için).
struct StatTile: View {
    let title: String
    let value: Money
    var tint: Color = .primary
    var caption: String?
    var captionTint: Color = .secondary

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value.formatted(decimals: false))
                .font(.headline)
                .monospacedDigit()
                .foregroundStyle(tint)
                .contentTransition(.numericText())
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            if let caption {
                Text(caption)
                    .font(.caption2)
                    .foregroundStyle(captionTint)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Bütçe/limit ilerleme çubuğu.
struct ProgressBar: View {
    let ratio: Double
    var tint: Color

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.secondary.opacity(0.15))
                Capsule()
                    .fill(tint.gradient)
                    .frame(width: geo.size.width * min(max(ratio, 0), 1))
            }
        }
        .frame(height: 8)
    }
}

extension BudgetLevel {
    var color: Color {
        switch self {
        case .ok: .income
        case .warning: .orange
        case .exceeded: .expense
        }
    }
}

/// Kart görünümlü bölüm kabı.
struct Card<Content: View>: View {
    var title: String?
    var trailing: AnyView?
    @ViewBuilder var content: Content

    init(_ title: String? = nil, trailing: AnyView? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.trailing = trailing
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if title != nil || trailing != nil {
                HStack {
                    if let title {
                        Text(title).font(.headline)
                    }
                    Spacer()
                    trailing
                }
            }
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 20))
    }
}
