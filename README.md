# Sakuga

Jellyfin / Emby / 飞牛影视 / 绿联影视第三方客户端，目标平台 macOS（Apple Silicon / arm64）、Android（arm64-v8a）及 Windows（x64）。
基于 `forui_app` 模板（Flutter 3.47.6 + Forui 0.27.5 + Riverpod 3.4.3），播放内核为 media_kit / libmpv，支持 Anime4K 超分辨率。

## 媒体服务器功能对比

下表比较的是 **Sakuga 目前已接入的功能**，不是服务器本身的全部能力。

| 功能 | Jellyfin | Emby | 飞牛影视 | 绿联影视 |
| --- | --- | --- | --- | --- |
| 登录方式 | 用户名／密码（默认）或 API 密钥 | 用户名／密码 | 用户名／密码 | 专用媒体库账号（HTTPS，自签名证书可校验指纹） |
| 分库浏览、分页、搜索 | 支持 | 支持 | 支持 | 支持 |
| 海报、影视详情、季／集 | 支持 | 支持 | 支持 | 支持 |
| 库内高级筛选与排序 | 支持 | 支持 | 暂不支持 | 仅按类型筛选 |
| 首页最近添加 | 支持 | 支持 | 暂不支持 | 支持 |
| 原画直接播放 | 支持 | 支持 | 支持 | 支持 |
| 服务端转码与画质切换 | 支持 | 支持 | 暂不支持 | 暂不支持 |
| 服务端提供的外部字幕 | 支持 | 支持 | 暂不支持 | 暂不支持 |
| 续播进度 | 同步至服务器 | 同步至服务器 | 同步至服务器 | 仅保存在本机 |
| 手动标记已看／未看 | 支持 | 支持 | 暂不支持 | 暂不支持 |

兼容性说明：Jellyfin 和 Emby 已通过本地 Docker 真实联调；飞牛影视已通过模拟服务测试，不同版本、反代及 FN Connect 尚未做真机兼容验证；绿联影视的兼容性可能随 UGOS Pro 固件变化。

## 状态

M0（工程基建与内核验证）进行中。当前已完成：

- 从模板迁移工程，删除组件展厅/任务/网络示例与非目标平台。
- 应用标识改为 `Sakuga` / `com.foliage.sakuga`。
- 五个主导航占位页：首页、媒体库、搜索、下载、设置。
- 接入 Predidit/media-kit fork（pin `83b7ca6`），加入 Anime4K shader 资源。
- `flutter analyze` 通过；Android arm64 debug APK 构建成功，16KB 对齐校验通过。
- Jellyfin 10.10.7 测试服联调通过（认证、UserViews、Items、PlaybackInfo 直连）。
- Linux 本地开发 runner 已加回；debug 构建与本地播放验证通过（WSLg 需 X11 + 软件 GL）。
- 设置页支持 **Jellyfin / Emby 服务器**：Jellyfin 默认使用用户名/密码登录，也可选择 API 密钥；已有 API 密钥配置继续使用原方式。Emby 使用用户名/密码登录；支持测试连接、编辑、删除与切换，服务器卡片显示类型与账户。
- Jellyfin / Emby 密码仅用于登录，不会保存；访问令牌与服务器信息统一通过 `shared_preferences` 持久化到配置 JSON。测试登录不会保存配置，点击「保存」后才写入。名称修改保留现有登录，修改地址或账户需要重新登录并更新本地身份；会话过期时可编辑服务器，输入密码后保存以重新登录。
- 媒体库页面已接入：`/Users` → `/UserViews` → `/Items`，支持媒体库切换、刷新与海报网格；配置服务器后会自动重新加载。
- 媒体库支持按库类型查询、分页滚动加载、剧集/季/集下钻，以及海报父级回退与 DPR 自适应。
- 详情页（背景图/简介/演职员/分集）与海报磁盘缓存已接入。
- 首页（继续观看/最近添加）与搜索（防抖、结果网格）已接入。

待完成：

- 后续播放功能完善。
- macOS DMG 的 Developer ID 签名与 Apple 公证（公开分发前配置）。
- 测试在 Linux 上受 media_kit native assets 编译问题阻塞（见 `docs/m0-status.md`）。
- Android 真机运行验证（当前环境无设备/模拟器）。

## 服务器配置备份与迁移

