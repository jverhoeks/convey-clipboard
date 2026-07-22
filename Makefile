# Convey — build & dev tasks
# Usage: `make <target>` (run `make help` to list targets)

SWIFT ?= swift
CLI_BIN := .build/debug/convey
APP_BIN := .build/debug/convey-app
PREFIX ?= /usr/local

.DEFAULT_GOAL := help

.PHONY: help build release test run cli app clean install uninstall next-version patch minor major _bump

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

run: app ## Build and launch the menu-bar app
	$(APP_BIN)

install: release ## Install the release CLI to $(PREFIX)/bin
	install -d "$(PREFIX)/bin"
	install -m 0755 .build/release/convey "$(PREFIX)/bin/convey"
	@echo "installed convey -> $(PREFIX)/bin/convey"

uninstall: ## Remove the installed CLI
	rm -f "$(PREFIX)/bin/convey"

clean: ## Remove build artifacts
	$(SWIFT) package clean
	rm -rf .build

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
