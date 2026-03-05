.PHONY: build sign bundle install clean

RELEASE_DIR = .build/release
APP_DIR = .build/MXRatchet.app
SIGN_ID = A0FD22414F94EA6BFC4F1EF1F5BFC369633D6710

build:
	swift build -c release

sign: build
	codesign --force --sign "$(SIGN_ID)" --identifier "com.ivor.mxratchet-helper" $(RELEASE_DIR)/MXRatchetHelper
	codesign --force --sign "$(SIGN_ID)" --identifier "com.ivor.mxratchet.app" $(RELEASE_DIR)/MXRatchet

bundle: sign
	@echo "Bundling MXRatchet.app..."
	mkdir -p $(APP_DIR)/Contents/MacOS
	cp $(RELEASE_DIR)/MXRatchet $(APP_DIR)/Contents/MacOS/
	cp Resources/Info.plist $(APP_DIR)/Contents/
	codesign --force --sign "$(SIGN_ID)" --identifier "com.ivor.mxratchet.app" $(APP_DIR)
	@echo "  Created: $(APP_DIR)"

install: bundle
	@echo "Installing mxratchet-helper to /usr/local/bin..."
	sudo mkdir -p /usr/local/bin
	sudo cp $(RELEASE_DIR)/MXRatchetHelper /usr/local/bin/mxratchet-helper
	sudo chmod 755 /usr/local/bin/mxratchet-helper
	sudo codesign --force --sign "$(SIGN_ID)" --identifier "com.ivor.mxratchet-helper" /usr/local/bin/mxratchet-helper
	@echo "Installing MXRatchet.app to ~/Applications..."
	mkdir -p $(HOME)/Applications
	rm -rf $(HOME)/Applications/MXRatchet.app
	cp -R $(APP_DIR) $(HOME)/Applications/MXRatchet.app
	@echo ""
	@echo "Done. To start the helper daemon:"
	@echo "  sudo cp com.ivor.mxratchet-helper.plist /Library/LaunchDaemons/"
	@echo "  sudo launchctl bootstrap system /Library/LaunchDaemons/com.ivor.mxratchet-helper.plist"

clean:
	swift package clean
	rm -rf $(APP_DIR)
