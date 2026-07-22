# Token King 四线治理总蓝图(2026-07-20)

> 跨 4 条工作线的实施总蓝图。经 writer 起草 + reviewer 对抗审查 + 主 agent 实测裁决定稿。
> 基线 `main` HEAD `b8bef40`。配套现状报告见 `docs/handoffs/2026-07-20-项目全貌深度分析.md`。
> **这是总蓝图,不是单线详细 spec**。每条线批准后各自走 spec→plan→实现。

---

## 0. 定稿说明:审查裁决的三处修正

writer 初稿有三处被 reviewer 挑出、经实测裁决修正:

| 争议 | 实测结论 | 对蓝图的影响 |
|------|----------|--------------|
| 数据修复 `464f6e5` 在哪 | 在 `main` 与 `codex/token-king-95-main`,**不在** `codex/token-king-95`(两个不同分支,早前混淆) | 「出包回归」担忧降级为「核对打包分支」动作,落到 L0 |
| `CurrencyFormatter.shared` 引用数 | 实测 **59 处(40 生产/19 测试)**,writer 的「8 处」是拍脑袋;`SubscriptionSettingsManager.shared` **66 处(45 生产)** | L1-M1 工期上调,「引用面最小」论据作废 |
| 3 个占位 provider 能否修 | Mimo/ZhipuGLM/Hunyuan **零 endpoint/URL 代码**(commit ede99ec 显式注册为 stub) | L2-M1 前必须先验 API 存在性,否则无法交付 |

据此新增 **L0 前置验证线**、**L3 测试基建提前到 L2 前**、**L1-M2 改按 provider 分批下沉**。

---

## 1. 总览

四条线整体是「先验假设、固地基、织测试网、再补业务、最后动承重墙」。核心依赖:L2 账单代码活在 provider switch 与共享单例引用里,L1 不先收敛,L2 每加特性都要跨 8+ 文件改 switch,白干且必留新 wiring bug。L4(拆 5278 行 God object)风险最高,必须等 L1 单例注入 + L3 交互测试网就位。

**顺序(经审查修正):L0 → L1 → L3基建 → L2 → L4**(L3 基建提前,先给 L2 建回归网)。

## 2. 依赖图

```
L0 前置验证 ──► L1 结构止血 ──┬──► L3 测试基建 ──► L2 账单补完 ──┐
                             │                                  ├──► L4 大重构
                             └──────────────────────────────────┘
```

- **强阻塞**:L0→L1(核对分支/API)、L1→L2(switch/单例)、L1→L4(单例注入)、L3基建→L2(先建网)、L1+L3→L4
- **可并行**:L1 内部「删死方法」与「单例解耦」并行;L3-M2/M3 与 L1 收尾可并行

## 3. 里程碑拆解

### L0 前置验证(半天,必须先做——消除两个致命假设)
| 里程碑 | 做什么 | 产出/判定 | 工作量 |
|--------|--------|-----------|--------|
| L0-M1 占位 provider API 可用性 | 查 Mimo/ZhipuGLM/Hunyuan 官方文档 + 抓包,确认有无用量查询 API | 有→L2-M1 成立;无→L2-M1 降级为「手动录入订阅额度」或砍掉 | 半天 |
| L0-M2 打包分支核对 | `git diff main codex/token-king-95-*` 核对账单/聚合相关文件差异,确认打包基线 | 明确出包应基于哪个分支、95 分支缺什么 | 半天 |

### L1 结构止血(先做,低风险——根治「改A坏BCD」)
| 里程碑 | 改什么 | 验证 | 回滚 | 工作量 |
|--------|--------|------|------|--------|
| L1-M1 单例解耦 | `CurrencyFormatter.shared`(59处/40生产)、`SubscriptionSettingsManager.shared`(66处/45生产)改构造注入,复用已有 `InitOptions.testing` seam(StatusBarController.swift:106-152) | `xcodebuild test` 全绿 + 9 条测试污染 bug(B01/B07/B08/B10-B15)+ B44 菜单卡死回归 | git revert 单 commit | 2-3天(引用面比初稿估的大) |
| L1-M2 provider 特性下沉 | 把散在 20+ switch 的 provider 特性(iconName/configInfo/f2bRaw 等)收进 `ProviderProtocol`,**按 provider 分批(每 PR 一族),非按特性** | 每批编译 + 该 provider 快照测 | 按批 revert(不留 switch/protocol 并存) | 1-2周(185 switch,初稿低估) |
| L1-M3 allCases 防线 | `testAllListedProvidersReturnExplicitEntries` 硬编码 27 数组改 `ProviderIdentifier.allCases`(31 case) | 该测试先转红→补齐→转绿 | 单文件 revert | 半天 |
| L1-M4 删死方法 + Zai挂target | 删 StatusBarController 7 个 0 调用死方法(mv 归档);`ZaiCodingPlanProviderTests` 挂 target(顺手并入) | Periphery 扫描 + 编译 + test 列表出现 Zai | 单 commit | 半天 |

### L3 测试基建(提前到 L2 前——先建网)
| 里程碑 | 改什么 | 验证 | 工作量 |
|--------|--------|------|--------|
| L3-M2 Widget 纯函数单测 | 抽 `WidgetDesignToken` 格式化、`ProviderSelectionIntent` 选择逻辑为纯函数,补单测(当前零测) | 新测绿,不需 UI runner | 1-2天 |
| L3-M3 注入式替代 sleep(35) | UITest 用注入固定数据取代 `sleep(35)`+真实 session 依赖 | E2E 连跑 3 次无 flake | 1-2天 |