在「设置 → 服务器」标题栏的「⋯」菜单中，可以导入或导出服务器配置。导出会生成一个 JSON 文件：桌面端选择保存位置，移动端通过系统分享菜单保存或发送。默认不包含 API 密钥和登录令牌，导入后可在编辑服务器时重新登录或填写密钥。若主动选择包含登录凭据，请妥善保管明文文件；账号密码不会导出。

导入时先预览新增项和重复项。确认后只追加新配置，不覆盖现有条目，也不改变已选中的服务器。

## Jellyfin / Emby 使用

在「设置 → 服务器」添加服务器，选择 **Jellyfin** 或 **Emby**，填写服务器地址、用户名和密码，再点击「保存」。Jellyfin 默认认证方式为「账号/密码」，也可切换为「API 密钥」后填写密钥。切换认证方式会清空不兼容的凭据并更新本地身份。地址可包含反向代理子路径（Emby 地址也可包含末尾的 /emby）；「安全连接」开关用于选择 HTTPS。无密码账号可留空密码。

支持普通视频媒体库的浏览、分页筛选、搜索、详情、季/集、直接播放、服务端转码、内封/外部字幕，以及播放进度和已看状态同步。查询使用登录账号的用户 ID，无需管理员权限。Emby Connect、直播和需要额外打开/关闭流程的动态媒体源暂不支持。

密码不会落盘；Jellyfin / Emby 访问令牌、Jellyfin API 密钥和服务器信息统一使用 `shared_preferences` 持久化，重启后从配置恢复。此前单独存储的 Emby 令牌需重新登录后写入配置。修改服务器地址或账号需要重新登录；删除服务器会清理对应的本地令牌。401 提示重新登录，403 显示权限错误。

已使用本地 Docker Emby 4.9.3.0 普通账号完成真实联调：媒体库/搜索/筛选、电影和两集剧集的原生播放、续播拖动、图片和中英文字幕、继续观看、进度写回及已看状态通过。可复用的测试服、账号和开放授权资源见 [Emby 联调环境](tool/emby-test/README.md)；详情见 [联调结果](tool/emby-test/RESULTS.md)。Jellyfin 账号登录也已通过 Docker Jellyfin 12.4.0 普通账号的真实浏览、原生播放、字幕和进度同步验证，见 [Jellyfin 联调环境](tool/jellyfin-test/README.md) 与 [结果](tool/jellyfin-test/RESULTS.md)。

## 飞牛影视使用

在「设置 → 服务器」选择「飞牛影视」，填入用于打开飞牛影视的地址（含端口或反代子路径，如有）、用户名和密码。可先点「测试连接」验证片库访问，再点「保存」。密码不保存；会话过期后，在原服务器配置里重新输入密码并保存。建议在受信任的局域网使用 HTTP，其它网络使用 HTTPS。

首版支持分库分页、全局搜索、海报和影视详情、季/集、原画直播放和服务端续播进度。飞牛服务器暂不开放库内高级筛选和排序、最近添加、转码档位、手动标记已看及外部字幕。参考 [fnmovie](docs/third-party-notices.md) 的接口在本地模拟服务上覆盖了鉴权、图片、Range 拖动和进度回读；不同飞牛影视版本、反代及 FN Connect 尚未做真机兼容验证。

运行飞牛专项测试：`fvm flutter test test/fnmovie_client_test.dart test/fnmovie_settings_test.dart`。要额外验证 libmpv 拖动，可通过 `--dart-define=FNMOVIE_NATIVE_FIXTURE=<MP4 绝对路径>` 指向 [Emby 联调环境](tool/emby-test/README.md) 中的 Big Buck Bunny 影片。

## 绿联影视使用

