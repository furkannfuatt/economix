# XcodeGen'in symlink kurulumu ayar şablonlarını bulamıyor; gerçek binary kullanılır.
XCODEGEN ?= $(HOME)/.local/share/xcodegen-dist/bin/xcodegen
SIM ?= iPhone 16 Pro
DEST = 'platform=iOS Simulator,name=$(SIM)'
XCB = xcodebuild -project Ecoomix.xcodeproj -scheme Ecoomix -derivedDataPath build/DerivedData
APP = build/DerivedData/Build/Products/Debug-iphonesimulator/Ecoomix.app

.PHONY: generate core-test test gemini-live build run demo screens screenshot device

generate: Config/Secrets.xcconfig
	@$(XCODEGEN) generate --quiet

# Anahtar dosyası yoksa şablondan oluşturulur (git'e girmez)
Config/Secrets.xcconfig:
	cp Config/Secrets.example.xcconfig $@

core-test:
	cd Packages/EcoomixCore && swift test

test: generate
	$(XCB) -destination $(DEST) test

build: generate
	$(XCB) -destination $(DEST) build

# Uygulamanın gerçek Gemini isteğini Config/Secrets.xcconfig'teki anahtarla dener (anahtar yazdırılmaz)
gemini-live: generate
	@TEST_RUNNER_GEMINI_LIVE_KEY="$$(sed -n 's/^[[:space:]]*GEMINI_API_KEY[[:space:]]*=[[:space:]]*//p' Config/Secrets.xcconfig | tr -d '[:space:]')" \
		$(XCB) -destination $(DEST) -only-testing:EcoomixTests/GeminiLiveTests test 2>&1 \
		| grep -E "GEMINI_CANLI|✔|✘|TEST (SUCCEEDED|FAILED)"

# Simülatörde gerçek (boş) veriyle çalıştırır
run: build
	xcrun simctl boot "$(SIM)" 2>/dev/null || true
	xcrun simctl install "$(SIM)" $(APP)
	xcrun simctl launch --terminate-running-process "$(SIM)" com.furkanfuat.ecoomix

# Simülatörde 12 aylık demo veriyle çalıştırır (iCloud'a gitmez)
demo: build
	xcrun simctl boot "$(SIM)" 2>/dev/null || true
	xcrun simctl install "$(SIM)" $(APP)
	xcrun simctl launch --terminate-running-process "$(SIM)" com.furkanfuat.ecoomix -demoData

# Demo veriyle tüm ekranları gezip build/screens/ altına görüntü kaydeder
screens: generate
	rm -rf build/screens && mkdir -p build/screens
	xcrun simctl uninstall "$(SIM)" com.furkanfuat.ecoomix 2>/dev/null || true
	TEST_RUNNER_SCREENSHOT_DIR="$(CURDIR)/build/screens" \
	TEST_RUNNER_IMPORT_FILE="$(CURDIR)/EcoomixUITests/Fixtures/garanti-ornek.csv" \
	TEST_RUNNER_IMPORT_PDF="$(CURDIR)/EcoomixUITests/Fixtures/garanti-ornek.pdf" \
	TEST_RUNNER_IMPORT_OCR_PDF="$(CURDIR)/EcoomixUITests/Fixtures/akbank-ornek-goruntu.pdf" xcodebuild -project Ecoomix.xcodeproj -scheme EcoomixScreens \
		-derivedDataPath build/DerivedData -destination $(DEST) test

screenshot:
	xcrun simctl io "$(SIM)" screenshot build/screenshot.png

# Kabloyla bağlı iPhone'a kurar: make device UDID=<cihaz-id>
device: generate
	xcodebuild -project Ecoomix.xcodeproj -scheme Ecoomix -configuration Release \
		-destination 'platform=iOS,id=$(UDID)' -allowProvisioningUpdates \
		-derivedDataPath build/DeviceData build
	xcrun devicectl device install app --device $(UDID) build/DeviceData/Build/Products/Release-iphoneos/Ecoomix.app