### L2 账单补完(依赖 L1 收敛 + L3 网)
| 里程碑 | 改什么 | 验证 | 回滚 | 工作量 |
|--------|--------|------|------|--------|
| L2-M1 修3个假占位 | **依赖 L0-M1 结论**:有 API→接真实 quota;无 API→手动录入/砍 | 真机 + 快照测 | 单文件 revert | 1-2天(或降级) |
| L2-M2 extractor 真实验证 | ZAI(有非官方端点 `/api/monitor/usage/quota/limit` 可验)/NanoGPT(需真机抓包)extractor 用真实 fixture 验证 | 真实 fixture 回归 | 单文件 revert | 1-2天 |
| L2-M3 F2 ROI 对比(最简版) | 「订阅价 vs API价 省/亏」——**先做单 provider 文本版,砍掉多 provider 对比矩阵**直到有数据支撑 | 新增单测 + 真机 | feature flag 隐藏 | 2-3天(初稿的多provider矩阵砍掉) |
| L2-M4 口径融合 + override收尾 | 两套账单同 provider 交叉说明(消 minimaxCN/mimo 矛盾);day/week 走 monthTotalOverride | 月度对账 + E2E | 单 commit | 1-2天 |
| L2-M5 Codex 去重加固(独立) | Codex 去重从「只比相邻」改全窗口+排序(独立 bug 修复,配回归) | 新增乱序/非相邻重复用例 | 单文件 revert | 半天 |

### L4 大重构(最后,中风险——拆 5278 行)
| 里程碑 | 改什么 | 验证 | 回滚 | 工作量 |
|--------|--------|------|------|--------|
| L4-M1 抽 Formatter | 从 StatusBarController 抽货币/token 格式化(纯函数) | 全测 + 真机菜单栏 | 单 commit | 1-2天 |
| L4-M2 抽 ShareCoordinator/MenuAssembler | 抽分享簇(:4127-4483)+ 菜单装配(updateMultiProviderMenu 960行) | L3 交互测网 + 真机 | 单 commit | 1-2周(5278行体量) |
| L4-M3 物删 #if false 死代码 | 观察期已过(2026-07-17),物删第一批 9 处 + 从 pbxproj 移引用;建 Periphery 护栏(不用 --strict) | 编译 + Periphery baseline | git revert | 半天 |

## 4. 红线与风险

- **L4 绝对红线**:`pendingStatusItem`/`attachTo`/`renderStatusItemImage` 是 macOS 26.x 菜单栏唯一可行桥接路径,**不可拆、不可改签名**(依据 `docs/handoffs/2026-07-04-statusbar-architecture-problem.md`)。抽取时三者留在 controller,只搬其余职责。
- **StatusBarController 5278 行体量**:L4-M2 远超「几天」,按 provider/职责分多 PR,每步打 git tag 支持 5 分钟回滚。
- **L1-M2 静态派发陷阱**:protocol extension-only 方法是静态派发,以协议类型调用会误走默认实现。纪律:**凡需 override 的特性一律在 protocol 本体声明**(不能只写 extension)。这正好替代「有 default 的 switch 漏 case 静默兜底」——新增 provider 编译器强制补齐,无处可漏。
- **L2-M1 前置假设**:3 个占位 provider 无网络代码,**L0-M1 未验证通过前不得开工 L2-M1**。
- **数据回归**:出包分支须经 L0-M2 核对(464f6e5 在 main 与 95-main,不在 95)。

## 5. 验证策略(每线「没坏别的」)

- **L1**:`cd CopilotMonitor && xcodebuild test -scheme CopilotMonitor -destination 'platform=macOS'` 全绿基线 + 9 条污染 bug + B44 场景回归;L1-M2 每批 provider 前后快照 diff
- **L3**:E2E 去 sleep 后连跑 3 次无 flake
- **L2**:月度对账(day_aggregates 增量表路径)+ 真机看两套账单同 provider 自洽
- **L4**:真机反复开合菜单栏 + L3 交互测网守护;每 milestone 打 git tag
- **eval 基线**(项目 SOP 要求):L1 开工前建立 eval 基线作为前置产物

## 6. 建议的第一步

**L0-M1(占位 provider API 可用性验证)**——半天,消除全蓝图最大的未验证假设。若三家无 quota API,L2-M1 直接降级,避免投入无法交付的里程碑。L0 通过后从 **L1-M4**(删死方法 + Zai 挂 target,半天零风险)或 **L1-M3**(allCases 防线,半天)起步热身,再攻 L1-M1 单例解耦。

## 7. provider 特性下沉推荐写法(POP over switch)

采用「protocol 声明需求 + extension 默认实现 + 个别 provider override」,替代跨文件穷举 switch。关键纪律见 §4 静态派发陷阱。参考 replace-conditional-with-polymorphism 范式。下沉后加第 32 个 provider:只改 1 新文件 + enum + pbxproj,编译器强制补齐,B02/B16-B29 类 wiring bug 从机制上消除。

## 8. 待用户决策

1. L0 验证是否立即启动(建议是,半天出结论)
2. 若三家占位 provider 无 API,L2-M1 选降级(手动录入)还是砍掉
3. L1-M1 单例解耦作为主攻方向确认(2-3 天,根治 9+ bug)
