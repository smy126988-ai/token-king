# Token King 聚合与刷新管线设计

## 1. 目标

保证历史聚合完整、累计 API 快照可更新，并把 30 秒全量重扫改为有 checkpoint 的增量刷新，使空闲运行不持续消耗大量 CPU、磁盘和日志。

## 2. 日聚合修复

当前生产 tick 只重算当天，历史事件无法进入 `day_aggregates`。新设计提供原子重建入口：

```swift
func repairDayAggregates(for month: YearMonth) throws -> AggregateRepairResult
```

实现要求：

- 在单一事务中按 `token_events` 的实际日期重建指定月份；
- 首次启动、schema 升级或一致性检查失败时自动 repair；
- 日常增量只更新受新事件影响的日期；
- 重建失败回滚，不留下空表或半张表；
- 提供逐字段一致性检查，而不是只比较 total。

## 3. API 快照语义

累计 API 数据不能复用 immutable raw event 的 `INSERT OR IGNORE`。新增 `api_snapshots`：

```sql
CREATE TABLE api_snapshots (
  provider TEXT NOT NULL,
  source TEXT NOT NULL,
  period TEXT NOT NULL,
  model TEXT NOT NULL,
  input INTEGER NOT NULL,
  output INTEGER NOT NULL,
  cache_read INTEGER NOT NULL,
  cache_write INTEGER NOT NULL,
  reasoning INTEGER NOT NULL,
  fetched_at INTEGER NOT NULL,
  PRIMARY KEY (provider, source, period, model)
)
```

- 累计快照用 `ON CONFLICT DO UPDATE` 替换旧值，不相加。
- 月份变化创建新 period。
- HTTP 非 2xx、无效 JSON 和认证失败不得写零快照。
- NanoGPT 由 extractor 明确指定 `.nanoGpt`，模型名不能覆盖 billing provider。

## 4. 增量导入

新增 `ingestion_checkpoints`，每个 source 记录可验证 checkpoint：

- SQLite：最大稳定 row id/updated marker；
- JSONL/wire：规范路径、inode、mtime、byte offset；
- 文件被截断或替换时安全重扫该文件；
- API：last success、ETag/period（如可用）。

Extractor 返回 `ExtractionBatch(events, checkpoint, metrics)`。只有 Store 事务提交成功后才保存 checkpoint，防止丢事件。

## 5. Store 写入

- 每个 batch 复用 prepared statement 并包在事务中；
- immutable event 保持 `source_id UNIQUE` 去重；
- 快照进入独立表；
- schema 使用单一 `current_version`，迁移幂等且有回滚测试；
- 删除未使用的 `model_pricing_cache`，或在明确消费者出现前不保留死表。

## 6. 刷新与 UI

`RefreshActor.tick()` 返回统一 `RefreshSnapshot`：新事件数、重复数、扫描文件数、耗时、各 source 错误、聚合修复状态和成本/Token 快照。

AppDelegate 每个刷新周期只把一个 snapshot 提交给 UI，并只触发一次 menu rebuild。相同 snapshot 不重建；增量进度只更新必要行。

## 7. 可观测性

结构化指标至少包括：

- tick 次数、错误率、p50/p95 延迟；
- 扫描文件数、新增/重复事件数；
- checkpoint fallback/rescan 次数；
- DB lock/transaction rollback 次数；
- 数据最后成功时间和 stale 时长。

不记录事件正文、模型输入、凭证或完整用户路径。

## 8. 验收

- 12 天 fixture 首次 tick 后生成 12 天聚合，五字段与 raw event 严格相等。
- 删除部分日聚合后重启可自动修复。
- 累计快照 100→150 的月总量为 150，不是 100 或 250。
- 无变化 tick 重处理比例 <1%，p95 <1 秒，空闲 CPU <2%。
- 单个刷新周期最多一次完整 menu rebuild。
- DB busy 时有受控重试/错误状态，不出现半聚合。
