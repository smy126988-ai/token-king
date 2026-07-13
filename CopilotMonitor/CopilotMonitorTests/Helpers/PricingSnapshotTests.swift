import XCTest
@testable import OpenCode_Bar

/// r1.c (audit/p1-r1.c-enum-pricing-snapshot, 2026-07-13):
/// PricingTable's `modelRate(for:)` and `rate(for:)` are the source of truth
/// for per-token costs that flow into F2b's `MonthCostCalculator`. Before
/// r1.c, the only regression coverage was round-trip tests like
/// "1M input should compute ¥X" — there was no lock-down against the
/// public pricing page. A future data-entry typo (e.g. swap input/output
/// columns) would slip through.
///
/// This file pins 11 representative model rates to the public pricing
/// pages they were sourced from. To refresh after a public price change:
///   1. Re-fetch the public page (URL in `source`)
///   2. Update the `input / output / cache` raw values
///   3. Update `capturedAt` to the current date
///   4. Update the corresponding PricingTable entry in the same commit
final class PricingSnapshotTests: XCTestCase {

    // MARK: - Snapshot data

    /// All snapshots, in the order they appear in the documentation.
    /// Adding a snapshot: append to this array AND update the table in
    /// `.swarm/workers/r1.c-enum-mapping.md`.
    static let allSnapshots: [PricingSnapshot] = [
        // MiniMax-M3 (CN-domestic, native CNY)
        PricingSnapshot(
            model: "MiniMax-M3",
            provider: .minimaxCN,
            input: 4.20, output: 16.80, cache: 0.84,
            currency: "CNY",
            source: URL(string: "https://platform.minimaxi.com/docs/guides/pricing-paygo")!,
            capturedAt: PricingSnapshot.date(2026, 7, 13),
            notes: "Standard tier, ≤512K context. Above 512K input is long-context tier (2×)."
        ),
        // kimi-k2-7-code (Kimi Code subscription, native CNY)
        PricingSnapshot(
            model: "kimi-k2-7-code",
            provider: .kimi,
            input: 6.50, output: 27.00, cache: 1.30,
            currency: "CNY",
            source: URL(string: "https://platform.kimi.com/docs/pricing/chat-k27-code")!,
            capturedAt: PricingSnapshot.date(2026, 7, 13),
            notes: "Native CNY per 1M; k2.7 successor to k2.6 (cache 1.10)."
        ),
        // claude-opus-4.8 (Anthropic, USD)
        PricingSnapshot(
            model: "claude-opus-4.8",
            provider: .claude,
            input: 5.00, output: 25.00, cache: 0.50,
            currency: "USD",
            source: URL(string: "https://www.anthropic.com/pricing")!,
            capturedAt: PricingSnapshot.date(2026, 7, 13),
            notes: "USD per 1M. cache = cache-read (0.50); cache-write is 6.25, excluded by F2b."
        ),
        // claude-haiku-4.5 (Anthropic, USD)
        PricingSnapshot(
            model: "claude-haiku-4.5",
            provider: .claude,
            input: 1.00, output: 5.00, cache: 0.10,
            currency: "USD",
            source: URL(string: "https://www.anthropic.com/pricing")!,
            capturedAt: PricingSnapshot.date(2026, 7, 13),
            notes: "USD per 1M. cache = cache-read (0.10); cache-write is 1.25, excluded by F2b."
        ),
        // claude-sonnet-4-5 (Anthropic, USD) — the F2a representative
        // (claude-sonnet-4-5 is intentionally the F2a representative; it has
        // no modelRate entry. F2a's representative `rate(for: .claude)` stores
        // the cache WRITE rate (¥25.46) as a conservative upper-bound — see
        // PricingTable.swift:65-69 round 5. We snapshot the public-page cache
        // READ rate here ($0.30 → ¥2.037) but mark the snapshot so the test
        // skips the cache comparison for this representative.
        PricingSnapshot(
            model: "claude-sonnet-4-5",
            provider: .claude,
            input: 3.00, output: 15.00, cache: 0.30,
            currency: "USD",
            source: URL(string: "https://www.anthropic.com/pricing")!,
            capturedAt: PricingSnapshot.date(2026, 7, 13),
            notes: "F2a representative. Cache field in F2a stores WRITE rate (3.75 → ¥25.46), not the read rate. Skipped in test.",
            useProviderRepresentative: true
        ),
        // deepseek-v4-pro (opencode-go tier, USD)
        PricingSnapshot(
            model: "deepseek-v4-pro",
            provider: .openCodeGo,
            input: 1.74, output: 3.48, cache: 0.0145,
            currency: "USD",
            source: URL(string: "https://models.dev/api.json")!,
            capturedAt: PricingSnapshot.date(2026, 7, 13),
            notes: "OpenCode Go tier; ~4× upstream DeepSeek direct API. Cache-read 1/120 of input."
        ),
        // mimo-v2.5-pro via opencode-go (USD)
        PricingSnapshot(
            model: "mimo-v2.5-pro",
            provider: .openCodeGo,
            input: 1.74, output: 3.48, cache: 0.0145,
            currency: "USD",
            source: URL(string: "https://models.dev/api.json")!,
            capturedAt: PricingSnapshot.date(2026, 7, 13),
            notes: "OpenCode Go tier; same USD as deepseek-v4-pro. Provider-aware override is required for xiaomi direct API."
        ),
        // mimo-v2.5-pro via xiaomi direct (CN, native CNY)
        PricingSnapshot(
            model: "mimo-v2.5-pro",
            provider: .xiaomiTokenPlanCN,
            input: 3.00, output: 6.00, cache: 0.025,
            currency: "CNY",
            source: URL(string: "https://mimo.mi.com/docs/en-US/price/pay-as-you-go")!,
            capturedAt: PricingSnapshot.date(2026, 7, 13),
            notes: "Provider-aware modelRate override; ~4× cheaper than opencode-go path."
        ),
        // qwen3.7-max (opencode-go tier, USD)
        PricingSnapshot(
            model: "qwen3.7-max",
            provider: .openCodeGo,
            input: 2.50, output: 7.50, cache: 0.50,
            currency: "USD",
            source: URL(string: "https://models.dev/api.json")!,
            capturedAt: PricingSnapshot.date(2026, 7, 13),
            notes: "OpenCode Go tier; cache ratio 0.20 (vs deepseek 1/120) — Qwen has explicit cache pricing line."
        ),
        // glm-4.6 (Z.AI Coding Plan, USD)
        PricingSnapshot(
            model: "glm-4.6",
            provider: .zaiCodingPlan,
            input: 0.60, output: 2.20, cache: 0.11,
            currency: "USD",
            source: URL(string: "https://docs.z.ai/guides/overview/pricing")!,
            capturedAt: PricingSnapshot.date(2026, 7, 13),
            notes: "Cache storage is limited-time free; cache here = cache-read.",
            useProviderRepresentative: true
        ),
        // gpt-4o (OpenAI/codex, USD) — the F2a codex representative
        PricingSnapshot(
            model: "gpt-4o",
            provider: .codex,
            input: 2.50, output: 10.00, cache: 1.25,
            currency: "USD",
            source: URL(string: "https://platform.openai.com/docs/pricing")!,
            capturedAt: PricingSnapshot.date(2026, 7, 13),
            notes: "Standard tier, $1.25 cached input (50% discount, automatic)."
        ),
    ]

