# Build Waldo without Xcode: Command Line Tools (xcode-select --install) are enough.
#
#   make run       build, assemble build/Waldo.app, sign it and open it
#   make app       same, without opening
#   make test      run the unit tests (eval: make test WALDO_EVAL=1)
#   make install   copy Waldo.app to /Applications
#   make clean
#
# Signing: uses your "Apple Development" identity when the keychain has one, so the
# Accessibility permission survives rebuilds. Without one it signs ad-hoc and macOS
# asks for the permission again after every rebuild. Override with
#   make run SIGN_IDENTITY="Apple Development: you@example.com (ABCDE12345)"

CONFIG   ?= release
APP      := build/Waldo.app
BIN_DIR   = $(shell swift build -c $(CONFIG) --show-bin-path)

SIGN_IDENTITY ?= $(shell security find-identity -v -p codesigning 2>/dev/null \
	| sed -n 's/.*"\(Apple Development: [^"]*\)".*/\1/p' | head -1)
ifeq ($(strip $(SIGN_IDENTITY)),)
SIGN_IDENTITY := -
SIGN_FLAGS    :=
else
SIGN_FLAGS    := --options runtime
endif

# Command Line Tools ship Swift Testing but SwiftPM doesn't find it on its own.
DEVELOPER_DIR ?= $(shell xcode-select -p)
CLT_DEV := $(DEVELOPER_DIR)/Library/Developer
ifneq ($(wildcard $(CLT_DEV)/Frameworks/Testing.framework),)
TEST_FLAGS := -Xswiftc -F -Xswiftc $(CLT_DEV)/Frameworks \
	-Xlinker -F -Xlinker $(CLT_DEV)/Frameworks \
	-Xlinker -rpath -Xlinker $(CLT_DEV)/Frameworks \
	-Xlinker -rpath -Xlinker $(CLT_DEV)/usr/lib
endif

.PHONY: all app run test install clean

all: app

app:
	swift build -c $(CONFIG)
	rm -rf $(APP)
	mkdir -p $(APP)/Contents/MacOS $(APP)/Contents/Frameworks $(APP)/Contents/Resources
	cp Config/Info.plist $(APP)/Contents/Info.plist
	cp Config/AppIcon.icns $(APP)/Contents/Resources/AppIcon.icns
	printf 'APPL????' > $(APP)/Contents/PkgInfo
	cp $(BIN_DIR)/Waldo $(APP)/Contents/MacOS/Waldo
	cp -R $(BIN_DIR)/llama.framework $(APP)/Contents/Frameworks/
	cp -R $(BIN_DIR)/KeyboardShortcuts_KeyboardShortcuts.bundle $(APP)/Contents/Resources/
	codesign --force --sign "$(SIGN_IDENTITY)" $(SIGN_FLAGS) --timestamp=none $(APP)/Contents/Frameworks/llama.framework
	codesign --force --sign "$(SIGN_IDENTITY)" $(SIGN_FLAGS) --timestamp=none $(APP)
	@echo "Signed with: $(SIGN_IDENTITY)"

# `open` would just focus a Waldo that's already running, so quit it first.
run: app
	-pkill -x Waldo && while pgrep -x Waldo >/dev/null; do sleep 0.1; done
	open $(APP)

test:
	$(if $(WALDO_EVAL),WALDO_EVAL=$(WALDO_EVAL)) $(if $(WALDO_EVAL_ONLY),WALDO_EVAL_ONLY=$(WALDO_EVAL_ONLY)) swift test $(TEST_FLAGS)

install: app
	rm -rf /Applications/Waldo.app
	cp -R $(APP) /Applications/Waldo.app

clean:
	rm -rf .build build
