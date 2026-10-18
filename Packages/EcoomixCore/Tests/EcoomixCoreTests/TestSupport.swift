import Foundation
@testable import EcoomixCore

/// Testlerde okunaklı tarih: d(2026, 10, 15)
func d(_ year: Int, _ month: Int, _ day: Int, hour: Int = 0) -> Date {
    FinanceCalendar.calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
}

func tl(_ lira: Int) -> Money { Money(minor: lira * 100) }
