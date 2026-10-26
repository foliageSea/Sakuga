# Sakuga 开发计划

> 版本：v0.3（决策稿） · 日期：2026-10-26 · 状态：**M0 进行中**（进度见 [m0-status.md](m0-status.md)）
> 目标平台：macOS（Apple Silicon / arm64）+ Android（arm64-v8a）为正式目标；**Linux 作为本地开发/验证平台**（不做正式发布）。
> 工程底座：`/home/foliage/projects/forui_app`（Flutter 3.47.6 + Forui 0.27.5 + Riverpod 3.4.3）
> 超分参考：Predidit/Kazumi（GPL-3.0，仅作行为参考，不复制其 Dart 代码）
> 配套调研：`docs/research/template-audit.md`、`kazumi-player.md`、`jellyfin-api.md`、`playback-engine.md`

---

## 0. TL;DR

| 项目 | 结论 |
| --- | --- |
| 产品 | **Sakuga**：面向自建 Jellyfin 服务器的第三方客户端，强调“打开即播、操作不打断、画质可感知”。 |
| 技术栈 | Flutter 3.47.6（FVM）+ Forui 0.27.5 + Riverpod 3.4.3 + go_router + Dio + media_kit（libmpv）。 |
| 播放内核 | **Predidit/media-kit fork（pin `83b7ca6`）**，只依赖 `media_kit` + `media_kit_video`，用 native assets 分发。原因：上游 Android libmpv 是 mpv 0.36 且关闭 Vulkan/libplacebo（没有 `gpu-next`），且上游 `media_kit_libs_android_video 1.3.8` 有构建期下载 406 的 open issue（#1469）。 |
| 超分 | 客户端 **Anime4K GLSL**（MIT）：关 / 自动 / 效率（M）/ 质量（VL）；通过 mpv `change-list glsl-shaders` 动态切换。macOS 走 `vo=libmpv`（底层 vo_gpu，无 gpu-next）；Android 14+ 且 Vulkan 1.2 可用 `gpu-next`。 |
| 后端 | Jellyfin REST API。**目标兼容 10.8–10.10（测试服 10.10.7）**；12.x 作为可选适配。统一用 `Authorization: MediaBrowser Token="…"` 请求头（10.x 可回退 `X-Emby-Token`），并按版本做 `/UserViews` 等端点降级。 |
| 工程集成 | 模板 macOS 是纯 SPM；上游 media_kit 只有 podspec，但 **fork 的 media_kit_video 提供 Package.swift**，优先保持纯 SPM（失败再回退 CocoaPods）。native assets 要求 **macOS 13**，构建期需联网下载 libmpv；Android 需实测 AGP 9.0.1/Gradle 9.1 + native assets。 |
| 体验重点 | 手势、交互式 seek + Trickplay 预览、片头片尾跳过、无缝连播、字幕/音轨快捷面板、PiP/后台、键盘与触控板、错误自愈。 |
| 排期 | 单人 10.5 周开发 + 2 周缓冲（约 12.5 周）；双人并行约 7–8 周。 |
| 最大风险 | ① Kazumi 是 GPL-3.0，不能复制其代码；② Android GLES 多 pass 偏色（#1438）与性能机型差异；③ macOS SPM/native assets + libmpv 下载/签名；④ Impeller 与视频浮层（Kazumi 两平台都关 Impeller）；⑤ media_kit fork 与 Flutter 3.47.8/AGP 9 的兼容性未实测；⑥ Jellyfin 10.8–10.10 端点差异与转码细节。 |

**已确认决策（2026-10-26）**：

| # | 决策 |
| --- | --- |
| 1 | 应用名 **Sakuga**，包名/Bundle ID **`com.foliage.sakuga`**。 |
| 2 | **不复制 Kazumi 代码，独立实现**；仅使用 Anime4K 官方 MIT shader 与公开文档。 |
| 3 | **暂不发布**：先做可运行的本地/内测包，商店上架与公证后续再开。 |
| 4 | Jellyfin **兼容 10.8–10.10**（测试服 10.10.7）；12.x 可选适配。 |
| 5 | macOS 最低 **13.0**（接受）。 |
| 6 | **关闭 Impeller**（Skia 基线，接受）；M0 再验证是否可开启。 |
| 7 | **离线下载不进 v1**（后续再评估）。 |
| 8 | UI 规范：**界面不写注释性/说明性文本**，只保留功能所需文案（按钮、状态、错误、必要帮助入口）。 |

---

## 1. 背景、目标与范围

### 1.1 产品定位

Sakuga 是一个 **Jellyfin 第三方客户端**，不是媒体服务器，也不做服务端转码。它解决三件事：

1. **连接自己的媒体库**：局域网/公网 Jellyfin，多服务器、多用户、Quick Connect。
2. **把视频稳定、好看地播出来**：直连优先、必要时转码、字幕/音轨完整、支持 Anime4K 超分。
3. **让“播放中的操作”顺手**：单手可完成暂停、快进、调音量/亮度、切字幕、跳片头、下一集。

**与现有 Jellyfin 客户端的差异**：

- **画质**：内置 Anime4K 超分（自动/效率/质量），并做掉帧/热/颜色守卫，而不是只做“能播”。
- **播放操作**：双击左右 seek、交互式 seek + Trickplay 预览、片头片尾跳过、无缝连播、panel hold、触觉反馈。
- **双端原生感**：macOS 菜单栏/媒体键/全屏 Space/迷你窗；Android PiP/后台音频/通知控制/手势导航避让。
- **可诊断**：播放信息页（PlayMethod/转码原因/vo/hwdec/掉帧/FD/颜色）与一键日志导出，问题可定位。

### 1.2 目标用户与核心场景

| 场景 | 用户动作 | 体验目标 |
| --- | --- | --- |
| 沙发上用 Mac 看剧 | 打开 App → 继续观看 → 播放 | 2 次点击内起播；全屏/窗口切换不打断；键盘可完成全部操作。 |
| 通勤/床上用 Android 看番 | 单手拿手机 → 播放 → 拖进度 → 切字幕 | 拇指可达；横滑 seek 有预览；误触少；超分可一键开关。 |
| 局域网 4K/HDR 片源 | 直接播放，不转码 | 直连成功率 ≥ 95%；HDR 正确 tone map 到 SDR；不卡顿。 |
| 公网/弱网 | 自动降码率/转码 | 不黑屏、不无限缓冲；可手动锁码率；错误可恢复。 |
| 追番连播 | 片尾自动下一集 | 片头/片尾跳过；下一集预加载；间隙 < 1s。 |

### 1.3 本期范围（P0，v1.0）

- 服务器：手动地址、局域网发现（UDP 7359）、HTTPS/自签名提示、用户名密码登录、Quick Connect、多服务器切换、token 安全存储。
- 浏览：首页（继续观看/最近添加/收藏）、媒体库网格、剧集/季/集、详情页（简介/演职员/相似）、搜索、排序筛选。
- 播放：PlaybackInfo 协商、直连/直连流/转码、HLS、进度上报与续播、音轨/字幕切换、ASS/PGS 字幕、倍速、画面比例、全屏/横屏、PiP、后台音频、媒体通知、错误恢复。
- 超分：关/自动/效率/质量四档、运行时切换、按设备默认、性能守卫与自动降级、Anime4K 许可声明。
- 播放体验：手势系统、交互式 seek、Trickplay 缩略图、章节、片头/片尾跳过、下一集倒计时、控制层自动隐藏、HUD、触觉反馈、键盘/触控板。
- 设置：播放（超分/硬解/渲染器/手势/字幕/码率）、外观、服务器/账户、日志与诊断、关于。
- 质量：单元/Widget/集成测试，Mac arm64 与 Android 真机矩阵，崩溃与日志。

### 1.4 非目标（本期不做）

- iOS、Windows、Web、Android TV / tvOS；**Linux 仅作为本地开发/验证平台，不做正式发布**。
- Jellyfin 服务端、转码器、媒体整理。
- 音乐/照片/直播电视/DVR（后续可评估）。
- DRM（Jellyfin 本身不提供 DRM 内容）。
- 弹幕（Kazumi 的核心能力，但 Jellyfin 场景非必需；可作为 P2）。
- 自建账号体系/云同步。
- **真 HDR/EDR 输出**：本期按 HDR→SDR tone map 实现，不承诺 HDR 直通（media_kit 相关 issue 长期 open）。

### 1.5 成功指标（v1.0 验收）

| 指标 | 目标 | 测量方式 |
| --- | --- | --- |
| 冷启动到可交互 | P50 ≤ 1.2s，P90 ≤ 2.5s | 启动埋点（本地日志） |
| 点击播放到首帧 | 局域网直连 P50 ≤ 1.5s，P90 ≤ 3s | 播放器事件时间戳 |
| Seek 响应（松手到画面） | P50 ≤ 300ms，P90 ≤ 800ms | 自动化 + 真机 |
| 手势误触率 | < 2%（用户可关闭边缘手势） | 内测反馈 + 事件统计 |
| 控制层响应 | 点击到视觉反馈 ≤ 100ms | 帧时间 |
| 超分帧率 | Mac M1 效率档 1080p→1440p ≥ 60fps、4K 输出 ≥ 30fps（spike 校准）；Android 旗舰效率档 1080p→1440p ≥ 45fps | 真机 spike |
| 超分颜色 | 开启/关闭色差 ΔE < 3（重点 Android GLES） | 测试图 + 截帧 |
| 崩溃自由会话 | ≥ 99.5% | 崩溃日志 |
| 直连成功率 | ≥ 95%（局域网，H.264/HEVC 常见组合） | PlaybackInfo 统计 |
| 包体 | Android arm64 AAB ≤ 70MB；macOS DMG ≤ 90MB | 构建产物 |

---

## 2. 调研结论

### 2.1 模板底座：forui_app 能直接用吗？

结论：**可以直接作为工程底座，但需要“删示例、换业务、补播放器基础设施、验证 macOS SPM/native assets”**。模板的价值在工程规范（日志、设置、路由、响应式外壳、本地化、测试），不在业务代码。

| 模块 | 现状 | 处置 |
| --- | --- | --- |
| `lib/app/` | 应用根、主题、路由、响应式 Shell、桌面标题栏 | **保留并改造**：路由换成 Sakuga 的 5 个分区；桌面标题栏保留；新增播放器全屏路由（需根 `navigatorKey`）。 |
| `lib/core/logging/` | 分级日志、按日文件、7 天保留、ZIP 导出、实时日志视图 | **原样保留**，播放器诊断直接复用。 |
| `lib/core/settings/` | SharedPreferences + JSON、写入队列、失败回滚 | **保留并扩展**：新增播放器设置、服务器列表；token 改走 Keychain/Keystore。 |
| `lib/core/network/` | Dio + 超时 + 取消 + Mock | **保留骨架，替换为 Jellyfin API Client**；拦截器改为 MediaBrowser 认证。 |
| `lib/core/window/` | window_manager 封装、macOS 自绘红黄绿 | **保留**；接口目前只有读 `fullScreen`，需补 `setFullScreen(bool)`，并同步 `test/fakes.dart`。 |
| `lib/shared/` | 本地化访问、响应式按钮、通用 widgets | **保留**，补充媒体卡片、骨架屏、空态。 |
| `lib/features/catalog/` + `assets/snippets/` + `tool/sync_snippets.dart` | 35 个组件 Demo | **删除**（连同 pubspec 的 assets/snippets 与 README 说明）。 |
| `lib/features/tasks/`、`features/network/` | 示例 CRUD/网络 | **删除**，替换为首页/媒体库/详情/搜索。 |
| `lib/features/overview/` | 任务统计卡片 | **重写**为 Jellyfin 首页（继续观看/最近添加）。 |
| `lib/l10n/` | 中英 ARB + 生成 | **保留并扩展**：播放器文案、错误码、无障碍标签。 |
| `test/` | 状态/网络/组件/布局测试 | **保留测试风格**，删除示例测试，补播放器与 API 测试。 |
| macOS 工程 | deployment target 12.0；App Sandbox；自绘标题栏；**纯 SPM、无 Podfile** | **改造**：最低 13.0（native assets 要求）；优先保持纯 SPM（fork 有 Package.swift），失败再回退 CocoaPods；补 ATS；签名/公证。 |
| Android 工程 | AGP 9.0.1 / Gradle 9.1.0 / Kotlin 2.3.20 / compileSdk 36 / minSdk 24 / targetSdk 36 | **改造**：applicationId、minSdk 26、签名、ABI、cleartext、PiP、前台服务、通知权限、extractNativeLibs。 |
| iOS/Windows/Web | 模板自带 | 本期**删除**（减少 CI 与维护面）。 |
| Linux | 模板自带 | **保留为本地开发/验证 runner**；不作为发布目标。 |