1. 按[绿联官方指南](https://support.ugnas.com/detail/article/zh-CN/908)，在 UGOS Pro 的「影视中心 → 设置 → 媒体服务器」启用媒体库服务，并配置专用媒体库账号，不要使用 NAS 管理员账号。
2. 在 Sakuga 的「设置 → 服务器」选择「绿联影视」，填入 NAS 主机名或 IP，默认 HTTPS 端口为 `9443`；使用自定义端口时请明确填写。无需填写 `/emby` 或其他路径。
3. 使用系统信任的证书可留空「证书 SHA-256 指纹」。使用自签名证书时，可点击「获取指纹」在弹窗中查看服务器当前提供的证书指纹（不会发送登录信息），并用复制图标将其复制到剪贴板。与 NAS 或可信局域网取得的指纹核对一致后，再点「填入指纹」；不要信任仅从未知公网连接看到的证书。更换证书后需重新核对指纹。建议使用有密码的专用账号和局域网/私网连接，不要把空密码服务暴露到公网。
4. 输入专用账号，点击「测试连接」验证能访问片库，再点「保存」。密码不落盘；会话失效时，编辑原配置并重新登录。

绿联适配直接复用 NAS 原有片库，支持分库分页、按类型筛选、搜索、海报、详情、季/集、原画和内封字幕。首页轮播从一批电影和剧集中本地随机挑选，优先使用有横幅的条目，不依赖 NAS 的随机排序。续播进度存于本机，不回写绿联；不支持转码画质、外部字幕、收藏或手动标记已看。不同固件可能存在差异，绿联影视中心并不是完整的 Emby 服务器。

可选真机联调：准备一个未纳入版本控制、仅用于测试的 JSON 文件，配置 `UGREEN_LIVE_TEST: true`、`UGREEN_TEST_URL`、`UGREEN_TEST_USERNAME`、`UGREEN_TEST_PASSWORD`、`UGREEN_TEST_FINGERPRINT`（后两项可为空）。片库需有一部带海报的电影和至少一集已入库的剧集。不要分发包含这些构建参数的测试包。

```sh
fvm flutter test integration_test/ugreen_server_test.dart -d <device> \
  --dart-define-from-file=/path/to/local-ugreen-test.json
```

## 播放质量

播放器顶部的「播放质量」可选择最高画质或 1080p (20 Mbps)、720p (8 Mbps)、480p (3 Mbps)、360p (1 Mbps)。档位同时向服务器下发码率上限和视频高度上限：源片超过任一上限时服务器拒绝直接播放并按上限缩放转码，否则仍直接播放。切换时停止当前会话并清理服务端转码任务，重新请求 PlaybackInfo 并从当前位置继续播放。选择在本次播放器内的后续剧集中保持，重新进入播放器恢复最高画质。

退出、切集和换画质时会在停止上报后调用 `DELETE /Videos/ActiveEncodings` 清理转码；协商成功但未进入播放（失败、被新的打开操作取代）的会话同样清理。目前不保留切换前手动选择的音轨／字幕，暂不支持直播放失败后的自动回退。

可选真实联调测试（需本地 Docker Jellyfin / Emby 及其 live-config）：

```sh
fvm flutter test integration_test/transcode_quality_test.dart -d <device> \
  --dart-define-from-file=tool/jellyfin-test/results/live-config.json \
  --dart-define-from-file=tool/emby-test/results/live-config.json
```

## 缓冲容量

「设置 → 常规 → 缓冲容量」可选标准 32 MiB（默认，与此前一致）、较大 128 MiB、大 256 MiB，用于前向预读上限；已播放部分的后向保留固定为 32 MiB，避免总占用随选项翻倍。设置在下次打开视频时生效（包括切集与切换播放质量）。增大缓冲可缓解短时网络波动，不能解决持续带宽不足；播放器启用了磁盘缓存，较大档位主要增加临时磁盘占用。

真实 libmpv 对本地 Docker Jellyfin 直接播放约 62 MiB 片源的测量：32 MiB 时前向缓存停在 32.0 MiB（约 227 秒），128 MiB 时缓存全部剩余内容（596 秒）。可选测试：

```sh
fvm flutter test integration_test/playback_buffer_test.dart -d <device> \
  --dart-define-from-file=tool/jellyfin-test/results/live-config.json
```

## ASS / SSA 字幕

ASS/SSA 与位图字幕使用 mpv/libass 原生渲染，尊重原始样式和内嵌字体；普通文本字幕保留应用样式设置。原生字幕截图已接入。实现、自动测试及目标设备验收边界见 [ASS 字幕说明](docs/ass-subtitles.md)。

## 开发

安装 FVM 后，在项目目录执行：

```sh
fvm install
fvm flutter pub get
fvm flutter run -d macos
```

Android：

```sh
fvm flutter run -d <android-device>
```

构建：

```sh
fvm flutter build apk --debug --target-platform android-arm64
tool/build_dmg.sh
fvm flutter build linux --debug
```

### Windows x64

在 Windows 10/11 x64 上安装 Visual Studio 的「使用 C++ 的桌面开发」工作负载（含 MSVC、Windows SDK 和 CMake 工具）及 FVM，然后在 PowerShell 中执行：

```powershell
fvm install
fvm flutter pub get
fvm flutter run -d windows
fvm flutter build windows --release
```

本地构建输出为 [Release 目录](<build/windows/x64/runner/Release/>)。使用 GitHub Release 的 Windows ZIP 时，请将整个压缩包解压到同一目录，再运行其中的 Sakuga.exe；不要单独移动 exe。播放器依赖的 libmpv 已随包提供，无需另装 mpv。如果系统提示缺少 MSVC 运行库，请安装[微软官方 Visual C++ Redistributable（x64）](https://aka.ms/vc14/vc_redist.x64.exe)。ZIP 中的应用未做代码签名，下载后可能触发 SmartScreen 提示。

Windows 首版不提供播放器的截图复制及 GPU 用量显示。

### macOS DMG

在 macOS 上安装 Xcode（完成首次启动配置）及 FVM 后执行：

```sh
fvm install
tool/build_dmg.sh
# 可传入 Flutter 构建参数，覆盖版本或添加 dart-define：
tool/build_dmg.sh --build-name=0.1.0 --build-number=2
```

脚本优先使用 FVM，否则使用 PATH 中的 Flutter，先构建 Release 应用，再用系统自带的 `hdiutil` 创建并校验压缩 DMG，无需安装额外打包工具。DMG 中包含 `Sakuga.app` 和 `Applications` 快捷入口，打开后拖入 Applications 即可安装。DMG 文件及挂载后的磁盘卷均使用构建产物中的应用图标。

输出目录为 `build/macos/dmg/`，文件名包含实际构建版本、构建号和架构，例如 `Sakuga-0.1.0+1-macos-arm64.dmg`；同时包含 arm64 和 x86_64 的应用使用 `universal` 后缀。构建产物已由 Git 忽略。

当前沿用 Xcode 工程的本地 ad-hoc 签名，脚本不执行 Developer ID 签名或 Apple 公证；对外公开分发前需另行配置，下载后的应用可能受到 Gatekeeper 限制。

### Android 发布签名

**GitHub Release：** 请生成并离线备份一把新的 Android 发布密钥，不要复用原先提交过的密钥。在 GitHub 仓库的 **Settings → Environments → android-release** 中添加以下 Environment Secrets，并将该环境限制为可信发布标签（例如 `v*.*.*`）；有条件时启用人工审批。发布标签应指向经过审核且包含此签名配置的提交。

| Secret | 内容 |
| --- | --- |
| `ANDROID_KEYSTORE_BASE64` | 新密钥库文件的完整 Base64 编码（Base64 不是加密） |
| `ANDROID_KEYSTORE_PASSWORD` | 密钥库密码 |
| `ANDROID_KEY_ALIAS` | 私钥别名 |
| `ANDROID_KEY_PASSWORD` | 私钥密码 |

Actions 只在 Android 发布构建步骤注入签名材料，缺失时构建失败。后续官方版本应继续使用同一把新密钥，不要为每次发布生成新密钥。使用旧密钥签名的侧载 APK 通常不能被新签名版本直接覆盖，用户应先备份再卸载重装。停止追踪不会从历史中移除旧凭据；对外开源前，请清理所有将公开的分支和标签，或从清理后的源码新建公开仓库。

**本地构建：** debug 不需要发布密钥。需要本地 release 时，创建不提交的 `android/key.properties`，设置 `storeFile`、`storePassword`、`keyAlias` 和 `keyPassword`。使用新密钥或专门的本地测试密钥；`storeFile` 的相对路径以 `android/` 为基准。缺少签名配置时 release 构建会报错。

```sh
fvm flutter build apk --release --target-platform android-arm64
# Google Play 使用 AAB：
fvm flutter build appbundle --release --target-platform android-arm64
```

本地 APK 输出为 `build/app/outputs/flutter-apk/app-release.apk`。

Linux（本地开发/验证，非发布目标）：

```sh
# WSLg 建议 X11 + 软件 GL；普通桌面可省略
GDK_BACKEND=x11 LIBGL_ALWAYS_SOFTWARE=1 fvm flutter run -d linux
```

Linux 需要系统多媒体库：

```sh
sudo apt install libva2 libva-drm2 libva-x11-2 libva-wayland2 libvdpau1 \
  libpulse0 libsndfile1 libasyncns0 libxss1 libxv1
```

没有 sudo 时，用项目脚本自动下载/解压到用户缓存并设置运行环境：

```sh
tool/run_linux.sh
```

脚本会调用 `tool/linux_deps.sh`（`apt-get download` + `dpkg-deb -x`，不需要 root），并设置 `GDK_BACKEND=x11`、`LIBGL_ALWAYS_SOFTWARE=1` 与 `LD_LIBRARY_PATH`。

本地播放验证（不提交 token）：

```sh
fvm flutter build linux --debug \
  --dart-define=DEV_START_ROUTE=/player \
  --dart-define=DEV_MEDIA_URL='<direct-play-url>'
GDK_BACKEND=x11 LIBGL_ALWAYS_SOFTWARE=1 ./build/linux/x64/debug/bundle/sakuga
```

检查：

```sh
fvm dart format --output=none --set-exit-if-changed lib test
fvm flutter analyze
fvm flutter test
```

## GitHub 发版

在干净的发布分支上，传入要发布的新版本号：

```sh
tool/release.sh --dry-run 0.1.1
tool/release.sh 0.1.1
```

脚本会把 `pubspec.yaml` 的 `0.1.0+1` 更新为 `0.1.1+2`，提交版本变更，并将当前分支和 `v0.1.1` 标签一并推送到 `origin`。如果推送失败，可用同一版本号重试，不会再次增加构建号。不传版本号时，只按 `pubspec.yaml` 中已提交的版本创建并推送标签，不修改文件。

[Release 工作流](<.github/workflows/release.yml>)会并行构建 Android arm64 APK、macOS Apple Silicon DMG 和 Windows x64 ZIP。三个构建都成功后才会创建 GitHub Release、生成发布说明并上传产物。失败时可在 Actions 页面重跑失败的任务，无需重新打标签。
若标签已推送但没有触发构建，可在 **Release → Run workflow** 中填写包含 Windows 支持的已有发布标签手动运行；不为旧标签补构建 Windows 包。若只想验证 Windows，可在 [Windows Build 工作流](<.github/workflows/windows.yml>)的 **Run workflow** 中选择包含 Windows 支持的分支，仅生成可下载的 `windows-release` 构建产物，不创建 GitHub Release。

例如 `0.1.0+1` 会发布到 `v0.1.0`，产物命名为 `Sakuga-0.1.0-1-android-arm64-v8a.apk`、`Sakuga-0.1.0-1-macos-arm64.dmg` 和 `Sakuga-0.1.0-1-windows-x64.zip`。Android 沿用项目现有的发布签名；macOS 仍是 ad-hoc 签名，未做 Apple 公证，下载后可能受到 Gatekeeper 限制。

## 应用图标

采用「漫画分镜」图标，SVG 与 1024 px PNG 源图位于 `assets/icons/`。
[图标生成配置](<icons_launcher.yaml>)启用 Android、macOS 与 Windows；Android 自适应图标使用透明前景与独立背景色，macOS 和 Windows 使用完整图标。

更新 PNG 源图后，执行：

```sh
fvm flutter pub get
fvm dart run icons_launcher:create
```

生成资源位于 [Android 资源目录](<android/app/src/main/res/>)、[macOS 图标集](<macos/Runner/Assets.xcassets/AppIcon.appiconset/>)与 [Windows ICO](<windows/runner/resources/app_icon.ico>)。重新构建应用后生效。

## 目录

```text
lib/
  app/          应用根、路由、响应式外壳、主题
  core/         设置、日志、网络、窗口、平台能力
  data/         Jellyfin / Emby / 飞牛影视 API、认证与本地存储
  features/     首页、媒体库、搜索、下载、设置、播放器
  shared/       跨功能 UI 与本地化
  l10n/         中英文 ARB
assets/
  shaders/      Anime4K GLSL（MIT）
  MiSans-Regular.ttf
docs/           开发计划与调研
macos/          macOS 工程
android/        Android 工程
windows/        Windows 工程
test/           单元与 Widget 测试
```

## 约定

- 界面不写注释性/说明性文本，只保留功能所需文案。
- 播放器 UI 自绘，使用 Forui 主题 token；业务页面使用 Forui 组件。
- 播放/超分/平台差异收敛在 `PlayerEngine` 与 `PlatformCapabilities` 后面。

## 许可

Sakuga 原创代码采用 [Apache License 2.0](LICENSE)。第三方依赖、字体、着色器和图标继续适用各自的条款，见[第三方许可与署名](THIRD_PARTY_NOTICES.md)。

Sakuga 是非官方媒体服务器客户端。

## 致谢

超分辨率实现参考了 [Kazumi](https://github.com/Predidit/Kazumi)，感谢 Kazumi 开发者和贡献者的开源分享。

## 文档

- [开发计划](docs/plan.md)
- [M0 状态](docs/m0-status.md)
- [调研报告](docs/research/)