    // MARK: - Tests

    /// Every snapshot's input / output / cache must match `PricingTable`
    /// after FX conversion (1 USD = 6.79 CNY for non-CNY currencies).
    /// Catches data-entry typos and accidental rate changes during refactors.
    ///
    /// Lookup strategy:
    /// 1. Provider-aware `modelRate(for: model, provider:)` for entries that
    ///    differ by provider (mimo-v2.5-pro via .xiaomiTokenPlanCN).
    /// 2. Provider-agnostic `modelRate(for: model)` for explicit model rates.
    /// 3. Provider-level `rate(for: provider)` as the representative-model
    ///    fallback (e.g. claude-sonnet-4-5 and glm-4.6 are intentionally
    ///    only at the provider level — see PricingTable.swift:303-310).
    func testPricingSnapshotMatchesPublicList() {
        let fx = PricingSnapshot.fxCNYPerUSD
        var failures: [String] = []
        for snapshot in Self.allSnapshots {
            // Step 1: try provider-aware modelRate.
            var lookupRate: PayAsYouGoRate? = PricingTable.modelRate(
                for: snapshot.model, provider: snapshot.provider
            )
            // Step 2: try provider-agnostic modelRate.
            if lookupRate == nil {
                lookupRate = PricingTable.modelRate(for: snapshot.model)
            }
            // Step 3: fall back to provider-level representative rate.
            // Snapshot must declare that this is a representative (the
            // default for the F2a PricingTable is one model per provider).
            if lookupRate == nil, snapshot.useProviderRepresentative {
                lookupRate = PricingTable.rate(for: snapshot.provider)
            }
            guard let rate = lookupRate else {
                failures.append("\(snapshot.model) (\(snapshot.provider)) did not resolve in PricingTable")
                continue
            }
            // Convert snapshot's raw values to RMB (PayAsYouGoRate's unit).
            let inputRMB = snapshot.currency == "USD" ? snapshot.input * fx : snapshot.input
            let outputRMB = snapshot.currency == "USD" ? snapshot.output * fx : snapshot.output
            let cacheRMB: Double?
            if let cacheUSD = snapshot.cache {
                cacheRMB = snapshot.currency == "USD" ? cacheUSD * fx : cacheUSD
            } else {
                cacheRMB = nil
            }
            // Compare with reasonable accuracy (sub-cent).
            let accuracy: Double = 0.01
            if abs(rate.input - inputRMB) > accuracy {
                failures.append("\(snapshot.model) input: expected ¥\(inputRMB), got ¥\(rate.input)")
            }
            if abs(rate.output - outputRMB) > accuracy {
                failures.append("\(snapshot.model) output: expected ¥\(outputRMB), got ¥\(rate.output)")
            }
            // For representative models, the F2a cache field uses the
            // conservative write rate (see PricingTable.swift:65-69 round 5),
            // which does NOT match the public-page cache-read rate. Skip the
            // cache comparison for representatives — the input/output check
            // is enough to catch the most common typos.
            if snapshot.useProviderRepresentative {
                continue
            }
            if let expectedCache = cacheRMB {
                guard let actualCache = rate.cache else {
                    failures.append("\(snapshot.model) cache: expected ¥\(expectedCache), got nil")
                    continue
                }
                if abs(actualCache - expectedCache) > accuracy {
                    failures.append("\(snapshot.model) cache: expected ¥\(expectedCache), got ¥\(actualCache)")
                }
            } else {
                if rate.cache != nil {
                    failures.append("\(snapshot.model) cache: expected nil, got ¥\(rate.cache!)")
                }
            }
        }
        if !failures.isEmpty {
            XCTFail("Pricing snapshot mismatches detected:\n  - " + failures.joined(separator: "\n  - "))
        }
    }

