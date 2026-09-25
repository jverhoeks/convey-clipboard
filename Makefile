# Convey — build & dev tasks
# Usage: `make <target>` (run `make help` to list targets)

SWIFT ?= swift
CLI_BIN := .build/debug/convey
APP_BIN := .build/debug/convey-app
PREFIX ?= /usr/local

.DEFAULT_GOAL := help

.PHONY: help build release test run dev-cert cli app bundle icon verify-bundle archive notarize cask clean install uninstall next-version patch minor major screenshots _bump

help: ## List available targets
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) \
		| awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-12s\033[0m %s\n", $$1, $$2}'

build: ## Debug build (both convey + convey-app)
	$(SWIFT) build

release: ## Optimized release build
	$(SWIFT) build -c release

test: ## Run the full test suite
	$(SWIFT) test

cli: ## Build the CLI, then print its usage
	$(SWIFT) build --product convey
	@$(CLI_BIN) || true

app: ## Build the menu-bar app
	$(SWIFT) build --product convey-app

# Stable local signature so Screen Recording grants survive rebuilds (see `make dev-cert`).
DEV_IDENTITY := $(shell security find-certificate -c "Convey Development" >/dev/null 2>&1 && echo "Convey Development" || echo -)

dev-cert: ## One-time: create the local "Convey Development" signing identity used by `make run`
	bash Packaging/dev-cert.sh

run: ## Build and launch "Convey Dev" (own bundle id + stable signature, so it never steals the brew app's grants)
	$(MAKE) bundle CONFIGURATION=debug ARCHS=$$(uname -m) CODE_SIGN_IDENTITY="$(DEV_IDENTITY)" BUNDLE_ID=org.verhoeks.convey.dev APP_NAME="Convey Dev"
	@pkill -x convey-app 2>/dev/null && sleep 1 || true  # one Convey at a time (shared lock, hotkeys, socket)
	open Convey.app

screenshots: ## Render the README images into docs/images (sample data only; does not touch history)
	$(SWIFT) build --product convey-app
	mkdir -p docs/images
	.build/debug/convey-app --screenshots docs/images

# --- Convey.app bundle: menu-bar app + CLI + resource bundle, ad-hoc signed ---
VERSION ?= $(shell git describe --tags --abbrev=0 2>/dev/null | sed 's/^v//')
APP := Convey.app

bundle: ## Build a fresh universal app; optional BIN_DIR for explicit prebuilt products
	SWIFT="$(SWIFT)" VERSION="$(or $(VERSION),0.0.0)" BIN_DIR="$(BIN_DIR)" CONFIGURATION="$(or $(CONFIGURATION),release)" ARCHS="$(or $(ARCHS),arm64 x86_64)" CODE_SIGN_IDENTITY="$(or $(CODE_SIGN_IDENTITY),-)" BUNDLE_ID="$(BUNDLE_ID)" APP_NAME="$(APP_NAME)" bash Packaging/bundle.sh

icon: ## Regenerate the complete macOS icon from vector source
	$(SWIFT) Packaging/GenerateIcon.swift .build/Convey.iconset
	iconutil -c icns .build/Convey.iconset -o Packaging/Convey.icns
	cp .build/Convey.iconset/icon_512x512@2x.png Packaging/Convey.png

verify-bundle: ## Verify icon, resources, version, signatures, and universal architectures
	bash Packaging/verify-bundle.sh "$(APP)"

archive: verify-bundle ## ZIP the verified universal app and write a SHA-256 checksum
	@mkdir -p dist
	@version=$$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$(APP)/Contents/Info.plist"); \
	archive="dist/Convey-$$version-macos-universal.zip"; \
	ditto -c -k --keepParent "$(APP)" "$$archive"; \
	shasum -a 256 "$$archive" > "$$archive.sha256"; \
	echo "created $$archive"

NOTARY_PROFILE ?= convey
notarize: ## Notarize + staple a Developer ID-signed Convey.app, then re-archive (one-time: xcrun notarytool store-credentials convey)
	@codesign -dv "$(APP)" 2>&1 | grep -q 'Authority=Developer ID Application' || { echo "error: $(APP) is not Developer ID signed; run make bundle CODE_SIGN_IDENTITY=\"Developer ID Application: …\"" >&2; exit 1; }
	@mkdir -p .build
	ditto -c -k --keepParent "$(APP)" .build/notarize.zip
	xcrun notarytool submit .build/notarize.zip --keychain-profile "$(NOTARY_PROFILE)" --wait
	xcrun stapler staple "$(APP)"
	spctl --assess --type execute --verbose "$(APP)"
	$(MAKE) --no-print-directory archive

TAP ?= ../../homebrew-tap
cask: ## Write Casks/convey.rb into $(TAP) for the latest GitHub release
	@tag=$$(gh release view --json tagName -q .tagName); v=$${tag#v}; \
	sha=$$(gh release download "$$tag" -p 'Convey-*.zip.sha256' -O - | cut -d' ' -f1); \
	mkdir -p "$(TAP)/Casks"; \
	sed -e "s/@VERSION@/$$v/" -e "s/@SHA256@/$$sha/" Packaging/convey.rb.tmpl > "$(TAP)/Casks/convey.rb"; \
	echo "wrote $(TAP)/Casks/convey.rb for $$tag — commit & push the tap"

APP_DIR ?= /Applications
install: ## Install Convey.app into $(APP_DIR) and link the `convey` CLI into $(PREFIX)/bin (like the cask)
	$(MAKE) bundle ARCHS=$$(uname -m) CODE_SIGN_IDENTITY="$(DEV_IDENTITY)"
	@pkill -x convey-app 2>/dev/null && sleep 1 || true
	@# Replace the contents, not the bundle: deleting an app in /Applications needs App Management permission.
	rm -rf "$(APP_DIR)/Convey.app/Contents"
	ditto Convey.app "$(APP_DIR)/Convey.app"
	@# Only this step may need root (/usr/local/bin is root-owned); never build as root.
	@{ mkdir -p "$(PREFIX)/bin" && ln -sf "$(APP_DIR)/Convey.app/Contents/MacOS/convey" "$(PREFIX)/bin/convey"; } 2>/dev/null \
		|| sudo ln -sf "$(APP_DIR)/Convey.app/Contents/MacOS/convey" "$(PREFIX)/bin/convey"
	open "$(APP_DIR)/Convey.app"
	@echo "installed $(APP_DIR)/Convey.app and $(PREFIX)/bin/convey -> app"

uninstall: ## Remove Convey.app from $(APP_DIR) and the CLI link
	@pkill -x convey-app 2>/dev/null || true
	rm -rf "$(APP_DIR)/Convey.app"
	rm -f "$(PREFIX)/bin/convey" 2>/dev/null || sudo rm -f "$(PREFIX)/bin/convey"

clean: ## Remove build artifacts
	$(SWIFT) package clean
	rm -rf .build Convey.app

# --- Releases: bump the semver tag and push it (triggers .github/workflows/release.yml) ---

next-version: ## Print the current + next patch/minor/major versions (no tagging)
	@current=$$(git tag --list 'v*' --sort=-v:refname | head -n1); current=$${current:-v0.0.0}; \
	v=$${current#v}; major=$${v%%.*}; rest=$${v#*.}; minor=$${rest%%.*}; patch=$${rest#*.}; \
	echo "current: $$current"; \
	echo "patch:   v$$major.$$minor.$$((patch+1))"; \
	echo "minor:   v$$major.$$((minor+1)).0"; \
	echo "major:   v$$((major+1)).0.0"

patch: ## Tag & push the next PATCH release (vX.Y.Z+1)
	@$(MAKE) --no-print-directory _bump BUMP=patch

minor: ## Tag & push the next MINOR release (vX.Y+1.0)
	@$(MAKE) --no-print-directory _bump BUMP=minor

major: ## Tag & push the next MAJOR release (vX+1.0.0)
	@$(MAKE) --no-print-directory _bump BUMP=major

# Internal: compute next version from the latest v* tag, create an annotated
# tag, and push it. Refuses on a dirty tree so releases never include
# uncommitted work.
_bump:
	@if [ -n "$$(git status --porcelain)" ]; then \
		echo "error: working tree not clean — commit or stash before releasing" >&2; exit 1; \
	fi
	@current=$$(git tag --list 'v*' --sort=-v:refname | head -n1); current=$${current:-v0.0.0}; \
	v=$${current#v}; major=$${v%%.*}; rest=$${v#*.}; minor=$${rest%%.*}; patch=$${rest#*.}; \
	case "$(BUMP)" in \
		patch) patch=$$((patch+1));; \
		minor) minor=$$((minor+1)); patch=0;; \
		major) major=$$((major+1)); minor=0; patch=0;; \
		*) echo "error: BUMP must be patch|minor|major" >&2; exit 1;; \
	esac; \
	next="v$$major.$$minor.$$patch"; \
	echo "releasing $$current -> $$next"; \
	git tag -a "$$next" -m "Convey $$next"; \
	git push origin "$$next"; \
	echo "pushed $$next — GitHub Actions will build & publish the release"
