# Token King Widget 视觉还原 — 现状报告(2026-07-18)

> 面向 Codex 的接手文档。Token King 六个桌面 widget 已完成向 quota-float **展开态 QuotaCard** 的视觉重构,用户逐尺寸真机验收通过。本文档:方向、现状、架构、数据语义、踩坑、死代码清单、遗留项、验证工作流。

---

## 1. 一句话现状

六个 widget(small / mediumOverview / mediumDetail / largeOverview / largeDetail / searchEngines)全部按 quota-float 展开卡(quota-states.png)重排:浅卡容器 + tier aurora + 5h 短窗剩余%大数字 + 发光渐变条 + 周窗 footer;真机两态(全彩/变暗)验收通过,编译 0 error、swiftlint 0、裸值 grep 空、中文 grep 空、#Preview 10。

## 2. 最终方向与参照物(重要,别搞错形态)

- **参照物 = quota-float 仓库 `docs/images/quota-states.png` 的展开态 QuotaCard**(eyebrow / "5-hour remaining" / 64px 剩余%大数字 / 发光进度条 / reset-time / weekly 30px 副指标 / provider mark)。
- **不是**收缩态 QuotaOrb(纯数字球)。前 6 轮失败主因就是照错了形态(orb vs card),用户最后以 quota-states.png 明确。
- 本地参照图缓存:`/tmp/quota-float-ref/quota-states.png`、`quota-orb.png`(易失);源:GitHub `change-42-yhmm/quota-float`。
- CSS 精确值来源:`src/components/QuotaCard.tsx` + `src/styles.css`(探索代理已全量提取,见 §7 与 git 历史)。

## 3. 各尺寸现状(TokenKingWidgetView.swift)

### small(systemSmall)— 迷你 QuotaCard,用户首轮验收
结构:`SmallWidgetView`
- eyebrow(名字大写 9px/600/字距1.7,`minimumScaleFactor(0.75)` 防长名截断)+ 右上发光状态点
- 描述行 "5-hour remaining"(8px;非 5h 窗显示 `<label> remaining`)
- 45px 剩余% + 17px bold %(orbCopy 系列 token)
- 6px 发光条:宽=剩余、`colorValue`=已用(critical 短条仍橙红)
- "resets in Xh Ym" / "Reset unknown"(8px)
- usage provider:45px $ 金额 + "spent"

### medium(overview + detail)— 紧凑 QuotaCard
结构:`MediumProviderCard`(两个实例共用)
- header:eyebrow 14px + 描述行 8px 叠排左上,状态点右上
- hero 45px(与 small 同号)**,数字框按 line-height .82 收框**(`quotaHeroBoxFactor`)
- 6px 发光条 → reset 12px
- footer:有 7d 窗 → "7D LEFT NN%" 17px + provider 图标 20px;无 → "Updated HH:MM:SS / Every 15 min"

### largeDetail — 近 1:1 QuotaCard
- header:eyebrow 14px + "5-hour remaining" 14px(.08em/.9)+ 右上 25px 磨砂圈状态灯
- **64px** hero(.82 收框)+ 21px %,`.padding(.top, 18/18/7)` 对齐 QuotaCard 三处 margin
- 6px 发光条 → reset 12px
- footer:"Weekly remaining · until M/d" 12px/300 + 30px 周数字 + 15px %,右侧 provider mark 43px

### largeOverview / searchEngines — 多 provider 列表(同语言)
- 标题 eyebrow 大写("TOKEN KING" / "SEARCH ENGINES")
- 行 = 点 + 图标 + 名 + 右侧 `<label> NN%`(**剩余**语义)+ 9px 发光条(宽=剩余、色=已用)
- "+N more" 折叠 + Monthly 月费页脚(保留,未动月花费计算)

## 4. 容器/背景架构(TokenKingWidget.swift)