#### 2.1.1 模板的 12 个“必须处理”集成点

1. **纯 SPM 的兼容性**：`macos/` 无 Podfile，Xcode 用 `XCLocalSwiftPackageReference`。上游 media_kit 三个原生包只有 podspec（GitHub 无 `Package.swift`，404），会强制回退 CocoaPods；但 **fork 的 `media_kit_video` 提供 `macos/.../Package.swift`（macOS 10.15+）**，理论上可保持纯 SPM。M0 必须验证 Flutter 3.47.8 + native assets + SwiftPM 的组合；失败再接受 CocoaPods（fork 也保留 podspec）。
2. **native assets 构建期下载**：fork 的 `hook/native_bundles.json` 在构建时下载 libmpv（Android jar / macOS xcframework）并按 sha256 校验。CI/新机器必须联网、有 C 编译器，并缓存 `native-cache`；离线构建需预热缓存。
3. **macOS 最低系统 13.0**：Flutter 3.47.8 native assets 的 macOS 生成器写死 `targetMacOSVersion = 13`，工程当前是 12.0，会出现“built for newer macOS”告警/链接失败。需同步改 `MACOSX_DEPLOYMENT_TARGET` 与文档。
4. **release 默认 universal**：只出 arm64 要 `flutter config --enable-macos-arm64-only`（或构建参数），否则 DMG 体积与测试面翻倍。
5. **Material 必须来自 `package:material_ui`**：Forui 0.27.5 依赖 `material_ui`，模板全库 0 处 `package:flutter/material.dart`；混用会得到两套 Theme/MaterialApp。
6. **无根 `navigatorKey`**：全屏播放器要压在外壳之上，必须在 `router.dart` 加 `GlobalKey<NavigatorState>`，播放器路由加 `parentNavigatorKey`。
7. **无方向/沉浸式控制**：全库无 `SystemChrome` 调用；播放器需自行设置横屏、隐藏状态栏/导航栏、退出恢复。
8. **无后台能力**：Android 清单只有 INTERNET；需补前台服务、WAKE_LOCK、POST_NOTIFICATIONS、PiP、extractNativeLibs。
9. **局域网 http 默认不通**：Android targetSdk 36 无 `usesCleartextTraffic`；macOS Info.plist 无 ATS。Jellyfin 常见 `http://192.168.x.x:8096` 会失败。
10. **release 仍用 debug 签名**：Android 必须换正式 keystore；macOS 无 `DEVELOPMENT_TEAM`，需补。
11. **媒体库 token 不能放 SharedPreferences**：用 `flutter_secure_storage`（Keychain/Keystore）。
12. **示例删除顺序**：删 catalog 必须同时删 `assets/snippets/`、`tool/sync_snippets.dart`、pubspec assets 条目与相关测试，否则 README 的 `--check` 流程会红。

### 2.2 Kazumi 的超分与播放器：能借鉴什么，不能拿什么

Kazumi v2.4.2 的播放器实现是本项目最有价值的参考，但 **Kazumi 整体是 GPL-3.0**。因此：

- ✅ 可以借鉴：交互模型、状态机、mpv 属性名、Anime4K 官方 shader 文件（MIT）、公开的 mpv/Jellyfin 文档。
- ❌ 不可以：复制 Kazumi 的 Dart 源码、逐行翻译、把其文件搬进闭源仓库。
- ✅ 如果 Sakuga 也选择 GPL-3.0 开源，则可以直接复用并保留版权声明；这需要产品决策（见第 9 节）。

#### 2.2.1 超分调用链（行为参考）

1. 启动时把 `assets/shaders/*.glsl` 复制到可写目录（`getApplicationSupportDirectory()/anime4k/<version>/`），因为 mpv 的 `glsl-shaders` 只接受文件系统绝对路径。
2. 创建 `Player` 与 `VideoController` 时指定 `vo` 与 `hwdec`：
   - Android：`vo=gpu`（GLES，稳健）或 `gpu-next`（Vulkan，Android 14+ / Vulkan 1.2）；`hwdec=auto-safe`。
   - macOS：`vo=libmpv`（底层 vo_gpu/OpenGL）；`hwdec=auto`（VideoToolbox）。
   - `mediacodec_embed` 与超分互斥，选择时强制关闭并解释。
3. 播放器/视频控制器初始化完成后，通过 `NativePlayer.command(['change-list','glsl-shaders','set', '<绝对路径1>:<绝对路径2>:...'])` 应用 shader 链；关闭时 `change-list glsl-shaders clr ''`。
4. shader 链（Anime4K 官方组合，含 `//!WHEN` 自动 1x/2x/4x 选择）：
   - 效率档：`Clamp_Highlights → Restore_CNN_M → Restore_CNN_S → Upscale_CNN_x2_M → AutoDownscalePre_x2 → AutoDownscalePre_x4 → Upscale_CNN_x2_S`
   - 质量档：`Clamp_Highlights → Restore_CNN_VL → Upscale_CNN_x2_VL → AutoDownscalePre_x2 → AutoDownscalePre_x4 → Upscale_CNN_x2_M`
5. 运行时切换：直接 set/clr，无需重开视频；失败时回滚并提示（Kazumi 只打 warn，本项目要补 UI）。

#### 2.2.2 平台/渲染器限制（必须写进产品逻辑）

- Android 的 `mediacodec_embed` 是低功耗路径，但直出 Surface，**字幕、OSD、视频滤镜、shader 全部不可用**；启用超分必须切到 `gpu`/`gpu-next`。
- `gpu-next` 依赖 Vulkan 1.2；低端机/Android 13 及以下可能黑屏，需要“自动”策略（≥ Android 14 才默认 gpu-next，否则 gpu）与一键回退。
- 硬解 + shader 同时开启在部分机型会花屏/掉帧；需要“硬解关闭”降级路径与性能提示。
- 超分只对“放大”有意义；源分辨率 ≥ 显示分辨率时应自动关闭或只保留 Restore（去压缩伪影）。
- HDR 内容 + Anime4K 的兼容性需要 spike；默认 HDR 关闭超分，SDR 动画内容默认开启。
- 超分是 GPU 密集操作，必须做掉帧/热状态监控与自动降级。
- **Impeller**：Kazumi 在 macOS 与 Android 都显式关闭 Impeller，原因是 BackdropFilter/ImageFilter.blur 叠在视频层上会触发 Impeller native abort（flutter#185506）。本项目必须做 spike 决定是否关闭 Impeller，或播放器 HUD 禁用 blur/saveLayer。

#### 2.2.3 播放交互（可借鉴的清单）

Kazumi 的播放器把交互拆得很细，值得作为“需求清单”而不是代码来源：

- 单击：移动端切换控制层；桌面端切换控制层/播放（按指针类型区分）。
- 双击：移动端播放/暂停；桌面端全屏。
- 长按：临时 2x/3x 倍速，松手恢复。
- 横滑：交互式 seek；靠近屏幕边缘时取消，避免与系统返回手势冲突。
- 竖滑：左半屏亮度、右半屏音量；HUD 显示；松手后延迟隐藏。
- 面板：自动隐藏（可配置 1–10s）；按住面板不隐藏（**租约/引用计数**，不是布尔标志）；菜单打开时阻止隐藏。
- 菜单：音轨、字幕、倍速、画面比例、超分、视频信息、截图、SyncPlay。
- 桌面：滚轮调音量、键盘快捷键、全屏、PiP。
- 播放完成：自动下一集；接近结尾的续播从头重播而不是误跳下一集。
- **Kazumi 没有但 Jellyfin 需要**：双击左右快进/快退、捏合缩放、字幕轨道/样式、音轨选择、章节、旋转锁定、A-B 循环、播放队列。

### 2.3 Jellyfin 接入：以 10.8–10.10 为基线

用户已确认兼容目标为 **10.8–10.10**；当前测试服为 **10.10.7**（`http://110.42.96.64:44762`，凭据只放本地环境变量/CI secret，不写入仓库）。12.x 作为**可选适配**，不阻塞 v1。

实测（10.10.7，2026-10-26）：

- `Authorization: MediaBrowser Token="…", Client="Sakuga", Device="…", DeviceId="…", Version="…"` 可用；`X-Emby-Token` 也可用。
- `/UserViews?userId=` 返回媒体库（测试服为“番剧”）；`/Items` 可取 51 个条目（mp4/h264/aac、mkv/h264/aac、mkv/hevc/aac，含 ASS/SRT 多字幕）。
- `PlaybackInfo` 对 mkv/h264/aac 返回 `SupportsDirectPlay=true`、无 `TranscodingUrl`，说明 DeviceProfile 直连路径可行。
- `MediaStream.DeliveryUrl` 在 10.10 自带 `api_key` 查询参数；客户端应剥离 token、改用请求头，避免日志/反代泄露。
- 该测试服 **未生成 Trickplay/MediaSegments**（`Trickplay={}`、`MediaSegments` 为空）；相关功能需服务器生成后再验收，未生成时走降级。

#### 2.3.1 认证

- 登录：`POST /Users/AuthenticateByName`，body `{"Username":"alice","Pw":"secret"}`；响应 `AuthenticationResult{User{Id,Name,ServerId},AccessToken,ServerId}`（**没有顶层 UserId**）。
- 请求头（10.8–10.10 与 12.x 均可）：
  ```
  Authorization: MediaBrowser Client="Sakuga", Device="<device>", DeviceId="<hash>", Version="<version>", Token="<token>"
  ```
  10.x 另可回退 `X-Emby-Token: <token>`（兼容老服务端/代理）；不要使用 `api_key` 查询参数。
- **12.x 差异（可选适配）**：12.0 移除了查询 `api_key`、`X-Emby-Token`、`X-Emby-Authorization`、`/emby/` 前缀、`/PlayingItems/*`、`GET /QuickConnect/Initiate`；只保留 `Authorization: MediaBrowser`。因此**统一用 Authorization 头**可以同时覆盖 10.8–10.10 与 12.x。
- **无 refresh token**：401 只能重新登录；不要设计静默刷新。
- **deviceId 必须按用户唯一**：服务端一个 deviceId 只允许一个 token；多用户同机用 `hash(设备ID + 用户名)`。
- Quick Connect：`POST /QuickConnect/Initiate` → 轮询 `GET /QuickConnect/Connect?secret=` → `POST /Users/AuthenticateWithQuickConnect`。

#### 2.3.2 浏览端点（10.9 发生迁移）

| 能力 | 10.9/10.10 端点 | 10.8 降级 | 12.x 备注 |
| --- | --- | --- | --- |
| 视图 | `GET /UserViews?userId=` | `GET /Users/{userId}/Views` | 同 10.9+ |
| 列表/搜索 | `GET /Items?userId=&parentId=&recursive=&includeItemTypes=&filters=&sortBy=&fields=` | 同 | 同 |
| 详情 | `GET /Items/{itemId}?userId=&fields=` | 同 | 同 |
| 剧集 | `GET /Shows/{seriesId}/Episodes?userId=&seasonId=` | 同 | 同 |
| 已看/收藏 | `POST/DELETE /UserPlayedItems/{itemId}?userId=`、`/UserFavoriteItems/{itemId}` | `/Users/{userId}/PlayedItems/{itemId}` 等 | 同 10.9+ |
| 用户数据 | `GET /UserItems/{itemId}/UserData?userId=` | 同 | 同 |
| 图片 | `GET /Items/{itemId}/Images/{type}/{index}?maxWidth=&tag=` | 同 | 同 |

