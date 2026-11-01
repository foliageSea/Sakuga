# Sakuga

Jellyfin 第三方客户端，目标平台 macOS（Apple Silicon / arm64）与 Android（arm64-v8a）。
基于 `forui_app` 模板（Flutter 3.47.6 + Forui 0.27.5 + Riverpod 3.4.3），播放内核为 media_kit / libmpv，支持 Anime4K 超分辨率。

## 状态

M0（工程基建与内核验证）进行中。当前已完成：

- 从模板迁移工程，删除组件展厅/任务/网络示例与非目标平台。
- 应用标识改为 `Sakuga` / `com.foliage.sakuga`。
- 五个主导航占位页：首页、媒体库、搜索、下载、设置。
- 接入 Predidit/media-kit fork（pin `83b7ca6`），加入 Anime4K shader 资源。
- `flutter analyze` 通过；Android arm64 debug APK 构建成功，16KB 对齐校验通过。
- Jellyfin 10.10.7 测试服联调通过（认证、UserViews、Items、PlaybackInfo 直连）。
- Linux 本地开发 runner 已加回；debug 构建与本地播放验证通过（WSLg 需 X11 + 软件 GL）。
- 设置页新增 **服务器** 配置入口：名称/URL/API 密钥、测试连接、编辑/删除；首页显示已保存服务器。
- 媒体库页面已接入：`/Users` → `/UserViews` → `/Items`，支持媒体库切换、刷新与海报网格；配置服务器后会自动重新加载。
- 媒体库支持按库类型查询、分页滚动加载、剧集/季/集下钻，以及海报父级回退与 DPR 自适应。
- 详情页（背景图/简介/演职员/分集）与海报磁盘缓存已接入。
- 首页（继续观看/最近添加）与搜索（防抖、结果网格）已接入。

待完成：

- 服务器登录（用户名密码）、API 密钥安全存储（Keychain/Keystore）、服务器切换、播放（下一步 M1/M2）。
- macOS DMG 的 Developer ID 签名与 Apple 公证（公开分发前配置）。
- 测试在 Linux 上受 media_kit native assets 编译问题阻塞（见 `docs/m0-status.md`）。
- Android 真机运行验证（当前环境无设备/模拟器）。

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

Release 构建使用仓库中的 `android/sakuga-release.jks`，别名为 `sakuga`，密码保存在同样纳入版本控制的 `android/key.properties` 中。克隆仓库后可直接构建，无需额外配置。`storeFile` 的相对路径以 `android/` 为基准。

缺少签名配置时 release 构建会报错；debug 构建不需要发布密钥。

```sh
fvm flutter build apk --release --target-platform android-arm64
# Google Play 使用 AAB：
fvm flutter build appbundle --release --target-platform android-arm64
```

APK 输出为 `build/app/outputs/flutter-apk/app-release.apk`。后续更新需继续使用仓库中的同一发布密钥。

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

## 应用图标

采用「漫画分镜」图标，SVG 与 1024 px PNG 源图位于 `assets/icons/`。
`icons_launcher.yaml` 仅启用 Android 与 macOS；Android 自适应图标使用透明前景与独立背景色，macOS 使用带白色圆角底的完整图标。

更新 PNG 源图后，执行：

```sh
fvm flutter pub get
fvm dart run icons_launcher:create
```

生成资源位于 `android/app/src/main/res/` 与 `macos/Runner/Assets.xcassets/AppIcon.appiconset/`。重新构建并安装应用后生效。

## 目录

```text
lib/
  app/          应用根、路由、响应式外壳、主题
  core/         设置、日志、网络、窗口、平台能力
  data/         Jellyfin API 与本地存储（M1 起）
  features/     首页、媒体库、搜索、下载、设置、播放器
  shared/       跨功能 UI 与本地化
  l10n/         中英文 ARB
assets/
  shaders/      Anime4K GLSL（MIT）
  MiSans-Regular.ttf
docs/           开发计划与调研
macos/          macOS 工程
android/        Android 工程
test/           单元与 Widget 测试
```

## 约定

- 界面不写注释性/说明性文本，只保留功能所需文案。
- 播放器 UI 自绘，使用 Forui 主题 token；业务页面使用 Forui 组件。
- 播放/超分/平台差异收敛在 `PlayerEngine` 与 `PlatformCapabilities` 后面。
- 不复制 Kazumi 的 Dart 代码；Anime4K shader 使用 MIT 原文件并保留许可。

## 第三方

- media_kit / libmpv / FFmpeg：见 `about` 页与各包许可。
- Anime4K：MIT，`assets/shaders/LICENSE`。
- MiSans：遵循 MiSans 字体知识产权许可协议。
- Jellyfin：本项目为非官方客户端。

## 文档

- [开发计划](docs/plan.md)
- [M0 状态](docs/m0-status.md)
- [调研报告](docs/research/)
