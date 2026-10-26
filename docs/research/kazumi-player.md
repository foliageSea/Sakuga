# Kazumi v2.4.2 播放器与超分实现调研（面向 Flutter Jellyfin 客户端）

调研对象：`/tmp/kazumi`（Predidit/Kazumi，`pubspec.yaml:4` 版本 2.4.2+20402，HEAD `36198d6`，Flutter 3.47.8 / Dart SDK >=3.10）。
本文所有行号为该工作副本内的行号；跨仓库结论（media-kit fork）标注了 raw URL 与 ref。

## 0. 对开发计划有决策影响的结论（先看这 8 条）

1. **超分不是 Flutter 层能力，而是 libmpv 的 `glsl-shaders` 属性**。Kazumi 只做三件事：把 `.glsl` 从 asset 复制到可写目录、拼绝对路径、调 `change-list glsl-shaders set/clr`（`player_playback_controller.dart:484-525`）。移植成本低，**前提是渲染器走 `vo=gpu`/`gpu-next`**。
2. **Android 上 `vo=mediacodec_embed` 与超分互斥**，代码强制降级（`player_playback_controller.dart:403-407` 关超分并强制 `hwdec=mediacodec`；`player_item.dart:859-882` 弹"兼容性提示"）。
3. **Kazumi 在 macOS 与 Android 都关掉了 Impeller**（`macos/Runner/Info.plist:34-35` `FLTEnableImpeller=false`；`android/app/src/main/AndroidManifest.xml:9-11` `EnableImpeller=false`）。HUD 注释给出原因：BackdropFilter/ImageFilter.blur 叠在视频层上会触发 Impeller native abort，见 flutter/flutter#185506（`player_adjustment_hud.dart:154-156,655,871`）。**这是本项目最重要的前置决策点**：视频贴图 + 半透明浮层在 Impeller 下的稳定性。
4. **Android 渲染器选择有 SDK 门槛**：`auto` 在 SDK>=34 用 `gpu-next`（Vulkan），否则 `gpu`（OpenGL），注释明确说避免 Android 13 及以下 Vulkan 支持差导致黑屏（`player_playback_controller.dart:384-397`）。
5. **播放器交互是"手机优先"的极简集**：没有双击快进/快退、没有捏合缩放、没有字幕/音轨菜单、没有旋转按钮。Jellyfin 客户端需要的这些必须自研（见 §5）。
6. **面板不消失靠"租约"（`PlayerPanelHold`）而非布尔标志**：一次性 lease + 引用计数式持有，`canHidePlayerPanel && holds.isEmpty` 才允许自动隐藏（`player_item.dart:964-1004`，`player_panel_hold.dart:6-26`）。该模式建议原样复用。
7. **超分失败是静默的**：`setShader` 整段 `try/catch` 只 `KazumiLogger().w`（`player_playback_controller.dart:522-524`），用户看不到 shader 编译失败。移植时应补 UI 反馈。
8. **依赖 media-kit 的 Predidit fork**（`pubspec.yaml:95-104`，ref `83b7ca63`），fork 新增 `enableAndroidSurfaceProducer` 开关（fork `media_kit_video/lib/src/video_controller/platform_video_controller.dart` 有、upstream main 无）。Kazumi 传 `false`（`player_playback_controller.dart:414`），即走 SurfaceTexture 路径——与"关 Impeller"属同一条技术线。

## 1. 超分调用链（完整）

### 1.1 档位模型
`lib/pages/player/controller/player_super_resolution.dart:1-16`：`off=1 / efficiency=2 / quality=3`（`storageValue` 持久化；`fromStorageValue` 兜底 off，`:28-33`）。只有 3 档，没有自定义 shader 链。

### 1.2 启动时把 shader 从 asset 复制到可写目录
- 入口：`lib/pages/init_page.dart:149` → `copyShadersToExternalDirectory()`（应用初始化阶段，早于播放）。
- 实现：`lib/services/shaders/shader_asset_service.dart:11-50`
  - `AssetManifest.loadFromAssetBundle(rootBundle)` 枚举 asset，筛 `assets/shaders/*.glsl`（`:12-13,23-24`）；
  - 目标目录 `getApplicationSupportDirectory()/anime_shaders`（`:14-15`）；
  - 逐个 `rootBundle.load` → `writeAsBytes`（`:38-40`）；
  - **已存在则跳过**（`:31-35`）→ 升级后 shader 不刷新（坑，见 §8）。