- 图片必须带 `tag=<ImageTags[type]>`，否则缓存无法失效。
- 用 `GET /System/Info/Public` 的 `Version` 判主版本，<10.9 走旧路由；12.x 走同一套新路由。

#### 2.3.3 播放协商（最关键）

- 一次 `POST /Items/{itemId}/PlaybackInfo`，body 带 `DeviceProfile`（mpv 全能力）、`MaxStreamingBitrate`、`StartTimeTicks`、`AudioStreamIndex`、`SubtitleStreamIndex`。
- 响应 `MediaSources[]`、`PlaySessionId`、`ErrorCode`。
- 直连：`GET /Videos/{itemId}/stream?static=true&mediaSourceId=&playSessionId=`。
- 转码/重封装：**原样使用服务器返回的 `TranscodingUrl`**；不要自己拼 `master.m3u8`（10.10 有 HLS 控制器，12.x 已从规范隐藏，原样使用最稳）。
- 外挂字幕：优先用 `MediaStream.DeliveryUrl`（服务器拼好的地址），但**剥离 `api_key` 查询参数**，改用请求头；或 `/Videos/{id}/{msId}/Subtitles/{index}/Stream.{format}`。
- 转码停止必须 `DELETE /Videos/ActiveEncodings?deviceId=&playSessionId=`，否则 ffmpeg 进程残留。
- `DeviceProfile` 建议（可直接落地，按实测裁剪）：

```json
{
  "Name": "Sakuga-mpv", "MaxStreamingBitrate": 120000000, "MaxStaticBitrate": 120000000,
  "DirectPlayProfiles": [
    { "Container": "mkv,webm,mp4,m4v,mov,ts,m2ts,avi,flv,3gp", "Type": "Video",
      "VideoCodec": "h264,hevc,av1,vp9,vp8,mpeg2video,mpeg4,vc1,msmpeg4",
      "AudioCodec": "aac,ac3,eac3,dts,flac,opus,vorbis,mp3,alac,pcm" },
    { "Container": "mp3,aac,flac,opus,ogg,wav,m4a", "Type": "Audio" }
  ],
  "TranscodingProfiles": [
    { "Container": "ts", "Type": "Video", "VideoCodec": "h264", "AudioCodec": "aac,ac3,eac3",
      "Protocol": "hls", "Context": "Streaming", "MinSegments": 1, "BreakOnNonKeyFrames": true }
  ],
  "CodecProfiles": [ { "Type": "VideoAudio", "Conditions": [
      { "Condition": "LessThanEqual", "Property": "AudioChannels", "Value": "8", "IsRequired": false } ] } ],
  "SubtitleProfiles": [
    { "Format": "srt", "Method": "External" }, { "Format": "ass", "Method": "External" },
    { "Format": "ssa", "Method": "External" }, { "Format": "vtt", "Method": "External" },
    { "Format": "pgssub", "Method": "External" }, { "Format": "dvdsub", "Method": "External" } ]
}
```

  注意：Android 侧 libmpv 构建**不含 TrueHD/MLP 解码器**，所以 TrueHD 应标记为需转码（或把 `truehd` 从 DirectPlay 音频白名单移除）；PGS 外部字幕在 mpv 的兼容性需 spike。

#### 2.3.4 进度与增强播放

- 进度：`POST /Sessions/Playing`、`/Sessions/Playing/Progress`、`/Sessions/Playing/Stopped`；10s 一次（jellyfin-web 约定），暂停/seek/退出立即补报；返回 204，fire-and-forget。
- 能力：`POST /Sessions/Capabilities/Full`（登录后一次，Dashboard 才显示可远程控制）。
- Trickplay：`fields=Trickplay` 取 `BaseItemDto.Trickplay` 的宽度/瓦片信息；图片 `GET /Videos/{itemId}/Trickplay/{width}/{index}.jpg`（10.9+；测试服未生成）。
- 片头片尾：`GET /MediaSegments/{itemId}?includeSegmentTypes=Intro,Outro`（10.10+；测试服未生成）。
- 章节：`fields=Chapters`。
- SyncPlay：`/SyncPlay/*` + WebSocket（P1）。
- 远程控制：`GET /Sessions`、`POST /Sessions/{id}/Playing`（P2）。
- 下载：`GET /Items/{itemId}/Download`（**v1 不做**，后续再评估）。

#### 2.3.5 Dart SDK 选择

| 选项 | 结论 |
| --- | --- |
| `dart_jellyfin` 0.3.1（2026-10-11，BSD-3，对齐 12.2） | 覆盖 PlaybackInfo/DeviceProfile/Trickplay/MediaSegments/SyncPlay/WebSocket，但对 10.10 未验证；**只作参考/fork 基线**。 |
| `jellyfin_dart` 0.1.2（停更 10.11） | 不建议。 |
| 自建 thin client | 最可控；核心 ~20 个模型手写/生成。**默认方案**，SDK 作为参考。 |

#### 2.3.6 12.x 可选适配

- 认证统一用 `Authorization: MediaBrowser`，无需分支。
- 端点使用 10.9+ 新路由，12.x 兼容。
- 12.x 不再支持 `api_key` 查询参数，字幕/图片 URL 必须走请求头；`TranscodingUrl` 仍原样使用。
- 12.x 的 HLS 控制器从规范隐藏，不影响“原样使用 TranscodingUrl”的策略。

### 2.4 播放内核选型

| 方案 | 超分 | 字幕 | 编码/容器 | 平台 | 结论 |
| --- | --- | --- | --- | --- | --- |
| **media_kit（libmpv）** | ✅ `glsl-shaders` | ✅ ASS/SSA/PGS/VobSub | ✅ 极广 | macOS/Android | **选它** |
| video_player（AVPlayer/ExoPlayer） | ❌ 无通用 shader 注入 | 部分 | 受平台限制 | 全平台 | 不适合（会大量转码） |
| fvp（libmdk） | 有限 | 一般 | 较广 | 移动/桌面 | 生态与可控性不如 mpv |
| 原生 AVPlayer + MetalFX（macOS） | ✅ 但仅 macOS | 一般 | 受 AVFoundation 限制 | macOS | 未来实验，不作为主路径 |

**包源决策：Predidit/media-kit fork，pin `83b7ca63772856e1ea0158916177e136f7b7b0be`。**

| 维度 | 上游 1.2.6 | fork@83b7ca6 |
| --- | --- | --- |
| Android libmpv | mpv 0.36，`-Dvulkan=disabled -Dlibplacebo=disabled` → **无 gpu-next** | mpv 0.41 + libplacebo + shaderc + Vulkan → **有 gpu-next** |
| 分发 | gradle/podspec 下载 jar/xcframework；Android 1.3.8 有下载 406 issue #1469 | Dart build hook（native assets），绕开 gradle 下载；Apple 侧提供 Package.swift + podspec |
| macOS libmpv | mpv 0.36 | mpv 0.36（仍无 gpu-next） |
| 最低要求 | Dart 2.17 | Dart 3.10 / Flutter 3.38；native assets macOS target 13 |
| 风险 | 维护 limited；Android 构建失败 | 与 Flutter 3.47.8/AGP 9 未实测；需 C 编译器 |

**结论**：选 fork，但必须在 M0 用 CI/真机复现构建；`PlayerEngine` 接口隔离，保留回退上游的方案。

---

## 3. 技术方案

### 3.1 总体架构

```
┌──────────────────────────────────────────────────────────────┐
│ UI 层（Forui）                                                │
│  Onboarding / Home / Library / Detail / Search / Player /    │
│  Downloads / Settings                                        │
└───────────────┬──────────────────────────────────────────────┘
                │ Riverpod providers / Notifier
┌───────────────▼──────────────────────────────────────────────┐
│ 功能控制器层                                                  │
│  AuthController  LibraryController  PlayerSessionController   │
│  SuperResolutionController  DownloadController  SyncPlay...   │
└───────────────┬──────────────────────────────────────────────┘
                │
┌───────────────▼──────────────────────────────────────────────┐
│ 领域/服务层                                                   │
│  JellyfinGateway  PlaybackNegotiator  DeviceProfileBuilder    │
│  ProgressReporter  ShaderRepository  MediaSessionService      │
│  PlayerEngine(接口)                                           │
└───────────────┬──────────────────────────────────────────────┘
                │
┌───────────────▼──────────────────────────────────────────────┐
│ 数据/平台层                                                   │
│  Dio  SecureStore  Prefs  ImageCache  FileStore  SQLite(P1)   │
│  media_kit  window_manager  audio_service  PiP  brightness... │
└──────────────────────────────────────────────────────────────┘
```

原则：

- **UI 不直接碰 media_kit**。播放器页面只消费 `PlayerSessionState` 与命令。
- **播放器状态机只有一个真相源**（`PlayerSessionController`），所有手势/菜单/键盘都调用命令，不各自改状态。
- **超分是播放器的一个子系统**，不是独立播放器；它订阅当前 `PlaybackPlan` 与设备能力。
- **平台差异收敛在 `PlayerEngine` 与 `PlatformCapabilities`**，业务层不写 `Platform.isAndroid` 分支。

### 3.2 工程与目录

从模板复制后，目标结构：

```text
lib/
  app/
    app.dart                 # 根节点、主题、本地化
    router.dart              # 路由：shell + /play/:itemId + /login；根 navigatorKey
    shell.dart               # 响应式导航（首页/媒体库/搜索/下载/设置）
    theme.dart               # Forui 主题 + 播放器颜色 token
    shortcuts.dart           # macOS 菜单/快捷键注册
  core/
    logging/                 # 复用模板
    settings/                # 设置模型 + 仓库（扩展播放器设置）
    network/
      dio_provider.dart
      auth_interceptor.dart  # Authorization: MediaBrowser
      error_mapper.dart
      redaction.dart
    security/secure_store.dart
    platform/
      capabilities.dart      # 设备能力探测（HDR/ABI/Vulkan/屏幕/字体）
      brightness.dart
      volume.dart
      orientation.dart
      pip.dart
      wake_lock.dart
      thermal.dart
    utils/                   # ticks 转换、时间格式、结果类型
  data/
    jellyfin/
      api_client.dart        # 端点封装
      models/                # 手写/生成 DTO（Item, MediaSource, PlaybackInfo...）
      auth_repository.dart
      library_repository.dart
      playback_repository.dart
      image_url.dart
    local/
      prefs.dart
      download_store.dart    # P1
  features/
    onboarding/
    home/
    library/
    detail/
    search/
    downloads/
    settings/
    player/
      player_page.dart
      player_route.dart
      controller/
        player_session_controller.dart
        player_state.dart
        playback_negotiator.dart
        progress_reporter.dart
        next_up_controller.dart
      engine/
        player_engine.dart        # 接口
        media_kit_engine.dart     # 实现
        engine_events.dart
      super_resolution/
        super_resolution_mode.dart
        shader_repository.dart
        super_resolution_controller.dart
        performance_guard.dart
      ui/
        player_surface.dart
        gesture_layer.dart
        controls/
        menus/
        hud/
        overlays/
  shared/
    widgets/                 # 媒体卡片、骨架屏、空态、错误视图
    localization.dart
  l10n/
assets/
  shaders/                   # Anime4K *.glsl + LICENSE
  fonts/subtitle/            # Android 字幕字体（OFL）
  images/                    # 品牌/占位图
test/
  unit/
  widget/
  integration/
tool/
  # 删除 sync_snippets，新增 release/notarize 脚本
```

### 3.3 依赖清单（新增/替换）

