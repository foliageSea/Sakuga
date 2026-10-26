# forui_app 模板审计 → Sakuga 迁移清单

- 审计对象：`/home/foliage/projects/forui_app`（git HEAD `e197723`，**只读**，未修改）
- 审计主机：Linux 6.18 WSL2 x86_64；项目 SDK 为 FVM 3.47.6（`.fvmrc:2`），系统 Flutter 3.47.8 / Dart 3.13.7
- 方法：逐文件阅读源码 + `pub.dev` API 与包归档解压比对 + Flutter 3.47.6 SDK 源码核对 + Gradle/AGP 最小复现探针（`/tmp/agp9probe`）

## 0. 决策摘要（先看这 8 条）

1. **模板可作底座**：分层、Provider 组织、路由、日志、设置、主题、本地化都是产品级完成度。真正要重写的是 `features/catalog`、`features/tasks`、`features/network` 三个示例域。
2. **工程是"纯 SPM"形态**：`macos`/`ios` 均无 Podfile，Xcode 用 `XCLocalSwiftPackageReference`（`macos/Runner.xcodeproj/project.pbxproj:234-235,713-718`）。引入只有 podspec 的插件会切回 CocoaPods 混合模式。
3. **media_kit 不支持 SPM**：`media_kit_video 2.0.1`、`media_kit_libs_macos_video 1.1.4`、`media_kit_libs_android_video 1.3.8` 包内只有 `*.podspec`；GitHub main 分支 `Package.swift` 实测 404。加入后 Flutter 会自动生成 Podfile（`flutter_tools/lib/src/macos/darwin_dependency_management.dart:88-101`）并告警"将来会变错误"（同文件 `:289-294`）。
4. media_kit macOS 的 podspec 在 `pod install` 期执行 `system("make")`，Makefile 用 `curl` 下载 libmpv xcframework 并校验 sha256（`media_kit_libs_macos_video-1.1.4/macos/Makefile:1-20`）→ 新机器/CI 必须联网且装了 `make`。
5. **本机无法验证 macOS**：主机是 Linux x86_64，`build/` 只有 `linux/` 与 `app/` 产物，无 `build/macos/`。macOS arm64 交付必须有 Mac 或 macOS CI runner。
6. **Jellyfin 局域网 http 默认不通**：Android 清单无 `usesCleartextTraffic`（`android/app/src/main/AndroidManifest.xml` 全文），targetSdk 36 下明文被禁；macOS `Info.plist` 无 `NSAppTransportSecurity`（`macos/Runner/Info.plist:4-31`）。两处都必须补。
7. **Material 必须来自 `package:material_ui`**：Forui 0.27.5 依赖 `material_ui ^1.0.0`，`toApproximateMaterialTheme()` 返回它的 `ThemeData`（`forui-0.27.5/lib/src/theme/theme_data.dart:981`）；`lib/` 全库 0 处 `package:flutter/material.dart`。混用会得到两套 `Theme`/`MaterialApp`。
8. **三处模板假设与播放器冲突**：桌面自绘标题栏（`lib/app/shell.dart:42-77,246-363`）、全应用 `AppTextScaler`（`lib/app/app.dart:30-39`）、无任何方向/沉浸式控制（`grep SystemChrome lib test` 为空）。详见 §8。

## 1. 目录与分层

| 层 | 职责 | 关键文件 |
| --- | --- | --- |
| `lib/app` | 只做装配：根 Widget、路由、响应式外壳、主题、字号换算 | `app.dart:17-45`、`router.dart:17-94`、`shell.dart:14-213`、`theme.dart:25-76`、`text_scaler.dart:5-24` |
| `lib/core` | 无 UI 的基础设施：设置、网络、日志、异常、窗口、运行环境 | `settings/settings.dart`、`network/api_client.dart`、`logging.dart`+4 个 `logging/*`、`window/desktop_window.dart`、`runtime_environment.dart` |
| `lib/shared` | 跨功能 UI 与适配：页面骨架、反馈、响应式、本地化入口 | `widgets.dart:12-262`、`localization.dart:5-7`、`responsive_button.dart`、`language_options.dart` |
| `lib/features` | 按功能切分，自带 Provider | `catalog`(35 demo)、`tasks`、`network`、`overview`、`settings` |
| `lib/l10n` | ARB + 生成物（已提交） | `app_en.arb`(147 行)、`app_zh.arb`(147 行)、`generated/*`(1864 行) |

