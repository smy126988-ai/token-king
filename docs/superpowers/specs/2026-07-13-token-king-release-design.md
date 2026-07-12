# Token King 发布与更新设计

## 1. 目标

建立唯一、可重复的 Token King 发布流程，使版本、源码、universal app、签名、公证、DMG、GitHub Release 和 Sparkle appcast 互相一致。

## 2. 产品与版本事实源

- 产物名固定为 `Token King.app`，可执行文件为 `Token King`。
- `Info.plist` 使用 `$(MARKETING_VERSION)` 和 `$(CURRENT_PROJECT_VERSION)`。
- Xcode target build settings 是应用版本事实源。
- Release tag 必须为 `v$(MARKETING_VERSION)`；workflow 在构建前断言一致。
- `CURRENT_PROJECT_VERSION` 单调递增，独立于展示版本。
- 菜单版本从运行 bundle 读取，commit hash 从构建产物读取。

## 3. 唯一 workflow

合并/淘汰重复发布入口，只保留一个手动或 tag 触发的 release workflow。步骤：

1. checkout 精确 tag；
2. 校验版本、工作树和 secrets；
3. fresh test + Release build；
4. archive `arm64 x86_64`；
5. 校验主程序和 CLI 双架构；
6. Developer ID 签名与 `codesign --verify --deep --strict`；
7. app ZIP 公证、staple、validate；
8. 创建只含 App 和 Applications symlink 的 DMG；
9. DMG 签名、公证、staple、`spctl`；
10. 生成 Sparkle signature/appcast；
11. 发布到 `smy126988-ai/token-king`；
12. 下载已发布产物重新验签和校验哈希。

任何一步失败都不得创建“成功”Release。

## 4. Sparkle

- appcast enclosure 指向 fork Release 的真实 DMG。
- `SUFeedURL` 指向 fork 可访问 appcast。
- 从旧版本到新版本完成一次端到端更新验证。
- 如果缺少 Sparkle 私钥或不准备提供自动更新，则明确移除菜单入口和文档承诺，不能保留空 feed 的假功能。

## 5. 本地开发安装

`scripts/build-and-install.sh` 使用当前 worktree DerivedData，构建后验证 bundle id/version/hash，只安装 `/Applications/Token King.app`，不残留旧 bundle 或 LaunchServices 注册。

开发安装可 ad-hoc；对外 DMG 必须 Developer ID + notarized。

## 6. 文档

重写 `docs/RELEASE_WORKFLOW.md`：

- 只描述 Token King；
- 禁止 `git add .`、`xattr -cr` 等绕过；
- 给出版本一致性、universal、签名、公证、staple、spctl 和回滚检查；
- 记录缺少证书/secret 时的明确阻断状态。

## 7. 验收

- workflow dry-run 不再出现 `OpenCode Bar.app` 或上游 Release URL。
- `tag == MARKETING_VERSION == DMG/appcast version`。
- 主程序与 CLI 都是 `arm64 x86_64`。
- GitHub Release 含 notarized DMG 和 appcast，下载 URL 可访问。
- 干净 Mac 无 Xcode、无终端绕过即可安装并启动。
- 旧版本可以发现并验证新版本更新。