| 依赖 | 版本建议 | 用途 | 备注 |
| --- | --- | --- | --- |
| media_kit | git fork pin `83b7ca6` | 播放内核 | 只加 `media_kit` + `media_kit_video`；不要加 `media_kit_libs_*`；fork 的 media_kit_video 自带 SwiftPM 包 |
| media_kit_video | 同 fork 同 commit | 视频渲染 | `vo`/`hwdec`/`enableAndroidSurfaceProducer` |
| flutter_secure_storage | ^9/^10 | token/密码 | Keychain / Keystore |
| audio_session | ^0.2 | 音频焦点/中断 | Android/iOS/macOS |
| audio_service | ^0.18 | 后台音频/媒体通知 | Android 前台服务 |
| wakelock_plus | ^1.2 | 播放时保持唤醒 | 全平台 |
| screen_brightness | ^2.x | 亮度手势 | Android/macOS |
| flutter_volume_controller | ^2.x | 音量手势 | Android；macOS 用 mpv 音量 |
| device_info_plus | ^11 | 设备能力/诊断 | 全平台 |
| connectivity_plus | ^6 | 网络状态 | 转码/重试策略 |
| cached_network_image | ^3.4 | 海报缓存 | 或自建 ImageProvider |
| dart_jellyfin | 0.3.1（可选） | API 模型/网关 | spike 后决定是否采用 |
| drift 或 sqlite3 | P1 | 下载/历史 | 下载功能再引入 |
| flutter_svg | ^2 | 品牌/图标 | 可选 |
| package_info_plus / path_provider / share_plus / url_launcher / archive / logging / stack_trace / intl | 模板已有 | 复用 | — |

字体：

- Android 必须随包提供字幕字体（思源黑体/Noto Sans CJK 子集，OFL），因为 media_kit Android 写死 `sub-font-provider=none`，缺字体可能完全不渲染。
- 应用 UI 字体：模板 MiSans（需遵守其许可）；也可换成 OFL 字体，减小包体。

删除：`assets/snippets/`、`tool/sync_snippets.dart`、catalog/tasks/network 示例相关依赖与测试。

### 3.4 网络与 API 层

- `Dio` 单例 + 每服务器一个 `JellyfinApiClient`（baseUrl 可带子路径，如 `https://host/jellyfin`）。
- 认证 Header（10.8–10.10 与 12.x 通用）：
  ```
  Authorization: MediaBrowser Client="Sakuga", Device="<device name>", DeviceId="<hash>", Version="<app version>", Token="<access token>"
  ```
  未登录时不带 Token；`DeviceId` 按用户派生（`hash(设备ID + 用户名)`）。10.x 若遇到代理/旧服务端不识别，回退 `X-Emby-Token`；12.x 不再支持旧头，只走 Authorization。
- 拦截器：
  - 注入认证头；401 → 标记档案失效、跳登录（不自动重试登录，避免 deviceId 单 token 冲突）；
  - 503 + `Retry-After` → 按头重试（服务端启动/重启）；
  - 超时/断网 → 统一 `AppException`（network/timeout/auth/server/format）；
  - 日志脱敏：不打印 token、密码、完整 URL 查询串。
- 自签名证书：默认拒绝；用户首次连接时展示证书指纹，确认后仅对该 host 放行（`badCertificateCallback`），不做全局信任。
- 明文 HTTP：
  - Android：`network_security_config` 允许私有地址明文（或 `usesCleartextTraffic=true` + UI 提示）；
  - macOS：`NSAppTransportSecurity/NSAllowsLocalNetworking`；
  - 公网地址默认要求 HTTPS。
- 图片：统一 `ImageUrlBuilder`（itemId/type/index/maxWidth/tag），带认证头；海报按 DPR 请求合适宽度。
- DTO：手写核心模型 + `json_serializable`；不要引入完整 OpenAPI 生成器（体积/构建时间不划算）。只覆盖 MVP 端点；服务端新增字段忽略。
- 版本路由：`ServerCapabilities` 记录 `Version`，<10.9 走旧端点（`/Users/{id}/Views` 等）。
- 时间：Jellyfin 用 `Ticks`（1 tick = 100ns）。统一 `Duration ticksToDuration(int)` / `int durationToTicks(Duration)`。

### 3.5 播放器架构

#### 3.5.1 状态机

```
idle → negotiating → loading → playing ⇄ paused
                         ↘ buffering ↗
playing → ended → (nextUp / replay / exit)
any → error → (retry / fallbackTranscode / exit)
```

状态字段（`PlayerSessionState`）：`status`, `item`, `mediaSource`, `playMethod`, `position`, `duration`, `buffer`, `isPlaying`, `rate`, `volume`, `audioTracks`, `subtitleTracks`, `activeAudio`, `activeSubtitle`, `videoParams`, `error`, `srMode`, `srEffective`, `stats`。

#### 3.5.2 打开播放的时序

1. UI 调 `play(itemId, startPosition, preferredAudio/Subtitle, maxBitrate)`。
2. `PlaybackNegotiator` 构建 `DeviceProfile`（按平台/设备能力）→ `POST /Items/{id}/PlaybackInfo`。
3. 选择 `MediaSource`：
   - `SupportsDirectPlay` 且客户端能力匹配 → 直连 URL（`static=true`），`PlayMethod=DirectPlay`；
   - 否则 `TranscodingUrl` 原样使用（HLS 或 DirectStream）；
   - 全失败 → 显式请求 h264/aac 转码。
4. 生成 `PlaybackPlan`（url、headers、playSessionId、mediaSourceId、subtitle delivery、duration、startPosition、transcode reasons）。
5. `PlayerEngine.open(plan)`：
   1. 等待 `waitForPlayerInitialization`；
   2. 创建/复用 `Player` + `VideoController`（`vo`/`hwdec`/`enableAndroidSurfaceProducer` 按平台）；
   3. 设置 `sub-fonts-dir`（Android 自带字体）、`http-header-fields`（认证）、`af=scaletempo2=max-speed=8`（倍速不变调）；
   4. `open(Media(url, start: ..., httpHeaders: ...))`；
   5. 首帧后应用 `glsl-shaders`（避免 VO 未就绪；若首帧闪烁明显再评估前置）；
   6. 外挂字幕 `sub-add`（用 DeliveryUrl/字幕 URL + headers）。
6. 首帧渲染后 → `POST /Sessions/Playing`；启动 `ProgressReporter`（10s + 事件触发）。
7. 播放中：位置/缓冲/轨道/视频参数流 → 更新状态；用户操作 → 命令。
8. 结束/退出：`POST /Sessions/Playing/Stopped`；转码则 `DELETE /Videos/ActiveEncodings`；保存本地进度。

#### 3.5.3 关键接口

```dart
abstract interface class PlayerEngine {
  Stream<EngineEvent> get events;
  Future<void> open(PlaybackPlan plan, {Duration startAt});
  Future<void> play();
  Future<void> pause();
  Future<void> seek(Duration target);
  Future<void> setRate(double rate);
  Future<void> setVolume(double volume);
  Future<void> selectAudio(int index);
  Future<void> selectSubtitle(int? index);
  Future<void> addExternalSubtitle(Uri uri, {String? title});
  Future<void> setShaderChain(List<String> absolutePaths); // 空列表 = 关闭
  Future<void> clearShaderChain();
  Future<PlayerStats> stats();
  Future<void> dispose();
}
```

- `PlayerEngine` 只暴露“能力”，不暴露 mpv 细节；`MediaKitEngine` 内部用 `NativePlayer.setProperty/command`。
- `PlayerSessionController` 负责状态机、命令串行化（避免 seek/open 竞态）、生命周期。
- `ProgressReporter` 独立：节流、失败重试、退出时 flush；暂停/seek/切集立即上报。
- `NextUpController`：提前请求下一集 PlaybackInfo（预加载），片尾前 20s 显示倒计时；用户取消则本次会话不自动跳。
- `PlayerEngine` 复用：同一页面切集不销毁 `Player`，只 `open` 新媒体；退出页面才 dispose。这样下一集间隙更短。

#### 3.5.4 直连/转码决策树

```text
播放请求(itemId, startTicks, 用户音轨/字幕偏好)
1) POST /Items/{id}/PlaybackInfo  body: DeviceProfile(mpv), MaxStreamingBitrate, StartTimeTicks
   enableDirectPlay/DirectStream/Transcoding = true
   ├─ ErrorCode != null → 报错(NotAllowed/NoCompatibleStream/RateLimitExceeded)
   └─ 选 MediaSources[Id==MediaSourceId || 0]，记下 PlaySessionId
2) 分支（按序）
   A. SupportsDirectPlay == true
      → GET {base}/Videos/{id}/stream?static=true&mediaSourceId=&playSessionId=
        PlayMethod=DirectPlay
        ├─ 播放器报错(容器/编码) → 该组合加入本地黑名单，回到 1)
        └─ 成功 → 3)
   B. TranscodingUrl != null
      → {base}{TranscodingUrl}（原样）
        PlayMethod = TranscodingSubProtocol=="hls" ? Transcode : DirectStream
   C. SupportsDirectStream == true 且无 TranscodingUrl
      → {base}/Videos/{id}/stream?static=false&mediaSourceId=…&container=ts
   D. 全失败 → 显式请求转码(h264/aac, 8Mbps) → 走 B
3) 播放中
   ├─ 每 10s：POST /Sessions/Playing/Progress
   ├─ 暂停/seek/切音轨字幕：立即补报
   ├─ 带宽不足：DELETE /Videos/ActiveEncodings → 重新 PlaybackInfo(更低 bitrate, 当前位置)
   └─ 退出：POST /Sessions/Playing/Stopped + DELETE /Videos/ActiveEncodings
```

#### 3.5.5 错误与降级

| 错误 | 处理 |
| --- | --- |
| PlaybackInfo 4xx/5xx | 展示服务器错误；401 重新登录；404 返回详情；503 按 Retry-After。 |
| 直连打开失败（容器/编码） | 自动重新协商，强制 `EnableDirectPlay=false`，走转码；提示“已切换转码”。 |
| 解码失败/黑屏 | 切换 `vo`（gpu-next ↔ gpu）或 `hwdec=no`；仍失败则转码。 |
| 网络中断 | 暂停 + 指数退避重连（3 次）；失败提示重试/切码率。 |
| 字幕加载失败 | 保留视频，提示字幕不可用；可重试/换轨道。 |
| 转码会话 404/410 | 重新 PlaybackInfo。 |
| 服务器时间/进度冲突 | 以本地位置为准，退出时上报覆盖。 |
| FD 增长（Android HLS #1391） | 长播监控 /proc/self/fd；异常时重建播放器并提示。 |

### 3.6 超分辨率方案

#### 3.6.1 档位与策略

| 档位 | shader 链 | 适用 | 默认 |
| --- | --- | --- | --- |
| 关闭 | 无 | 4K 源、HDR、低端机、省电 | 4K/HDR 自动 |
| 效率（M） | Clamp + Restore_M/S + Upscale_x2_M + DownscalePre + Upscale_x2_S | 1080p→1440p/4K，移动端 | Android 默认 |
| 质量（VL） | Clamp + Restore_VL + Upscale_x2_VL + DownscalePre + Upscale_x2_M | 720p/1080p 动画，Mac/旗舰 | Mac 高端默认 |
| 自动（新增） | 按内容/分辨率/设备/热状态选效率或关闭 | 普通用户 | 推荐默认 |
| 低端兜底（可选） | mpv 内置 `ewa_lanczossharp` + deband（非 CNN） | 低端机/省电 | 自动降级 |

自动策略输入：

- 源分辨率 vs 屏幕物理分辨率（放大倍数）；
- 内容类型：Jellyfin `Genres` 含 Animation / 动漫库标记；
- 平台：macOS 默认效率（M1 4K 输出 VL 可能只有 30fps），M1 Pro/Max 可质量；Android 旗舰效率，质量仅 1080p 输出；
- 设备档位：RAM/CPU 核心/GPU（粗分高端/中端/低端）；
- HDR：默认关闭；
- 热状态/掉帧：运行中降级；
- 用户手动选择优先于自动，且本次会话记住。

