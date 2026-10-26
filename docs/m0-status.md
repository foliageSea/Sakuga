# M0 状态：工程基建与内核验证

> 日期：2026-10-26 · 工程：`/home/foliage/projects/sakuga` · 版本：0.1.0+1
> 环境：WSL2 Ubuntu 24.04 x86_64 / Flutter 3.47.6（FVM）/ Android SDK 已安装 / 无 Android 设备或模拟器 / 无 Mac。

## 1. 已完成

### 1.1 工程迁移

- 从 `/home/foliage/projects/forui_app` 同步 `lib`、`test`、`android`、`macos`、`assets`、`pubspec.yaml`、`l10n.yaml` 等。
- 删除 `ios/`、`windows/`、`linux/`、`web/`、`macos/RunnerTests/`。
- 删除模板示例：`features/catalog`、`features/tasks`、`features/network`、`features/overview`、`assets/snippets`、`tool/sync_snippets.dart`。
- 保留并改造：`app/`、`core/`（日志/设置/网络/窗口）、`shared/`、`l10n/`、`settings`。

### 1.2 应用标识

| 项 | 值 |
| --- | --- |
| 应用名 | Sakuga |
| Dart 包名 | `sakuga` |
| Android namespace / applicationId | `com.foliage.sakuga` |
| macOS bundle id | `com.foliage.sakuga` |
| macOS 最低系统 | 13.0（待改工程配置；模板原 12.0） |
| Android minSdk | 26 |
| 版本 | `0.1.0+1` |

### 1.3 导航骨架

- 五个分支：`/home`、`/library`、`/search`、`/downloads`、`/settings`。
- 新增占位页：`features/home`、`library`、`search`、`downloads`。
- Shell 侧栏/底部导航改为五项；桌面自绘标题栏保留。
- 新增根 `rootNavigatorKey`；新增 `/player` 全屏空播放页（`Player` + `VideoController`，无媒体），为 M2 铺路。

### 1.4 播放内核

- `pubspec.yaml` 接入 Predidit/media-kit fork：
  - `media_kit` / `media_kit_video`，ref `83b7ca63772856e1ea0158916177e136f7b7b0be`。
  - 不引入 `media_kit_libs_*`；使用 native assets。
- `main()` 调用 `MediaKit.ensureInitialized()`。
- `assets/shaders/` 已放入 Anime4K GLSL（含 `LICENSE`，MIT）。
- 依赖冲突处理：
  - media_kit_video 依赖 `wakelock_plus 1.3.3` → `package_info_plus <9`；
  - 因此 `package_info_plus` 降到 `^8.3.1`，`share_plus` 降到 `^12.0.2`。

### 1.5 构建与检查

| 检查 | 结果 |
| --- | --- |
| `fvm flutter pub get` | 通过 |
| `fvm flutter gen-l10n` | 通过 |
| `fvm flutter analyze` | 通过（No issues found） |
| `fvm flutter build apk --debug --target-platform android-arm64` | 通过，APK 173MB（debug，含 media_kit/Video 与 Vulkan validation layer） |
| 16KB 对齐 `zipalign -c -P 16 -v 4` | 通过 |
| macOS arm64 构建 | 未验证（当前主机 Linux） |
| `fvm flutter test` | **失败**（见 §3） |

APK 内原生库：`libmpv.so`（22.8MB）、`libmediakitandroidhelper.so`、`libmedia_kit_event_loop.so`、`libVkLayer_khronos_validation.so`（debug）。

### 1.6 Jellyfin 测试服联调

测试服 `http://110.42.96.64:44762`（10.10.7，凭据只放本地环境变量）：

- `Authorization: MediaBrowser` 与 `X-Emby-Token` 均可用。
- `/UserViews` 返回“番剧”库；`/Items` 返回 51 个条目。
- mkv/h264/aac 的 `PlaybackInfo` 返回 `SupportsDirectPlay=true`，无 `TranscodingUrl`。
- `DeliveryUrl` 自带 `api_key`；客户端应剥离并改用请求头。
- 测试服未生成 Trickplay/MediaSegments（404/空）。

详细记录：[jellyfin-10.10-probe.md](research/jellyfin-10.10-probe.md)。

## 2. 待完成（M0 剩余）

1. **macOS arm64**：已把 `MACOSX_DEPLOYMENT_TARGET` 改为 13.0、补 ATS/本地网络说明；在 Mac/CI 上执行 `fvm flutter build macos --arch arm64`，验证：
   - 纯 SPM + native assets 是否成立（fork 的 `media_kit_video` 有 Package.swift）；
   - 失败则回退 CocoaPods；
   - 13.0 deployment target、entitlements、ATS。
2. **测试**：解决 Linux 上 media_kit native assets 编译问题，或改为在 macOS/CI 跑 `flutter test`。
3. **Impeller 决策**：M0 基线关闭；在 Android 真机/Mac 上验证 HUD blur 是否仍触发 abort。
4. **Android 真机**：安装 APK，验证启动、导航、media_kit 初始化不崩溃。
5. **CI**：PR 跑 format/analyze/test；主分支构建 Android arm64；macOS 用 Apple Silicon runner。

## 3. 已知阻塞：Linux 上 `flutter test` 失败

现象：

```text
No Visual Studio installation found with the requested Microsoft.VisualStudio.Component.VC.Tools.x86.x64 component.
Hook.build hook of package:media_kit has invalid output
- Code asset ".../libmedia_kit_event_loop.so" does not exist as a file.
```

背景：

- `flutter test` 在 Linux 上为 host 构建 native assets（target_os=linux）。
- media_kit 的 hook 用 `native_toolchain_c` 编译 `libmedia_kit_event_loop.so`；当前环境解析器回退到 MSVC，导致编译失败。
- `flutter build apk` 走 Android NDK，不受影响；`flutter analyze` 不受影响。
- 关闭 native assets 也不行（media_kit/objective_c 声明需要 code assets）。

处理建议：

- 优先在 macOS/CI 跑测试；或
- 修复 WSL 下 clang 解析（给 `native_toolchain_c` 提供可解析的 clang），或升级/替换 `native_toolchain_c`；或
- 在 CI 中使用 macOS runner 跑单元/Widget 测试，Android 只做构建。

## 4. 下一步

按计划进入 M1：Jellyfin 认证、服务器档案、首页/媒体库/详情/搜索。M0 的 macOS 构建与测试阻塞并行处理。
