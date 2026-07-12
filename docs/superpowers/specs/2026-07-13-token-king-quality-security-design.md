# Token King 安全、测试与运行稳定设计

## 1. 目标

让默认开发和 CI 验证完全离线、覆盖真实 target，并把生产诊断、build hash 和状态栏生命周期收敛成可安全长期运行的实现。

## 2. 默认离线测试

- 所有真实网络测试必须同时满足独立 Live test plan 和 `RUN_LIVE_PROVIDER_TESTS=1`。
- 默认 `CopilotMonitorTests` 使用完整响应 fixture、fake credential provider 和 URLProtocol/本地 session。
- mock 解析测试不得先读取真实 TokenManager；机器没有凭证时也必须执行。
- CI 明确拒绝默认测试产生外部请求，可通过 URLProtocol guard 或网络审计断言验证。

## 3. Target 完整性

新增脚本比较 `CopilotMonitorTests/**/*.swift` 与 pbxproj Sources membership。缺失文件使 CI 失败。当前已知五个遗漏测试文件全部加入 active target。

UI tests 使用 testing/demo mode 注入确定性菜单数据：

- 不读取用户 Provider、SQLite 或 Keychain；
- 用 accessibility identifier 等待实际状态，不用固定 `sleep(35)`；
- shared scheme/test plan 可在 CI 或专用 GUI runner 执行。

## 4. 日志策略

- 生产默认只用 `os.Logger`，敏感字段使用 privacy；
- 禁止记录 token/cookie/key 的任何片段，以及邮箱、account/project id；
- 完整本地路径归一化为来源类型或 `~` 相对路径；
- 菜单树、anchor fingerprint、KVO dump 只在 DEBUG 且显式诊断开关开启时运行；
- 如保留文件诊断，创建权限 0600、限制大小并轮转，退出或过期清理。

新增自动扫描测试，确保 fixture 日志中常见 credential pattern 为零。

## 5. Build hash

`Inject Git Hash` 只能写入 `$TARGET_BUILD_DIR/$INFOPLIST_PATH`，不得修改源码 `Info.plist`。构建前后 `git status --porcelain` 必须一致。

## 6. 状态栏 bridge

保持当前经实测可点击的 SwiftUI `MenuBarExtra` 路线，但把桥接集中到 `StatusItemBridge`：

- Controller 不直接扫描窗口；
- 移除 `value(forKey: "statusItem")` 私有 KVC；
- 只保留公开回调和安全反射的 best-effort secondary attach；
- 失败时保留 primary item 并记录非敏感状态；
- observer、retry 和 notification 生命周期集中释放。

不在没有实测证据时盲目改成纯 AppKit。

## 7. 验收

- 默认 fresh test 零真实 Provider 请求。
- 磁盘测试文件与 target membership 100% 一致。
- 默认 suite 的 skip 仅保留明确的环境型测试。
- build/test 后源码工作树保持干净。
- 24 小时默认日志增长 <5MB，敏感 pattern 计数为零。
- 冷启动 100 次、登录启动、休眠唤醒、当前可用显示器矩阵无重复、消失或不可点击图标。