    /// All snapshots must be no older than 90 days. Public pricing pages
    /// change without version-stamped diffs (Anthropic, OpenAI, Moonshot,
    /// Xiaomi, Z.AI all do this), so a snapshot that's >90 days old means
    /// the price may have drifted. Failing this test is a reminder to
    /// re-fetch and update.
    func testSnapshotsAreRecent() {
        let stale = Calendar.current.date(byAdding: .day, value: -90, to: Date())!
        var staleSnapshots: [String] = []
        for snapshot in Self.allSnapshots {
            if snapshot.capturedAt < stale {
                let days = Calendar.current.dateComponents([.day], from: snapshot.capturedAt, to: Date()).day ?? 0
                staleSnapshots.append(
                    "\(snapshot.model) (\(snapshot.provider)) captured \(days) days ago — re-fetch \(snapshot.source)"
                )
            }
        }
        if !staleSnapshots.isEmpty {
            XCTFail("Stale snapshots (>90 days old):\n  - " + staleSnapshots.joined(separator: "\n  - "))
        }
    }

    /// Structural test: the snapshot list must contain at least 8 models,
    /// per the r1.c task spec. Catches a future refactor that drops the
    /// snapshot array to an empty literal.
    func testSnapshotCoverage() {
        XCTAssertGreaterThanOrEqual(
            Self.allSnapshots.count, 8,
            "r1.c task spec: at least 8 model snapshots required; got \(Self.allSnapshots.count)"
        )
    }