依赖方向实测：`core` 不引用 `shared/features/app`；`shared` 不引用 `features`；**唯一分层倒置**是 `features/settings/settings_page.dart:13-14` 引用 `app/theme.dart`、`app/text_scaler.dart` —— 迁移时把这两个文件下沉到 `shared/` 或 `core/` 即可闭环。

Provider 组织（4 种形态，迁移时照抄）：
- 单例依赖：`Provider`，如 `preferencesProvider`（`settings.dart:105`）、`dioProvider`（`api_client.dart:64-68`，`onDispose` 关闭）、`desktopWindowProvider`（`desktop_window.dart:102-106`）、`runtimeEnvironmentProvider`（`runtime_environment.dart:6`）、`fileLogStoreProvider`（`logging.dart:22`）。
- 仓储注入：`settingsRepositoryProvider`（`settings.dart:106-108`）、`taskRepositoryProvider`（`task_repository.dart:45-47`）；测试用内存实现覆盖（`test/fakes.dart:32-54`）。
- 同步状态：`NotifierProvider` + 串行写队列（`settings.dart:110-128`）。
- 异步状态：`AsyncNotifierProvider`（`task_repository.dart:48`）、`FutureProvider.autoDispose.family`（`api_client.dart:137-155`，`ref.onDispose` 取消请求）。
- 启动引导：`main.dart:18-37` 先建临时 `ProviderContainer` 读设置、初始化窗口，再 `runApp` 并覆盖 `initialSettingsProvider`/`desktopWindowProvider`。未使用 riverpod codegen（`pubspec.yaml:33-38` 无 generator）。

## 2. 路由与响应式外壳

- 单个 `StatefulShellRoute`，4 个分支（`/overview`、`/components`、`/examples`、`/settings`），`initialLocation: '/overview'`（`router.dart:19,21-80`）。
- 分支保活 + 淡入滑动：`animatedBranchContainer`（`branch_transition.dart:9-16,24-44`）；目录/预览用 `NoTransitionPage` 避免透出旧内容（`router.dart:44-57`）。
- 返回逻辑靠父路径推导 `backLocation`（`router.dart:24-29`）+ `FHeader.nested`（`shell.dart:159-178`）。
- `errorBuilder` 用 Forui 组件（`router.dart:82-90`）；`routerProvider` 在 `ref.onDispose` 里 `router.dispose()`（`router.dart:92`）。
- **未设置 `navigatorKey`**（`router.dart:17-20`）：要把全屏播放器压在外壳之上，必须新增根 `GlobalKey<NavigatorState>` 并给播放器路由加 `parentNavigatorKey`。
- 断点：`mobileBreakpoint = 600.0`（`shared/widgets.dart:12`）；`< 600` 底部导航（`shell.dart:186-198`）；`< 1024 || settings.compactSidebar` 用 76px 紧凑侧栏；否则 240px（`shell.dart:32-33,84-88`）。内容内边距随宽度 16/24/32（`widgets.dart:24-29`），最大宽 1440（`widgets.dart:46`）。
- 断点已被测试矩阵覆盖 390/599/600/601/1023/1024/1025/1440 + 200% 字号（`test/widget_test.dart:129-171`）。

## 3. 平台工程现状

**macOS**（目标平台，保留）
- 部署目标 12.0：`MACOSX_DEPLOYMENT_TARGET = 12.0`（`project.pbxproj:474,556,606`），`LSMinimumSystemVersion = $(MACOSX_DEPLOYMENT_TARGET)`（`Runner/Info.plist:23-24`）。
- 依赖管理：纯 SPM（见 §0.2）；`macos/Flutter/ephemeral/Packages/FlutterGeneratedPluginSwiftPackage` 为生成物。
- 签名：`CODE_SIGN_STYLE = Automatic`，`CODE_SIGN_IDENTITY = "-"`（ad-hoc），**无 `DEVELOPMENT_TEAM`**（`project.pbxproj:460,488-489,620-621,640-641`）→ 发布必须补团队与公证。
- entitlements：Release 仅 `app-sandbox` + `network.client` + `files.user-selected.read-write`（`Runner/Release.entitlements`）；Debug/Profile 另加 `allow-jit`、`network.server`（`Runner/DebugProfile.entitlements`）。
- 窗口：`window_manager` 在 `runApp` 前初始化（`main.dart:26-27` → `desktop_window.dart:39-58`）：1280×800、最小 480×600、`TitleBarStyle.hidden`、`windowButtonVisibility: false`、标题写死 `'Forui Starter'`（`:44-51`）。自绘标题栏高 48，macOS 画红黄绿三点（`shell.dart:265-293`），全屏时隐藏（`shell.dart:42`）。
- arm64：debug 构建用宿主架构；**release 默认 universal（x86_64+arm64）**，用 `flutter config --enable-macos-arm64-only` 才只出 arm64（`flutter_tools/lib/src/macos/build_macos.dart:243-251`，flag 定义 `lib/src/features.dart:317-328`）。