- **为什么不能直接用 asset path**：代码无注释，但实现即答案——libmpv 的 `glsl-shaders` 只接受文件系统路径，而 Flutter asset 在 Android 打包进 APK、在 macOS 打包进 `.app`，不是运行期可寻址的真实文件，必须先落盘。（推断，非注释原文）
- 注册：`lib/core_module.dart:39` 单例；注入 `PlayerController`（`player_controller.dart:40`）。

### 1.3 shader 链定义与拼接
- 质量档 `mpvAnime4KShaders`（`lib/utils/constants.dart:133-140`）：
  `Clamp_Highlights → Restore_CNN_VL → Upscale_CNN_x2_VL → AutoDownscalePre_x2 → AutoDownscalePre_x4 → Upscale_CNN_x2_M`
- 效率档 `mpvAnime4KShadersLite`（`:143-151`）：
  `Clamp_Highlights → Restore_CNN_M → Restore_CNN_S → Upscale_CNN_x2_M → AutoDownscalePre_x2 → AutoDownscalePre_x4 → Upscale_CNN_x2_S`
- 路径拼接 `lib/utils/media.dart:43-50`：逐个 `path.join(dir, name)`，POSIX 用 `:`、Windows 用 `;` 连接（mpv list 属性分隔符规则）。
- 组合语义（用 shader 自带元数据核查）：
  - `Clamp_Highlights.glsl:24,73` 的 `//!DESC` 是 `Anime4K-v4.0-De-Ring-*`（v4.0 里它就是 De-Ring + 高光钳制），放首位去掉振铃/过曝，避免后级 CNN 放大伪影；
  - `Restore_CNN_*.glsl:24` 为 v4.0 Restore（去压缩伪影），必须在 Upscale 之前；
  - `Upscale_CNN_x2_*.glsl:31` 的 `//!WHEN OUTPUT.w MAIN.w / 1.200 > ...`：仅当显示尺寸 > 1.2 倍原生分辨率时才真正 2x 放大；
  - `AutoDownscalePre_x2.glsl:30`：`(OUTPUT/NATIVE < 2.0) && (OUTPUT/NATIVE > 1.2)` 时先降采样一半，让后面的 2x 落在接近屏幕分辨率；`AutoDownscalePre_x4.glsl:30` 对应 2.4x~4x 区间。→ 这套链是"按显示缩放比自动选 1x/2x/4x"的 Anime4K 标准做法，非随意排列。
  - 资产自带 MIT/Unlicense 头（`assets/shaders/LICENSE` 与各文件首行），Anime4K 版本混合 v3.2（Upscale）与 v4.0（Restore/Clamp）。

### 1.4 setShader 实现（关键 40 行）
`lib/pages/player/controller/player_playback_controller.dart:484-525`：

```dart
final pp = currentPlayer.platform as NativePlayer;
await pp.waitForPlayerInitialization;                             // :489
await pp.waitForVideoControllerInitializationIfAttached;          // :490
if (!identical(mediaPlayer, currentPlayer)) return;               // :491-493 竞态保护
efficiency -> pp.command(['change-list','glsl-shaders','set', abs(Lite)]);  // :496-504
quality    -> pp.command(['change-list','glsl-shaders','set', abs(Full)]);  // :506-515
off        -> pp.command(['change-list','glsl-shaders','clr','']);          // :517-519
superResolutionMode = mode;                                       // :521 仅成功后写 observable
```

