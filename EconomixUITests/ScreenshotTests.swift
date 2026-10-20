import XCTest

/// Demo veriyle ekranları gezer ve görüntüleri SCREENSHOT_DIR klasörüne yazar (make screens).
final class ScreenshotTests: XCTestCase {
    private let outputDir = ProcessInfo.processInfo.environment["SCREENSHOT_DIR"].map { URL(fileURLWithPath: $0) }

    @MainActor
    func testCaptureScreens() {
        let app = XCUIApplication()
        app.launchArguments = ["-demoData", "-tab", "summary", "-paymentsSection", "Taksitler"]
        app.launch()
        sleep(3)
        func snap(_ name: String) { capture(name) }
        func tab(_ title: String) { selectTab(title, in: app) }

        snap("01-ozet")
        app.swipeUp()
        snap("02-ozet-dagilim")
        app.swipeUp()
        snap("03-ozet-oneriler")

        if app.buttons["Tümü"].firstMatch.waitForExistence(timeout: 2) {
            app.buttons["Tümü"].firstMatch.tap()
            sleep(1)
            snap("04-oneriler")
            app.swipeUp()
            snap("05-oneriler-alt")
            app.navigationBars.buttons.firstMatch.tap()
        }

        tab("Ödemeler")
        app.swipeUp()
        snap("09-taksitler-liste")
        app.buttons["Düzenli"].firstMatch.tap()
        sleep(1)
        app.swipeUp()
        snap("10-duzenli-alt")

        tab("Ayarlar")
        snap("11-ayarlar")

        // Kategoriler > Yatırım sekmesi
        app.buttons["Kategoriler ve bütçeler"].firstMatch.tap()
        app.buttons["Yatırım"].firstMatch.tap()
        sleep(1)
        snap("23-kategoriler-yatirim")
        app.navigationBars.buttons.firstMatch.tap()

        // Hızlı ekle: yatırım türü
        app.buttons["İşlem ekle"].firstMatch.tap()
        if app.buttons["Yatırım"].firstMatch.waitForExistence(timeout: 3) {
            app.buttons["Yatırım"].firstMatch.tap()
            sleep(1)
            snap("24-ekle-yatirim")
        }
    }

    /// Raporlar: her dönem türü, haftalık gruplama, döküm listesi ve alttaki grafik kartları.
    @MainActor
    func testCaptureReports() {
        let app = XCUIApplication()
        app.launchArguments = ["-demoData", "-tab", "reports"]
        app.launch()
        sleep(3)
        func snap(_ name: String) { capture(name) }
        func range(_ title: String) {
            for _ in 0..<8 where !app.buttons[title].firstMatch.isHittable { app.swipeDown() }
            app.buttons[title].firstMatch.tap()
            sleep(1)
        }

        range("6 Ay")
        snap("30-rapor-6ay")
        for name in ["31-rapor-6ay-kumulatif", "32-rapor-6ay-gelir-gider", "33-rapor-6ay-kategoriler",
                     "34-rapor-6ay-haftanin-gunleri", "35-rapor-6ay-isyerleri"] {
            app.swipeUp()
            snap(name)
        }

        range("Ay")
        snap("36-rapor-ay")
        app.buttons["Haftalık"].firstMatch.tap()
        sleep(1)
        snap("37-rapor-ay-haftalik")
        app.buttons["Dökümü göster"].firstMatch.tap()
        sleep(1)
        app.swipeUp()
        snap("38-rapor-ay-dokum")
        app.swipeUp()
        snap("39-rapor-ay-kumulatif")

        range("Hafta")
        snap("40-rapor-hafta")
        app.swipeUp()
        snap("41-rapor-hafta-kumulatif")

        range("Özel")
        snap("42-rapor-ozel")
        app.swipeUp()
        snap("43-rapor-ozel-alt")

        range("Yıl")
        snap("44-rapor-yil")
        app.swipeUp()
        snap("45-rapor-yil-alt")

        // Kategori ayrıntısı seçili dönemin işlemlerini listeler.
        let market = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Market")).firstMatch
        for _ in 0..<6 where !market.isHittable { app.swipeUp() }
        market.tap()
        sleep(1)
        snap("46-rapor-kategori")
        app.swipeUp()
        snap("47-rapor-kategori-islemler")
    }

    @MainActor
    private func selectTab(_ title: String, in app: XCUIApplication) {
        // Aşağı kaydırınca küçülen sekme çubuğunu geri getirmek için yukarı kaydır.
        for _ in 0..<3 where !app.tabBars.buttons[title].firstMatch.exists {
            app.swipeDown()
        }
        let button = app.tabBars.buttons[title].firstMatch
        if button.waitForExistence(timeout: 2) {
            button.tap()
        } else {
            app.buttons[title].firstMatch.tap()
        }
        sleep(1)
    }

    @MainActor
    private func capture(_ name: String) {
        let png = XCUIScreen.main.screenshot().pngRepresentation
        if let outputDir {
            try? png.write(to: outputDir.appending(path: "\(name).png"))
        }
        let attachment = XCTAttachment(data: png, uniformTypeIdentifier: "public.png")
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
