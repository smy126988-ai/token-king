# Token King 桌面 Widget P0 — 外部审查意见 & 修改指令

> 面向读者：负责改代码的 AI（minimax / Orchestrator）
>
> 作者：外部技术审查员（独立 grep 实证，非转述）
>
> 日期：2026-07-14
>
> 输入：`docs/handoffs/2026-07-14-widget-p0-review-report.md`（复审报告）+ 6 份 worker 报告 + 关键源码实读
>
> 结论：**代码层完成度高，但不能立即 mark P0 done。3 项代码修改 + 1 项必须由用户桌面实测闭环。**

---

## 0. 最重要：一处复审判断被推翻（必读）

复审报告 §7.2 / MAJOR-3 判定「W6 误判，实际 W3 用了 `widget.writer`、W2 用了 `widget.mapper`」。

**这个判断是错的。W6 才是对的。** 独立 grep 实证：

```
# WidgetLogger.* 的真实调用者——只有 provider，共 3 处，全在 TokenKingWidget.swift
TokenKingWidget/TokenKingWidget.swift:65  WidgetLogger.provider.warning(...)
TokenKingWidget/TokenKingWidget.swift:77  WidgetLogger.provider.notice(...)
TokenKingWidget/TokenKingWidget.swift:81  WidgetLogger.provider.error(...)

# 各文件其实自建了 private logger，category 字符串同名但根本没走 WidgetLogger
Services/WidgetSnapshotMapper.swift:17       static let logger = Logger(subsystem:"com.tokenking", category:"widget.mapper")
Services/WidgetSnapshotCoordinator.swift:17  private let logger = Logger(subsystem:"com.tokenking", category:"widget.coordinator")
Services/WidgetSnapshotWriter.swift:11       private let logger = Logger(subsystem:"com.tokenking", category:"widget.writer")
Shared/SharedPaths.swift:84                  static let logger = Logger(subsystem:"com.tokenking", category:"widget.paths")
```

**真相**：`WidgetLogger` 里的 `writer/mapper/paths/views` 确实是死代码（定义了但没人通过它调用）。而且暴露一个双重维护问题：同一个 category 字符串（如 `widget.writer`）在两处硬编码。还有第 6 个 category `widget.coordinator` 散落在 Coordinator 自建 logger 里，根本不在 `WidgetLogger` 中。

**根因教训**：复审时「看到 category 字符串存在」就下结论，没查「谁在调用」。多 agent 产出必须 grep 到调用链这一层。

---

## 1. 必改的 3 项代码（commit 前完成）

### 修改 1｜清理 WidgetLogger 死代码（对应 W6 MAJOR-3）

**问题**：`Shared/WidgetLogger.swift` 里 `writer/mapper/paths/views` 4 个 category 无人通过 `WidgetLogger.*` 调用；各业务文件自建 private logger 绕过它。

**修法（二选一，推荐 A）**：
- **A（推荐，改动小、诚实）**：`WidgetLogger` 只保留 `provider`（widget target 唯一真实使用者）。删掉 `writer/mapper/paths/views`。app target 那几个文件继续用各自的 private logger（它们本来就在用，且跨 target 复用集中 logger 本就别扭）。
- **B（彻底统一）**：把 `WidgetSnapshotWriter/Mapper/Coordinator/SharedPaths` 的 private logger 全部替换成 `WidgetLogger.writer/mapper/…`，消除 category 字符串双重定义。但需确认 app target 能正常引用 `WidgetLogger`（它在 `Shared/`，app target 应可见）。

**为什么推荐 A**：widget 是独立编译单元，`WidgetLogger` 实际只服务 widget target 的 provider 日志。承认这一点比硬凑集中化更干净。`views` category 无任何渲染日志，无论选哪个都删。

**验收**：`grep -rn "WidgetLogger\.\(writer\|mapper\|paths\|views\)" --include="*.swift" CopilotMonitor/` 应为 0 命中（选 A）或全部有真实调用（选 B）。无死代码 category。

---

### 修改 2｜补 timeline next refresh 日志（对应 W6 MAJOR-4 / spec R11）

**问题**：`TokenKingWidget/TokenKingWidget.swift:55-59` 的 `getTimeline()` 算了 `nextRefresh` 但没记日志。spec R11 明确要求「timeline next refresh date」。

**修法**：`getTimeline()` 内 `completion(...)` 之前加：
```swift
WidgetLogger.provider.debug("timeline next=\(nextRefresh, privacy: .public) status=\(entry.readStatus.rawValueString, privacy: .public)")
```

**验收**：`getTimeline` 内有一条含 `nextRefresh` 的 debug 日志。

---

### 修改 3｜monthlyCost USD 反推加防护（外部审查新发现）

**问题**：`Services/WidgetSnapshotCoordinator.swift:62-77`——`MonthlyTotal` 没有 USD 字段，USD 是用 `CurrencyFormatter.currentRate` 从 RMB 反推（RMB ÷ rate）。若 `currentRate` 为 0 或未初始化，USD 会算出 `inf` / `NaN` 写进 JSON，widget 显示脏数据。

**当前数据合理**（usd=12961.31 / rmb=87984.98，汇率约 6.79），但缺边界防护。

**修法**：反推前判 `rate > 0`，否则 USD 置 nil 或跳过 monthlyCost（让 schema 的 `monthlyCost?` optional 生效）。

