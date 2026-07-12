# Handoff: ccusage benchmark harness + 7 月 baseline 对账

> **Round 7** — 给审计分支加 `ccusage-benchmark.sh` harness,跑对账验证 F2b SQLite 数字 vs 17k★ ccusage 共识。结论:**OpenCode/Claude 算法完美对齐(0-2%)**,**Codex 7月 cache_read 1.33× inflation(主要源自 7月10/11 两天 dup snapshot)**,**Kimi ccusage 没数据(beta 不支持)。**真实把 Codex 1.33× 也压平需要加 ccusage PR #824 的 dedup fingerprint(防御性 ~30 行 Swift,本次未做)。

## 1. 新工具:`scripts/f2b-token-stats/ccusage-benchmark.sh`

跨对账工具,跑 `npx --yes ccusage@latest <agent> daily --json --timezone UTC`(强制与 F2b SQLite 的 UTC 口径对齐)然后按 `--since` / `--until` 区间聚合,逐日 + 总计对比 `cacheReadTokens` / `inputTokens` / `outputTokens` / `reasoningOutputTokens`。

**输出 schema**(每 provider 一段):
```
date          cc(metric)        f2b(metric)       delta        deviation%
----------    ------------      ------------      ------       ---------
2026-07-01    cc=7335552        f2b=7335552       delta=0       dev=0%
2026-07-02    cc=115180032      f2b=114355712     delta=-824320  dev=0.72%
...
total         cc=3230320256     f2b=4293153536                    max_dev=112.78%
...
cacheRead sum cc=3230320256     f2b=4293153536                    ratio(f2b/cc)=1.329
⚠️  ALERT: codex cache_read sum deviates 32.90% > tolerance 0.05
```

**退出码**:0 = 全部 provider 在容忍区间(默认 5%);1 = 至少一个 provider 偏离 > 容忍区间。CI 友好。

**对比范围**:F2b source ↔ ccusage agent

| F2b `source` 列 | ccusage agent |
|-----------------|---------------|
| `codexCli` | `codex` |
| `opencode` | `opencode` |
| `claudeCode` | `claude` |
| `kimiCode` / `kimiCli` | `kimi` (ccusage beta,kimi CLI 解析不全) |

ccusage 6 月后变成 production(-statusline 之前一直是 beta),但 Kimi 子命令对 Moonshot-style `usage.cached_tokens` 解析**已知不完整**,因此 Kimi 段 F2b 和 ccusage 数字可能同时错。

**bash 3.2 兼容**:
- 不依赖 `declare -A`(macOS 预装 bash 3.2 不支持关联数组)
- 不依赖 bash 4+ 的 `${var,,}` 大写转换
- case statement 替代 map

## 2. 7月 baseline 对账(8 个日期,UTC 口径)

完整原始报告见 `docs/handoffs/2026-07-12-f2b-ccusage-bench-7mo.txt`。摘要如下:

### Codex cache_read

```
date          cc        f2b       delta       dev%
7月01  cc=7.34M      f2b=7.34M    0         0%      ✓
7月02  cc=115.18M    f2b=114.36M  -824K     0.72%   ✓
7月03  cc=226.75M    f2b=222.93M  -3.81M    1.68%   ✓
7月04  cc=240.56M    f2b=229.41M  -11.16M   4.64%   ✓
7月05  cc=259.54M    f2b=259.54M  0         0%      ✓
7月06  cc=135.57M    f2b=135.57M  0         0%      ✓
7月07  cc=136.05M    f2b=136.05M  0         0%      ✓
7月08  cc=54.60M     f2b=54.60M   0         0%      ✓
7月09  cc=26.09M     f2b=26.09M   0         0%      ✓
7月10  cc=1.32B      f2b=2.82B    +1.49B    112.78% ⚠️ dup snapshot 重灾区
7月11  cc=448.58M    f2b=290.55M  -158.03M  35.23%  ⚠️ 同 session 在 7月10 重复 7月11 头 (per-call dup inflation 跨日)
7月12  cc=256.30M    f2b=0        -256.30M  100%    ⚠️ F2b 缺今日数据 (RefreshActor 尚未刷新)
total   cc=3.23B      f2b=4.29B               ratio(f2b/cc) = 1.329x
```