- **顺序**：必须先等 player 与 videoController 初始化完成，否则 `change-list` 会打到未就绪的 mpv 实例（两个 await 就是为此）。
- **enable/disable 语义**：`set` 是整链替换（幂等，切档不叠加）；`clr` 清空即关闭。
- **与 hwdec/vo 的关系**：`setShader` 本身不检查 hwdec/vo；约束在别处——① `mediacodec_embed` 时直接关超分（`:403-407`）；② 设置页文案要求"超分需要启用硬件解码，若仍不生效请把渲染器切成 gpu"（`super_resolution_settings.dart:37`）。软件解码也能挂 shader，但性能上不推荐。
- **调用时机**：① `createVideoController` 内在 `player.open()` **之前**设置（`:445-450`），mpv 对后续打开的文件生效；② 播放中切档走 `PlayerController.setShader`（`player_controller.dart:292-297`）← 面板菜单（`player_item_panel.dart:634-640`）。
- **失败静默**：`:522-524` 只打 warn，不通知 UI。

## 2. 渲染器 / 硬解约束

| 事实 | 证据 |
|---|---|
| 可选渲染器 `auto/gpu/gpu-next/mediacodec_embed`，UI 描述"mediacodec_embed 功耗最低，不支持超分辨率" | `constants.dart:125-130` |
| `auto`：SDK>=34 → `gpu-next`（Vulkan），否则 `gpu`；理由是避开 Android 13- 的 Vulkan 黑屏 | `player_playback_controller.dart:384-397` |
| `mediacodec_embed` → 强制 `hAenable=true`、`hwdec='mediacodec'`、`superResolutionMode=off` | `:403-407` |
| VideoController 配置：`vo`、`enableHardwareAcceleration`、`enableAndroidSurfaceProducer:false`、`hwdec: hAenable?decoder:'no'`、`androidAttachSurfaceAfterVideoParameters:false` | `:409-418` |
| 硬解码器候选表（mediacodec / mediacodec-copy / videotoolbox / videotoolbox-copy 等） | `constants.dart:96-122`；UI `decoder_settings.dart` |
| 硬解开关默认 true；解码器默认 `auto-safe` | `settings_keys.dart:46-55` |
| fork 里 Android 默认 `vo='gpu'`、`hwdec=auto-safe`；`gpu-next` 时额外设 `gpu-api=vulkan,opengl`；`mediacodec_embed` 需重设 `vid` | fork `media_kit_video/.../android_video_controller/real.dart:151-152,196,66-68` |
| macOS/iOS 默认 `vo='libmpv'`、`hwdec='auto'` | fork `.../native_video_controller/real.dart:120-121` |
| 音画同步用 `af=scaletempo2=max-speed=8`（倍速不变调） | `player_playback_controller.dart:331` |
| Android 音量上限/音频输出：`volume-max=100`，`ao=opensles` 或 `audiotrack` | `:335-348` |

**为什么 MediaCodec 渲染器不支持 shader**（结论，非注释原文）：`vo=mediacodec_embed` 把解码输出直接交给 Android Surface 合成，画面不经过 mpv 的 GPU 渲染管线，因此 `glsl-shaders` 无 hook 可挂；要超分必须走 `vo=gpu/gpu-next`（mpv 内部 ra 管线）才能应用 user shader。代码层面 Kazumi 只做"检测 + 关超分 + 弹窗提示"，没有自动切换渲染器。

## 3. 手势矩阵（重点）

挂载条件：`PlayerGestureDetector` 只在**非桌面且未锁定**时挂载（`player_item.dart:1561-1563`）；桌面端横滑 seek / 竖滑亮度音量全部不存在。