- 六个配置统一 `QuotaCardBackground(tier:)`:实色浅卡 `orbCardBackground`(#edf3f8)+ `AuroraBackgroundView(tier:)` + 1px 白描边(顶 .42 → 底 .34 渐变)。纯渐变,零 material/scrim。
- **tier 来源**:`providerTier(snapshot:selectedProviderId:)`(单 provider 卡 = 展示 provider 的短窗已用)、`overviewTier(snapshot:)`(多 provider 卡 = 所有 provider 短窗已用的峰值)。**不要回退到快照峰值**(那会把背景钉死在 critical 粉)。
- **边距标定**:六配置均 `.contentMarginsDisabled()`,内容统一显式 `padding(cardContentPadding = 16)`(TokenKingWidgetView.body)。原因:系统默认 content margins 按 family 不同(small≈16、medium≈9-13 且不对称),曾导致三尺寸边距观感不一。16 = quota-float 卡 padding 30px/320px × 166pt ≈ 15.6。
- vibrant/accented:系统在 vibrant 会替换 containerBackground 并单色化内容,**无需任何门控代码**(早期"浅色卡白上白"问题已通过"背景交给系统"根治;不要再在内容层自画浅色底)。

## 5. 数据语义层(全 widget 统一)

- `shortWindow(of:)`:id=="5h" 的窗口,回退 primary。**hero/条/reset/dot 全部跟短窗**。
- `weeklyWindow(of:)`:id=="7d"/"weekly",footer 副指标。
- **显示值 = 剩余 %**(`100 - usedPercent`),quota-float 语义;**条宽 = 剩余、条色 = 已用**(`CapsuleProgressBar(value:colorValue:)` 拆分,critical 短条仍橙红)。
- tier 阈值:used <60 healthy / <85 caution / ≥85 critical(沿用 Severity;Aurora.tier 同色板)。
- usage 类型 provider:显示 $ 花费,不显示 %。

## 6. 设计 token 规则(必须遵守)

- 视图层零裸值:颜色/字号/间距/圆角/线宽一律 `WidgetDesignToken.*`;**0/1 允许裸写**;禁止 `zeroInt/tinyGap` 式假 token(历史遗留尚未清,见 §8)。
- 新 token 必须可溯源(quota-float 源码值或注明换算);`WidgetDesignToken.swift` 只加不改已有值。
- 全英文文案;视图文件零中文字符(含注释,grep 会查)。

## 7. 踩坑记录(每条都是真机/真图验证过的)

1. **先锁渲染参照物再动手**:CSS 精确值 ≠ 渲染效果(壁纸/blur/层叠)。凭 CSS 脑扑连错两轮,拿到 quota-states.png 才锚定。
2. **先确认用户要的是产品的哪种形态**(orb 球 vs 展开卡),再谈复刻精度。
3. **vibrant 白上白**:内容层自画浅色卡会在 vibrant 被系统映白、与白字相融。正解=背景全走 containerBackground 让系统接管。
4. **色相打架**:背景 aurora tier(快照峰值 critical 粉)与卡内 tier(短窗 healthy 蓝)不一致时"杯垫贴纸"感。正解=容器与内容同一 tier。
5. **SwiftUI 默认行高 ~1.2 在数字框上下垫隐形空隙**,hero→bar 等间距全面偏松;quota-float 是 `line-height:.82`。正解=`quotaHeroBoxFactor` 收框(已用于 medium/large detail;small 未用,用户已验收其现状)。
6. **系统 content margins 按 family 不同**,标定做法见 §4。
7. **medium(166pt)内容预算极限**:16pt 上下边距 + 全元素栈 ≈134pt 上限,hero 45px/描述 8px 是上限解;加元素必溢出顶边距。
8. **长 provider 名截断**:eyebrow 一律 `minimumScaleFactor(0.75)` 自动缩,不许 lineLimit 截断。

## 8. 死代码清理状态

已在 `codex/token-king-95-main` 清理：

- `RingGauge`、`ProviderBadge` 两个零引用视图。
- orb 时代的零引用 token：`orbHeroSize`、`orbHeroTracking`、`orbHeroCardTracking`、`orbCopyRadius`、`orbCardRadius`、`orbAuroraScale`、`orbAuroraGlowRadius`、`orbAuroraWarmRadius`、`orbAuroraCoolRadius`、`orbCardBackgroundOpacity`、`orbCardHighlightOpacity`、`orbCardBorderOpacity`、`orbCardShadowColor`、`orbCardShadowRadius`、`orbCardShadowY`、`orbCopyScale`、`orbTracking`、`orbSize`、`wNameSize`。

仍可继续做的纯代码卫生项：将历史 `zeroInt`、`zeroDouble`、`zeroSpacing`、`zeroLength`、`singleLine` 调用改成 Swift 的 `0` / `1` 字面量；这不改变视觉或数据语义，优先级低于真实数据和安全收口。

清理注意:`orbCardBorderWidth`、`percentHeroMediumSize`、`mediumHeroTracking`、`weeklyNumberSize`、`largeBarTopMargin` 仍在用,别误删。

## 9. 已知遗留 / 后续建议

1. **large detail reset→weekly 之间弹性空档偏大**(footer 沉底设计使然,参照物也有但比例小);若用户再提,可把 weekly 块上移或给大卡加周窗进度条。
2. **small 的 hero 未收 .82 框**(用户已验收其现状,改动需重新验收)。
3. **usage provider 的 medium/large 版式较简**($ + spent),quota-float 无对应形态,可再设计。
4. **"Primary remaining" 描述文案**:无 5h 窗的 provider(codex/tavily 等)显示窗口 label,quota-float 恒为 "5-hour remaining";是否统一文案待产品决定。
5. **周报月花费卡片(Monthly footer)** 保留在 largeOverview,quota-float 无此元素。
6. 桌面摆位:large detail 底部易被 Dock 遮挡(用户摆位,非布局问题)。

## 10. 验证工作流(命令级,每轮必跑)

```bash
# 1. 编译(必须 SUCCEEDED)
cd CopilotMonitor && xcodebuild build -project CopilotMonitor.xcodeproj -target TokenKingWidget \
  -destination 'platform=macOS' ENABLE_USER_SCRIPT_SANDBOXING=NO 2>&1 | grep -E "error:|BUILD (SUCCEEDED|FAILED)"
# 2. 装机(Release + adhoc 签名 + PlugInKit 注册)
bash scripts/build-and-install.sh
# 3. 重启 widget 渲染
killall WidgetKitExtension chronod 2>/dev/null; sleep 5
# 4. 截图(机器常被占用,先记录可见 app 再恢复)
osascript -e 'tell application "Finder" to activate'
osascript -e 'tell application "System Events" to keystroke "h" using {option down, command down}'
sleep 2 && screencapture -x desktop-fullcolor.png
osascript -e 'tell application "Clash Party" to activate'   # 变暗态:任一 app 前置即可
sleep 2 && screencapture -x desktop-dimmed.png
# 锁屏时:轮询 ioreg -n Root -d1 -a 的 CGSSessionScreenIsLocked,解锁后自动拍(脚本模式见 git 历史)
# 5. 静态检查
swiftlint lint CopilotMonitor/TokenKingWidget/*.swift   # 期望 0
grep -nE '\.system\(size: *[0-9]|Color\(red:|#[0-9a-fA-F]{6}' CopilotMonitor/TokenKingWidget/TokenKingWidgetView.swift  # 期望空
perl -CSD -ne 'print "$.:$_" if /\p{Han}/' CopilotMonitor/TokenKingWidget/TokenKingWidgetView.swift  # 期望空
```

验收纪律:逐元素 PASS/FAIL,拿不准判 FAIL;VLM 自评不算数,用户 + 外部模型裁决。

## 11. 产物索引

- 参照图:quota-states.png(见 §2);原型基准 16 张:`docs/handoffs/screenshots/2026-07-16-prototype-baseline/`
- 过程截图:`docs/handoffs/screenshots/2026-07-16-round0-current/` … `round8/`(round5/8 部分被用户窗口遮挡,以用户自拍为准)
- 关键 commit(新→旧):
  - 本轮(待提交):中/大 QuotaCard 化 + 容器统一 + 边距标定 + .82 收框 + 防截断
  - `7c7bebd` small 迷你 QuotaCard 定案
  - `4f19eda` 短窗/周窗数据语义 + orb 卡(后被取代)
  - `ac680f9` medium QuotaCard 层级 + small orb 放大(后被取代)
  - `17ed073` tier aurora 背景
- 过程 handoff:`2026-07-16-widget-quotacard-medium-redesign.md`(含 Round 1-7 追加)、`2026-07-16-quota-float-design-tokens.md`(quota-float CSS 全量提取)
