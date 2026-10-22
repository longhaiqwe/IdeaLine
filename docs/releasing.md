# 灵感晾台发布与更新

使用 Sparkle 2.9.2，与 PinSnip 的技术方案一致。Swift Package Manager 固定依赖版本，`Package.resolved` 应随源码保存。接入遵循 [Sparkle 官方文档](https://sparkle-project.org/documentation/) 和 [菜单栏应用提醒说明](https://sparkle-project.org/documentation/gentle-reminders/)。

## 本地开发

```sh
swift test
python3 scripts/test_release_config.py
scripts/build-app.sh
```

生成 `build/灵感晾台.app`。构建会在临时目录中装配、验证后输出，旧产物保留为带时间戳的 previous 包。默认本机架构、ad-hoc 签名，绝不能用它覆盖已安装的正式签名版本。没有更新配置也能使用应用；更新菜单说明缺少服务，两个自动更新开关禁用，不启动 Sparkle 网络检查。

构建脚本使用 macOS 自带命令和 Swift、Python 3。Sparkle.framework 连同 XPC 服务与 Updater.app 一起嵌入，保持符号链接，按从内到外的顺序签名。

## 首次配置

本仓库已配置更新源 `https://raw.githubusercontent.com/longhaiqwe/IdeaLine/main/appcast.xml` 和 `idealine` 钥匙串账户对应的公钥。私钥保存在维护者的 Mac 钥匙串中，不在 GitHub 上。新维护机器需要迁移已有私钥，不能直接生成新密钥覆盖发布身份。以下步骤供初始设置或独立 fork 参考。

当前正式签名为 `Developer ID Application: hai long (5RFJK73RSL)`，Team ID 为 `5RFJK73RSL`；本机公证 profile 为 `shiyinfm-notary`。后续发布与本机升级必须保持此签名身份，不能用 ad-hoc 或 Apple Development 包覆盖正式版。替换前验证完整签名、公证、Bundle ID，并保存旧版和数据备份；安装目录优先沿用现有位置。

1. 确定本应用自己的更新源，例如 GitHub 仓库中的 `appcast.xml`，不要使用 PinSnip 的更新源。
2. 生成此应用的 Sparkle 密钥；私钥留在钥匙串，不写入仓库：

   ```sh
   swift package resolve
   .build/artifacts/sparkle/Sparkle/bin/generate_keys --account idealine
   ```

3. 编辑 `release.json`：`feed_url` 填写公开可访问的 HTTPS 清单地址，`public_ed_key` 填写上一步输出的公钥。两项必须同时填写。`version` 是 `1.1.0` 格式，`build` 是严格递增的正整数字符串。Bundle ID 保持 `local.longhai.IdeaLine`，本地数据目录保持不变。
4. 准备稳定的 Developer ID Application 证书，以及 `notarytool` 钥匙串凭据 profile。首次正式分发后保持签名身份和公钥稳定。

## 准备发行包

每次发布先修改 `release.json`，增加 `build`，并编写 `docs/releases/<version>.md`。如果已有线上清单，先将它同步至仓库根目录 `appcast.xml`；脚本据此拒绝重复或倒退的构建号，并保留更新历史。

```sh
export IDEALINE_CODE_SIGN_IDENTITY='Developer ID Application: <证书名称> (<Team ID>)'
export IDEALINE_NOTARY_PROFILE='<notarytool profile>'
export IDEALINE_DOWNLOAD_URL_PREFIX='https://github.com/longhaiqwe/IdeaLine/releases/download/v1.2.0/'
scripts/prepare-release.sh
```

默认使用 `idealine` 钥匙串账户，可通过 `IDEALINE_SPARKLE_ACCOUNT` 显式指定。脚本校验公钥匹配，运行测试，构建 arm64 + x86_64 Universal 应用，签名、公证、staple，然后打包并用 Sparkle 生成 EdDSA 签名清单。失败即停止，不产生可发布的最终清单。私钥始终由 Sparkle 从钥匙串读取，不导出。

产物在 `build/Release/`：应用、`IdeaLine-v<version>-macOS-universal.zip`、`appcast.xml`。此脚本**不上传、不发布、不替换用户正在使用的应用**。

发布顺序：先上传 ZIP 到 `IDEALINE_DOWNLOAD_URL_PREFIX` 对应地址，确认文件可下载，再发布生成的清单至 `feed_url`，将同一清单保存为仓库根目录的 `appcast.xml`。首次带更新能力的版本也必须发布有效清单。签名后不要修改 ZIP。

提交本次源码、`release.json` 和发布说明后，为该提交创建 `v<version>` 标签并推送到 GitHub。Release 必须指向此标签，并附上应用 ZIP 和 `SHA256SUMS.txt`；GitHub 自动生成的源码包不能替代应用安装包。上传后重新下载，核对 SHA-256，解压并执行 `codesign --verify --deep --strict`、`xcrun stapler validate` 和 `spctl --assess --type execute -vv`。检查应用版本、构建号以及 `arm64` / `x86_64` 架构，再发布更新清单。

## 验收

- 关于面板显示正确版本、构建号；主菜单和状态栏菜单均能打开检查更新。
- 使用真实发行包验证无更新、发现新版、断网、下载失败和签名错误；只有验证通过的更新允许安装。
- 后台检查不会自动弹出安装窗口，状态栏图标和菜单显示新版入口；手动点击使用 Sparkle 标准更新界面。
- 自动检查默认每天一次；自动下载安装默认关闭，可自行开启。偏好由 Sparkle 持久化；关闭自动检查时保留下载偏好但禁用该选项。
- 以旧的已签名版本实际升级到新版本，确认草稿、选题、归档和排序不变；数据读取或保存失败时先处理数据问题再升级。
- 在 ARM 与 Intel 的目标机器上分别验证启动、检查、安装及重启。

本地测试与打包不等于端到端更新验收；端到端流程需要真实发布地址、密钥、证书及两个可升级的发行包。