| 手势 | 生效条件 | 行为 | 证据 |
|---|---|---|---|
| 单击 | 触控设备 / 桌面鼠标 | 移动端与触控笔：切换控制栏显隐；桌面鼠标：播放/暂停 | `player_item.dart:491-500`；判定 `player_pointer_interaction.dart:9-14` |
| 双击 | 未锁定 | 桌面鼠标且非 PiP：切全屏；其余（含移动端）：播放/暂停 | `player_item.dart:502-512`；判定 `player_pointer_interaction.dart:16-22` |
| 长按 | 未锁定 | 临时倍速 `longPressPlaySpeed`（默认 2.0x）并显示倍速 HUD，松手恢复 | `player_item.dart:1463-1481,1347-1348`；默认值 `settings_keys.dart:81-85` |
| 横滑 | 移动端 | 交互式 seek：先暂停 → 预览（`delta*180000/width` ms/px）→ 松手 seek 并恢复原播放态 | `player_item.dart:1564-1593`；`player_seek_controller.dart:91-161` |
| 横滑到画面边缘 | 移动端 | "松开取消"：delta 归零，松手不 seek，位置回滚 | `player_gesture_detector.dart:39-43,50-66`；`player_seek_controller.dart:138-141`；HUD 文案 `player_adjustment_hud.dart:742-757` |
| 竖滑（左半屏） | 移动端 + 滑动手势开 | 亮度 `brightness - dy/(height*2)`，clamp 0..1，走 `setApplicationScreenBrightness` | `player_item.dart:1608-1619,1077-1082` |
| 竖滑（右半屏） | 移动端 + 滑动手势开 | 音量 `base - dy/(height*0.03)`，用 `preciseVolume` 累计避免节流误差 | `player_item.dart:1620-1637`；`player_playback_controller.dart:100-101,542-562` |
| 滚轮 | 桌面 | 音量 `-dy/60`，音量 HUD 显示 2s | `player_item.dart:1405-1414,514-523` |
| 悬停 | 桌面 | 鼠标在 `50 < y < h-70` 显示面板（且不重启隐藏计时，避免卡帧） | `player_item.dart:1390-1403,967-976` |
| 进度条按下/拖动 | 全部 | 按下即 seek（recognizer 直接 `resolve(accepted)`）；拖动显示时间气泡（鼠标拖动/悬停才有 bubble，触屏靠中央 HUD） | `player_progress_bar.dart:104-129,214-247,284-302` |
| 捏合缩放 | — | **无**（全目录无 `onScale`） | grep 仅命中 longPress |
| 双击左右两侧快进/快退 | — | **无**（双击一律 播放/暂停 或 全屏） | 同上 |

配套状态机：`PlayerPanelController`（`player_panel_controller.dart:11-56`）持有 `lockPanel / showVideoController / showSeekTime / seekCancelPending / showBrightness / showVolume / showPlaySpeed / brightnessSeeking / volumeSeeking / seekDirection / canHidePlayerPanel`，`reset()` 在退出播放器时统一清态。

## 4. 面板、HUD 与"按住面板不隐藏"

- **HUD 三件套**（均在 `player_item_panel.dart:459-506` 顶部居中）：`PlayerSeekHud`（+/- 偏移量、目标时间/总时长、取消态）、`PlayerSpeedHud`、`PlayerAdjustmentHud`（音量/亮度，200px 宽滑块 + 图标）。HUD 隐藏时不订阅播放 tick（`player_item_panel.dart:462-463` 注释 "Hidden HUDs must not observe playback ticks"）。
- **面板自动隐藏**：`_startHideTimer()` 用 `playerControllerLayerDisappearTime`（默认 4000ms，`settings_keys.dart:563-567`）→ `hideVideoController()`（`player_item.dart:1084-1101`）。显隐由 `AnimationController(300ms)` 驱动 `SlideTransition`（`player_item.dart:1306-1309`、`player_item_panel.dart:529-564`）。
- **"按住面板不隐藏"= 租约**：
  - `acquirePlayerPanelHold()`：`canHidePlayerPanel=false` + 取消隐藏计时 + 显示面板，返回 `PlayerPanelHold`（`player_item.dart:987-1004`）；
  - `release()` 一次性且幂等；最后一个 release 时恢复 `canHidePlayerPanel=true` 并重启计时（`:990-997`、`player_panel_hold.dart:6-26`）；
  - 现成包装：`PlayerPanelHoldMouseRegion`（hover 进出，`player_panel_hold.dart:72-120`）、`PlayerPanelHoldFocusRegion`（文本框聚焦，`:29-69`）、`PlayerPanelHoldMenuAnchor`（菜单展开，`:122-179`）、`PlayerPanelHoldCollectButton`（`:181-228`）；进度条拖动也持有一份（`player_item.dart:681-716`）；
  - 全屏切换/路由销毁时 `_releasePlayerPanelHolds()` 静默释放，防面板永久卡住（`:1014-1023`）。