**Android**（目标平台，保留，需改配置）
- AGP 9.0.1 / Kotlin 2.3.20（`android/settings.gradle.kts:22-23`），Gradle 9.1.0（`android/gradle/wrapper/gradle-wrapper.properties:5`）。
- `compileSdk=36`、`minSdk=24`、`targetSdk=36`、NDK 28.2.13676358（由 `app/build.gradle.kts:9-10,22-23` 取 `flutter.*`；值来自 `flutter_tools/gradle/src/main/kotlin/FlutterExtension.kt:23-42`）；Java/Kotlin 17（`app/build.gradle.kts:12-15,37-41`）。
- 权限只有 `INTERNET`（`AndroidManifest.xml:2`）；`configChanges` 已含 `orientation|screenSize`（`:13`）→ 旋转不重建 Activity，利于播放器。
- **release 仍用 debug 签名**（`app/build.gradle.kts:28-33`）→ 必须换正式签名。
- ABI：release APK 65 MB / debug 179 MB，含 `arm64-v8a`、`armeabi-v7a`、`x86_64`（`unzip -l` 实测，各 ~17-21 MB 原生库）；无 `splits`/`abiFilters` 配置。
- `android/gradle.properties:4-6` 的 `android.newDsl=false`、`android.builtInKotlin=false` 是 Flutter migrator 写的兼容开关 —— **别删**，老式插件 DSL 依赖它（见 §10 探针）。

**可删平台**：`ios/`、`windows/`、`linux/` 整个目录（`lib/` 无平台分支引用；`isDesktop` 判断保留 macOS 即可，`desktop_window.dart:8-9`），同时清理 `.metadata:14-31` 平台条目、`README.md:15,165`、`docs/validation.md` 的 iOS/Windows/Linux 段落。`macos/RunnerTests` 与 `ios/RunnerTests` 可一并删除（无 `test/` 引用）。

## 4. 可直接复用的基础设施

| 能力 | 现状 | 位置 |
| --- | --- | --- |
| 日志 | `initializeLogging()` 幂等初始化；Debug `FINE+`、Release/Profile `WARNING+`；记录 类名+调用点 `file:line`；`LoggingMixin` 自动命名 | `core/logging.dart:15-17,25-31,39,99-116` |
| 日志文件 | `getApplicationSupportDirectory()/logs/app-YYYY-MM-DD.log`，保留 7 天，异步串行写+flush | `logging.dart:56-63`、`logging/file_log_store.dart:7` |
| 实时日志视图 | 内存 1000 条 / ~2 MiB 上限，级别筛选、暂停、搜索、复制 | `logging/live_log_store.dart:32-40`、`features/settings/live_logs_section.dart` |
| 日志导出 | ZIP（archive 4.5.1）+ 桌面保存 / 移动分享 + 运行环境报告 | `logging/log_export_service.dart:16-30`、`log_archive_service.dart:11-12` |
| 设置 | `AppSettings` 不可变 + `copyWith` + JSON；`SharedPreferencesAsync` 键 `forui.settings.v1`；写入串行、失败保留旧值 | `core/settings/settings.dart:12-76,86,110-128` |
| 异常 | `FailureKind{network,timeout,server,storage,invalidData,cancelled}` → 文案映射 | `core/app_exception.dart:1-9`、`shared/widgets.dart:153-163` |
| 网络 | Dio + 10s 三向超时 + 日志拦截器（不打印 URL/头/体）+ `DemoAdapter` + `mapNetworkError` + Provider 释放即取消 | `core/network/api_client.dart:15-37,39-62,69-82,137-155` |
| 主题 | Forui `neutral` 为基，主题色 6 选 1、圆角系数 0–2 统一缩放、MiSans 字体、桌面/触屏密度自动切换 | `app/theme.dart:8-76`、`pubspec.yaml:45-48` |
| 字号 | 系统缩放 × 应用档位（按 DPR 0.57–1.2），自定义 `TextScaler` 不破坏系统曲线 | `app/text_scaler.dart:5-24` |
| 本地化 | ARB(142 键) + `gen-l10n`（`l10n.yaml:1-5`）+ 生成物入库 + `nullable-getter:false` | `lib/l10n/*`、`shared/localization.dart:5-7` |
| 测试 | 93 处 `test/testWidgets`、15 个文件；内存仓储/假窗口/假导出器；宽度与字号矩阵 | `test/fakes.dart:11-70`、`test/widget_test.dart:129-171` |
| 片段同步 | 把 `lib/features/catalog/demos/*.dart` 复制为 `assets/snippets/*.txt`，支持 `--check` | `tool/sync_snippets.dart:5-24` |
| Lint | `flutter_lints 6`，排除各平台目录 | `analysis_options.yaml:10-18` |

