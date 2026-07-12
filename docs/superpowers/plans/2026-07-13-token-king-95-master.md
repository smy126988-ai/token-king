# Token King 95+ Master Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task.

**Goal:** 按依赖顺序执行五份 phase plan，以可复现证据把 Token King 从当前约 52 分提升到 95 分以上。

**Architecture:** 数据正确性和刷新管线是产品数字的底座；测试/安全先建立护栏；产品体验在可信 snapshot 上完成；发布只在全部 gate 通过后进行。

**Tech Stack:** Swift/AppKit/SQLite/XCTest/XCUITest/GitHub Actions/macOS signing toolchain.

---

## 执行顺序

1. Quality Task 1：test target membership。
2. Quality Task 2：Offline/Live 隔离。
3. Data Tasks 1-6：typed pricing、source-aware input、coverage、oracle、UI。
4. Pipeline Tasks 1-8：schema/snapshot/repair/checkpoint/RefreshSnapshot/performance。
5. Product Tasks 1-4：格式、真实五态、显隐、中文与 accessibility。
6. Quality Tasks 4-6：日志、build hash、StatusItemBridge。
7. Quality Task 3：建立唯一 demo/UI harness。
8. Product Tasks 5-6：完整 UI 验收、README/backlog/screenshots。
9. Release Tasks 1-5：版本 SSOT、installer、Sparkle 决策、唯一 workflow、dry-run。
10. 全量 regression、runtime soak、独立 code review。
11. Release Task 6：只有全部 gate GREEN 才 tag/publish/外部回读。

## 每个 Task 的执行合同

- 开工前把 phase task 展开成一个 work packet：exact files、完整 RED 命令、预期失败原因、最小实现、完整 GREEN 命令、精确 `git add` 文件。
- 实现者必须先提交 RED 证据；同一代理不得自称 review 通过。
- 每个 task 依次经过 spec review 和 code-quality review；问题修复后重新验证。
- 不并发修改同一 worktree；一次只允许一个 implementer 写代码。
- 所有 commit/代码注释/PR 使用英文；用户文档可中文。

## 95 分 Gate

| 维度 | 分值 | 必须证据 |
|---|---:|---|
| 数据正确性 | 25 | CTCA ≤¥0.01/行、总额≤1%、coverage完整、12天历史一致 |
| 运行稳定与性能 | 20 | offline fresh suite、idle CPU<2%、p95<1s、日志<5MB/24h |
| 产品体验 | 20 | 四核心数字、五态、显隐、中文、deterministic UI screenshots |
| 安全与工程质量 | 20 | 100% target membership、零默认外网、零敏感日志、bridge矩阵 |
| 发布与更新 | 15 | universal、签名、公证、干净DMG、fork Release、回读/更新 |

任何一项核心 gate 未通过，不能用其他分项加分掩盖，也不能宣称 95+。
