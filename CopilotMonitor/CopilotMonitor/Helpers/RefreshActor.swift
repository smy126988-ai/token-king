import Foundation
import os.log

private let logger = Logger(subsystem: "com.opencodeproviders", category: "RefreshActor")

/// 30s tick 增量刷新 (F2b Layer 3 协调).
/// 7 个 TokenExtractor 并发触发 → 归一化 → 写 Store → 重算 month_aggregates.
actor RefreshActor {
    private let store: TokenUsageStore
    private let calc: MonthCostCalculator
    private let extractors: [TokenExtractorProtocol]
    private var tickTask: Task<Void, Never>?
    private let intervalSeconds: UInt64

    /// Mirrors `store.initError` so callers (e.g. `StatusBarController`) can
    /// detect a failed store without awaiting on the actor.
    nonisolated var initError: SQLiteError? { store.initError }

    /// 生产路径：使用 7 个真实 extractor。
    init(store: TokenUsageStore, pricingTable: PricingTable.Type = PricingTable.self,
         intervalSeconds: UInt64 = 30) {
        self.init(
            store: store,
            extractors: [
                OpenCodeExtractor(),
                ClaudeCodeExtractor(),
                CodexExtractor(),
                KimiCLILegacyExtractor(),
                KimiCodeExtractor(),
                ZAIExtractor(),
                NanoGPTExtractor()
            ],
            pricingTable: pricingTable,
            intervalSeconds: intervalSeconds
        )
    }

    /// 可注入 extractor 的初始化器（测试用）。
    init(store: TokenUsageStore, extractors: [TokenExtractorProtocol],
         pricingTable: PricingTable.Type = PricingTable.self,
         intervalSeconds: UInt64 = 30) {
        self.store = store
        self.calc = MonthCostCalculator(pricingTable: pricingTable)
        self.extractors = extractors
        self.intervalSeconds = intervalSeconds
    }

    func start() {
        if let error = self.initError {
            logger.error("RefreshActor start() skipped: TokenUsageStore init failed: \(String(describing: error), privacy: .public)")
            return
        }
        tickTask?.cancel()
        tickTask = Task { [weak self, intervalSeconds] in
            while !Task.isCancelled {
                await self?.tick()
                try? await Task.sleep(nanoseconds: intervalSeconds * 1_000_000_000)
            }
        }
    }

    func stop() {
        tickTask?.cancel()
        tickTask = nil
    }

    /// 单次 tick: 7 个 extractor 并发 → upsert → refresh aggregates
    private func tick() async {
        let rawEventsPerExtractor = await withTaskGroup(of: [TokenEvent].self) { group in
            for extractor in extractors {
                group.addTask {
                    do {
                        return try await extractor.extractAll()
                    } catch {
                        logger.error("Extractor failed: \(error.localizedDescription, privacy: .public)")
                        return []
                    }
                }
            }
            var all: [TokenEvent] = []
            for await events in group { all.append(contentsOf: events) }
            return all
        }

        for raw in rawEventsPerExtractor {
            do {
                // Periodic API snapshots (Z.AI / NanoGPT) use a stable source_id
                // and carry CUMULATIVE counters, so they must REPLACE the previous
                // snapshot in-place. Streaming sources (OpenCode / Claude Code /
                // Codex / Kimi) keep `INSERT OR IGNORE` so per-batch dedup stays.
                if Self.isSnapshotSource(raw.source) {
                    try await store.upsertSnapshot(raw)
                } else {
                    try await store.upsertEvent(raw)
                }
            } catch {
                logger.error("upsertEvent failed: \(error.localizedDescription, privacy: .public)")
            }
        }

        do {
            try await store.refreshMonthAggregates()
        } catch {
            logger.error("refreshMonthAggregates failed: \(error.localizedDescription, privacy: .public)")
        }

        // F1: refresh day_aggregates for today (single-day incremental aggregate).
        do {
            try await store.refreshDayAggregates()
        } catch {
            logger.error("refreshDayAggregates failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Manual tick trigger (for testing or on-demand refresh).
    func tickNow() async {
        if let error = self.initError {
            logger.error("RefreshActor tickNow() skipped: TokenUsageStore init failed: \(String(describing: error), privacy: .public)")
            return
        }
        await tick()
    }

    /// True when `source` is a periodic API quota snapshot (cumulative counters,
    /// stable source_id). Snapshot rows must be REPLACED, not deduped, otherwise
    /// the user sees the first-ever reading forever.
    static func isSnapshotSource(_ source: TokenSource) -> Bool {
        switch source {
        case .zaiApi, .nanoGptApi:
            return true
        case .opencode, .claudeCode, .codexCli, .kimiCli, .kimiCode:
            return false
        }
    }

    /// 当前月 provider 维度汇总 (UI consumption).
    func fetchMonthlyTotals() async -> [MonthlyTotal] {
        let aggs = await store.fetchMonthAggregates()
        return calc.calculateMonthlyTotals(aggs)
    }

    /// 单 provider 当前月 cost (UI consumption).
    func monthlyTotal(for provider: String) async -> MonthlyTotal? {
        let totals = await fetchMonthlyTotals()
        return totals.first { $0.provider == provider }
    }
}
