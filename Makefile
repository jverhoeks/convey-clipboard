# Convey — build & dev tasks
# Usage: `make <target>` (run `make help` to list targets)

SWIFT ?= swift
CLI_BIN := .build/debug/convey
APP_BIN := .build/debug/convey-app
PREFIX ?= /usr/local

.DEFAULT_GOAL := help

.PHONY: help build release test run cli app clean install uninstall

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
