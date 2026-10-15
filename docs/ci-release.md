# BrightnessFollow 的 GitHub Actions 发布

普通 CI 对提交和 PR 运行 Swift 测试、脚本检查及公证恢复测试，不读取签名 Secrets。
`Release macOS` 在 arm64 `macos-26` 机器上构建已合入 `main` 的代码。

## 一次性配置

在 `iobee/BrightnessFollow` 的 Settings → Secrets and variables → Actions 中配置：

| 类型 | 名称 | 内容 |
| --- | --- | --- |
| Variable | `MACOS_SIGN_IDENTITY` | 完整的 Developer ID Application 身份名称 |
| Variable | `MACOS_TEAM_ID` | 对应 Apple 开发者团队 ID |
| Secret | `MACOS_CERTIFICATE_BASE64` | 仅该证书和对应私钥的加密 PKCS#12，Base64 编码 |
| Secret | `MACOS_CERTIFICATE_PASSWORD` | PKCS#12 的随机导出密码 |
| Secret | `APPLE_ID` | 公证账号 |
| Secret | `APPLE_APP_SPECIFIC_PASSWORD` | 公证专用密码，不是 Apple 账号主密码 |

私钥写入 GitHub Secrets 会使它离开本机，需先获账号所有者授权。工作流只在临时钥匙串
配置步骤注入这些凭据；签名和所有公证请求明确指定该钥匙串，任务结束后自动清理。
发布到同一仓库，使用 Actions 自动提供的 `GITHUB_TOKEN`，不需要额外个人访问令牌。
参考：[GitHub 官方签名方案](https://docs.github.com/en/actions/how-tos/deploy/deploy-to-third-party-platforms/sign-xcode-applications)。

## 发包

1. 将当前应用源码和 CI 配置通过 MR 合入 `main`。
2. 更新 `Resources/Info.plist` 的版本及构建号并合入 `main`。
3. 推送 `v<版本>` 标签；或手动启动 **Release macOS** 并勾选 `publish`。

手动运行默认只构建和验证，不公开发布。标签必须与应用版本一致，源码必须已合入
`main`。`Scripts/release.sh` 复用本地同一套测试、Developer ID 签名、公证、装订和
ZIP/DMG 验收流程。通过后生成安装包、`SHA256SUMS` 和 `release.json`。

发布先创建草稿，逐项核对 GitHub 附件的 SHA-256 和大小，最后公开为 Latest。
已发布版本、不同哈希的同名文件和版本回退都会被拒绝，不覆盖已有附件。

## 公证超时或任务中断

工作流始终尝试保存 **release-checkpoint** 附件（保留 14 天），其中包含原始签名包、
提交 ID 和构建来源，不包含证书私钥或钥匙串。手动再次运行同一源码提交，把前一次任务
的数字 ID 填入 `resume_run_id`，即可恢复原构建并继续查询 Apple。

恢复会检查仓库、工作流、事件和提交 SHA；不接受 PR、其他仓库或不同提交的构建。
上传结果不明确时会停止，要求核对 Apple 历史，不会自动重复上传。
本地开发和 `./Scripts/release.sh` 用法保持可用。

配置文件已提交并不代表云端签名验收完成。需要 Secrets 就绪、MR 合并，再完成一次
真实的 Release macOS 运行，才能确认完整 CI 链路。