## 5. 保留清单（直接搬）

1. `lib/main.dart`（改：应用名/窗口初始化参数/去掉 mock 设置读取顺序不变）。
2. `lib/app/`：`app.dart`、`router.dart`（改路由表）、`shell.dart`、`theme.dart`、`text_scaler.dart`、`branch_transition.dart`。
3. `lib/core/` 全部（`network/api_client.dart` 只保留 `createDio` 骨架与 `mapNetworkError`）。
4. `lib/shared/` 全部（`widgets.dart`、`localization.dart`、`responsive_button.dart`、`language_options.dart`、`calendar_header.dart` 视需求）。
5. `lib/l10n/` 机制（ARB + `l10n.yaml` + `generated/`）。
6. `lib/features/settings/` 的 5 个 Tab 骨架（General/Appearance/Logs/Runtime/About，`settings_page.dart:174-445`）与 `runtime_environment_section.dart`。
7. `macos/`（改 bundle id、应用名、签名、entitlements 增补）、`android/`（改 applicationId/签名/清单）。
8. `test/fakes.dart` 与测试工具函数；`analysis_options.yaml`；`tool/` 目录随 catalog 一起处理。

## 6. 替换清单（要重写）

| 项 | 原因 | 连带改动 |
| --- | --- | --- |
| `features/catalog`（35 demo + `demo_registry.dart` 313 行 + `catalog_page/demo_page`） | 纯组件展厅，与 Jellyfin 无关 | `assets/snippets/`(35 文件/144K)、`pubspec.yaml:43-44` assets 条目、`tool/sync_snippets.dart`、`test/widget_test.dart:105-171`、README:105-106 |
| `features/tasks`（5 文件） | 模板 CRUD 示例 | `overview_page.dart:20` 依赖 `tasksProvider`、`test/state_test.dart`(6 例)、`test/fakes.dart:44-54`、键 `forui.tasks.v1`(`task_repository.dart:18`) |
| `features/network/network_demo.dart` + `networkItemsProvider` + `DemoAdapter` | mock 演示，非真实 API | `test/network_test.dart`(4 例)；`mapNetworkError` 保留 |
| `features/overview/overview_page.dart` | 任务统计卡片 → 改为 Jellyfin 首页（继续观看/最近添加） | 断点与 `PageContent` 复用 |
| 网络基址 | 现在是编译期常量 `USE_MOCK_API`/`API_BASE_URL`（`api_client.dart:12-13`）；Jellyfin 需运行时填服务器地址 | 新增服务器配置状态 + 动态 `Dio` 重建 + token 拦截器（当前拦截器只记方法名，`api_client.dart:39-62`） |
| 设置项 | `language` 白名单硬编码 `['zh','en']`（`settings.dart:57`） | 增语言需同步改白名单 + ARB + `languageOptions` |
| 应用标识 | `forui_app`/`com.foliage.foruiApp`/`com.foliage.forui_app`、窗口标题 `'Forui Starter'`、ARB `appTitle` | `pubspec.yaml:1`、`macos/Runner/Configs/AppInfo.xcconfig`、`android/app/build.gradle.kts:8,19`、`desktop_window.dart:48`、`app_en.arb:3` |
| 文档 | README 与 `docs/validation.md` 含过期事实（见 §9） | 重写 |

