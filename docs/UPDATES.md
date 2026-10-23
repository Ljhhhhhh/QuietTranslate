# 更新发行

QuietTranslate 使用 [Sparkle](https://sparkle-project.org/documentation/) 更新应用，更新清单来自公开仓库 `Ljhhhhhh/QuietTranslate` 的最新正式 GitHub Release 附件 `appcast.xml`。检查更新会连接 GitHub；更新包的实际下载可能转向 GitHub 的附件 CDN。此过程不发送翻译文本或引擎凭据。

## 首次准备

```sh
zsh scripts/setup-signing.sh
zsh scripts/setup-updates.sh
```

前者复用应用签名身份；后者在登录钥匙串中创建或复用账号 `local.quiettranslate.sparkle` 的 EdDSA 私钥，将公钥保存为 `Resources/UpdatePublicKey.txt`。公钥和 `Package.resolved` 应随源码提交；私钥不能提交或作为 Release 附件上传。换机器时需要迁移原应用签名证书及私钥、原 Sparkle 私钥，不要重新生成身份。

## 构建与发布

1. 修改根目录 `VERSION`，使用严格递增的三段数字版本号。打包将它同时写入 `CFBundleVersion` 和显示版本；同版本重建不会被识别为新版。
2. 执行 `zsh scripts/package.sh`。脚本嵌入并签名 Sparkle 框架及辅助程序，验证应用签名，生成 DMG 和带 EdDSA 更新包签名的清单，并校验更新包签名。缺少或不匹配的更新密钥会中止打包。
3. 在 GitHub 创建对应 `v<版本号>` 的正式 Release，将 `build/updates/QuietTranslate-<版本号>.dmg` 和 `build/updates/appcast.xml` 一起作为附件上传。先上传全部附件再发布；不要将预发布或草稿设为最新正式版本。清单中使用的下载地址绑定该版本标签，发布后不要替换同名 DMG。

使用 GitHub CLI 可以先创建草稿，检查附件后再到 GitHub 发布：

```sh
version=$(cat VERSION)
gh release create "v$version" --repo Ljhhhhhh/QuietTranslate --draft \
  --title "QuietTranslate $version" --generate-notes \
  "build/updates/QuietTranslate-$version.dmg" build/updates/appcast.xml
```

安装包仅支持构建机器的 CPU 架构；生成清单会记录硬件要求。若需要同时支持 Intel 和 Apple Silicon，需先将构建流程改为通用二进制，不能用另一个架构的同名附件覆盖已发布更新。

对外发行仍需使用 Developer ID 签名并完成 Apple 公证；本机自签名不等于公证。若公证或装订修改了 DMG，必须针对最终 DMG 重新运行 Sparkle 的 `generate_appcast`，不能继续使用修改前的签名清单。工具位于 `.build/artifacts/sparkle/Sparkle/bin/`，执行时指定 `--account local.quiettranslate.sparkle` 和与该标签一致的 `--download-url-prefix`。

## 安装与验证边界

首个带更新能力的版本需手动安装到“应用程序”，退出旧应用后替换；从应用程序启动，避免从只读 DMG 运行。后续使用菜单栏“检查更新…”或等待定期检查；可关闭“自动检查更新”，手动检查仍然可用。应用默认不静默安装更新。

发布前需检查标签、附件下载地址、架构和版本号。编译、包签名与更新包签名检查不代表下载安装、重启或辅助功能授权保留已通过；真实升级验证遵循项目 AGENTS.md 的 E2E 授权规则。
