import Foundation
import Testing
@testable import EcoomixCore

@Suite("Bütçe")
struct BudgetEvaluatorTests {
    let october = YearMonth(year: 2026, month: 10)

    @Test("Ay ortasında gidişata göre tahmin")
    func projection() {
        let s = BudgetEvaluator.evaluate(limit: tl(6_000), spent: tl(3_000), month: october, asOf: d(2026, 10, 10, hour: 9))
        #expect(s.ratio == 0.5)
        #expect(s.level == .ok)
        #expect(s.projected == tl(9_300))
        #expect(s.projectedLevel == .exceeded)
        #expect(s.remaining == tl(3_000))
    }

    @Test("Eşik seviyeleri", arguments: [(4_700, BudgetLevel.ok), (4_800, .warning), (6_000, .exceeded), (7_000, .exceeded)])
    func levels(spent: Int, expected: BudgetLevel) {
        let s = BudgetEvaluator.evaluate(limit: tl(6_000), spent: tl(spent), month: october, asOf: d(2026, 11, 2))
        #expect(s.level == expected)
    }

    @Test("Geçmiş ayda tahmin harcamaya eşittir")
    func pastMonth() {
        let s = BudgetEvaluator.evaluate(limit: tl(6_000), spent: tl(2_000), month: october, asOf: d(2026, 12, 1))
        #expect(s.projected == tl(2_000))
    }

    @Test("Aşılan eşikler yalnızca yeni geçişlerde döner")
    func crossings() {
        #expect(BudgetEvaluator.crossedThresholds(limit: tl(1_000), before: tl(700), after: tl(1_050)) == [0.8, 1.0])
        #expect(BudgetEvaluator.crossedThresholds(limit: tl(1_000), before: tl(850), after: tl(900)).isEmpty)
        #expect(BudgetEvaluator.crossedThresholds(limit: tl(1_000), before: .zero, after: tl(800)) == [0.8])
        #expect(BudgetEvaluator.crossedThresholds(limit: .zero, before: .zero, after: tl(800)).isEmpty)
    }
}
