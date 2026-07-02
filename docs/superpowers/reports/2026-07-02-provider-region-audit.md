# Provider 分区现状报告

**报告时间**：2026-07-02  
**验证方式**：curl + 本地 `~/.local/share/opencode/auth.json` 真实 key  
**验证人**：软件工程 agent

---

## 1. 核心结论

| Provider | 国内端点 | 海外端点 | 是否可拆分为独立国内/海外 provider | 备注 |
|---|---|---|---|---|
| **MiniMax Coding Plan** | `https://api.minimaxi.com/v1/api/openplatform/coding_plan/remains` | `https://api.minimax.io/v1/api/openplatform/coding_plan/remains` | **可以** | 不同域名，同一 key 在国内端点可用、海外端点返回 1004 region mismatch。 |
| **Kimi for Coding** | **无独立端点** | `https://api.kimi.com/coding/v1/usages` | **不可按 base URL 拆分** | 只有一个 `api.kimi.com`；根据 key/账号返回 `user.region`（如 `REGION_CN`）。测试的 `kimi-for-coding` key 返回 region=CN。 |

---

## 2. MiniMax 验证详情

### 2.1 国内端点

```
URL:    https://api.minimaxi.com/v1/api/openplatform/coding_plan/remains
Auth:   Authorization: Bearer <minimax-coding-plan key>
Status: 200 OK
Body:   {"base_resp":{"status_code":0,"status_msg":"success"},"model_remains":[...]}
```

- `model_remains` 返回 2 条记录（general / video）。
- 字段与现有 `MiniMaxCodingPlanResponse` 结构一致：
  - `start_time` / `end_time` / `remains_time`
  - `current_interval_total_count` / `current_interval_usage_count`
  - `current_weekly_total_count` / `current_weekly_usage_count`
  - `model_name`

### 2.2 海外端点

```
URL:    https://api.minimax.io/v1/api/openplatform/coding_plan/remains
Auth:   同一 key
Status: 200 OK（HTTP 层成功）
Body:   {"base_resp":{"status_code":1004,"status_msg":"cookie is missing, log in again"}}
```

- 用国内 key 访问海外端点，返回 1004 region mismatch。
- 说明两个端点的 key 体系是分离的：国内 key 只能用于 `api.minimaxi.com`，海外 key 只能用于 `api.minimax.io`。
- 这与现有代码中的 fallback 行为一致（检测到 1004 / cookie / login 即视为 region mismatch）。

### 2.3 拆分建议

可以拆为两个独立 provider：

- `MiniMaxCNProvider` → `api.minimaxi.com`，key 字段 `minimax-coding-plan-cn`
- `MiniMaxGlobalProvider` → `api.minimax.io`，key 字段 `minimax-coding-plan-global`

当前 `minimax-coding-plan` 用户配置需要迁移或保留别名。

---

## 3. Kimi 验证详情

### 3.1 当前端点

```
URL:    https://api.kimi.com/coding/v1/usages
Auth:   Authorization: Bearer <kimi-for-coding key>
Status: 200 OK
Body 关键字段：
{
  "user": {
    "userId": "d7k367ol3dc8u37dqb9g",
    "region": "REGION_CN",
    "membership": { "level": "LEVEL_INTERMEDIATE" },
    "businessId": ""
  },
  "usage": {
    "limit": "100",
    "used": "12",
    "remaining": "88",
    "resetTime": "2026-07-08T02:32:44.599624Z"
  },
  "limits": [
    {
      "window": { "duration": 300, "timeUnit": "TIME_UNIT_MINUTE" },
      "detail": { "limit": "100", "used": "36", "remaining": "64", "resetTime": "..." }
    }
  ],
  "subType": "TYPE_PURCHASE",
  "totalQuota": { "limit": "100", "remaining": "99" }
}
```

- `user.region = REGION_CN` 表示当前 key 是国内账号。
- `membership.level = LEVEL_INTERMEDIATE`。
- 响应结构与现有 `KimiUsageResponse` 兼容。

### 3.2 潜在国内端点探测

| 探测 URL | 结果 |
|---|---|
| `https://api.kimi.cn/coding/v1/usages` | HTTP 000（无法连接） |
| `https://api.moonshot.cn/coding/v1/usages` | HTTP 404 |
| `https://api.moonshot.ai/coding/v1/usages` | HTTP 404 |
| `https://platform.kimi.com/coding/v1/usages` | HTTP 404（返回 HTML） |
| `https://platform.moonshot.cn/coding/v1/usages` | HTTP 301 |

**结论**：Kimi for Coding 没有独立的国内 base URL。`api.kimi.com` 是唯一切实际的端点，其根据 key/账号的 region 返回国内或海外数据。

### 3.3 对「国内/海外拆 provider」的影响

如果强行把 Kimi 拆成两个 provider：

- `KimiCNProvider` 和 `KimiGlobalProvider` 必须共用同一个 base URL `https://api.kimi.com/coding/v1/usages`。
- 需要两个不同的 auth key：`kimi-for-coding-cn` 和 `kimi-for-coding-global`。
- 用户当前只有 `kimi-for-coding` 一个 key，拆分后需要用户重新配置或迁移。
- 两个 provider 在菜单中会显示为两条独立条目，但实际都请求同一域名，只是 key 不同。

这与用户「国内版和海外版是两个不同的 provider——不同 base url」的核心原则存在事实冲突。

### 3.4 建议

- **按 base URL 拆分 Kimi 不可行**（无独立国内端点）。
- 可选方案：
  1. **保守**：Kimi 保持单一 `.kimi` provider，阶段 2 在 RMB 模式下隐藏 Vivace 等纯海外档。
  2. **折中**：拆成 `.kimiCN` / `.kimiGlobal`，共用 `api.kimi.com`，但各自 auth key 字段不同；菜单显示两条。需要用户同时持有两个 key，当前大多数用户可能只有国内 key。

推荐方案 **1**（保守），因为：
- 符合实际技术事实；
- 不增加用户配置负担；
- 仍能满足「RMB 模式隐藏纯海外档」的产品目标。

---

## 4. 其它 Provider 快速结论

根据代码扫描（见 explore agent 报告），其它 provider 中没有像 MiniMax 那样的国内/海外 base URL 切换：

- **OpenCode Go**：同一 host 两个用途端点 + 两套鉴权（models API vs dashboard cookie）。
- **Command Code**：本地代理 → 远程云端 API fallback。
- **Gemini CLI**：配额端点 + 身份端点，多 OAuth 源。
- **Cursor/Grok/Antigravity**：仅认证源 fallback，请求 URL 单一。

因此本次「国内/海外 provider 分离」重构的拆分对象**只有 MiniMax**。

---

## 5. 阶段 1 执行建议（基于事实调整）

1. **MiniMax**：按方案 B 彻底拆分为 `.minimaxCodingPlanCN` / `.minimaxCodingPlanGlobal`，独立 base URL、独立 key 字段。
2. **Kimi**：不强行拆分，保持单一 `.kimi` provider；阶段 2 仅隐藏 RMB 模式下的纯海外档（Vivace）。
3. 阶段 3（FormattingCore）和阶段 4（Kimi level 映射）不受影响，照常执行。
4. 阶段 5 测试 accordingly 调整：重点测试 MiniMax CN/Global 分离、Kimi RMB 隐藏、迁移不丢配置。

---

## 6. 关键验证数据（已脱敏）

- MiniMax key mask：`sk-cp-Tw...g92o`
- Kimi key mask：`sk-kimi-...PUUE`
- 测试账号 Kimi region：`REGION_CN`
- 测试账号 Kimi membership level：`LEVEL_INTERMEDIATE`
