# =============================================================================
# Token King - Development Makefile
# =============================================================================

.PHONY: setup lint lint-swift lint-actions release run help version version-check version-show

# Default target
help:
	@echo "Available commands:"
	@echo "  make setup          - Configure git hooks (run once after clone)"
	@echo "  make release        - Build Release, ad-hoc sign, install to /Applications"
	@echo "  make run            - Build+install (release) then launch the app"
	@echo "  make lint           - Run all linters"
	@echo "  make lint-swift     - Run SwiftLint only"
	@echo "  make lint-actions   - Run action-validator only"
	@echo "  make version        - Inject git-describe version into source Info.plist"
	@echo "  make version-check  - Build and verify the built Info.plist matches git"
	@echo "  make version-show   - Print current git-derived version"

# =============================================================================
# Build & Install (personal fork — ad-hoc signed, installed to /Applications)
# =============================================================================
release:
	@bash scripts/build-and-install.sh

run: release
	@open "/Applications/Token King.app"

# =============================================================================
# Version single source of truth (git describe -> build artifact Info.plist)
# =============================================================================
version:
	@bash scripts/inject-version.sh

version-check:
	@DERIVED=/tmp/tk-version-check; \
	rm -rf "$$DERIVED"; \
	xcodebuild build \
		-project CopilotMonitor/CopilotMonitor.xcodeproj \
		-scheme CopilotMonitor \
		-configuration Debug \
		-derivedDataPath "$$DERIVED" \
		-destination 'platform=macOS' >/dev/null 2>&1; \
	PLIST="$$DERIVED/Build/Products/Debug/Token King.app/Contents/Info.plist"; \
	bash scripts/inject-version.sh --check "$$PLIST"; \
	RC=$$?; \
	rm -rf "$$DERIVED"; \
	exit $$RC

version-show:
	@git describe --tags --always --dirty 2>/dev/null || echo "0.0.0-unknown"

# =============================================================================
# Setup - Run once after cloning
# =============================================================================
setup:
	@echo "Configuring git hooks..."
	@git config core.hooksPath .githooks
	@echo "✓ Git hooks configured"
	@echo ""
	@echo "Pre-commit will now run:"
	@echo "  - SwiftLint on .swift files"
	@echo "  - action-validator on .github/workflows/*.yml files"

# =============================================================================
# Linting
# =============================================================================
lint: lint-swift lint-actions

lint-swift:
	@echo "Running SwiftLint..."
	@swiftlint lint CopilotMonitor/CopilotMonitor

lint-actions:
	@echo "Running action-validator..."
	@for f in .github/workflows/*.yml; do \
		echo "Validating $$f..."; \
		npx --yes @action-validator/cli "$$f"; \
	done