#### 3.6.2 资源与生命周期

- shader 资源放 `assets/shaders/`，启动后异步复制到 `ApplicationSupport/anime4k/<shaderVersion>/`（版本戳/哈希，升级覆盖；Kazumi 的“已存在跳过”会导致升级不生效，需避免）。
- 复制失败不阻塞播放；超分菜单置灰并提示。
- 应用时机：首帧后设置（VO 就绪）；运行时切换用 `change-list`。
- 关闭：`change-list glsl-shaders clr ''`；恢复默认缩放。
- 与 `vo` 的约束：`mediacodec_embed` 时强制关闭并解释；切换渲染器需要重建 `VideoController`（重建播放器），产品上提示“切换渲染器将重新加载视频”。
- macOS 走 `vo=libmpv`（底层 vo_gpu，mpv 0.36，libplacebo/Vulkan 关闭），shader 走 GLSL 150；不要指望 gpu-next 专属特性。
- Android 14+ 且 Vulkan 1.2 才默认 `gpu-next`；否则 `gpu`。gpu-next 失败自动回退。

#### 3.6.3 性能守卫

- 每 1s 读取 mpv 统计（`frame-drop-count`、`decoder-frame-drop-count`、`estimated-vf-fps`、`video-params`、`vo-passes`），连续 10s 掉帧率 > 5% → 提示“超分导致掉帧，建议切效率档/关闭”，可一键降级。
- 监听热状态：Android `PowerManager.getCurrentThermalStatus()`、macOS `ProcessInfo.thermalState`；过热时自动降档。
- 电量低于 20% 且未充电时默认不启用质量档（可设置）。
- 首次开启质量档弹确认（“可能造成卡顿”），可记住选择。
- **颜色验收**：Android GLES 多 pass 可能存在偏色（media_kit #1438）；开启前后用测试图截帧比较 ΔE < 3，不达标则优先 gpu-next 或关闭。
- 诊断页展示：当前档位、实际 shader 列表、vo/hwdec、分辨率、fps、掉帧、GPU 名称、颜色检查结果。

#### 3.6.4 设置项

- 默认超分模式：自动/关闭/效率/质量。
- 仅动画启用（默认开）。
- 低电量/过热自动降级（默认开）。
- 首次提示（可关）。
- 高级：自定义 shader 目录（P2）、导入 .glsl（P2）、渲染器选择（Android：auto/gpu/gpu-next/mediacodec_embed）、硬解开关、硬解解码器选择、mpv 缩放器（低端兜底）。
- 关于页：Anime4K MIT 许可、mpv/libmpv 许可、FFmpeg 许可、字体许可。

### 3.7 播放体验设计（重点）

设计原则：

1. **不打断**：任何操作都不应导致黑屏、重新缓冲、音频爆音。
2. **可预期**：手势有即时视觉/触觉反馈；松手才提交 seek（可配置实时 seek）。
3. **单手可达**：手机横屏时主要操作在拇指区；菜单从底部弹出。
4. **桌面原生感**：键盘/触控板/菜单栏/媒体键/全屏空间行为符合 macOS 习惯。
5. **可恢复**：误触可撤销；错误有明确下一步。
6. **稳定优先**：视频贴图上的 blur/saveLayer 默认禁用（Impeller abort 风险），用纯色/渐变替代。

**Impeller 基线**：M0 先关闭 Impeller（macOS `Info.plist` 的 `FLTEnableImpeller=false`；Android manifest 的 `EnableImpeller=false`），与 Kazumi 保持一致；同时验证 Flutter 3.47.8 是否已修复 flutter#185506。若修复且 HUD 无 blur abort，再开启并跑完整 20 条体验脚本；否则保持关闭（Skia）。

#### 3.7.1 手势矩阵

| 手势 | 手机（横屏） | Mac（触控板/鼠标） | 反馈 | 备注 |
| --- | --- | --- | --- | --- |
| 单击 | 显示/隐藏控制层 | 播放/暂停（或显示控制层，可设置） | 控制层淡入/播放图标 | 桌面单击语义可配置 |
| 双击左/右 | 后退/前进 10s（可设 5/10/30） | 同左，或全屏 | 屏幕侧边涟漪 + 时间差 | 中心双击 = 播放/暂停 |
| 长按 | 临时 2x/3x 倍速 | 同左 | “2x”角标 + 轻微震动 | 松手恢复 |
| 横滑 | 交互式 seek（松手提交） | 同左 | 时间气泡 + 缩略图 + 目标位置 | 边缘 24dp 取消，避免系统返回 |
| 竖滑左半 | 亮度 | 亮度（可选） | 亮度 HUD | 退出播放可选恢复 |
| 竖滑右半 | 音量 | 音量 | 音量 HUD | 系统音量与 mpv 音量同步策略 |
| 双指捏合 | 缩放/裁剪画面 | 同左 | 缩放比例 HUD | 双击复位；缩放后单指拖动平移 |
| 双指双击 | 复位缩放/比例 | 同左 | 动画复位 | 可选 |
| 三指左右滑 | 快退/快进 30s（可选） | — | 时间差 | 与系统手势冲突则默认关 |
| 下拉 | 显示剧集/播放列表 | — | 底部抽屉 | 可选 |
| 锁定 | 锁图标/长按锁 | 菜单 | 锁定态提示 | 锁定后仅解锁手势可用 |

手势冲突处理：

- Android 手势导航：左右边缘 24dp 不响应横滑；底部 24dp 不响应竖滑。
- macOS 触控板滚动用于音量（可设置），横向滚动 seek。
- 菜单/弹层打开时禁用手势层；拖动进度条时禁用手势层。
- 无障碍模式/大字体下，手势区域与按钮尺寸同步放大。

#### 3.7.2 控制层

布局（横屏）：

- 顶部：返回、标题/剧集信息、右侧“投屏/同步/更多”。
- 底部：当前时间 / 进度条（含缓冲、章节、片头片尾标记）/ 总时间；下方一排：播放/暂停、上一集、下一集、快退 10s、快进 10s、字幕、音轨、倍速、画面、超分、锁定、全屏。
- 右侧竖排（可选）：音量/亮度快捷、截图、信息。
- 菜单从底部/右侧弹出，移动端用 bottom sheet，桌面用 popover。

自动隐藏：

- 默认 3s；设置 1–10s；暂停时 5s；菜单打开/拖动/长按不隐藏。
- 手指按住控制层时暂停计时（**panel hold 租约**：一次性、幂等、引用计数），松开后重新计时。
- 鼠标移动到控制层区域时保持显示；离开后计时。

#### 3.7.3 进度条与 Trickplay

- 进度条：已播/缓冲/章节/片头片尾区间；拖动时放大拇指、显示时间气泡。
- Trickplay：Jellyfin `fields=Trickplay` 取瓦片信息；按时间计算 tile 索引与偏移，显示 160×90 预览；预取相邻 tile；加载失败降级为纯时间气泡。
- 交互式 seek：拖动时暂停（记录 wasPlaying），只更新预览位置；松手后 seek 并恢复播放；支持“取消拖动”回到原位置。
- 快进/快退按钮：默认 10s，可设 5/10/30；长按连续步进（可选）。
- 章节：进度条上小刻度；点击/菜单跳章；显示章节名。
- 片头/片尾：MediaSegments 返回区间；进入区间显示“跳过片头/片尾”按钮（可设自动跳过）；与下一集倒计时协调。

#### 3.7.4 菜单

| 菜单 | 内容 | 交互 |
| --- | --- | --- |
| 字幕 | 关闭/内置轨道/外挂/搜索/上传；延迟 ±0.5s；大小/位置/背景/描边；ASS 样式覆盖 | 切换即时生效；延迟调整显示 HUD |
| 音轨 | 轨道列表（语言/声道/编码）；音频延迟；音量增强/归一化 | 切换即时；转码时需重新协商 |
| 倍速 | 0.25–4.0（常用档）；音调校正 | 长按临时倍速独立 |
| 画面 | 适应/填充/拉伸/16:9/4:3/自定义；旋转/镜像；缩放 | 即时；记忆每设备 |
| 超分 | 关/自动/效率/质量；当前生效说明；性能提示 | 运行时切换；失败回滚 |
| 质量 | 自动/直连优先/码率上限（如 4/8/20/40Mbps）；当前 PlayMethod/码率/转码原因 | 变更触发重新协商（保持位置） |
| 信息 | 容器/视频/音频/字幕编码、分辨率、fps、码率、vo/hwdec、丢帧、缓冲、服务器/会话、FD 数 | 可复制/导出诊断 |
| 更多 | 截图、锁定、PiP、同步播放、投屏、睡眠定时 | P1/P2 |

#### 3.7.5 字幕体验

- 默认优先：用户语言 > 中文 > 英文 > 第一条；ASS 优先于 SRT（保留特效）。
- 外挂字幕通过 mpv `sub-add` 加载 Jellyfin 字幕 URL（带认证 header），支持 `sub-delay`、`sub-pos`、`sub-scale`、`sub-ass-override`。
- **Android 字体**：必须把 CJK 字体放到 `sub-fonts-dir` 并设置默认字体；否则可能完全不渲染。macOS 走 CoreText 系统字体。
- 位图字幕（PGS/VobSub）不支持样式调整，菜单隐藏相关项并说明；PGS 外部字幕需 spike。
- 字幕搜索/上传（P1）：Jellyfin RemoteSearch + 上传到服务器。
- 双语字幕（P2）：两条字幕同时显示需要双 `sub-add` + 轨道叠加；mpv 原生只显示一条，需评估。
- 字幕延迟快捷：菜单 +/- 0.5s；显示 HUD。

#### 3.7.6 音轨与音频

- 音轨切换即时；转码时切换音轨需要重新 PlaybackInfo（保持位置），UI 显示“正在切换”。
- **TrueHD/MLP**：Android libmpv 无解码器，必须转码；DTS-HD MA 是否全解需 spike。
- 音频直通（P1）：HDMI/蓝牙设备能力探测；不支持时自动 PCM。
- 音量：手机侧滑调系统音量（与 mpv 音量同步，避免双衰减）；Mac 调 mpv 音量 + 系统音量键由 macOS 处理。
- 音频焦点：来电/其他 App 播放时暂停；恢复时按策略继续。
- 后台音频：Android 前台服务 + media notification；macOS 窗口关闭后是否继续（设置项，默认暂停）。

#### 3.7.7 连播、片头片尾、续播

- 续播：进入详情/播放时读取 `UserData.PlaybackPositionTicks`；本地记录作为兜底；起播前询问“从上次位置继续/从头”（可设置默认）。
- 下一集：剧集上下文传入播放队列；片尾前 20s 预请求；倒计时 5s（可取消）；自动跳转复用播放器。
- 片头/片尾：MediaSegments；按钮 + 自动跳过设置；与“下一集”不冲突。
- 播放完成：标记已看；若接近结尾的续播，从头重播而不是误跳下一集。
- 播放列表/队列：P1。

#### 3.7.8 后台、PiP、媒体会话

- Android：
  - `audio_service` + 前台服务（`mediaPlayback` 类型）；通知含播放/暂停/上一集/下一集/进度。
  - **后台帧堆积**（media_kit #1378）：切后台时停止/解绑视频 Surface（或暂停视频渲染），只保留音频；回前台重建 Surface。需 spike 验证。
  - PiP：**自研 platform channel**（media_kit 无官方 PiP，PR #1410 未合并）；进入后台/按 Home 自动进入（可设置）；PiP 中显示播放/暂停/快进/字幕 action；恢复时无缝。
  - 锁屏/通知媒体控制；蓝牙/耳机拔出暂停。