## 7. 删除清单

- 平台：`ios/`、`windows/`、`linux/`、`macos/RunnerTests/`（见 §3）。
- 示例资产：`assets/snippets/`（35 个 `.txt`）；`assets/MiSans-Regular.ttf` 7.7 MB 若换字体则删（`pubspec.yaml:45-48`、`theme.dart:23`）。
- 代码：`features/catalog/`、`features/tasks/`、`features/network/`、`shared/calendar_header.dart`（若日历不用）、`tool/sync_snippets.dart`。
- 测试：`test/state_test.dart`、`test/network_test.dart`、`test/widget_test.dart` 中 demo/任务相关用例；`test/zz_scratch_test.dart`（未跟踪的临时文件，`git status` 可见）。
- 注意顺序：**删 demo 必须同时删 `assets/snippets` 与 `tool/sync_snippets.dart`，并去掉 `pubspec.yaml:43-44`**，否则 README 的 `--check` 流程会红；`demo_registry.dart:64` 是唯一运行时读取 snippets 的地方。

## 8. 接入播放器需改动文件

| 文件 | 改动 | 依据 |
| --- | --- | --- |
| `lib/app/router.dart` | 加根 `navigatorKey`；新增 `GoRoute('/play/:id')` 用 `parentNavigatorKey` 压在外壳之上（全屏）；或新增第 5 个分支做"库内播放" | 现无 `navigatorKey`（`:17-20`），外壳会包住所有分支（`:21-80`） |
| `lib/app/shell.dart` | 全屏播放页不要 `FScaffold` header/footer、不要自绘标题栏与 `SafeArea(top: !window.available)` | `:38-39,42-77,157-200` |
| `lib/core/window/desktop_window.dart` | 抽象类只有读 `fullScreen`，**无进入/退出全屏方法** → 加 `setFullScreen(bool)` 并实现（`window_manager 0.5.2` 已有 `setFullScreen`） | 接口 `:11-22`、`fullScreen` `:42`、provider `:102-106` |
| `test/fakes.dart` | `FakeWindow` 实现该接口，加方法即编译失败，需同步 | `:56-70` |
| `lib/app/app.dart` | 播放器 UI 若要忽略应用字号档位，在播放页内包一层 `MediaQuery` 覆盖 `textScaler` | 全局注入 `:30-39` |
| `lib/app/text_scaler.dart` | 注意 DPR 分档使字号在 0.57–1.2 间跳变；字幕/控制条不要依赖它 | `:5-13` |
| Android 代码 | 新增 `SystemChrome.setPreferredOrientations`（横屏锁定）与 `setEnabledSystemUIMode(immersive)`，退出时恢复；清单已允许旋转不重建（`AndroidManifest.xml:13`） | 全库无 `SystemChrome` 调用 |
| `android/app/src/main/AndroidManifest.xml` | 若需后台播放：前台服务 + `WAKE_LOCK`（模板零后台能力）；如需 http 服务器：`android:usesCleartextTraffic="true"` 或 network-security-config | 仅 `INTERNET`（`:2`） |
| `macos/Runner/Info.plist` | 局域网 http 需 `NSAppTransportSecurity` 例外（`NSAllowsLocalNetworking`） | 现无 ATS 段（`:4-31`） |
| `lib/core/network/api_client.dart` | 播放需带 `Authorization`/token 与流地址；现为编译期 baseUrl + 仅记方法名拦截器 | `:12-13,39-62` |
| `pubspec.yaml` | 新增播放依赖（见 §10） | — |

## 9. 版本与工具链约束

