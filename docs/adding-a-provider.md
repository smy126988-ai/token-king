# 如何新增一个 Provider

以新增 `FooProvider` 为例。Token King 的 pbxproj 手动管理，**每个 `.swift` 新文件必须手动注册**，漏一处就编译失败或文件不参与编译。

## 步骤总览（7 处改动）

### 1. 建 Provider 文件

`CopilotMonitor/CopilotMonitor/Providers/FooProvider.swift`：

```swift
import Foundation
import os.log

private let logger = Logger(subsystem: "com.opencodeproviders", category: "FooProvider")

final class FooProvider: ProviderProtocol {
    let identifier: ProviderIdentifier = .foo
    let type: ProviderType = .quotaBased   // 或 .usageBased

    private let tokenManager: TokenManager
    private let session: URLSession

    // 网络慢的 provider 覆写超时（默认 10s）
    var fetchTimeout: TimeInterval { 30.0 }

    init(tokenManager: TokenManager = .shared, session: URLSession = .shared) {
        self.tokenManager = tokenManager
        self.session = session
    }

    func fetch() async throws -> ProviderResult {
        guard let apiKey = tokenManager.getFooAPIKey() else {
            throw ProviderError.authenticationFailed("Foo API key not available")
        }
        // ...请求 + 解析，返回 ProviderResult(usage:details:)
    }
}
```

### 2. ProviderIdentifier 枚举 + 4 个穷举 switch

`CopilotMonitor/CopilotMonitor/Models/ProviderProtocol.swift`：

- `enum ProviderIdentifier` 加 `case foo`
- 4 个穷举 switch 各加 `.foo` 分支：`displayName`（品牌名，**不翻译**）、`shortDisplayName`、`iconName`（SF Symbol），以及其它对 identifier 穷举的地方
- ⚠️ Swift 穷举 switch 缺分支 = 编译错误，编译器会帮你找全

### 3. TokenManager 加 key 读取

`CopilotMonitor/CopilotMonitor/Services/TokenManager.swift`：

- auth.json 的 Codable struct 加字段（如 `let foo: AuthEntry?`，JSON key 用 `foo` 或带连字符的实际字段，配 `CodingKeys`）
- 加 `func getFooAPIKey() -> String? { auth.foo?.key }`

### 4. ProviderManager 注册

`CopilotMonitor/CopilotMonitor/Services/ProviderManager.swift` 的 `makeDefaultProviders()`：加 `FooProvider()` 到数组。

### 5. 订阅预设（可选）

`CopilotMonitor/CopilotMonitor/Models/SubscriptionSettings.swift`：

- 加 `static let foo: [SubscriptionPreset] = [...]`（国内套餐填 `cnyCost`）
- `presets(for:)` 穷举 switch 加 `case .foo: return foo`

### 6. pbxproj 手动注册（最易漏，共 6 条）

`CopilotMonitor.xcodeproj/project.pbxproj`，参考现有 `MiniMaxProvider.swift` 的注册（用助记 UUID 命名如 `FOOAPP...`/`CLIFOO...`/`FOOFILE...`）：

- **PBXBuildFile ×2**：`CopilotMonitor` app target 一条、`opencodebar-cli` CLI target 一条
- **PBXFileReference ×1**：文件引用
- **PBXGroup ×1**：加到 Providers group 的 children
- **PBXSourcesBuildPhase ×2**：app Sources 一条、CLI Sources 一条

搜索现有 provider 名（如 `grep -n MiniMaxProvider project.pbxproj`）照抄 6 处结构，改文件名和 UUID。

### 7. 测试

`CopilotMonitorTests/FooProviderTests.swift`（也要 pbxproj 注册到 test target），至少测解析逻辑。

## 验收

```bash
cd CopilotMonitor && xcodebuild test -scheme CopilotMonitor -destination 'platform=macOS' 2>&1 | tail -30
```

BUILD SUCCEEDED + 新测试通过 + 原有测试不回归。

## 常见坑

- 漏 pbxproj 任一处 → `"Cannot find 'FooProvider' in scope"` 或文件不编译。
- provider 文件若被 CLI target 用，`CurrencyFormatter` 等仅在主 app target 的类不可用——数据层别预烤 `$`/`¥`，格式化放 `ProviderMenuBuilder`。
- `displayName`/`authSource`/logger 串/SF Symbol 名/被 `==` 比较的状态串**不翻译**（阶段3铁律）。