    /// Structural test: every snapshot's model must be unique in the
    /// `modelRate(for:)` lookup, with the exception of provider-aware
    /// entries (mimo-v2.5-pro resolves differently under .openCodeGo vs
    /// .xiaomiTokenPlanCN). This catches accidental duplicate model
    /// entries that would silently shadow each other.
    func testSnapshotModelsAreUnique() {
        var byModel: [String: Int] = [:]
        for snapshot in Self.allSnapshots {
            byModel[snapshot.model, default: 0] += 1
        }
        let duplicates = byModel.filter { $0.value > 1 }
        // mimo-v2.5-pro is allowed to appear twice (provider-aware override).
        let allowedDuplicates: Set<String> = ["mimo-v2.5-pro"]
        let unexpectedDuplicates = duplicates.filter { !allowedDuplicates.contains($0.key) }
        XCTAssertTrue(
            unexpectedDuplicates.isEmpty,
            "Unexpected duplicate model entries: \(unexpectedDuplicates). Allowed: \(allowedDuplicates)"
        )
    }
}

// MARK: - PricingSnapshot struct

/// Public pricing snapshot for a single model/provider pair.
/// Values are stored in the **original currency** of the public page
/// (CNY for China-domestic, USD for international). The test applies
/// `fxCNYPerUSD` (6.79) before comparing against `PricingTable.modelRate`.
struct PricingSnapshot {
    let model: String
    let provider: ProviderIdentifier
    /// Per 1M tokens, in `currency`.
    let input: Double
    /// Per 1M tokens, in `currency`.
    let output: Double
    /// Per 1M tokens, in `currency`. nil when the public page has no
    /// cache pricing line for this model.
    let cache: Double?
    let currency: String  // "USD" or "CNY"
    let source: URL
    let capturedAt: Date
    let notes: String
    /// True when this snapshot is the provider's representative model
    /// (no modelRate entry — fallback to `rate(for: provider)`).
    /// Default false. Set true for models like claude-sonnet-4-5 and
    /// glm-4.6 that are documented as the F2a provider-level
    /// representative in PricingTable.swift.
    let useProviderRepresentative: Bool

    init(model: String, provider: ProviderIdentifier,
         input: Double, output: Double, cache: Double?,
         currency: String, source: URL, capturedAt: Date, notes: String,
         useProviderRepresentative: Bool = false) {
        self.model = model
        self.provider = provider
        self.input = input
        self.output = output
        self.cache = cache
        self.currency = currency
        self.source = source
        self.capturedAt = capturedAt
        self.notes = notes
        self.useProviderRepresentative = useProviderRepresentative
    }

    /// FX rate baseline (round 9 / round 11 / t1.x consensus).
    /// Same value used throughout PricingTable.swift's USD-to-CNY conversion.
    static let fxCNYPerUSD: Double = 6.79

    /// Helper for readable dates in test literals.
    static func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        return Calendar(identifier: .gregorian).date(from: components) ?? Date()
    }
}
