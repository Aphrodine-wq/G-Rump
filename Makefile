JOBS := $(shell sysctl -n hw.ncpu)

.PHONY: run run-app build build-debug build-release clean reset app zip release-zip dmg sign notarize package help

# ── Development ───────────────────────────────────────

run: build-debug ## Build debug and run (terminal only — bare binary can't take keyboard focus when launched from scripts; prefer run-app)
	.build/debug/GRump

run-app: ## Build optimized native release, assemble signed dev .app, launch via LaunchServices
	./scripts/dev-app.sh

build: build-debug ## Alias for build-debug

build-debug: ## Fast debug build (no optimizations)
	swift build -j $(JOBS)

build-release: ## Optimized universal release build (arm64 + x86_64)
	swift build -c release --arch arm64 --arch x86_64 -j $(JOBS)

clean: ## Remove all build artifacts
	rm -rf .build dist

# ── Packaging ─────────────────────────────────────────

app: ## Build release + create .app bundle in dist/
	./scripts/package.sh

zip: ## Build release + downloadable .zip of the .app in dist/
	./scripts/package.sh --zip

release-zip: ## Build + sign + notarize + .zip — the release artifact (requires DEVELOPER_ID, APPLE_ID, TEAM_ID, APP_PASSWORD)
	./scripts/package.sh --sign --notarize --zip

dmg: ## Build release + create .app + .dmg in dist/
	./scripts/package.sh --dmg

sign: ## Build + sign .app (requires DEVELOPER_ID env var)
	./scripts/package.sh --sign

package: ## Build + sign + .dmg (requires DEVELOPER_ID)
	./scripts/package.sh --sign --dmg

notarize: ## Build + sign + .dmg + notarize (requires DEVELOPER_ID, APPLE_ID, TEAM_ID, APP_PASSWORD)
	./scripts/package.sh --sign --dmg --notarize

# ── Utilities ────────────────────────────────────────

reset: ## Reset app state (wipe UserDefaults, caches, data) for fresh-boot testing
	@echo "Resetting G-Rump app state..."
	@pkill -x GRump 2>/dev/null || true
	@defaults delete com.grump.app 2>/dev/null || true
	@rm -rf "$$HOME/.grump"
	@rm -rf "$$HOME/Library/Application Support/GRump"
	@rm -rf "$$HOME/Library/Application Support/com.grump.app"
	@echo "✓ App state reset. Kill any frozen windows, then relaunch."

# ── Help ──────────────────────────────────────────────

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-15s\033[0m %s\n", $$1, $$2}'
