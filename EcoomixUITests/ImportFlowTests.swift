import XCTest

/// Ayarlar > Ekstre içe aktar yolunu gerçek dokunuşlarla sürer (dosya DEBUG -importFile ile verilir).
final class ImportFlowTests: XCTestCase {
    @MainActor
    func testPDFImportPreview() throws {
        let file = try XCTUnwrap(ProcessInfo.processInfo.environment["IMPORT_PDF"])
        let app = XCUIApplication()
        app.launchArguments = ["-demoData", "-tab", "settings", "-importFile", file]
        app.launch()

        app.buttons["Ekstre içe aktar"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Banka"].waitForExistence(timeout: 10), "PDF önizlemesi açılmadı")
        capture("15-pdf-onizleme")
        let installmentRow = app.staticTexts["VATAN BILGISAYAR"]
        for _ in 0..<5 where !installmentRow.exists { app.swipeUp() }
        XCTAssertTrue(installmentRow.exists, "Taksitli satır okunamadı")
        capture("16-pdf-onizleme-alt")
    }

    /// Metin katmanı olmayan PDF'in cihazda görüntüden (OCR) okunması.
    @MainActor
    func testOCRPDFImport() throws {
        let file = try XCTUnwrap(ProcessInfo.processInfo.environment["IMPORT_OCR_PDF"])
        let app = XCUIApplication()
        app.launchArguments = ["-demoData", "-tab", "settings", "-importFile", file]
        app.launch()

        app.buttons["Ekstre içe aktar"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Banka"].waitForExistence(timeout: 30), "OCR önizlemesi açılmadı")
        let note = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "görüntüden okundu")).firstMatch
        XCTAssertTrue(note.exists, "OCR notu görünmüyor")
        capture("19-ocr-onizleme")
        let installment = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Taksit 2/3")).firstMatch
        for _ in 0..<5 where !installment.exists { app.swipeUp() }
        XCTAssertTrue(installment.exists, "Akbank taksit satırı okunamadı")
        capture("20-ocr-onizleme-alt")
    }

    /// Gerçek Gemini isteği yapar; yalnızca GEMINI_UI_LIVE=1 ile çalışır.
    @MainActor
    func testGeminiCategorizeInPreview() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["GEMINI_UI_LIVE"] == "1", "Canlı Gemini testi kapalı")
        let file = try XCTUnwrap(ProcessInfo.processInfo.environment["IMPORT_PDF"])
        let app = XCUIApplication()
        app.launchArguments = ["-demoData", "-tab", "settings", "-importFile", file]
        app.launch()

        app.buttons["Ekstre içe aktar"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Banka"].waitForExistence(timeout: 10))
        let button = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Gemini ile belirle")).firstMatch
        for _ in 0..<4 where !button.isHittable { app.swipeUp() }
        capture("17-kategori-oncesi")
        button.tap()
        let done = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "kategori atadı")).firstMatch
        XCTAssertTrue(done.waitForExistence(timeout: 120), "Gemini sonucu gelmedi")
        capture("18-kategori-sonrasi")
    }

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
