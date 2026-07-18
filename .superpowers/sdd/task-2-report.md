# Task 2 Integration Report

## RED evidence

- Membership fixture and repository check passed at the inherited 79/79 state; this includes the unsafe temporary Tavily membership and is not the final boundary.
- `scripts/tests/check-offline-test-boundaries-tests.sh` failed with exit 127 because the checker fixture did not exist.
- `xcodebuild -scheme TokenKingLiveProviders -showTestPlans` failed because the shared live scheme did not exist.
- `AppLaunchModeTests` was added first and the targeted test build failed because `AppLaunchMode` did not exist.
- Source `Info.plist` SHA-256 before Xcode verification: `283e8fe6bd50b7990a718f6fb93957d69fa186c04dca628810ddb07d336fd2f4`.

## GREEN evidence

- `plutil -lint` passed for `project.pbxproj`.
- Xcode lists the physical `CopilotMonitorLiveTests` target and the `TokenKingLiveProviders` shared scheme.
- `xcodebuild -showTestPlans` reports `OfflineTests` for `CopilotMonitor` and `LiveProviderTests` for `TokenKingLiveProviders`.
- Membership checker fixture and repository checks passed with 82 files on disk and 82 active offline test sources.
- Offline-boundary checker fixture and repository checks passed with 82 offline files and 5 live files.
- All four live integration methods use `try LiveProviderTestGate.requireEnabled()` as their exact first executable statement.
- `AppLaunchModeTests`: 9 tests passed, 0 failures.
- Targeted offline provider suite: 41 tests passed, 0 failures, 0 skips.
- Full `OfflineTests` plan under a new empty `HOME` with `RUN_LIVE_PROVIDER_TESTS` unset: 768 tests passed, 0 failures, 0 skips.
- The full offline log contained 0 real-home auth/key loads. Seven auth loads were deliberate temporary fixtures created by unit tests under the test process temporary directory.
- Gated `LiveProviderTests` with `RUN_LIVE_PROVIDER_TESTS` unset: 5 tests executed, 0 failures, 4 expected skips.
- The five membership-regression suites all executed in the full offline run: `AntigravityProviderVarintTests`, `CLIFormatterTests`, `ClaudeProviderTests`, `SubscriptionSettingsManagerTests`, and `ZaiCodingPlanProviderTests`.
- Source `Info.plist` SHA-256 remained `283e8fe6bd50b7990a718f6fb93957d69fa186c04dca628810ddb07d336fd2f4` after all Xcode runs.

## Concerns

- Xcode emitted host-system `com.apple.linkd.autoShortcut` connection warnings during test launch. They did not affect test results or start production runtime services.
