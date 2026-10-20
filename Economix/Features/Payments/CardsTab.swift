import SwiftUI
import SwiftData
import EconomixCore

struct CardsTab: View {
    @Environment(AppRouter.self) private var router
    @Query(filter: #Predicate<Account> { !$0.isArchived }, sort: \Account.sortOrder) private var accounts: [Account]
    @Query private var entries: [LedgerEntry]

    var body: some View {
        let cards = accounts.filter(\.isCreditCard)
        if cards.isEmpty {
            ContentUnavailableView {
                Label("Kredi kartı yok", systemImage: "creditcard")
            } description: {
                Text("Ayarlar > Hesaplar ve kartlar bölümünden kartını, hesap kesim günüyle birlikte ekle.")
            }
            .padding(.top, 40)
        } else {
            let snapshots = entries.map(\.snapshot)
            ForEach(cards) { card in
                let summary = CardLedger.summary(cardID: card.id.uuidString, cycle: card.cycle,
                                                 transactions: snapshots, asOf: .now)
                CardSummaryCard(card: card, summary: summary) {
                    var request = EditorRequest(kind: .transfer)
                    request.presetToAccountID = card.id
                    request.presetAmount = summary.remainingDue.isZero ? nil : summary.remainingDue
                    router.editor = request
                }
            }
        }
    }
}

struct CardSummaryCard: View {
    let card: Account
    let summary: CardSummary
    let onPay: () -> Void

    var body: some View {
        Card {
            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color(hex: card.colorHex).gradient)
                    .frame(width: 34, height: 24)
                Text(card.name).font(.headline)
                Spacer()
                Button("Borç öde", action: onPay)
                    .buttonStyle(.glass)
                    .controlSize(.small)
            }

            let last = summary.lastStatement
            let daysLeft = FinanceCalendar.calendar.dateComponents(
                [.day], from: FinanceCalendar.calendar.startOfDay(for: .now), to: last.dueDate).day ?? 0

            VStack(alignment: .leading, spacing: 4) {
                Text("Son ekstre · \(TR.dayMonth(last.closingDate))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack(alignment: .firstTextBaseline) {
                    Text(summary.remainingDue.formatted())
                        .font(.title2.weight(.bold))
                        .monospacedDigit()
                    Spacer()
                    dueBadge(daysLeft: daysLeft)
                }
                if summary.paidSinceClosing.minor > 0 {
                    Text("Ekstre \(summary.lastStatementTotal.formatted()) · ödenen \(summary.paidSinceClosing.formatted())")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }

            Divider()

            HStack(alignment: .top) {
                StatTile(title: "Bu dönem", value: summary.openPeriodSpending,
                         caption: "Kesim \(TR.dayMonth(summary.openStatement.closingDate))")
                StatTile(title: "Gelecek taksitler", value: summary.futureInstallments)
            }

            if let limit = card.creditLimit, limit.minor > 0 {
                let ratio = summary.usedLimit.ratio(of: limit)
                VStack(alignment: .leading, spacing: 6) {
                    ProgressBar(ratio: ratio, tint: BudgetLevel.level(for: ratio).color)
                    HStack {
                        Text("Limit kullanımı \(TR.percent(ratio))")
                        Spacer()
                        Text("Kullanılabilir \((limit - summary.usedLimit).formatted(decimals: false))")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                }
            }
        }
    }

    @ViewBuilder
    private func dueBadge(daysLeft: Int) -> some View {
        if summary.remainingDue.isZero {
            Label("Ödendi", systemImage: "checkmark.circle.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(ChartPalette.single)
        } else if daysLeft < 0 {
            Label("Son ödeme geçti", systemImage: "exclamationmark.triangle.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.expense)
        } else {
            Label("Son ödeme \(TR.dayMonth(summary.lastStatement.dueDate)) · \(daysLeft) gün",
                  systemImage: daysLeft <= 3 ? "exclamationmark.circle.fill" : "calendar")
                .font(.caption.weight(.semibold))
                .foregroundStyle(daysLeft <= 3 ? Color.orange : Color.secondary)
        }
    }
}