- macOS：
  - `MPNowPlayingInfoCenter` + `MPRemoteCommandCenter`（播放/暂停/快进/上一集/下一集）；媒体键。
  - 窗口全屏到独立 Space；退出全屏恢复窗口尺寸。
  - 迷你播放器（P1）：始终置顶小窗；原生 PiP（AVKit）作为 P2 评估（media_kit 无现成 PiP）。
  - 菜单栏：播放/暂停、快进/快退、字幕、音轨、全屏、画中画。

#### 3.7.9 键盘与触控板（macOS）

| 键 | 行为 |
| --- | --- |
| Space / K | 播放/暂停 |
| ← / → | ±5s |
| Shift + ← / → | ±30s |
| J / L | ±10s |
| ↑ / ↓ | 音量 ±5 |
| M | 静音 |
| F / Ctrl+Cmd+F | 全屏 |
| Esc | 退出全屏/关闭菜单 |
| C | 字幕菜单 |
| A | 音轨菜单 |
| [ / ] | 倍速 -/+ |
| 0–9 | 跳到百分比 |
| S | 截图 |
| I | 信息 |
| P | PiP/迷你窗 |
| 双击 | 全屏（可设置） |
| 滚动 | 音量（可设置） |
| 横向滚动 | seek |
| 捏合 | 缩放 |

快捷键可自定义（P1），存设置。

#### 3.7.10 错误、空态与恢复

- 加载：海报模糊背景 + 进度；超过 8s 显示“仍在加载/检查网络/切换转码”。
- 缓冲：小 spinner + “缓冲中”；超过 10s 提供“降低码率”。
- 播放失败：错误卡片（原因 + 重试 + 转码 + 返回）；日志一键导出。
- 服务器断连：顶部 banner；恢复后自动重连（播放中则重试）。

#### 3.7.11 无障碍与国际化

- 所有按钮有语义标签；播放器控制可用键盘/遥控焦点遍历。
- 支持动态字体（播放器控制层使用固定比例，避免溢出）。
- 高对比度/减少动画设置；字幕默认大小可调。
- 中英文文案；错误码映射为可读文案；RTL 预留（P2）。
- **UI 文案规范**：界面不写注释性/说明性文本；只保留功能所需文案（按钮、状态、错误、必要帮助入口）。设置项用“标签 + 当前值/选项”，不写长段解释；解释放帮助页/文档。

#### 3.7.12 性能预算

| 项 | 预算 |
| --- | --- |
| 播放器页面首帧 | ≤ 1.5s（局域网直连） |
| 控制层动画 | 200–250ms，60/120fps 不掉帧 |
| 手势→视觉反馈 | ≤ 1 帧 |
| seek 提交→画面 | ≤ 300ms（局域网） |
| 进度条拖动预览 | 60fps（trickplay 解码异步） |
| 内存 | 1080p ≤ 500MB；4K ≤ 1GB（Android） |
| 超分额外功耗 | ≤ 25%（相对关闭） |
| 日志写入 | 异步，不阻塞 UI |

### 3.8 平台适配

#### 3.8.1 macOS（Apple Silicon / arm64）

- 构建：`flutter build macos --release --arch arm64`；开启 `flutter config --enable-macos-arm64-only` 避免 universal 双架构。
- 最低系统：**13.0**（已确认；native assets 要求；模板当前 12.0）。
- 依赖管理：优先保持模板的纯 SPM（fork 的 `media_kit_video` 有 Package.swift）；若 Flutter 3.47.8 仍生成 Podfile，则接受 CocoaPods 混合模式。无论哪条路，native assets 都会在构建期下载 libmpv，CI 需网络/C 编译器并缓存。
- 签名/公证：**v1 暂不发布**，本地开发用 ad-hoc 签名即可；正式分发时再做 Developer ID + `notarytool` + Hardened Runtime + DMG。
- 沙盒：模板已开启 App Sandbox；Release entitlements 已含 `network.client`、`files.user-selected.read-write`（保留）；本地网络权限 macOS 15+ 需 `NSLocalNetworkUsageDescription`；若用 Bonjour 发现加 `NSBonjourServices`。
- ATS：`NSAppTransportSecurity/NSAllowsLocalNetworking`，否则局域网 http Jellyfin 不通。
- 渲染：`vo=libmpv`（mpv 0.36，OpenGL 3.2 core），**无 gpu-next**；HDR 按 SDR tone-map；ProMotion 120Hz 需实测。
- 窗口：全屏隐藏自绘标题栏；进入全屏独立 Space；退出恢复；迷你窗用 `window_manager` 置顶 + 无边框。
- 菜单栏：`PlatformMenuDelegate`/原生菜单（播放、字幕、音轨、视图、窗口、帮助）。
- 本地网络发现：UDP 7359 可能被防火墙拦截；提供手动地址兜底。
- Impeller：基线关闭（`FLTEnableImpeller=false`），M0 验证后再决定。

#### 3.8.2 Android（arm64-v8a）

- 构建：`minSdk 26`（PiP/前台服务；Flutter 默认 24，fork 插件 21），`targetSdk 36`，`compileSdk 36`；ABI 仅 `arm64-v8a`（+ debug x86_64）；App Bundle + ABI split。
- 16KB page size：Google Play 对 targetSdk 35+ 要求 16KB 对齐；fork 的 libmpv 1.3.1 需构建后 `zipalign -c -P 16 -v 4` + `llvm-readelf` 校验（暂不发布也要保证可安装）。
- Manifest：
  - `INTERNET`、`ACCESS_NETWORK_STATE`、`WAKE_LOCK`、`FOREGROUND_SERVICE`、`FOREGROUND_SERVICE_MEDIA_PLAYBACK`、`POST_NOTIFICATIONS`（13+）；
  - `android:extractNativeLibs="true"`（libmpv .so 需要；以实际打包验证为准）；
  - `android:supportsPictureInPicture="true"`、`configChanges` 含 `screenSize|smallestScreenSize|screenLayout|orientation`；
  - `android:usesCleartextTraffic="true"` 或 network security config：Jellyfin 常见 `http://192.168.x.x:8096`，必须允许；建议仅对私有地址放行并在 UI 提示。
- 播放：
  - `vo=gpu`（默认稳健）/ `gpu-next`（Android 14+，Vulkan 1.2）；`hwdec=auto-safe`；`mediacodec_embed` 无超分/字幕/OSD。
  - 硬解兼容：HEVC 10-bit、AV1（设备支持则直连，否则转码）；HDR（HDR10/HLG）tone-map 到 SDR。
  - 音频：OpenSL ES / AudioTrack；蓝牙延迟；音频焦点；TrueHD 转码。
- 后台：前台服务 + 通知；Android 14+ 前台服务类型声明；从用户点击播放启动；后台停止视频 Surface 防帧堆积。
- PiP：自定义 `PictureInPictureParams`（aspect ratio、actions）；Android 12+ 无缝调整；退出 PiP 恢复。
- 屏幕：刘海/挖孔 insets；横屏沉浸式（隐藏状态栏/导航栏，可设置）；保持常亮；旋转锁定；高刷（`flutter_displaymode`）。
- 存储：下载后续再做；导出用 MediaStore/SAF。
- 热/电：`PowerManager` 热状态；低电量策略；超分自动降级。
- Impeller：基线关闭（manifest `EnableImpeller=false`），M0 验证后再决定。

#### 3.8.3 Linux（本地开发/验证平台，不发布）

- 定位：用于在 Linux 开发机上验证 UI、media_kit 播放、超分 shader 与 Jellyfin 接口；**不作为发布目标**，不做 deb/AppImage/商店分发。
- 构建/运行：
  ```sh
  fvm flutter create --platforms=linux --project-name sakuga .   # 已加回
  fvm flutter build linux --debug
  fvm flutter run -d linux
  ```
- 系统依赖（media_kit 的 bundled libmpv 需要）：
  ```sh
  sudo apt install libva2 libva-drm2 libva-x11-2 libva-wayland2 libvdpau1 \
    libpulse0 libsndfile1 libasyncns0 libxss1 libxv1
  ```
  无 sudo 时用 `tool/run_linux.sh`：它调用 `tool/linux_deps.sh` 把依赖下载/解压到 `~/.cache/sakuga/linux-deps`，并设置 `LD_LIBRARY_PATH`、`GDK_BACKEND=x11`、`LIBGL_ALWAYS_SOFTWARE=1`。
- 渲染：Linux runner 已调用 `fl_dart_project_set_enable_impeller(project, FALSE)`，与 macOS/Android 的“关闭 Impeller”基线一致；WSLg 下还需 `GDK_BACKEND=x11 LIBGL_ALWAYS_SOFTWARE=1` 才能稳定创建 media_kit 视频纹理。
- 开发播放验证（不写入仓库的 token）：
  ```sh
  fvm flutter build linux --debug \
    --dart-define=DEV_START_ROUTE=/player \
    --dart-define=DEV_MEDIA_URL='<direct-play-url>'
  GDK_BACKEND=x11 LIBGL_ALWAYS_SOFTWARE=1 ./build/linux/x64/debug/bundle/sakuga
  ```
  仅用于本地验证；正式播放器在 M2 接入 Jellyfin 协商。
- 限制：Wayland/EGL 组合在部分环境会崩溃，优先 X11；Linux 的窗口/快捷键/媒体键/打包不在 v1 范围。

### 3.9 数据、缓存与离线

- 设置：SharedPreferences（模板）；播放器设置单独 key/版本；迁移策略。
- Token：`flutter_secure_storage`；多服务器 `serverId -> {url, token, userId, deviceId}`；退出登录清除。
- 图片：磁盘缓存（cached_network_image 或自建 LRU）；按 maxWidth 请求；弱网降级占位图。
- 播放进度：服务器 `UserData` 为准，本地记录最近位置（离线/失败兜底）；冲突时取较新/较大值（可配置）。
- 历史/继续观看：服务器 API + 本地缓存。
- **离线下载：v1 不做**，后续再评估（原 P1 内容移到 P2）。
- 缓存清理：设置页显示占用；LRU；退出时清理临时转码缓存。

### 3.10 安全、隐私与合规

- 不在日志中输出 token/密码/完整 URL；错误上报前脱敏。
- 自签名证书仅对用户确认的服务器放行；展示 SHA-256 指纹。
- 默认无遥测；崩溃上报（若启用）需明确开关与隐私说明。
- 测试服凭据只放本地环境变量/CI secret，不写入仓库、不写进日志。
- 服务器 API 密钥：当前开发期临时存 `SharedPreferences`（`sakuga.servers.v1`），**仅用于内测**；M1 必须迁移到 Keychain/Keystore（`flutter_secure_storage`），并避免写入日志/导出。
- 许可证：
  - Anime4K shader：MIT，保留 `LICENSE` 与关于页声明。
  - media_kit / libmpv / FFmpeg：MIT/LGPL/GPL 组合，随包附许可；FFmpeg 的 LGPL/GPL 取决于编译选项，需在关于页说明。
  - 字幕字体：OFL（如 Noto Sans CJK），保留许可。
  - Forui：MIT（确认版本许可）。
  - **Kazumi：GPL-3.0，不复制代码**；Sakuga 独立实现，仅参考行为与公开文档。
- 商标：不要使用 Jellyfin 官方 Logo/名称暗示官方；关于页注明“非 Jellyfin 官方客户端”。

---

## 4. 里程碑与排期

### 4.1 单人排期（10.5 周 + 2 周缓冲）

