# XcodeGen'in symlink kurulumu ayar şablonlarını bulamıyor; gerçek binary kullanılır.
XCODEGEN ?= $(HOME)/.local/share/xcodegen-dist/bin/xcodegen
SIM ?= iPhone 16 Pro
DEST = 'platform=iOS Simulator,name=$(SIM)'
XCB = xcodebuild -project Economix.xcodeproj -scheme Economix -derivedDataPath build/DerivedData
APP = build/DerivedData/Build/Products/Debug-iphonesimulator/Economix.app

.PHONY: generate core-test test gemini-live build run demo screens screenshot device fixtures readme-images appstore-screens archive upload

generate: Config/Secrets.xcconfig
	@$(XCODEGEN) generate --quiet

# Anahtar dosyası yoksa şablondan oluşturulur (git'e girmez)
Config/Secrets.xcconfig:
	cp Config/Secrets.example.xcconfig $@

core-test:
	cd Packages/EconomixCore && swift test

# UI testindeki Akbank düzenli (EBCDIC kodlu, Type3 yazı tipli) örnek PDF'i Core testlerindeki üreticiyle yazar
fixtures:
	cd Packages/EconomixCore && AKBANK_FIXTURE_OUT="$(CURDIR)/EconomixUITests/Fixtures/akbank-ornek.pdf" swift test --filter writeUIFixture

test: generate
	$(XCB) -destination $(DEST) test

build: generate
	$(XCB) -destination $(DEST) build

# Uygulamanın gerçek Gemini isteğini Config/Secrets.xcconfig'teki anahtarla dener (anahtar yazdırılmaz)
gemini-live: generate
	@TEST_RUNNER_GEMINI_LIVE_KEY="$$(sed -n 's/^[[:space:]]*GEMINI_API_KEY[[:space:]]*=[[:space:]]*//p' Config/Secrets.xcconfig | tr -d '[:space:]')" \
		$(XCB) -destination $(DEST) -only-testing:EconomixTests/GeminiLiveTests test 2>&1 \
		| grep -E "GEMINI_CANLI|✔|✘|TEST (SUCCEEDED|FAILED)"

# Simülatörde gerçek (boş) veriyle çalıştırır
run: build
	xcrun simctl boot "$(SIM)" 2>/dev/null || true
	xcrun simctl install "$(SIM)" $(APP)
	xcrun simctl launch --terminate-running-process "$(SIM)" com.furkanfuat.economix

# Simülatörde 12 aylık demo veriyle çalıştırır (iCloud'a gitmez)
demo: build
	xcrun simctl boot "$(SIM)" 2>/dev/null || true
	xcrun simctl install "$(SIM)" $(APP)
	xcrun simctl launch --terminate-running-process "$(SIM)" com.furkanfuat.economix -demoData

# Demo veriyle tüm ekranları gezip build/screens/ altına görüntü kaydeder
screens: generate
	rm -rf build/screens && mkdir -p build/screens
	xcrun simctl uninstall "$(SIM)" com.furkanfuat.economix 2>/dev/null || true
	TEST_RUNNER_SCREENSHOT_DIR="$(CURDIR)/build/screens" \
	TEST_RUNNER_IMPORT_FILE="$(CURDIR)/EconomixUITests/Fixtures/garanti-ornek.csv" \
	TEST_RUNNER_IMPORT_PDF="$(CURDIR)/EconomixUITests/Fixtures/garanti-ornek.pdf" \
	TEST_RUNNER_IMPORT_AKBANK_PDF="$(CURDIR)/EconomixUITests/Fixtures/akbank-ornek.pdf" xcodebuild -project Economix.xcodeproj -scheme EconomixScreens \
		-derivedDataPath build/DerivedData -destination $(DEST) test

