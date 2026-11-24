# 打包与发布

[文档索引](README.md) · [本地开发与测试](development.md)

各平台的版本号与构建号以 [pubspec.yaml](../pubspec.yaml) 的 `X.Y.Z+BUILD` 为准。以下命令均在项目根目录执行。对外分发前，请按实际安装包核对原生库、字体及其他第三方资源的许可和分发条件，见[第三方许可与署名](../THIRD_PARTY_NOTICES.md)。

## Android：本地签名与构建

Debug APK 不需要发布密钥。构建 release 时，创建不提交的 `android/key.properties`，填写 `storeFile`、`storePassword`、`keyAlias` 和 `keyPassword`；`storeFile` 的相对路径以 `android/` 为基准。缺少签名配置时 release 构建会失败。

```sh
fvm flutter build apk --release --target-platform android-arm64
# 需要 AAB 时：
fvm flutter build appbundle --release --target-platform android-arm64
```

本地 APK 默认输出到 `build/app/outputs/flutter-apk/app-release.apk`。GitHub Actions 另用按 ABI 拆分参数只打包 arm64-v8a，并保留配置的构建号作为 Android versionCode。

### GitHub Actions 签名

在仓库的 **Settings → Environments → android-release** 配置以下 Environment Secrets。将环境限制在可信发布标签（如 `v*.*.*`），有条件时启用人工审批。

| Secret | 内容 |
| --- | --- |
| `ANDROID_KEYSTORE_BASE64` | 密钥库文件的完整 Base64 编码；Base64 不是加密 |
| `ANDROID_KEYSTORE_PASSWORD` | 密钥库密码 |
| `ANDROID_KEY_ALIAS` | 私钥别名 |
| `ANDROID_KEY_PASSWORD` | 私钥密码 |

使用迁移后的发布密钥并离线备份；不要复用曾提交到仓库的旧密钥，也不要每次发布都重新生成密钥。旧签名的 APK 通常不能由新签名版本直接覆盖，用户应先备份再卸载重装。删除工作树中的密钥文件不会清理 Git 历史；公开源码前须处理将公开的历史分支与标签，或从清理后的源码创建新仓库。工作流只在 Android release 构建步骤注入签名材料，并拒绝仍跟踪旧签名文件的标签。

## macOS：DMG

在 macOS 上配置 Xcode，并用 FVM 安装项目 SDK，然后执行：

```sh
tool/build_dmg.sh
```

[DMG 脚本](../tool/build_dmg.sh)优先使用 FVM，未安装 FVM 时使用 PATH 中的 Flutter；可传入 `--build-name`、`--build-number` 等 Flutter 构建参数。脚本构建 release 应用，并用系统自带的 `hdiutil` 创建和校验 DMG，输出到 `build/macos/dmg/`。本地文件名格式为 `Sakuga-版本+构建号-macos-架构.dmg`；CI 只发布 Apple Silicon 产物。

DMG 包含 `Sakuga.app` 和「应用程序」快捷入口。当前沿用本地 ad-hoc 签名，不执行 Developer ID 签名或 Apple 公证；公开分发需另行配置。

## Windows：安装包与便携包

准备 [Windows 工具链](development.md)、[Inno Setup 6.3 或更新的 6.x 版本](https://jrsoftware.org/isdl.php)与 PowerShell 7。以下为匹配的本地构建参数示例：

```powershell
fvm flutter build windows --release --build-name=0.1.5 --build-number=6
./tool/build_windows_installer.ps1 -BuildName 0.1.5 -BuildNumber 6
```

[打包脚本](../tool/build_windows_installer.ps1)使用现有的 Flutter Release 目录，不会重新编译应用。找不到 Inno Setup 时，可传入 `-IsccPath`。EXE 输出到 `dist/`，默认安装到当前用户的 `%LOCALAPPDATA%\Programs\Sakuga`，创建开始菜单快捷方式并可选桌面快捷方式。新版本可覆盖安装，可通过「已安装的应用」卸载；卸载不删除用户设置。安装包与便携包目前均未签名，不含 MSVC 运行库。

验证 CI 打包可在 [Windows Build](../.github/workflows/windows.yml) 选择包含 Windows runner 和打包脚本的分支执行 **Run workflow**。它会检查安装与卸载，并生成包含 EXE 和 ZIP 的 `windows-release` 构建产物，不创建 GitHub Release。

## 发布到 GitHub

在干净的发布分支上，将以下示例版本换成未发布的新版本。先检查预览结果，再执行发布：

```sh
tool/release.sh --version
tool/release.sh --dry-run 0.1.6
tool/release.sh 0.1.6
```

[发布脚本](../tool/release.sh)在版本名变化时将构建号加一，提交版本变更并将分支和标签一并推送至 `origin`。脚本不会检查新版本名是否高于当前版本，预览也不会验证远端标签或工作区状态。若推送失败且标签尚未到达远端，可用相同版本重试；不带版本时只按已提交的当前版本打标签、推送标签，不改文件。

[Release 工作流](../.github/workflows/release.yml)验证标签 `vX.Y.Z` 与源码版本匹配，构建 Android arm64、macOS arm64 和 Windows x64；全部成功后才创建 GitHub Release 并上传：

- `Sakuga-版本-构建号-android-arm64-v8a.apk`
- `Sakuga-版本-构建号-macos-arm64.dmg`
- `Sakuga-版本-构建号-windows-x64-setup.exe`
- `Sakuga-版本-构建号-windows-x64.zip`

失败时在 Actions 重跑失败任务，不要重打标签。若已有标签未触发构建，可在 **Release → Run workflow** 输入该标签；标签须包含当前构建所需的 Windows 安装器和 Android 签名迁移，不适用于给旧版本补发安装包。
