DEVELOPER_DIR ?= /Applications/Xcode-beta.app/Contents/Developer
CLANG_MODULE_CACHE_PATH ?= /tmp/mfan-clang-cache
SWIFTPM_MODULECACHE_OVERRIDE ?= /tmp/mfan-swiftpm-cache

SWIFT = env \
	DEVELOPER_DIR="$(DEVELOPER_DIR)" \
	CLANG_MODULE_CACHE_PATH="$(CLANG_MODULE_CACHE_PATH)" \
	SWIFTPM_MODULECACHE_OVERRIDE="$(SWIFTPM_MODULECACHE_OVERRIDE)" \
	xcrun swift

.PHONY: build test release helper-pkg app verify-app probe run-daemon clean

build: test release

test:
	$(SWIFT) test --disable-sandbox

release:
	$(SWIFT) build -c release --disable-sandbox

helper-pkg: release
	DEVELOPER_DIR="$(DEVELOPER_DIR)" \
	CLANG_MODULE_CACHE_PATH="$(CLANG_MODULE_CACHE_PATH)" \
	SWIFTPM_MODULECACHE_OVERRIDE="$(SWIFTPM_MODULECACHE_OVERRIDE)" \
	./script/package_helper.sh

app: release
	DEVELOPER_DIR="$(DEVELOPER_DIR)" \
	CLANG_MODULE_CACHE_PATH="$(CLANG_MODULE_CACHE_PATH)" \
	SWIFTPM_MODULECACHE_OVERRIDE="$(SWIFTPM_MODULECACHE_OVERRIDE)" \
	./script/package_app.sh

verify-app: app
	./script/verify_app.sh

probe: release
	$(SWIFT) run -c release --disable-sandbox fancontrold probe

run-daemon: release
	sudo "$$($(SWIFT) build -c release --show-bin-path --disable-sandbox)/fancontrold" \
		--allowed-uid "$$(id -u)"

clean:
	$(SWIFT) package clean
