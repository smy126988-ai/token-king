# =============================================================================
# OpenCode Bar - Development Makefile
# =============================================================================

.PHONY: setup lint lint-swift lint-actions release run help

# Default target
help:
	@echo "Available commands:"
	@echo "  make setup        - Configure git hooks (run once after clone)"
	@echo "  make release      - Build Release, ad-hoc sign, install to /Applications"
	@echo "  make run          - Build+install (release) then launch the app"
	@echo "  make lint         - Run all linters"
	@echo "  make lint-swift   - Run SwiftLint only"
	@echo "  make lint-actions - Run action-validator only"

# =============================================================================
# Build & Install (personal fork — ad-hoc signed, installed to /Applications)
# =============================================================================
release:
	@bash scripts/build-and-install.sh

run: release
	@open "/Applications/Token King.app"

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
