#if DEBUG
import Foundation
import SwiftData
import EcoomixCore

/// Simülatörde görsel kontrol için 12 aylık gerçekçi veri. Yalnızca `-demoData` ile, ayrı yerel dosyaya yazılır.
enum DemoData {
    static func loadIfNeeded(into context: ModelContext) throws {
        guard try context.fetchCount(FetchDescriptor<LedgerEntry>()) == 0 else { return }
        try SeedService.seedDefaults(in: context)

        let categories = try context.fetch(FetchDescriptor<EntryCategory>())
        func cat(_ key: String) -> EntryCategory? { categories.first { $0.seedKey == key } }

        let cash = try context.fetch(FetchDescriptor<Account>()).first!
        let bank = makeAccount("Maaş Hesabı", .bank, "#0A84FF", context: context)
        let bonus = makeAccount("Garanti BBVA Bonus", .creditCard, "#0E8F6B", statementDay: 15, context: context)
        let world = makeAccount("Yapı Kredi World", .creditCard, "#5856D6", statementDay: 5, context: context)
        let axess = makeAccount("Akbank Axess", .creditCard, "#FF3B30", statementDay: 25, context: context)
        bonus.creditLimitMinor = 150_000_00
        world.creditLimitMinor = 90_000_00
        axess.creditLimitMinor = 60_000_00

        cat("market")?.monthlyLimitMinor = 9_000_00
        cat("yemek")?.monthlyLimitMinor = 4_500_00
        cat("eglence")?.monthlyLimitMinor = 1_500_00
        cat("giyim")?.monthlyLimitMinor = 2_500_00
        cat("ulasim")?.monthlyLimitMinor = 6_000_00

        var rng = SeededGenerator(seed: 42)
        let calendar = FinanceCalendar.calendar
        let today = calendar.startOfDay(for: .now)
        let current = YearMonth(date: today)
        let service = LedgerService(context: context)

        func add(_ lira: Double, _ kind: TxKind, _ date: Date, _ category: EntryCategory?, _ account: Account,
                 _ merchant: String, to: Account? = nil) {
            guard date <= today else { return }
            let entry = LedgerEntry(amount: Money(minor: Int(lira * 100)), kind: kind, date: date, merchant: merchant)
            context.insert(entry)
            entry.category = category
            entry.account = account
            entry.toAccount = to
        }

        let markets = ["Migros", "A101", "BİM", "ŞOK Market", "CarrefourSA", "Macrocenter"]
        let food = ["Starbucks", "Yemeksepeti", "Getir Yemek", "Simit Sarayı", "Kahve Dünyası", "Trendyol Yemek", "Burger King"]
        let fun = ["Biletix", "Cinemaximum", "Steam", "Bowling"]
        let clothes = ["Zara", "LC Waikiki", "Koton", "Decathlon"]

        for offset in (0..<12).reversed() {
            let month = current.adding(months: -offset)
            let winter = [11, 12, 1, 2, 3].contains(month.month)
            func day(_ d: Int) -> Date { calendar.date(byAdding: .hour, value: 12, to: month.date(day: d))! }
            func randomDay() -> Date { day(Int.random(in: 1...month.dayCount, using: &rng)) }
            func pick<T>(_ list: [T]) -> T { list[Int.random(in: 0..<list.count, using: &rng)] }
            func amount(_ range: ClosedRange<Double>) -> Double { (Double.random(in: range, using: &rng) * 100).rounded() / 100 }
            let cards = [bonus, axess, world]

            if offset % 3 == 1 { add(amount(4_000...9_000), .income, day(20), cat("freelance"), bank, "Freelance proje") }
            add(amount(650...1_100), .expense, day(12), cat("fatura"), bank, "Enerjisa Elektrik")
            add(winter ? amount(1_800...3_200) : amount(250...600), .expense, day(14), cat("fatura"), bank, "İGDAŞ Doğalgaz")
            add(449.90, .expense, day(8), cat("fatura"), world, "Türk Telekom İnternet")
            add(599, .expense, day(18), cat("fatura"), world, "Turkcell")

            for _ in 0..<Int.random(in: 9...13, using: &rng) {
                add(amount(180...1_900), .expense, randomDay(), cat("market"), pick(cards), pick(markets))
            }
            for _ in 0..<Int.random(in: 14...22, using: &rng) {
                add(amount(75...480), .expense, randomDay(), cat("yemek"), Bool.random(using: &rng) ? bonus : cash, pick(food))
            }
            for _ in 0..<4 {
                add(amount(1_400...2_300), .expense, randomDay(), cat("ulasim"), bonus, Bool.random(using: &rng) ? "Opet" : "Shell")
            }
            add(amount(250...400), .expense, day(2), cat("ulasim"), cash, "İstanbulkart Dolum")
            for _ in 0..<Int.random(in: 1...3, using: &rng) {
                add(amount(150...900), .expense, randomDay(), cat("eglence"), axess, pick(fun))
            }
            if Int.random(in: 0..<3, using: &rng) == 0 {
                add(amount(600...3_500), .expense, randomDay(), cat("giyim"), axess, pick(clothes))
            }
            if Int.random(in: 0..<4, using: &rng) == 0 {
                add(amount(300...1_500), .expense, randomDay(), cat("saglik"), bank, "Eczane")
            }
            add(amount(200...700), .expense, randomDay(), cat("bakim"), cash, "Kuaför")

            // Kart borcu ödemeleri
            add(amount(14_000...19_000), .transfer, day(25), nil, bank, "", to: bonus)
            add(amount(3_500...6_000), .transfer, day(15), nil, bank, "", to: world)
            add(amount(3_000...6_500), .transfer, day(5), nil, bank, "", to: axess)
        }

        func ago(_ months: Int, day: Int) -> Date { current.adding(months: -months).date(day: day) }

        // Düzenli kalemler: geçmiş vadeleri RecurringGenerator üretir.
        let start = current.adding(months: -11).start
        func recurring(_ title: String, _ lira: Double, _ kind: TxKind, _ frequency: Frequency, day: Int,
                       _ category: EntryCategory?, _ account: Account, subscription: Bool, startDate: Date? = nil) {
            let item = RecurringItem(title: title, amount: Money(minor: Int(lira * 100)), kind: kind,
                                     frequency: frequency, dayOfMonth: day, startDate: startDate ?? start,
                                     isSubscription: subscription)
            context.insert(item)
            item.category = category
            item.account = account
        }
        recurring("Maaş", 62_000, .income, .monthly, day: 1, cat("maas"), bank, subscription: false)
        recurring("Kira", 18_000, .expense, .monthly, day: 5, cat("kira"), bank, subscription: false)
        recurring("Netflix", 229.99, .expense, .monthly, day: 3, cat("abonelik"), bonus, subscription: true)
        recurring("Spotify", 99.99, .expense, .monthly, day: 9, cat("abonelik"), bonus, subscription: true)
        recurring("YouTube Premium", 79.99, .expense, .monthly, day: 11, cat("abonelik"), world, subscription: true)
        recurring("Apple iCloud+", 39.99, .expense, .monthly, day: 16, cat("abonelik"), world, subscription: true)
        recurring("Amazon Prime", 149.90, .expense, .monthly, day: 21, cat("abonelik"), axess, subscription: true)
        recurring("MacFit", 1_750, .expense, .monthly, day: 1, cat("eglence"), bonus, subscription: true)
        recurring("Microsoft 365", 1_299, .expense, .yearly, day: 12, cat("abonelik"), world, subscription: true,
                  startDate: current.adding(months: -7).start)
        try context.save()
        try RecurringGenerator(context: context).run()

        try service.addInstallmentPurchase(total: Money(minor: 72_000_00), count: 12, purchaseDate: ago(4, day: 10),
                                           category: cat("elektronik"), account: bonus, merchant: "Apple Store",
                                           title: "iPhone 17 Pro")
        try service.addInstallmentPurchase(total: Money(minor: 45_000_00), count: 9, purchaseDate: ago(7, day: 22),
                                           category: cat("elektronik"), account: world, merchant: "MediaMarkt",
                                           title: "Dizüstü bilgisayar")
        try service.addInstallmentPurchase(total: Money(minor: 24_000_00), count: 6, purchaseDate: ago(2, day: 3),
                                           category: cat("ev"), account: axess, merchant: "IKEA", title: "Koltuk takımı")
        try service.addInstallmentPurchase(total: Money(minor: 18_000_00), count: 3, purchaseDate: ago(1, day: 17),
                                           category: cat("seyahat"), account: bonus, merchant: "Pegasus",
                                           title: "Bodrum tatili")
        try context.save()
    }

    private static func makeAccount(_ name: String, _ type: AccountType, _ color: String, statementDay: Int = 15,
                                    context: ModelContext) -> Account {
        let account = Account(name: name, type: type)
        account.colorHex = color
        account.statementDay = statementDay
        context.insert(account)
        return account
    }
}

/// Tekrarlanabilir demo verisi için SplitMix64.
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
#endif