- **锁定面板**：`lockPanel` 为 true 时顶/底栏与遮罩全部 `Visibility(false)`，只留右侧竖排（截图 + 锁）（`player_item_panel.dart:513-528,985-1023`）；双击/长按/滑动手势同时被禁。
- **键盘**：`PlayerKeyboardShortcuts` 用 `FocusManager.addEarlyKeyEventHandler` 抢在焦点控件前处理（`player_keyboard_shortcuts.dart:57,85-129`），支持 KeyRepeat 做"按住 →"临时倍速（`:119-126`；业务 `player_item.dart:439-468`），默认键位见 `constants.dart:211-230`（空格 / ←→ / N P / M / F / Esc / D / S / K / 1-3 / X / Z）。

## 5. 菜单结构 & 与 Jellyfin 需求差距

- 宽屏底栏（`player_item_panel.dart:686-727`）：弹幕开关 → 超分辨率 → 倍速 → 视频比例 → 选集。
- 顶栏（`:807-982`）：返回 / 标题（可拖动窗口）/ 快进按钮 / 截图（桌面）/ 画中画 / 收藏 / "更多"；紧凑布局把 比例·倍速·超分·一起看 收进 Submenu。
- "更多"还含：弹幕切换、视频详情、远程投屏（DLNA）、外部播放、定时关闭（15/30/60/自定义）。
- 右侧竖条（移动端全屏才出现）：截图 + 锁定；显示条件 `(compact || !fillsWindow) && !lockPanel`（`:513-516`）。
- **Jellyfin 客户端需要但 Kazumi 没有**（必须自研）：字幕轨道选择与样式、音轨选择、章节跳转、音频延迟、旋转/方向锁定、双击左右快进、捏合缩放、A-B 循环、播放队列 UI。

## 6. 设置项清单（键 / 默认值 / UI 位置）

| 设置 | 键 | 默认 | UI |
|---|---|---|---|
| 硬件解码 | `hAenable` | true | `player_settings.dart:251-261` |
| 硬件解码器 | `hardwareDecoder` | `auto-safe` | `decoder_settings.dart`（选项表 `constants.dart:96-122`） |
| 视频渲染器（仅 Android） | `androidVideoRenderer` | `auto` | `renderer_settings.dart` |
| 超分辨率档位 | `defaultSuperResolutionType` | 1（off） | `super_resolution_settings.dart:36-57` |
| 关闭超分提示 | `superResolutionWarn` | false | `super_resolution_settings.dart:58-75` |
| 低内存模式（缓冲） | `LowMemoryMode` | 跟随网络 | `low_memory_mode_settings.dart` |
| 低延迟音频（Android） | `androidEnableOpenSLES` | true | `player_settings.dart:281-295` |
| 后台播放 | `backgroundPlayback` | false | `:308-319` |
| 记忆播放（跳转上次位置） | `playResume` | true | `:320-331`；生效于 `pages/video/video_controller.dart:276-289`（offset 秒传入 `createVideoController(offset:)`） |
| 自动连播 | `autoPlayNext` | true | `:332-343` |
| 自动进入画中画（Android） | `androidAutoEnterPIP` | false | `:344-358` |
| 滑动手势 | `brightnessVolumeGesture` | true | `:384-397` |
| 控制栏消失时间 | `playerControllerLayerDisappearTime` | 4000 | `:506-517`（滑块 1-10s） |
| 默认倍速 / 长按倍速 | `defaultPlaySpeed` / `defaultShortcutForwardPlaySpeed` | 1.0 / 2.0 | `:453-475` |
| 方向键跳转 / 跳过时长 | `arrowKeySkipTime` / `buttonSkipTime` | 10 / 80 | `:476-505` |
| 默认视频比例 | `defaultAspectRatioType` | 1（自动） | `:518-526`；枚举 `player_aspect_ratio.dart:3-24`（自动/裁切/拉伸/4:3） |
| 日志等级 / 调试模式 / 错误提示 | `playerLogLevel` / `playerDebugMode` / `showPlayerError` | 2 / false / - | `:412-448` |

缓冲实现（可直接抄）：`playback_cache_policy.dart:16-17,30-35,51-74`——`demuxer-max-bytes`/`demuxer-max-back-bytes` 在低内存模式（移动数据）下 2MB，否则 1500MB；另设 `demuxer-cache-dir` 指向临时目录以启用硬盘二级缓存（`player_playback_controller.dart:320-323`，注释说明 media-kit 默认路径按 Linux 配置在其他平台失效）。

