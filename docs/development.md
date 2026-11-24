# 本地开发与测试

[文档索引](README.md) · [打包与发布](release.md)

## 环境准备

安装 [FVM](https://fvm.app/) 和目标平台的 Flutter 工具链，在项目根目录运行：

```sh
fvm install
fvm flutter pub get
fvm flutter doctor -v
fvm flutter devices
```

Flutter 版本由 [.fvmrc](../.fvmrc) 锁定，应用版本和依赖以 [pubspec.yaml](../pubspec.yaml) 为准。项目使用 Forui、Riverpod、go_router 与 media_kit；首次构建需要联网获取 Dart 依赖和播放器原生库。

## 运行与构建

下表的 `DEVICE_ID` 请替换为 `fvm flutter devices` 列出的设备 ID。各桌面版本须在对应平台上构建。

| 平台 | 工具链 | 运行 | 本地构建 |
| --- | --- | --- | --- |
| macOS（Apple Silicon） | Xcode（完成首次启动配置） | `fvm flutter run -d macos` | `fvm flutter build macos --release`；DMG 见[打包说明](release.md) |
| Android（arm64-v8a） | Android SDK、JDK 17 和 Flutter SDK 所需的 NDK | `fvm flutter run -d DEVICE_ID` | `fvm flutter build apk --debug --target-platform android-arm64`；release 需[签名配置](release.md) |
| Windows（x64） | Visual Studio「使用 C++ 的桌面开发」工作负载（含 MSVC、Windows SDK 和 CMake 工具） | `fvm flutter run -d windows` | `fvm flutter build windows --release`；产物位于 `build/windows/x64/runner/Release/` |
| Linux（仅开发） | Flutter Linux 桌面工具链与下列运行库 | `fvm flutter run -d linux` | `fvm flutter build linux --debug` |

### Linux / WSLg

如果播放器提示缺少系统动态库，Debian/Ubuntu 可尝试安装：

```sh
sudo apt install libva2 libva-drm2 libva-x11-2 libva-wayland2 libvdpau1 \
  libpulse0 libsndfile1 libasyncns0 libxss1 libxv1
```

WSLg 遇到渲染问题时，可试用 X11 与软件 GL：

```sh
GDK_BACKEND=x11 LIBGL_ALWAYS_SOFTWARE=1 fvm flutter run -d linux
```

没有 sudo 时可运行 `tool/run_linux.sh`。它通过 [linux_deps.sh](../tool/linux_deps.sh) 下载并解包运行库到用户缓存，设置 `LD_LIBRARY_PATH` 后启动应用；默认使用 X11 和软件 GL，可通过环境变量覆盖。系统构建工具仍须另行安装。

调试播放器时，可以用无需认证的本地测试流跳过导航和服务器选择：

```sh
fvm flutter run -d linux \
  --dart-define=DEV_START_ROUTE=/player \
  --dart-define=DEV_MEDIA_URL='http://127.0.0.1:8000/sample.mp4'
```

替换为实际可访问的测试流。不要把生产令牌写入构建参数或分发带测试参数的程序。

## 检查与联调

```sh
fvm dart format --output=none --set-exit-if-changed lib test integration_test
fvm flutter analyze
fvm flutter test
```

- 单元与 Widget 测试在 [test/](../test/)；设备或真实服务集成测试在 [integration_test/](../integration_test/)，需要合适的设备和测试配置。
- 真实服务：[Jellyfin Docker 联调环境](../tool/jellyfin-test/README.md) · [Emby Docker 联调环境](../tool/emby-test/README.md)。先准备测试电影、剧集及字幕，再启动服务并生成本地测试配置；全新检出不自带测试媒体，Jellyfin 复用 Emby 的媒体目录。默认 Compose 镜像指定 `linux/arm64` 且端口仅绑定回环，跨架构运行与异机设备连通性需单独处理。不要提交凭据。
- 专项测试：[飞牛影视与绿联影视](servers.md) · [转码与缓冲](playback.md) · [ASS / SSA](ass-subtitles.md)。

## 目录与约定

- [lib/app/](../lib/app/)：应用根、路由、主题与响应式外壳。[lib/core/](../lib/core/)：设置、日志和平台能力。
- [lib/data/](../lib/data/)：四种服务器的适配、认证、媒体数据及持久化。[lib/features/](../lib/features/)：页面与播放器功能。[lib/shared/](../lib/shared/) 与 [lib/l10n/](../lib/l10n/)：通用组件和中英文文案。
- 普通业务页面使用 Forui 组件；播放器使用自绘控件与 Forui 主题 token。播放内核与平台差异分别在播放器引擎和平台能力层处理。
- [assets/](../assets/)：着色器、字体、图标等资源。[tool/](../tool/)：构建、发布和测试辅助脚本。

### 更新应用图标

在 [assets/icons/](../assets/icons/) 更新源图后运行 `fvm dart run icons_launcher:create`，再重新构建应用。生成平台和输入文件见 [icons_launcher.yaml](../icons_launcher.yaml)；生成资源位于 [Android 资源目录](../android/app/src/main/res/)、[macOS 图标集](../macos/Runner/Assets.xcassets/AppIcon.appiconset/) 与 [Windows ICO](../windows/runner/resources/app_icon.ico)。