- 工具链：`.fvmrc:2` = 3.47.6；系统 `flutter` 是 3.47.8/Dart 3.13.7（`flutter --version`）；`docs/validation.md:7` 记录验证用 Dart 3.13.5。`pubspec.yaml:6-8` 要求 `sdk >=3.13.0 <4.0.0`、`flutter >=3.47.0`。**建议统一到 3.47.6**（否则 `pubspec.lock` 与生成物会漂）。
- 钉死依赖：`forui: 0.27.5`（最新 0.27.6）、`forui_lucide: 0.27.0`、`flutter_riverpod: 3.4.3`（均为精确版本，`pubspec.yaml:15-18`）；`material_ui ^1.6.0` 实际锁 1.6.0（最新 1.8.0）、`go_router ^18.0.2` 锁 18.0.2（最新 18.1.1）。升级需一次只动一个并跑 93 个测试。
- 平台下限：macOS 12.0（`project.pbxproj:474`）、iOS 15.0（`ios/Runner.xcodeproj/project.pbxproj:363`，删 iOS 后无关）。
- Android：AGP 9.0.1 / Gradle 9.1.0 / Kotlin 2.3.20 / compileSdk 36 / minSdk 24 / targetSdk 36 / NDK 28.2.13676358。README:92 写的"AGP 8.12.1+ 与 Gradle 8.13+"是**旧事实**（`docs/validation.md:20` 还写着 Gradle 8.14/AGP 8.11.1），当前配置已满足且更高，需更正文档。
- `android.newDsl=false` 让 AGP 9 仍接受老式 Groovy DSL（`compileSdkVersion 36`、`minSdkVersion 16`、`$buildDir`）；**探针实测**：AGP 9.0.1 + Gradle 9.1.0 + `newDsl=false` 配置通过（`/tmp/agp9probe`）。
- 现有原生插件都自带 `Package.swift`（实测：share_plus 13.3.1、package_info_plus 10.2.2、window_manager 0.5.2、file_selector_macos 0.9.5+2、file_selector_ios 0.5.3+7），所以无 Podfile 也能构建。判断“加插件会不会引入 Podfile”的最快方法：解包该插件看有没有 `Package.swift`。

## 10. media_kit 评估（含实测证据）

- 版本：`media_kit 1.2.6`、`media_kit_video 2.0.1`、`media_kit_libs_video 1.0.7`（→ macos 1.1.4 / android 1.3.8 / ios 1.1.4）。
- **SPM 不兼容（确定性结论）**：三个原生包只有 podspec；`raw.githubusercontent.com/media-kit/media-kit/main/.../Package.swift` = 404。接入后 Flutter 生成 Podfile 并走 CocoaPods 混合模式（`darwin_dependency_management.dart:88-101`），同时告警（`:289-294`）。
- macOS 构建期外部依赖：podspec `system("make")` → `Makefile` 用 `curl` 下载 `libmpv-xcframeworks v0.6.0` 并 `shasum -a 256 -c` 校验；离线环境/受限 CI 会失败。
- Android 构建期外部依赖：`media_kit_libs_android_video-1.3.8/android/build.gradle:50-99` 在配置期下载 4 个 ABI 的 jar（含 x86），且用 `task downloadDependencies(type: Exec)`（无 commandLine）+ `assemble.dependsOn`。**探针实测**：空 `Exec` 任务在 Gradle 8.14 与 9.1.0 上执行都会报 `command 'null'` 失败 —— 是否真的触发取决于构建图，必须在目标工程实测一次 `flutter build apk`。
- 体积：每个 ABI 多一份 libmpv（Android jar 各 ~20 MB 级），与当前 3 ABI 的 65 MB release APK 叠加；建议同时上 `--split-per-abi` 或 AAB。
- 替代方案：`video_player 2.14.1`（`video_player_avfoundation 2.12.3` 自带 `darwin/video_player_avfoundation/Package.swift` → 保持纯 SPM、无 Podfile、体积小），代价是 AVPlayer/ExoPlayer 的容器与音频编码覆盖远不如 libmpv（Jellyfin 直连 MKV/AC3/DTS 会走转码）。**建议在计划里把"是否接受转码"作为显式决策点**。
- 无论选哪个，都要先解决 §0.6 的明文 HTTP 与 §8 的全屏/方向/后台三件事。

## 11. 不确定项（需实测/决策）

1. media_kit 在 AGP 9.0.1 + Gradle 9.1.0 下能否完整 `assemble`（只验证了配置阶段；`Exec` 探针仅证明该写法有风险）。
2. macOS arm64 构建、签名、公证均未在本机验证（Linux 主机）；`flutter config --enable-macos-arm64-only` 的产物与 libmpv xcframework 架构兼容性需在 Mac 上确认。
3. forui 0.27.6 / material_ui 1.8.0 / go_router 18.1.1 的升级影响未验证（当前锁 0.27.5 / 1.6.0 / 18.0.2）。
4. Jellyfin 端侧播放协议选择（直连 vs HLS 转码）、后台音频方案（模板无任何后台能力）属于产品决策，不在本次模板审计范围内。