## 7. 依赖与平台配置

- `media_kit` + `media_kit_video`：git `https://github.com/Predidit/media-kit.git` ref `83b7ca63772856e1ea0158916177e136f7b7b0be`，path `./media_kit` / `./media_kit_video`（`pubspec.yaml:95-104`）；锁定版本 1.1.11 / 1.2.5（`pubspec.lock:1003-1020`）。
- fork 自定义 API（逐文件比对可核查）：
  - `VideoControllerConfiguration.enableAndroidSurfaceProducer`（默认 true）——**upstream main 无此字段**（对比 `https://raw.githubusercontent.com/media-kit/media-kit/main/media_kit_video/lib/src/video_controller/platform_video_controller.dart` 仅含 `androidAttachSurfaceAfterVideoParameters`）；
  - `androidAttachSurfaceAfterVideoParameters`（按 vo 推断默认值）——upstream 亦有；
  - `Player.safeScreenshot()` 是 fork 的兼容包装（fork `media_kit/lib/src/player/native/player/real.dart:1093-1107`，直接转发 `screenshot()`），Kazumi 用于截图（`player_playback_controller.dart:632-639`）；
  - `setProperty` / `command` / `waitForPlayerInitialization` 均为 upstream 已有 API，不是 fork 私有。
- Android：`EnableImpeller=false`（`AndroidManifest.xml:9-11`）、`extractNativeLibs=true`（`:8`，libmpv .so 需要）、`supportsPictureInPicture=true` + `resizeableActivity`（`:17-20`）、`WAKE_LOCK`（`:83`）、`FOREGROUND_SERVICE(_MEDIA_PLAYBACK/_DATA_SYNC)` + audio_service / foreground_task 两个 service（`:55-78`）。**没有** `android:keepScreenOn`，也没有 wakelock 插件——屏幕常亮不靠 Flutter 层，移植时需自行加 `wakelock_plus` 之类。
- macOS：`FLTEnableImpeller=false`（`Info.plist:34-35`）；entitlements 开 `app-sandbox` + `network.client` + 下载目录读写（`macos/Runner/DebugProfile.entitlements`）——沙盒下 shader 目录必须落 `Application Support`，正好对应 §1.2。
- PiP：Android 走自定义 MethodChannel `com.predidit.kazumi/pip`（`lib/services/player/pip_utils.dart:23-107`，含 play_pause / forward / 弹幕 3 个 PiP 动作）；桌面"画中画"其实是 `window_manager` 置顶小窗（`:118-134`），不是系统 PiP。
- 其他与播放相关的 fork 依赖：`audio_service_mpris`、`audio_service_win` 也是 Predidit 的 git 依赖（`pubspec.yaml:36-44`），与播放器无关，可忽略。

## 8. 踩坑与限制（按风险排序）

1. **Impeller 与视频浮层**：Kazumi 两平台都关 Impeller（见 §0-3）。若新项目坚持开 Impeller，HUD/弹窗的 blur / saveLayer 可能 abort，需逐项验证。
2. **shader 升级不生效**：`shader_asset_service.dart:31-35` 只复制不存在的文件，无版本戳/哈希，Anime4K 升级后老用户仍是旧文件。
3. **setShader 静默失败**：`:522-524`；且"关闭提示"开关一旦打开就永久不再提示（`player_item.dart:884-955`）。
4. **质量档性能弹窗是唯一性能防线**：仅 `quality` 触发"可能卡顿"确认（`:884-889`），效率档无提示。
5. **Android 后台预取污染流**：注释说明后台网络被禁后 demuxer 反复重连会把流判成 EOF，故后台时 `cache-secs=0`、`demuxer-readahead-secs=0`，回前台恢复（`player_playback_controller.dart:235-267`）。不照做会出现"切后台回来永久卡住"。
6. **mediacodec_embed 必须重设 `vid`**，否则报 "Could not open codec" 且永不渲染（fork `android_video_controller/real.dart:64-68` 注释）。
7. **桌面端手势缺失**：桌面没有横滑 seek、没有竖滑亮度音量（`player_item.dart:1561`），只有键盘 + 进度条；macOS 上 Esc 在非全屏时是 `windowManager.hide()` 且**排除 macOS**（`player_item.dart:474-481`）。
8. **旋转**：无旋转按钮，全屏切换交给 `videoPageController.fullscreen`（`player_item.dart:958-962`），Android 靠 Manifest `configChanges` 自行处理。
9. **弹幕编辑暂停/恢复的边界**：只恢复"自己造成的暂停"，且要求 `lifecycleState==resumed` 且当前路由在最上层（`player_item_panel.dart:187-209`）——状态机不写清很容易"后台回来自动播放"。