| 里程碑 | 周期 | 目标 | 交付物 | 验收标准 |
| --- | --- | --- | --- | --- |
| **M0 基建与内核验证** | 1.5 周 | 工程可跑、内核 go/no-go | 从模板初始化 Sakuga；删除示例；改包名/图标/启动页；CI；日志/设置/l10n/主题；**media_kit fork 双端构建 spike**；SPM/native assets/macOS 13；Impeller 关闭基线；SR 首帧 spike；ATS/cleartext；全屏路由/方向；Linux 开发 runner | macOS arm64 与 Android arm64 debug 构建成功；Linux debug 构建与本地播放验证；SR 能在两端打开/关闭；Impeller 决策记录；局域网 http Jellyfin 10.10.7 可连 |
| **M1 连接与浏览** | 1.5 周 | 能登录、能找到片 | 服务器配置/API 密钥（已落地基础版）/登录/Quick Connect/多服务器；首页/媒体库（基础版已落地）/详情/搜索；图片；继续观看；错误/空态；版本路由 | 真机连 10.10.7 + 10.8/10.9；浏览 1000+ item 列表流畅；登录失败有明确提示 |
| **M2 播放 MVP** | 2 周 | 能稳定播 | media_kit 集成；PlaybackInfo + DeviceProfile；直连/转码/HLS；基础控制层；手势；字幕/音轨；进度上报；续播；全屏/横屏；错误降级；字幕字体 | 6 类样片（MP4/H.264、MKV/HEVC、AV1、ASS、PGS、HDR）可播；首帧/seek 达标；进度在服务器可见；Android 中文 ASS 不缺字 |
| **M3 超分** | 1 周 | 超分可用可关 | shader 资源管线（版本戳）；四档 + 自动；运行时切换；Android vo/hwdec 策略；性能守卫；颜色验收；设置页；许可声明 | Mac M1 效率档生效且可切换（4K 输出 ≥30fps）；Android 旗舰效率档 ≥45fps；mediacodec_embed 下正确禁用；掉帧自动降级；ΔE<3 |
| **M4 体验打磨** | 2 周 | “好用” | Trickplay 预览；章节；片头片尾；下一集预加载/倒计时；PiP/后台/媒体会话；键盘/触控板/菜单栏；HUD/动画/触觉；无障碍；诊断页；UI 文案审查 | 通过 20 条体验验收脚本（见 6.3）；无 P0/P1 交互缺陷；UI 无注释性文本；真机手感评审通过 |
| **M5 增强** | 1.5 周 | 差异化 | SyncPlay；远程控制/投屏；多用户；字幕搜索/上传；播放列表；诊断增强 | SyncPlay 两端同步误差 < 500ms；远程控制可暂停/seek；多用户切换正常 |
| **M6 打包与内测** | 1 周 | 可安装、可内测 | macOS arm64 本地包（ad-hoc/开发签名）；Android AAB/APK（arm64）；版本/更新日志；隐私/许可页；内测检查单 | 本地安装可运行；Android 真机可安装；日志/诊断可用；无发布商店依赖 |

缓冲：+2 周用于 spike 失败、平台问题、内测反馈。**暂不发布**，M6 不做公证/商店上架。

### 4.2 双人并行（约 7–8 周）

- A（播放/平台）：M0 后半 → M2 → M3 → M4 平台部分（PiP/后台/macOS）。
- B（数据/UI）：M1 → M2 UI/手势 → M4 菜单/设置/无障碍 → M5 SyncPlay/远程控制。
- 每日 15 分钟同步；共享任务板；写作用域分离（见任务拆分）。

### 4.3 关键路径

`M0（内核构建 + Impeller + SR）→ M1 → M2（PlaybackInfo/DeviceProfile/字幕字体）→ M3（shader）→ M4（体验）→ M6`。

- M0 的 go/no-go 是最大不确定项：如果 fork 在 macOS/AGP 9 上构建失败，需要回退上游 1.2.6（放弃 Android gpu-next）或换播放内核，整个计划要重估。
- M2 的 DeviceProfile 是第二大不确定项：先用“保守直连 + 可转码”跑通，再逐步放宽；测试服 10.10.7 已确认 mkv/h264/aac 可直连。
- M4 的 Trickplay/MediaSegments 依赖服务器已生成；测试服当前未生成，需先生成或走降级。

---

## 5. 任务拆解（Backlog）

### P0（v1.0 必须）

**工程**
- [ ] 从 forui_app 初始化仓库；删除 catalog/tasks/network/snippets。
- [ ] 改 applicationId/bundle id/应用名/图标/启动页/版本号（`com.foliage.sakuga`）。
- [ ] 统一 FVM 3.47.6；配置 analyze/format/test CI。
- [ ] 删除非目标平台工程（iOS/Windows/Web）；Linux 保留为本地开发 runner。
- [ ] 日志/设置/主题/l10n 迁移与验证。
- [ ] macOS 13.0 + SPM/native assets（失败回退 CocoaPods）+ arm64-only + ATS；Android minSdk 26 + cleartext + 前台服务/PiP 清单。
- [ ] 根 navigatorKey + 全屏播放器路由；SystemChrome 方向/沉浸式。
- [ ] 打包字幕字体 + sub-fonts-dir。
- [ ] UI 文案审查：移除注释性/说明性文本，只保留功能文案。

**连接**
- [ ] 服务器地址输入/校验/子路径/自签名确认。
- [ ] 用户名密码登录 + token 安全存储 + 401 处理 + deviceId 派生。
- [ ] Quick Connect。
- [ ] 多服务器列表/切换/删除。
- [ ] UDP 7359 发现（可选，手动兜底）。
- [ ] 版本探测与 10.8/10.9/10.10/12.x 路由降级。

**浏览**
- [ ] 首页（继续观看/最近添加/收藏）。
- [ ] 媒体库网格 + 排序/筛选。
- [ ] 剧集/季/集列表。
- [ ] 详情页（元数据/演职员/相似/版本）。
- [ ] 搜索（防抖/历史）。
- [ ] 图片 URL/缓存/占位/失败重试。
- [ ] 已看/收藏操作。

**播放**
- [ ] DeviceProfileBuilder（平台/编码/容器/字幕/码率；TrueHD 转码）。
- [ ] PlaybackInfo 请求/解析/MediaSource 选择/降级。
- [ ] 直连/直连流/HLS 播放。
- [ ] 播放器状态机 + 命令串行化。
- [ ] 基础控制层（播放/暂停/seek/音量/全屏）。
- [ ] 手势系统（单击/双击左右/长按/横滑/竖滑/锁定）。
- [ ] 交互式 seek + 取消/恢复。
- [ ] 音轨/字幕轨道枚举/切换/延迟。
- [ ] 外挂字幕加载（DeliveryUrl 剥离 api_key + headers）。
- [ ] 进度上报（开始/进度/停止/暂停/seek）。
- [ ] 续播（服务器 + 本地）。
- [ ] 全屏/横屏/旋转/沉浸式。
- [ ] 错误映射/重试/转码降级/ActiveEncodings 清理。
- [ ] 生命周期（前后台/音频焦点/耳机拔出）。
- [ ] 屏幕常亮。

**超分**
- [ ] shader 资源复制/校验/版本戳。
- [ ] 四档/自动策略/设备分档。
- [ ] 运行时 set/clr + 失败回滚 + UI 提示。
- [ ] Android vo/hwdec 策略 + mediacodec_embed 禁用。
- [ ] 性能守卫/热状态/低电量。
- [ ] 颜色验收（GLES 偏色）。
- [ ] 设置页 + 首次提示 + 许可。

**体验**
- [ ] 控制层自动隐藏/panel hold 租约。
- [ ] HUD（音量/亮度/seek/倍速）。
- [ ] Trickplay 缩略图（服务器生成后验收）。
- [ ] 章节标记/跳转。
- [ ] MediaSegments 片头片尾跳过（服务器生成后验收）。
- [ ] 下一集预加载/倒计时/取消。
- [ ] 播放完成/已看/自动连播。
- [ ] PiP（Android，自研）。
- [ ] 后台音频/媒体通知/帧堆积处理。
- [ ] macOS Now Playing/媒体键/菜单栏。
- [ ] 键盘快捷键/触控板。
- [ ] 诊断页/日志导出（含 FD/掉帧/颜色）。
- [ ] 无障碍标签/焦点。
- [ ] 空态/加载/错误 UI。

### P1（v1.1）

- SyncPlay（群组/同步/延迟校准）。
- 远程控制/投屏（Jellyfin Sessions）。
- 字幕远程搜索/上传。
- 播放列表/队列。
- 自定义快捷键。
- 迷你播放器（macOS）。
- 多用户快速切换。
- 家长控制/媒体库过滤（若服务器支持）。

### P2（后续）

- 离线下载（队列/断点/配额/离线播放）。
- 弹幕（需要第三方源，非 Jellyfin 原生）。
- 音乐/照片/直播电视。
- 原生 PiP（macOS AVKit）。
- 自定义 shader 导入/FSRCNNX/ravu。
- MetalFX / 平台原生超分实验。
- Android TV 遥控器布局。
- 投屏 DLNA/Chromecast。

---

## 6. 测试与质量

### 6.1 测试金字塔

- **单元测试**：Ticks 转换、DeviceProfile 生成、MediaSource 选择、PlaybackInfo 降级、进度节流、SR 模式映射、手势数学、状态机转换、URL 构建、错误映射、认证头构造。
- **Widget 测试**：控制层布局/隐藏、菜单、HUD、空态、设置页、登录表单。
- **集成测试**：`integration_test` 跑 Android 模拟器 + macOS；用本地 Jellyfin Docker/测试服 + 样片。
- **端到端手测**：真机矩阵（见 6.2）+ 体验脚本（见 6.3）。
- **UI 文案检查**：截图/遍历页面，确认无注释性说明文本；只保留功能文案。

### 6.2 真机/环境矩阵

| 平台 | 设备/系统 | 必测 |
| --- | --- | --- |
| macOS | M1/M2/M3（macOS 13/14/15） | arm64 构建、SPM/native assets、全屏/多 Space、libmpv、shader、tone-map、媒体键、本地包 |
| Android 旗舰 | Snapdragon 8 Gen 2/3、Tensor G3（Android 14/15/16） | gpu-next、硬解、超分、颜色、PiP、120Hz、HDR→SDR |
| Android 中端 | Snapdragon 7 系/天玑 8000（Android 13/14） | gpu、超分效率档、热降级、弱网 |
| Android 低端 | 4GB RAM（Android 12/13） | 1080p 播放、内存、mediacodec_embed、字幕字体 |
| 服务器 | Jellyfin 10.8/10.9/10.10.7（12.x 可选） | 登录/浏览/PlaybackInfo/转码/进度/字幕/版本路由 |

测试服：`http://110.42.96.64:44762`（10.10.7，凭据只放本地环境变量）。实测：番剧库、51 个条目、mp4/h264/aac 与 mkv/h264/hevc/aac、ASS/SRT 多字幕；mkv/h264/aac 可直连；**Trickplay/MediaSegments 未生成**。

样片集：H.264/AAC MP4、HEVC/AC3 MKV、AV1/Opus WebM、10-bit HEVC、HDR10、4K、ASS 特效字幕、PGS 字幕、多音轨、外挂 SRT、TrueHD 音频。

### 6.3 播放体验验收脚本（20 条）

1. 从首页“继续观看”进入，2 次点击内起播。
2. 播放中单击显示/隐藏控制层，3s 自动隐藏。
3. 双击左侧后退 10s，右侧前进 10s，中心暂停。
4. 长按 2x，松手恢复 1x，角标消失。
5. 横滑 seek：时间气泡/缩略图跟随，松手后画面到位，无爆音。
6. 边缘横滑不触发 seek（系统返回优先）。
7. 左半竖滑亮度、右半竖滑音量，HUD 正确。
8. 锁定后仅解锁可用；解锁后控制层恢复。
9. 拖动进度条：暂停预览、松手 seek、恢复原播放状态。
10. 片头按钮出现/点击跳转；自动跳过设置生效。
11. 片尾倒计时出现/取消/自动下一集；间隙 <1s。
12. 切换音轨即时生效；转码时提示并保持位置。
13. 切换字幕/延迟 ±0.5s/样式调整生效；PGS 样式项隐藏；中文不缺字。
14. 开启效率/质量超分，画面变化可感知；关闭恢复；颜色无偏。
15. mediacodec_embed 下超分置灰并说明。
16. 超分掉帧时提示降级；一键关闭。
17. Android 按 Home 进入 PiP，PiP 内播放/暂停/快进可用；后台 30 分钟音频不断。
18. 锁屏/通知媒体控制可用；耳机拔出暂停。
19. macOS 媒体键/菜单栏/键盘快捷键全部可用；全屏独立 Space。
20. 断网 10s 后恢复：自动重连/重试；失败有明确提示与转码选项。

