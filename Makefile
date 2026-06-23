# Timeout — 构建与分发（无需 Xcode，仅 Command Line Tools）
# 个人用途：ad-hoc 签名 + Hardened Runtime；公开分发见下方 notarize 注释。

BUNDLE_ID   := com.aurelius.timeout
APP_NAME    := Timeout
CONFIG      := release
BUILD_DIR   := .build
BIN         := $(BUILD_DIR)/$(CONFIG)/$(APP_NAME)
APP_BUNDLE  := $(APP_NAME).app
ENTITLEMENTS:= Resources/TimeoutRelease.entitlements
INFO_PLIST  := Resources/Info.plist

.PHONY: all build app run test test-integration clean sign run-debug

all: app

## 编译（release）
build:
	swift build -c $(CONFIG)

## 装配 Timeout.app 并 ad-hoc 签名（Hardened Runtime + entitlements）
app: build
	@echo "==> 装配 $(APP_BUNDLE)"
	@rm -rf $(APP_BUNDLE)
	@mkdir -p $(APP_BUNDLE)/Contents/MacOS
	@mkdir -p $(APP_BUNDLE)/Contents/Resources
	@cp $(BIN) $(APP_BUNDLE)/Contents/MacOS/$(APP_NAME)
	@cp $(INFO_PLIST) $(APP_BUNDLE)/Contents/Info.plist
	@printf 'APPL????' > $(APP_BUNDLE)/Contents/PkgInfo
	@echo "==> ad-hoc 签名（Hardened Runtime + entitlements）"
	@codesign --force --deep --options runtime --entitlements $(ENTITLEMENTS) -s - $(APP_BUNDLE)
	@xattr -dr com.apple.quarantine $(APP_BUNDLE) 2>/dev/null || true
	@echo "==> 完成：./$(APP_BUNDLE)"

## 运行（装配后 open）
run: app
	@open $(APP_BUNDLE)

## 直接 swift run（调试，不打包）
run-debug:
	swift run

## 单元测试（无权限，CI 可跑；自建运行器，CLT 无 XCTest）
test:
	swift run TimeoutTests

## 集成测试（需权限/真机，本地手跑）
test-integration:
	swift test --filter TimeoutIntegrationTests

clean:
	swift package clean
	rm -rf $(APP_BUNDLE)

# === 公开分发（需 Developer ID 证书，按需取消注释） ===
# archive-release:
# 	swift build -c release
# 	$(MAKE) app
# 	xcrun notarytool submit $(APP_BUNDLE).zip --apple-id $(APPLE_ID) --team-id $(TEAM_ID) --keychain-profile $(NOTARY_PROFILE) --wait
# 	xcrun stapler staple $(APP_BUNDLE)
# 	spctl -a -vvv -t install $(APP_BUNDLE)