**验收**：`currentRate <= 0` 时 snapshot 不写出 inf/NaN 的 usd。

---

## 2. 明确不改的（避免过度工程）

- **getSnapshot / getTimeline 重复 readEntry（W6 MAJOR-5）**：可接受。widget 一次读 ~2KB 极轻，上 actor/NSCache 是过度工程。**不改。**
- **schema 加字段（复审 Q4）**：不加 `lastWeekDailyTotals` / `lastSyncedAt` / `accountCount`。都无消费者，`version` 字段已提供向前兼容能力，将来连同 UI 一起加。**严守 spec「不加无消费者字段」。**
- **CFBundleVersion 0 vs 1（MINOR）**：发布流程再对齐，P0 不动。

---

## 3. 必须由用户桌面实测的（代码测不出来）

### R16：widget 真的读到文件 + decode 成功（P0 DONE 的硬门槛）

**为什么代码测不出来**：这条验证的是 ad-hoc 签名下能否穿过 macOS 沙盒墙读共享文件——**这是整个方案唯一的真风险**。给 appex 加 XCTest 模拟 `getTimeline()`（复审 Q1 选项 B）是伪验证，它在进程内跑、绕过了沙盒墙，测了等于没测。`WidgetCenter.reloadTimelines()`（选项 C）也要等系统调度。

**结论**：Q1 选 **A**——承认代码层完成，R16 靠用户桌面手动加 widget 闭环。

**用户操作步骤**：
```
1. 桌面右键 → Edit Widgets（编辑小组件）
2. 搜 "Token King"（先确认能搜到——这验证 Info.plist 平台字段修复生效）
3. 加 Small / Medium / Large
4. 看是否显示真实 provider 数据 + monthlyCost
5. Console.app 过滤 subsystem == "com.tokenking"
6. 期望看到：widget.provider notice "read snapshot v1 providers=7 ageSec=X status=ok"
```

**判定**：
- 看到 `status=ok` 正向日志 + widget 显示真实数据 → R16 闭环，**才能 mark P0 done**。
- 搜不到 / EmptyState / Console 有 `deny(1) file-read*` → 沙盒墙没过，进入 P1 补救（localhost HTTP）。

### R18：6 场景边界矩阵（Q2 选 A+B 组合）

- **前 4 场景（无文件 / 坏 JSON / 半写入 / stale）写 XCTest**：`readEntry()` 是纯逻辑，喂不同文件内容即可测，成本低、回归价值高。这是唯一能自动化守住的部分。
- **后 2 场景（主 app 杀 / 重启）写进 AGENTS.md 手工清单**：「每次 widget 升级必须手工跑」。
- **不选纯跳过（选项 C）**：不是怕崩，是「坏 JSON 显示 corrupt / stale 显示 badge」这些用户可见文案一旦回归无人知晓。

---

## 4. P1 优先级（Q5）

**P1 第一步不是选功能，是先靠 R16 桌面实测定分叉**：

- **home-relative-path 在 ad-hoc 下真 work（R16 闭环通过）**：
  - localhost HTTP（方案④）**跳过**——它是沙盒墙失败时的兜底，墙没塌不需要。
  - P1 首选：主 app 写完 snapshot 后调 `WidgetCenter.shared.reloadTimelines()`。低成本、直接提升刷新感知，比 Darwin notify 靠谱（notify 的 reload 行为无实测）。
- **不 work（沙盒墙过不去）**：
  - localhost HTTP 立刻从 P1 升为 P0 补救，其它全让路。

**Aurora 背景 / tier 配色 / 第 4 family** 全是锦上添花，P2 再说。

**P1 top 2**：①R16 桌面实测闭环 ②（过了的话）`reloadTimelines()` 主动刷新。

---

## 5. 对 6-worker swarm 模式的评价（供流程复盘）

- **W6 adversary 是最高价值角色**：抓出真 CRITICAL（Info.plist 缺平台字段，直接决定 widget 显不显示）。对抗验收必须保留。
- **W4 报告失真率最高**（WidgetLogger 声称 43 行实为 14 行、虚报测试数），恰好是 adversary 的用武之地。
- **验证层本身也需要被验证**：这次 Orchestrator 的「独立复审」在 MAJOR-3 上判错，根因是没查调用链。多 agent 链路里，复审结论（尤其「翻案」类结论）可信度要打折，需再独立核实。
- **区分噪声与缺陷**：测试数 752 vs 750、报告行数对不上，是过程噪声，不该占据 commit 决策注意力。真正卡 commit 的只有：R16 未闭环 + logger 死代码 + timeline 日志缺失。

---

## 6. 给 Orchestrator 的行动清单

1. 改 3 项代码（§1）：清理 logger 死代码、补 timeline 日志、monthlyCost 防护。
2. 写 R18 前 4 场景 XCTest（§3）。
3. 复跑全量测试确认 750（+新增边界测试）/0 未破 + SwiftLint 0 warning。
4. **提示用户桌面手动加 widget 做 R16 实测**（§3 步骤）——这一步过了才 commit + mark P0 done。
5. R16 结果决定 P1：过 → `reloadTimelines()`；不过 → localhost HTTP 升 P0。

**不 commit 派**：working tree 未 commit 是对的。上述 §1 改完 + R16 桌面实测通过，再 commit。