## 9. 可复用代码清单（文件 → 用途 → 移植难度）

| 文件 | 用途 | 难度 |
|---|---|---|
| `lib/services/shaders/shader_asset_service.dart`（51 行） | asset→可写目录复制，可近乎原样复制 | 低（建议加版本戳） |
| `lib/pages/player/controller/player_super_resolution.dart`（34 行） | 三档枚举 + storageValue | 低 |
| `lib/utils/media.dart:43-50` | shader 绝对路径拼接（平台分隔符） | 低 |
| `player_playback_controller.dart:484-525`（setShader） | mpv change-list 调用与竞态保护 | 中（依赖 media_kit NativePlayer） |
| `player_playback_controller.dart:379-418` | vo / hwdec / VideoController 配置与 SDK 分支 | 中 |
| `player_panel_hold.dart`（229 行） | 面板租约 + 4 个包装组件 | 低，**建议复用** |
| `player_seek_controller.dart`（178 行） | 交互式 seek 状态机（暂停→预览→seek→恢复） | 中 |
| `player_gesture_detector.dart`（72 行） | 横滑 seek + 边缘取消 | 低 |
| `player_progress_bar.dart`（370 行） | 自绘进度条 + 拖动气泡 + 无障碍 | 中（可整文件复用） |
| `player_adjustment_hud.dart`（931 行） | seek / 倍速 / 音量亮度 HUD | 高（强依赖主题与动画细节，建议只借鉴结构） |
| `player_keyboard_shortcuts.dart`（194 行） | 早于焦点的键盘分发 + KeyRepeat 长按 | 中 |
| `player_item.dart:1379-1656`（build） | 手势与浮层层级装配参考 | 中（按 Jellyfin 场景裁剪） |
| `playback_cache_policy.dart`（79 行） | demuxer 缓冲策略 | 低 |
| `constants.dart:96-151` | 解码器 / 渲染器 / Anime4K 链常量表 | 低（照抄） |

## 10. 不确定项（未能在本工作副本内证实）

1. **macOS 上 Anime4K 是否真的生效**：Kazumi 在 macOS 用 `vo=libmpv`（fork `native_video_controller/real.dart:120`），代码无平台门控、也无 macOS 成功/失败日志证据，`setShader` 失败只 warn。需在目标机实测 `gpu-next` + Anime4K 的帧率与 shader 编译错误。
2. **`--glsl-shaders` 与硬件解码的严格关系**：代码只体现"mediacodec_embed 不支持"这一硬约束；"必须开硬解"仅来自设置页文案（`super_resolution_settings.dart:37`），代码未强制。mpv 手册对该属性的 vo 限制未核实（未成功抓取手册页）。
3. **fork 相对 upstream 的完整 diff 未获取**：GitHub REST API 触发限流（"API rate limit exceeded"），只能逐文件比对确认 `enableAndroidSurfaceProducer`、`safeScreenshot` 两处为 fork 新增，其余差异未逐一枚举。
4. **Anime4K 官方推荐顺序文档未取到**：`bloc97/Anime4K` 的 `GLSL_Instructions.md` 已 404（README 仅 106 行），故 §1.3 的组合语义是由 shader 自带 `//!WHEN`/`//!DESC` 元数据反推，不是引用官方文档。
5. **Jellyfin 侧基线未对照**：本文只做 Kazumi 侧；与 Jellyfin 官方/第三方客户端（Findroid、Jellyfin Android TV 等）的手势与菜单基线对比需另一份调研。
