import XCTest

/// Ayarlar > Ekstre içe aktar yolunu gerçek dokunuşlarla sürer (dosya DEBUG -importFile ile verilir).
final class ImportFlowTests: XCTestCase {
    @MainActor
    func testImportPreviewRendersAndCommits() throws {
        let file = try XCTUnwrap(ProcessInfo.processInfo.environment["IMPORT_FILE"])
        let app = XCUIApplication()
        app.launchArguments = ["-demoData", "-tab", "settings", "-importFile", file]
        app.launch()

        app.buttons["Ekstre içe aktar"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Banka"].waitForExistence(timeout: 10), "Önizleme açılmadı")
        capture("12-import-onizleme")

        app.swipeUp()
        capture("13-import-onizleme-alt")
        let commit = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "İçe aktar")).firstMatch
        if !commit.exists { app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "işlemi içe aktar")).firstMatch.tap() }
        else { commit.tap() }
        XCTAssertTrue(app.staticTexts["İçe aktarıldı"].waitForExistence(timeout: 10))
        capture("14-import-sonuc")
    }

    @MainActor
    private func capture(_ name: String) {
        let png = XCUIScreen.main.screenshot().pngRepresentation
        if let dir = ProcessInfo.processInfo.environment["SCREENSHOT_DIR"] {
            try? png.write(to: URL(fileURLWithPath: dir).appending(path: "\(name).png"))
        }
    }
}