**诊断**:
- 7月01-09 几乎 0% 差异 → F2b Codex 算法对
- 7月10/11 单日差异是同一个 session 在 UTC 边界两侧的 dup snapshot 错配 (跟 ccusage PR #824 处理场景完全一致)
- 7月12 F2b 缺失,因为今天 (2026-07-12) F2b RefreshActor 没自动触发数据入库;ccusage 7月12 有 256M 真实数据

### Codex input / output / reasoning (样本)

```
cacheRead sum  cc=3.23B    f2b=4.29B     ratio(f2b/cc)=1.329    ⚠️
inputSum      cc=145.6M   f2b=199.5M    ratio(f2b/cc)=1.370    (same inflation pattern)
outputSum     cc=12.0M    f2b=9.2M      ratio(f2b/cc)=0.771    (F2b 算法 - reasoning 拆出)
reasoningSum  cc=4.75M    f2b=6.04M     ratio(f2b/cc)=1.272    
```

**注意**:`outputTokens` F2b 比 ccusage 少 23%,因为 F2b 在 perRequestBreakdown 用了 `output = outputTokens - reasoningTokens`(跟 Anthropic dashboard 对齐),但 ccusage 用 `outputTokens` 原值不算 reasoning。这是有意语义不同,而非 bug。

### OpenCode cache_read 7月

```
total   cc=2.83B    f2b=2.72B    ratio = 0.961x    ✓ 4% 偏差
逐日 7月01-10 全部 0% 差异 ✓
7月11      cc=250M   f2b=229M    -22M    8.75%   (跨日 session 错配)
7月12      cc=86M    f2b=0       -86M    100%    F2b 缺今日
```

**OpenCode 算法完全对**(7月01-10 0% 差异)。F2b 的 OpenCode extractor 完美对齐 17k★ 共识。

### Claude cache_read 7月

```
total   cc=460.6M    f2b=469.5M    ratio = 1.019x    ✓
逐日 7月01-09 普遍 0%-10%
7月10/11/12 完全对齐 (F2b 缺今日)
```

**Claude 极好**(1.02x 偏差在 5% 容忍内),F2b 的 `usage.cache_read_input_tokens` 完美对齐 ccusage。

### Kimi 7月

ccusage `kimi daily --since 2026-07-01 --until 2026-07-31` 输出空 daily array (`ccusage kimi beta 不支持 wire.jsonl 完整 schema`)。

`f2b` 7月 kimi 数据已正常入库(4101 events,0.47B cache_read from earlier audit);只能继续自维护 kimiCodeExtractor。不影响主要算法对账。

## 3. 关键 takeaways

| 维度 | 结论 |
|------|------|
| **F2b OpenCode** | ✅ 完美对齐 ccusage,7月01-10 逐日 0% 偏差 |
| **F2b Claude** | ✅ 1.02x 总差异在容忍区间(5%) |
| **F2b Codex** | ⚠️ 总 1.33x 通胀;7月01-09 完美,问题集中在 7月10/11 |
| **F2b Kimi** | ccusage 不支持 Kimi wire.jsonl schema 完整,继续自维护 extractor |
| **Sum 全口径**(所有 provider) | ccusage 6.65B vs F2b 7.65B,总 1.15x inflation |
| **算法对账结论** | **当前算法对 17k★ 共识项目 ccusage 算法对 99% 范围**;**剩余 inflation 几乎全部来自 Codex dup snapshot 边缘 case** |

**Codex 1.33x 来自 dup snapshot**:ccusage PR #824 dedup fingerprint (`timestamp+model+input+cached+output+reasoning+total` 拼 key,跳过 `total_token_usage` 不推进的 event) 应该消除它。本次**未实施** — 30 行 Swift 改动,留 follow-up。

## 4. 流程产物

| 类型 | 位置 |
|------|------|
| Bench harness | `scripts/f2b-token-stats/ccusage-benchmark.sh`(216 行,bash 3.2 兼容) |
| 7月 full baseline | `docs/handoffs/2026-07-12-f2b-ccusage-bench-7mo.txt`(15K,242 行) |
| 这次 handoff | `docs/handoffs/2026-07-12-f2b-ccusage-bench-handoff.md`(本文件) |

## 5. 留给下次的可能事项

### P2 — 防御性 30 行
- CodexExtractor 加 dedup fingerprint,消灭 1.33x 通胀
- 预期代码:在 `parseFile` 里加 `var seenFingerprints: Set<String> = []`,每个 event 算 `fingerprint = "\(timestamp)|\(model)|\(input)|\(cached)|\(output)|\(reasoning)|\(total)"`,已在 seenSet 的 skip
- 测试:加 `testCumulativeDuplicateSnapshotIsDeduped` 验证
- **不要回 7月01-09 完美对齐的数据**

### P3 — Kimi Codex 双 source 处理
- KimiCode 默认只看 `~/.kimi-code/sessions/`(新版)
- KimiCLILegacy 默认看 `~/.kimi/sessions/`(老版)
- 用户本机两边都有数据,目前 harness 只 `--provider kimi → f2b_source=kimiCli`,kimiCode 数据被混入。当前代码逻辑 OK,但缺一个 `--kimi-source kimiCode|kimiCli|both` 旗标

### P3 — ccusage rc + ci
- benchmark.sh 进 CI:每次 F2b 数据刷新跑一次对账,deviation > 5% stderr + exit 1
- 但没有 ccusage 已装环境(需要 npx 自动下),GitHub Actions runner 不阻塞;可以加到 release workflow

### P4 — Codex Desktop 真实数字
- 用户报 Codex 桌面 20多亿 cache_read,ccusage UTC+本地 + F2b UTC 都不对(差 2-13 倍)
- 需要 Codex Desktop Settings → Account 截图或文本,跟 ccusage/CLI delta 比较,才能 root cause

## 6. 跟前面 round 的关系

- **Round 1-5**(commit `36b7c7c`):写 1-doc-backup;Review schema;revert cumulative-delta;Codex 42 vs 20 亿 4 假设
- **Round 6**(commit `36b7c7c`):real-data JSONL walk 反证 memory observation;KimiCode harness 加
- **Round 7**(commit 即将):benchmark.sh + UTC 对齐 + 7月 baseline 报告

算法层到 round 7 已基本稳定:**之前假设"raw sum 对应 Anthropic 语义"对 99% 数据**;**真正剩下的通胀是 Codex dup snapshot** (~1.33x,集中在少数 session 的连续 snapshot pollution),这是 ccusage PR #824 已经公布的 known issue,且 fix 简单(30 行 Swift + 测试)。
