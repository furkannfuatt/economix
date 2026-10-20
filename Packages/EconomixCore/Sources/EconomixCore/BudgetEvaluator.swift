import Foundation

public enum BudgetLevel: Int, Comparable, Sendable {
    case ok, warning, exceeded

    public static func < (lhs: BudgetLevel, rhs: BudgetLevel) -> Bool { lhs.rawValue < rhs.rawValue }

    public static func level(for ratio: Double) -> BudgetLevel {
        if ratio >= BudgetEvaluator.exceededThreshold { return .exceeded }
        if ratio >= BudgetEvaluator.warningThreshold { return .warning }
        return .ok
    }
}

public struct BudgetStatus: Hashable, Sendable {
    public let limit: Money
    public let spent: Money
    /// Ay sonuna kadar aynı hızla harcanırsa ulaşılacak tutar.
    public let projected: Money

    public var remaining: Money { limit - spent }
    public var ratio: Double { spent.ratio(of: limit) }
    public var level: BudgetLevel { .level(for: ratio) }
    public var projectedLevel: BudgetLevel { .level(for: projected.ratio(of: limit)) }
}

public enum BudgetEvaluator {
    public static let warningThreshold = 0.8
    public static let exceededThreshold = 1.0

    public static func evaluate(limit: Money, spent: Money, month: YearMonth, asOf date: Date,
                                rule: MonthRule = .calendarMonths) -> BudgetStatus {
        var projected = spent
        if rule.period(of: month).contains(date) {
            let elapsedDays = rule.elapsedDays(in: month, asOf: date)
            projected = spent.scaled(numerator: rule.dayCount(of: month), denominator: elapsedDays)
        }
        return BudgetStatus(limit: limit, spent: spent, projected: projected)
    }

    /// Harcama `before` → `after` olunca yeni geçilen eşikler (bildirim için).
    public static func crossedThresholds(limit: Money, before: Money, after: Money,
                                         thresholds: [Double] = [warningThreshold, exceededThreshold]) -> [Double] {
        guard limit.minor > 0 else { return [] }
        let old = before.ratio(of: limit), new = after.ratio(of: limit)
        return thresholds.filter { old < $0 && new >= $0 }
    }
}