# README görselleri: temiz durum çubuğuyla demo ekranları (açık + koyu) ve kapak (Python + Pillow gerekir).
# Raporlar "Ay" görünümünde açılır (günlük harcama grafiği); yoksa son seçilen dönem hatırlanır.
readme-images: generate
	xcrun simctl boot "$(SIM)" 2>/dev/null || true
	xcrun simctl status_bar "$(SIM)" override --time "9:41" --dataNetwork wifi --wifiMode active --wifiBars 3 \
		--cellularMode active --cellularBars 4 --operatorName "" --batteryState charged --batteryLevel 100
	xcrun simctl ui "$(SIM)" appearance light
	$(MAKE) screens
	mkdir -p build/readme
	xcrun simctl install "$(SIM)" $(APP)
	for spec in light:transactions:islemler light:reports:raporlar light:payments:odemeler \
	            dark:dashboard:ozet-koyu dark:reports:raporlar-koyu dark:transactions:islemler-koyu; do \
		mode=$${spec%%:*}; rest=$${spec#*:}; tab=$${rest%%:*}; name=$${rest#*:}; \
		xcrun simctl ui "$(SIM)" appearance $$mode; \
		xcrun simctl launch --terminate-running-process "$(SIM)" com.furkanfuat.economix -demoData -tab $$tab -reportRange month >/dev/null; \
		sleep 5; xcrun simctl io "$(SIM)" screenshot build/readme/$$name.png >/dev/null; \
	done
	xcrun simctl ui "$(SIM)" appearance light
	python3 scripts/make-readme-images.py

# App Store ekran görüntüleri: 6,9 inç (iPhone 17 Pro Max, 1320×2868), demo veri, temiz durum çubuğu → build/appstore/
APPSTORE_SIM ?= iPhone 17 Pro Max
APPSTORE_SHOTS = 01-ozet 36-rapor-ay 02-ozet-dagilim 09-taksitler-liste 33-rapor-6ay-kategoriler 04-oneriler 21-akbank-taksit 31-rapor-6ay-kumulatif
appstore-screens:
	xcrun simctl boot "$(APPSTORE_SIM)" 2>/dev/null || true
	xcrun simctl status_bar "$(APPSTORE_SIM)" clear
	xcrun simctl status_bar "$(APPSTORE_SIM)" override --time "9:41" --dataNetwork wifi --wifiMode active --wifiBars 3 \
		--cellularMode active --cellularBars 4 --operatorName "" --batteryState charged --batteryLevel 100
	xcrun simctl ui "$(APPSTORE_SIM)" appearance light
	$(MAKE) screens SIM="$(APPSTORE_SIM)"
	rm -rf build/appstore && mkdir -p build/appstore
	i=1; for name in $(APPSTORE_SHOTS); do \
		cp build/screens/$$name.png build/appstore/$$(printf %02d $$i)-$$name.png; i=$$((i+1)); \
	done
	@ls build/appstore

# App Store arşivi (Release, otomatik imzalama) → build/Economix.xcarchive
archive: generate
	rm -rf build/Economix.xcarchive
	xcodebuild -project Economix.xcodeproj -scheme Economix -configuration Release -destination 'generic/platform=iOS' \
		-archivePath build/Economix.xcarchive -allowProvisioningUpdates archive

# App Store Connect'e yükler (önce App Store Connect'te uygulama kaydı açılmış olmalı; bkz. docs/app-store.md).
# Her yüklemede CURRENT_PROJECT_VERSION (project.yml) bir artırılmalı.
upload: archive
	xcodebuild -exportArchive -archivePath build/Economix.xcarchive -exportPath build/export \
		-exportOptionsPlist scripts/ExportOptions.plist -allowProvisioningUpdates

screenshot:
	xcrun simctl io "$(SIM)" screenshot build/screenshot.png

# Kabloyla bağlı iPhone'a kurar: make device UDID=<cihaz-id>
device: generate
	xcodebuild -project Economix.xcodeproj -scheme Economix -configuration Release \
		-destination 'platform=iOS,id=$(UDID)' -allowProvisioningUpdates \
		-derivedDataPath build/DeviceData build
	xcrun devicectl device install app --device $(UDID) build/DeviceData/Build/Products/Release-iphoneos/Economix.app