### 6.4 性能与稳定性

- 启动/首帧/seek 打点，Release 模式测量；每次发版跑基线。
- Frame timing（`SchedulerBinding.addTimingsCallback`）统计 jank；播放器页面 jank < 1%。
- 内存/句柄泄漏：反复进出播放器 50 次，内存回到基线 ±10%；Android 长播监控 FD（#1391）。
- 长播 2h：内存/温度/电量曲线；无崩溃；后台 30 分钟音频。
- 弱网：限速 1/3/5 Mbps、丢包 1%/5%、切换 Wi-Fi/蜂窝。
- 崩溃/ANR 监控（若启用）；日志导出包含设备/播放器/服务器信息。
- 颜色：测试图 + 截帧 ΔE 检查（Android GLES 超分）。
- 包体/16KB：AAB 解包检查 .so 对齐与 ABI。

### 6.5 CI

- PR：`dart format --set-exit-if-changed`、`flutter analyze`、`flutter test`。
- 主分支：macOS arm64 debug/release 构建；Android arm64 debug/release 构建；产物归档。
- 发布：暂不发布；仅构建内测包。
- 缓存：pub、Gradle、Flutter、media_kit native-cache（libmpv 下载）、CocoaPods（若回退）。
- 注意：media_kit fork 使用 native assets，需要 C 编译器与网络下载二进制；CI 要允许并缓存。macOS 需要 Apple Silicon runner（或自托管 Mac mini）。

---

## 7. 打包与内测（暂不发布）

### 7.1 macOS

- v1 目标：本地可运行的 arm64 包；开发期 ad-hoc 签名即可。
- 正式分发（后续）：Developer ID Application + `notarytool` + Hardened Runtime + DMG。
- 沙盒/权限：首次访问局域网弹窗文案；下载目录说明（v1 无下载）。
- Mac App Store：暂不考虑。

### 7.2 Android

- v1 目标：arm64 debug/release APK 或 AAB，真机安装。
- 签名：内测可用本地 keystore；Play App Signing 后续再配。
- 16KB 校验、targetSdk 36、前台服务声明、PiP 声明。
- 商店上架：暂不做。

### 7.3 版本与内测

- SemVer：`0.1.0` 起步；构建号递增。
- 内测：直接安装包 + 日志导出；收集手势/超分/字幕反馈。
- 回滚：保留上一版安装包。

---

## 8. 风险与对策

| # | 风险 | 概率 | 影响 | 对策 |
| --- | --- | --- | --- | --- |
| 1 | **Kazumi GPL-3.0** 代码不能用于闭源 | 高 | 高 | 已确认独立实现；只参考行为/公开文档；Anime4K 用 MIT 原文件。 |
| 2 | **media_kit fork 与 Flutter 3.47.8 / AGP 9 / Gradle 9.1 不兼容** | 中 | 高 | M0 双端构建 spike；固定 commit；`PlayerEngine` 抽象；回退上游 1.2.6（放弃 gpu-next）。 |
| 3 | **macOS SPM + native assets** 组合不成立，回退 CocoaPods | 中 | 中 | M0 先验证纯 SPM；失败则接受 CocoaPods；CI 装 CocoaPods/make/curl；缓存 libmpv；本地包先跑通。 |
| 4 | **macOS 最低 13** 损失 12 用户 | 中 | 中 | 已确认接受 13；若后续必须 12，改用上游 media_kit（mpv 0.36，仍可 vo=gpu 超分）并放弃 Android gpu-next 统一版本。 |
| 5 | **Impeller 与视频浮层 abort**（flutter#185506） | 中 | 高 | 已确认基线关闭 Impeller；HUD 禁用 blur；M0 spike 验证是否可开启。 |
| 6 | Android GLES 多 pass 偏色（#1438） | 中 | 高 | 颜色 ΔE 验收；优先 gpu-next（Vulkan）；不达标则限制/关闭。 |
| 7 | Android 后台帧堆积（#1378）/FD 泄漏（#1391） | 中 | 高 | 后台停止视频 Surface；FD 监控；长播测试；异常重建播放器。 |
| 8 | Android 字幕字体缺失（sub-font-provider=none） | 高 | 中 | 随包 CJK 字体 + `sub-fonts-dir`；中文 ASS 验收。 |
| 9 | 超分性能不足/发热 | 高 | 中 | 效率档默认；掉帧/热降级；低电量策略；首次提示；关闭入口显眼。 |
| 10 | macOS libmpv 签名/本地包 | 中 | 中 | v1 先 ad-hoc；正式分发前做 dylib 重签/公证 spike。 |
| 11 | Jellyfin 10.8–10.10 端点/认证差异 | 中 | 高 | 以 10.10.7 为基线；版本路由；Authorization 头 + X-Emby-Token 回退；真机联调。 |
| 12 | HDR/10-bit/AV1/TrueHD 兼容 | 中 | 中 | tone-map SDR；TrueHD 转码；设备能力探测；样片测试。 |
| 13 | 16KB page size / 安装政策 | 中 | 高 | 构建后校验；fork libmpv 1.3.1；CI 检查。 |
| 14 | Forui 缺少播放器控件 | 中 | 低 | 播放器 UI 自绘，使用 Forui token；不强行套组件。 |
| 15 | 手势与系统手势冲突 | 中 | 中 | 边缘留白；可关闭；真机验证；按钮兜底。 |
| 16 | 排期低估 | 中 | 中 | 2 周缓冲；M0/M3 先 spike；砍 P1。 |
| 17 | 自签名 HTTPS/局域网 HTTP | 高 | 中 | 证书指纹确认；cleartext 仅私有地址；ATS 例外；文档说明。 |
| 18 | 许可证/商标 | 中 | 高 | 关于页声明；不暗示官方；法律审查。 |

---

## 9. 决策与待确认

### 已确认（2026-10-26）

1. 应用名 **Sakuga**，包名/Bundle ID **`com.foliage.sakuga`**。
2. **不复制 Kazumi 代码，独立实现**。
3. **暂不发布**（本地/内测包）。
4. Jellyfin **兼容 10.8–10.10**（测试服 10.10.7）；12.x 可选。
5. macOS 最低 **13.0**。
6. **关闭 Impeller**（Skia 基线）。
7. **离线下载不进 v1**。
8. UI 不写注释性/说明性文本，只保留功能文案。

### 仍需确认

1. **设计资源**：是否有现成品牌/图标/字体？还是先用占位？
2. **团队与时间**：单人还是双人？目标内测日期？
3. **遥测/崩溃上报**：是否允许（默认关闭）？是否需要自建？
4. **12.x 适配优先级**：v1 是否必须兼容 12.x，还是 10.8–10.10 优先、12.x 后续？

---

## 附录 A：Kazumi 代码映射（仅行为参考）

| Kazumi 文件 | 作用 | Sakuga 对应 | 复用方式 |
| --- | --- | --- | --- |
| `player_super_resolution.dart` | 超分档位枚举 | `super_resolution_mode.dart` | 重新设计（增加自动/低端兜底） |
| `shader_asset_service.dart` | asset→可写目录 | `shader_repository.dart` | 独立实现（加版本戳/哈希） |
| `player_playback_controller.dart` `setShader` | `change-list glsl-shaders` | `media_kit_engine.setShaderChain` | 按 mpv 文档独立实现 |
| `assets/shaders/*.glsl` | Anime4K | `assets/shaders/` | **可直接使用（MIT）**，保留 LICENSE |
| `player_gesture_detector.dart` | 横滑/竖滑 | `gesture_layer.dart` | 重新设计手势规格 |
| `player_seek_controller.dart` | 交互式 seek | `player_session_controller` + `seek_session` | 借鉴状态机思路 |
| `player_panel_hold.dart` | 面板租约 | `ui/panel_hold.dart` | 借鉴租约模式（独立实现） |
| `player_item_panel.dart` / `player_progress_bar.dart` | 控制层/进度条 | `ui/controls`、`ui/menus` | 重新设计（Forui 风格） |
| `player_keyboard_shortcuts.dart` | 快捷键 | `app/shortcuts.dart` | 按 macOS 习惯重做 |
| `playback_cache_policy.dart` | 缓冲策略 | `player/cache_policy.dart` | 借鉴参数（demuxer-max-bytes 等） |
| `constants.dart` 解码器/渲染器/shader 链 | 常量表 | `platform/capabilities.dart` | 参考取值 |

## 附录 B：MVP 端点清单（10.10 基线）

- 启动：`GET /System/Info/Public`、`POST /Users/AuthenticateByName`（或 Quick Connect）。
- 首页：`GET /UserViews?userId=`（10.8 用 `/Users/{userId}/Views`）、`GET /Items?userId=&filters=IsResumable&sortBy=DatePlayed`、`GET /Items?userId=&sortBy=DateCreated`。
- 浏览：`GET /Items?parentId=...`、`GET /Items/{id}`、`GET /Shows/{id}/Episodes`。
- 播放：`POST /Items/{id}/PlaybackInfo`、`GET /Videos/{id}/stream?static=true` 或 `TranscodingUrl`、`GET .../Subtitles/...`。
- 进度：`POST /Sessions/Playing`、`/Progress`、`/Stopped`；`DELETE /Videos/ActiveEncodings`。
- 增强：`GET /MediaSegments/{id}`（10.10+）、`fields=Trickplay` + `GET /Videos/{id}/Trickplay/{width}/{index}.jpg`（10.9+）。
- P1：`/SyncPlay/*`、`/Sessions/*`、`/Items/{id}/RemoteSearch/Subtitles/*`、`POST /Sessions/Capabilities/Full`。
- 12.x 可选：同一套路由；认证只走 `Authorization: MediaBrowser`；不要用 `api_key`。

## 附录 C：参考资料

- forui_app 模板：`/home/foliage/projects/forui_app`（README、lib、platform 工程）
- 调研报告：`docs/research/template-audit.md`、`kazumi-player.md`、`jellyfin-api.md`、`playback-engine.md`
- 测试服：`http://110.42.96.64:44762`（Jellyfin 10.10.7；凭据只放本地环境变量）
- Kazumi：https://github.com/Predidit/Kazumi （GPL-3.0；播放器/超分参考）
- Anime4K：https://github.com/bloc97/Anime4K （MIT）
- media_kit：https://github.com/media-kit/media-kit （MIT；1.2.6 / video 2.0.1 / libs 1.3.8）
- Predidit media_kit 分支：https://github.com/Predidit/media-kit （MIT；Kazumi 使用，pin 83b7ca6）
- Jellyfin OpenAPI：https://api.jellyfin.org/openapi/jellyfin-openapi-stable.json （12.3.0）；版本化规范 `https://api.jellyfin.org/openapi/stable/jellyfin-openapi-{version}.json`（10.8.13/10.9.11/10.10.7 已验证）
- Jellyfin 认证 gist：https://gist.github.com/nielsvanvelzen/ea047d9028f676185832e51ffaf12a6f
- mpv 手册（glsl-shaders / vo / hwdec / sub-font-provider / sub-fonts-dir）：https://mpv.io/manual/stable/
- Flutter/Forui/Riverpod 文档。

---

## 下一步（建议）

1. 进入 **M0**：从 forui_app 初始化 Sakuga 工程、清理示例、改 `com.foliage.sakuga`、接 media_kit 空播放页、跑通 Android arm64 构建；macOS arm64 在 Mac/CI 上验证。
2. 用测试服 10.10.7 做 **M0 内核 spike**：直连 + Anime4K 效率/质量档 + 掉帧/颜色统计；同时验证 ASS 中文字幕与 `sub-fonts-dir`。
3. 需要你确认剩余 4 个问题（设计资源、团队/时间、遥测、12.x 优先级）后，再锁定 M1 排期。

