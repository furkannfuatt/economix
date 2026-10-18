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

        tab("Raporlar")
        app.swipeUp()
        snap("06-raporlar-oran")
        app.swipeUp()
        snap("07-raporlar-kategoriler")
        app.swipeUp()
        snap("08-raporlar-isyerleri")

        tab("Ödemeler")
        app.swipeUp()
        snap("09-taksitler-liste")
        app.buttons["Düzenli"].firstMatch.tap()
        sleep(1)
        app.swipeUp()
        snap("10-duzenli-alt")

        tab("Ayarlar")
        snap("11-ayarlar")
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
