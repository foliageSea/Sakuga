# 播放内核与超分可行性（media_kit / mpv）

> **历史调研。** 环境、版本、结论与建议均以调研时点为准；当前使用与开发步骤见[文档索引](../README.md)。

> 目标项目：Jeffyfin（Flutter Jellyfin 客户端，macOS arm64 + Android）。取证日 2026-10-26。
> 本机环境：Flutter 3.47.8 / Dart 3.13.7（`flutter --version`），native assets 已在 stable 默认开启。
> 引用规范：pub.dev 版本号 / 仓库文件:行号 / URL。凡未实测的推断均已标注「需 spike」。

## 0. 摘要（决策级）

1. **内核选 libmpv，但包源必须是 Predidit/media-kit fork 并 pin 提交**：上游 Android 的 libmpv 编译时 `-Dvulkan=disabled -Dlibplacebo=disabled`（mpv 0.36），因此 **上游 Android 根本没有 vo=gpu-next**，而 fork 的 libmpv 是 0.41 + Vulkan/libplacebo/shaderc。
2. **超分只走 mpv `glsl-shaders` + Anime4K（M/VL 两档）**，与 Kazumi 同路径；不引入 libplacebo 自定义 pass，因为 macOS 侧 libmpv 也关了 libplacebo/Vulkan，只有 vo=gpu 一条渲染路径。
3. **Android 必须自带字幕字体**：media_kit Android 初始化即设 `sub-font-provider=none`（严格字体匹配，缺字体会直接不渲染），而 Android 构建的 libass 无 fontconfig。这是本计划最容易踩的字幕坑。
4. **HDR/EDR 不作为承诺**：media_kit 的 macOS 纹理是 CGL/OpenGL + CVPixelBuffer 8bit 合成通路，HDR 相关 issue 长期 open（#615）。计划按「HDR 内容 tone-map 到 SDR」实现。
5. **PiP 与后台播放需自研**：media_kit 无官方 PiP（PR #1410 仍 open），后台播放存在帧堆积/ImageReader 打满的已知问题（#1378）。

## 1. 选型结论表

| 决策项 | 结论 | 依据 | 风险 / 备注 |
|---|---|---|---|
| 播放内核 | libmpv（media_kit） | mpv 手动文档 vo/hwdec/glsl-shaders 能力 | 见 §4 |
| 包来源 | `git: Predidit/media-kit`，ref 固定 `83b7ca63772856e1ea0158916177e136f7b7b0be`，path `./media_kit` 与 `./media_kit_video` | Kazumi `pubspec.yaml:95-104` 同款写法 | fork 与上游 API 有差异，升级需整体同步 |
| 依赖形态 | 只依赖 `media_kit` + `media_kit_video`，**不再引 `media_kit_libs_*`** | fork `media_kit/doc/native_assets.md`（「Remove every media_kit_libs_* dependency」） | 需 C 编译器与 native assets；Flutter 3.47.8 已默认开启 |
| macOS 渲染 | `vo=libmpv`（默认）+ media_kit 自带 CGL OpenGL 3.2 core 纹理 | `media_kit_video` 2.0.1 `platform_video_controller.dart:76-89`；`macos/.../gl/OpenGLHelpers.swift:8-18` | 无 gpu-next（darwin libmpv 关闭 libplacebo/vulkan） |
| macOS 硬解 | `hwdec=auto`（→videotoolbox） | 同上 `:84-89` | HEVC 可用；AV1 仅 M3+ 硬解，需回落软解 |
| Android 渲染 | `vo=gpu`（GLES，`gpu-context=android`）为基线；Android 14+ 且 Vulkan 1.2 设备切 `gpu-next` | Kazumi `player_playback_controller.dart:383-400` | gpu-next 依赖 fork 的 Vulkan 构建 |
| Android 硬解 | `auto-safe`（`hwdec-codecs=h264,hevc,mpeg4,mpeg2video,vp8,vp9,av1`） | `media_kit_video` `android_video_controller/real.dart:160-190` | 硬解+着色器必须走 gpu/gpu-next，mediacodec_embed 不可用 |
| 超分 | Anime4K 效率档(M)/质量档(VL)，`change-list glsl-shaders set` | Kazumi `player_playback_controller.dart:491-520`、`constants.dart:132-150` | 需实测帧预算（§6） |
| 字幕 | libass（ASS/SSA 特效 + PGS/VobSub 位图）+ 自带字体目录 `sub-fonts-dir` | mpv 手册 `--sub-font-provider`、`--sub-fonts-dir` | Android 必须设字体目录（§7） |
| 音频 | 直解 AAC/AC3/EAC3/DTS/FLAC/Opus；TrueHD 走服务端转码 | fork android tag v1.3.1 `buildscripts/flavors/default.sh`：解码器白名单含 `dca`(L130)，仅有 `--enable-demuxer=truehd`(L192) 而**无 truehd 解码器** | 需按 Jellyfin `TranscodingProfiles` 配置 |
| 后台播放 | `audio_service` + 前台服务 `mediaPlayback` | Kazumi `AndroidManifest.xml:57-62` | 需处理视频纹理在后台的帧堆积（#1378） |
| PiP | 自研 platform channel | media_kit PR #1410 仍 open（2026-04-16） | 无官方 API |

## 2. 包与版本（pub.dev API，2026-10-26 查询）

| 包 | 最新版 | 发布时间 | 平台 / 要点 |
|---|---|---|---|
| `media_kit` | 1.2.6 | 2025-12-13 | Dart SDK `>=3.1.0 <4.0.0`；纯 Dart + FFI |
| `media_kit_video` | 2.0.1 | 2025-12-02 | flutter `>=3.7.0`；windows/linux/macos/ios/android/web |
| `media_kit_libs_video` | 1.0.7 | 2025-10-05 | 聚合包：android ^1.3.8 / macos ^1.1.4 / ios ^1.1.4 / windows ^1.0.11 / linux ^1.2.1 |
| `media_kit_libs_macos_video` | 1.1.4 | **2023-09-27** | 两年多未更新；podspec `s.platform = :osx, '10.9'` |
| `media_kit_libs_android_video` | 1.3.8 | 2025-10-05 | gradle 任务下载 4 个 ABI jar；minSdkVersion 16，compileSdk 36，AGP 8.13.0；CHANGELOG「16KB page size support」 |

上游二进制（实测自源码构建脚本，非猜测）：
- macOS：`media_kit_libs_macos_video-1.1.4/macos/Makefile` 下载 `libmpv-xcframeworks_v0.6.0_macos-universal-video-default.tar.gz`；`media-kit/libmpv-darwin-build@v0.6.0/downloads.lock` → **mpv 0.36.0 / ffmpeg 6.0 / libass 0.17.1**。
- Android：`media_kit_libs_android_video-1.3.8/android/build.gradle` 下载 `libmpv-android-video-build@v1.1.7` 的 arm64-v8a / armeabi-v7a / x86_64 / x86 四个 jar；该 tag 的 `buildscripts/include/depinfo.sh` → `v_mpv=78d4374…`（mpv VERSION `0.36.0`）、`v_ffmpeg=6.0`、`v_libass=0.17.1`；`buildscripts/scripts/mpv.sh` → **`-Dvulkan=disabled -Dlibplacebo=disabled`**。

### 2.1 Predidit fork（ref 83b7ca6）改了什么

fork 已是「重写打包 + 升级二进制」的分支，不是小补丁：

| 维度 | 上游 | fork@83b7ca6 |
|---|---|---|
| 二进制分发 | gradle/podspec 下载 jar/xcframework | **Dart build hook（native assets）**，清单 `media_kit/hook/native_bundles.json` |
| Android libmpv | v1.1.7 = mpv 0.36.0，无 Vulkan/libplacebo | **v1.3.1 = mpv 0.41.0**，`libplacebo 1dd0226` + `shaderc` + `-Dvulkan=enabled`，libass 0.17.5 |
| macOS libmpv | v0.6.0（mpv 0.36.0） | **0.6.8（仍 mpv 0.36.0 + ffmpeg 6.0）**，`-Dlibplacebo=disabled`、`-Dvulkan=disabled`（`nix/packages/mk-pkg-mpv/default.nix:148,162`）；带 Kazumi 定制补丁 `ffmpeg-hls-kazumi-combined.patch` 等 |
| 最低 SDK | Dart 2.17 / Android 5.0 | **Dart 3.10 / Flutter 3.38**（`doc/native_assets.md`），android minSdk 21（`media_kit_video/android/build.gradle:35`） |
| Android 纹理 | 仅 SurfaceProducer | 新增 `enableAndroidSurfaceProducer`（默认 true）+ SurfaceTexture 回退（`VideoOutput.java:42-56`、`platform_video_controller.dart:125`） |
| 其它 | — | Windows D3D11 零拷贝、Linux 三缓冲、OHOS、Apple SwiftPM、事件循环原生化、每播放器独立线程 |

**结论**：gpu-next 超分只能靠 fork；同时 fork 也顺带绕开上游 `libs_android_video 1.3.8` 的 gradle 下载故障（issue #1469：构建期下载 jar 返回 HTTP 406，2026-10-22 仍 open）。

## 3. 平台差异表（macOS arm64 vs Android）

| 维度 | macOS arm64 | Android |
|---|---|---|
| libmpv 版本 | 0.36.0（fork darwin 0.6.8，universal arm64+x86_64 xcframework） | 0.41.0（fork android v1.3.1） |
| 可用 vo | `libmpv`（默认，底层 vo_gpu/OpenGL）；**无 gpu-next** | `gpu`（GLES）、`gpu-next`（Vulkan，fork 才有）、`mediacodec_embed` |
| 纹理通路 | CGL OpenGL 3.2 core + CVPixelBuffer（Metal 兼容） | `TextureRegistry.SurfaceProducer`（默认）/ `SurfaceTexture`（回退） |
| 硬解 | `hwdec=auto` → videotoolbox | `auto-safe`/mediacodec，codec 白名单固定 |
| 超分着色器 | glsl-shaders（GLSL 150，vo_gpu 路径） | glsl-shaders（GLES 300 / gpu-next 的 libplacebo hook） |
| 字幕字体 | CoreText provider（系统字体可用） | `sub-font-provider=none` → **必须自带字体** |
| 最低系统 | 项目当前 `MACOSX_DEPLOYMENT_TARGET=12.0`；native assets 生成器写死 `targetMacOSVersion = 13` | Flutter 3.47.8 默认 minSdk 24；fork 插件 21 |
| ABI | universal（arm64 + x86_64） | arm64-v8a / armeabi-v7a / x86_64 / x86 |
| 签名 | App Sandbox + Hardened Runtime + notarize（当前项目仅 sandbox，缺 network.client） | release keystore；16KB page 需 AGP 8.x |
| HDR | 无 EDR 通路，按 SDR tone-map | 未支持（#615） |
| 高刷 | 120Hz 取决于 Flutter 合成器与 CVDisplayLink，需实测 | 取决于设备刷新率与 SurfaceProducer |

## 4. macOS Apple Silicon 要点

- **arm64/universal**：`libmpv-xcframeworks_0.6.8_macos-universal-*` 与上游 v0.6.0 均为 universal（`native_bundles.json` 中 `macos_arm64`/`macos_x64` 指向同一 universal 包），Apple Silicon 原生运行，无 Rosetta。
- **最低系统冲突（必须处理）**：Flutter 3.47.8 的 native assets macOS 生成器 `targetMacOSVersion = 13`（`flutter_tools/lib/src/isolated/native_assets/macos/native_assets.dart:14`），但 app 模板仍是 `MACOSX_DEPLOYMENT_TARGET = 12.0`（`templates/app/macos.tmpl/...project.pbxproj.tmpl:494`；本项目 `macos/Runner.xcodeproj/project.pbxproj:474` 也是 12.0）。用 fork 时需把工程改为 **13.0**，否则链接期会出现「built for newer macOS」告警/失败。
- **entitlements**：本项目 `macos/Runner/Release.entitlements` 目前只有 `app-sandbox`，**缺 `com.apple.security.network.client`**（Release 下无法访问 Jellyfin）；外挂字幕/下载需要 `files.user-selected.read-write`。Kazumi 的做法（`/tmp/kazumi/macos/Runner/Release.entitlements`）可作参照：sandbox + network.client + network.server + downloads/user-selected。
- **JIT 不需要**：`com.apple.security.cs.allow-jit` 仅 Debug（Flutter JIT）需要，Release 不需要。
- **签名/公证**：native assets 打包的 dylib 由 Flutter 在 `macos_assemble.sh embed` 阶段用 app 身份重签（`native_assets.dart:180-200`、`native_assets_host.dart:173-198`，无身份时 ad-hoc `-`）。因此开启 Hardened Runtime 后**一般不需要** `disable-library-validation`；若公证后 dyld 报「code signature invalid」，再补该 entitlement（列为 spike S6）。
- **渲染与色彩**：`vo=libmpv` 走 mpv render API + OpenGL；darwin 构建关闭 libplacebo/Vulkan，所以 gpu-next 专属特性（film grain、部分 PARAM 类型、HDR 直通）不可用。HDR 内容需 `--target-colorspace-hint=no` + tone-mapping 落到 SDR；**不要承诺 EDR**。
- **ProMotion 120Hz**：纹理帧由 Flutter 合成，能否 120Hz 取决于 Flutter macOS embedder 与显示器刷新率；media_kit 侧无 refresh-rate 接口，需实测（S3）。

## 5. Android 要点

- **实现**：libmpv + Flutter 纹理。`VideoOutput.java:46-56`：默认 `createSurfaceProducer()`，可切 `createSurfaceTexture()`。初始化属性序列（`android_video_controller/real.dart:160-190`，顺序敏感）：`vo=null` → `android-surface-size` → `wid=(intptr_t)Surface` → `vo=gpu`；并设 `opengl-es=yes`、`gpu-context=android`、`force-window=yes`、`sub-use-margins=no`、**`sub-font-provider=none`**、`sub-scale-with-window=yes`、`hwdec-codecs=h264,hevc,mpeg4,mpeg2video,vp8,vp9,av1`。
- **vo 能力**：上游 libmpv 无 Vulkan/libplacebo → `gpu-next` 不可用；fork 的 mpv 0.41 带 `libplacebo + shaderc + Vulkan`，且 mpv 主分支存在 `video/out/vulkan/context_android.c`（Vulkan-on-Android 支持）。Kazumi 的判定：SDK ≥ 34 用 gpu-next，否则 gpu（`player_playback_controller.dart:383-400`）。
- **mediacodec_embed 限制**（mpv 手册 `--vo=mediacodec_embed` 节）：直出 Surface，**字幕渲染、OSD、视频滤镜全部不可用**；必须 `hwdec=mediacodec`。Kazumi 明确「不支持超分」并在切档时弹窗阻止（`player_item.dart:857-870`、`constants.dart:129`）。
- **硬解 + 着色器共存**：仅 `vo=gpu`/`gpu-next` + `hwdec=mediacodec`（零拷贝 interop）或 `mediacodec-copy` 可行；Kazumi 的设置页提示「超分需启用硬件解码，不生效时切 gpu」（`super_resolution_settings.dart:37`）。
- **音频**：fork android 默认构建解码白名单含 `dca`(DTS)、aac/ac3/eac3/flac/opus/mp3 等，**不含 truehd/mlp**（`buildscripts/flavors/default.sh`）。→ Jellyfin 端需把 TrueHD 标为需转码。
- **后台/PiP/常亮**：media_kit 无内置 PiP（#1410 open）；后台时 Flutter 不再消费纹理会导致 ImageReader 帧堆积（#1378 open，2026-02-04）；屏幕常亮用 `wakelock_plus`（media_kit_video 已依赖）；`audio_service` 前台服务 + `foregroundServiceType="mediaPlayback"` 需自行声明（本项目 `AndroidManifest.xml` 目前无任何权限/PiP/服务声明）。
- **刘海/挖孔/旋转**：由 Flutter 层处理；需 `configChanges` 已含 orientation/screenSize（本项目已具备），全屏时用 `SystemChrome.setEnabledSystemUIMode`，Android 15 起注意 edge-to-edge 强制。

## 6. 超分可行性

**机制**：mpv `--glsl-shaders` 用户着色器钩子（手册 `--glsl-shader/--glsl-shaders`，"injected at almost arbitrary points"）。注意两点：① 语法未稳定（手册原文 Warning）；② `MAINPRESUB` 阶段在 gpu-next 不存在，按 MAIN 处理（手册 Hookable textures 节）。运行期改档用 `change-list glsl-shaders set|clr`（Kazumi `player_playback_controller.dart:491-520`）。

**Anime4K v4**：shader 文件为 mpv 用户着色器格式，Kazumi 直接打包 9 个 `.glsl`（`assets/shaders/`，含 Clamp_Highlights / Restore_CNN_S|M|VL / Upscale_CNN_x2_S|M|VL / AutoDownscalePre_x2|x4）。官方给出的成本模型：**CNN 每升一档（S→M→L→VL）耗时翻倍，M≈5ms、L≈10ms、VL≈20ms**（Vega64，4K 输出；Anime4K README「Each step in size … doubles the processing time」）。

**GLES 精度风险（Android 关键）**：media_kit issue #1438（open，2026-08-04）记录：GLES 上下文 + libmpv 旧 GPU 渲染器时，2D sampler 被声明为 `precision mediump sampler2D`，多 pass 着色器（Anime4K 类）出现明显偏色。→ Android 上必须做「颜色正确性」验收，不能只看是否变清晰。

**替代/补充方案**：
| 方案 | 可用性 | 说明 |
|---|---|---|
| libplacebo 内置 scaler（ewa_lanczossharp、spline36 等） | macOS/Android 均可（vo=gpu 也有 mpv 自带实现） | 成本极低，无 CNN 质量，作为「低端机兜底档」 |
| FSRCNNX / ravu | 需 gpu-next + libplacebo 自定义 pass | macOS 不可用（darwin 关闭 libplacebo）；Android 仅 fork gpu-next |
| NNEDI3 | mpv 无内置；需着色器或 vapoursynth | 不作计划内方案 |
| MetalFX（macOS 原生） | 与 mpv 纹理通路不兼容 | 不采用 |
| Android 原生超分 | 无通用 API（各家私有） | 不采用 |

**量级判断（需 spike 验证，非实测）**：1080p→4K 单帧预算 16.6ms（60fps）。M 档两 pass ≈10ms（桌面 GPU 参考）在中端骁龙上很可能超预算；VL 档基本只适合旗舰（8 Gen 2+）。计划默认「效率档=M」，质量档需设备分档开关。

## 7. 字幕与音轨

- **libass 已内置**（libass 0.17.1 / 0.17.5），ASS/SSA 特效字幕、PGS/VobSub 位图字幕均可渲染（mpv 手册提到 PGS/DVD/DVB 位图字幕的 `--sub-ass` 相关选项）。
- **字体是硬约束（Android）**：media_kit 设 `sub-font-provider=none`；手册说明 none 会「禁用系统字体，只用内嵌字体/subfont.ttf/fonts 子目录，且缺字体时可能**完全不渲染**」。Android 的 libass 构建无 fontconfig（`dep_libass=(freetype fribidi harfbuzz)`）。→ 必须随包提供字体（如思源黑体/思源宋体子集）并设 `sub-fonts-dir=<应用目录>`；macOS 走 CoreText provider，可用系统字体。
- **外挂字幕**：`sub-add <url|file>`；Jellyfin 字幕可直接用 API 下载 URL 交给 mpv（带 `httpHeaders`），避免自行解析。字幕延迟 `--sub-delay`、位置 `--sub-pos`、缩放 `--sub-scale`、样式覆盖 `--sub-ass-override` 均可用。
- **音轨切换**：`aid` 属性 / media_kit `setAudioTrack`；多音轨与 Jellyfin `MediaStreams` 对齐。
- **Jellyfin 直连 vs 转码决策**（建议内置判定表）：
  | 条件 | 动作 |
  |---|---|
  | 容器 mp4/mkv/webm，视频 h264/hevc/av1/vp9，音频 aac/ac3/eac3/dts/flac/opus | 直连（DirectPlay） |
  | 音频 TrueHD/MLP | 音频转码（Android 无 truehd 解码器） |
  | 视频 10bit HDR 且用户未开 HDR 实验 | 转码为 SDR 或 tone-map（不承诺 EDR） |
  | PGS 位图字幕 + 目标端不支持 | 服务端烧录（Burn-in）或转 SRT |
  | 高码率 4K（>60Mbps）+ 移动网络 | 转码 |

## 8. 风险登记（均来自上游 issue，可复核）

| # | 风险 | 状态/日期 | 对计划的影响 |
|---|---|---|---|
| #1469 | `media_kit_libs_android_video 1.3.8` gradle 下载 jar 返回 HTTP 406 | open / 2026-10-22 | 用上游包会直接构建失败 → 必须 fork |
| #1378 | Android 后台播放帧堆积、ImageReader 打满 | open / 2026-02-04 | 后台策略需 detach/停止视频输出 |
| #1391 | Android HLS 播放 FD 泄漏 ~25/s（Snapdragon 778G） | open / 2026-03-08 | 长播必须监控 FD |
| #615 | HDR 显示异常（Android/iOS） | open / 2023-11-22 | 不承诺 HDR |
| #1438 | GLES + 多 pass 着色器偏色（mediump sampler） | open / 2026-08-04 | Android 超分需颜色验收 |
| #1454 | `NativePlayer.setProperty` 未遵循 async 配置 | open / 2026-09-21 | 属性写入需等待 `waitForPlayerInitialization` |
| #1410 | PiP 一等支持 PR | open / 2026-04-16 | 自研 PiP |
| #966 / #1380 | GLSL 自定义着色器无官方 API | closed / open | 通过 `NativePlayer.command` 注入，属非公开但稳定用法 |

## 9. Spike 清单（8 项，Mac arm64 + Android 真机）

| ID | 平台 | 内容 | 通过标准 |
|---|---|---|---|
| S1 | 双端 | 注入 Anime4K M/VL，`vo-passes` 打印 pass 列表，截帧比对 | 三个 shader pass 均出现在 `vo-passes`；开启/关闭清晰度可辨；**无偏色**（与关闭态色差 ΔE<3） |
| S2 | Android | 探测 Vulkan 1.2 与 `vo=gpu-next` 可用性（`--gpu-api=vulkan --gpu-context=android`），失败回退 gpu | Android 14+ 真机 gpu-next 首帧成功且可播 30 分钟不黑屏；13 及以下自动回退 gpu 无崩溃 |
| S3 | 双端 | 4K HEVC/AV1（含 10bit HDR 样本）硬解 + 超分同开，记录 renderFps/dropped | macOS：4K60 稳定、掉帧<1%；Android 旗舰 4K30 稳定；HDR 样本走 tone-map 后不偏灰/过曝 |
| S4 | Android | 后台播放（audio_service + mediaPlayback 前台服务）与 PiP（自研） | 切后台 30 分钟音频不断、无 ImageReader 告警；PiP 小窗画面正常、可暂停/拖动 |
| S5 | 双端 | 连续播放 3 小时 + 反复 open/dispose 200 次 | RSS 增长 <50MB，FD 数不随时间线性增长（对照 #1391） |
| S6 | macOS | 开启 Hardened Runtime + sandbox，签名→公证→`spctl -a` 安装运行 | notarize 通过；首次启动能拉 Jellyfin API；外挂字幕可选本地文件；无 dyld 签名错误（否则评估 disable-library-validation） |
| S7 | 双端 | ASS 特效字幕（含中日字体）、PGS、外挂 SRT 加载 | 中文不缺字（Android 走 `sub-fonts-dir`）；PGS 位图正确；`sub-delay` 生效 |
| S8 | 双端 | 对 Jellyfin 库样本跑直连/转码判定表 | 直连样本 0 转码；TrueHD/HDR 样本被正确判为转码；起播时间 <2s |

## 10. 实施要点（代码级，可直接落地）

1. `pubspec.yaml`：只加 fork 的两个包（同 commit），移除任何 `media_kit_libs_*`；`hooks.user_defines.media_kit.cache-directory` 可复用下载缓存。
2. macOS 工程：`MACOSX_DEPLOYMENT_TARGET=13.0`；Release entitlements 补 `network.client`、`files.user-selected.read-write`；Release 不保留 `allow-jit`。
3. Android：`minSdk` 24（Flutter 默认）；manifest 增 `INTERNET`、`WAKE_LOCK`、`FOREGROUND_SERVICE_MEDIA_PLAYBACK`、`supportsPictureInPicture`；按 ABI 打包或 app bundle。
4. 播放器初始化顺序（照抄 media_kit 语义）：先 `waitForPlayerInitialization` → 建 `VideoController`（`vo`/`hwdec`/`enableAndroidSurfaceProducer`）→ 设 `sub-fonts-dir` 等属性 → `open(Media(url, httpHeaders: ...))` → 再设 `glsl-shaders`（避免首帧前 VO 未就绪）。
5. 档位开关：效率档 = Restore_M + Upscale_x2_M + AutoDownscalePre_x2；质量档 = Restore_VL + Upscale_x2_VL + AutoDownscalePre_x2/x4（与 Kazumi `constants.dart:132-150` 一致）；mediacodec_embed 下隐藏超分入口。

## 11. 参考来源

- pub.dev API：`https://pub.dev/api/packages/media_kit`（1.2.6）、`.../media_kit_video`（2.0.1）、`.../media_kit_libs_video`（1.0.7）、`.../media_kit_libs_macos_video`（1.1.4）、`.../media_kit_libs_android_video`（1.3.8）
- 上游构建仓库：`https://github.com/media-kit/libmpv-darwin-build`（tag v0.6.0 `downloads.lock`：mpv 0.36.0）、`https://github.com/media-kit/libmpv-android-video-build`（tag v1.1.7 `buildscripts/include/depinfo.sh`、`buildscripts/scripts/mpv.sh`）
- fork：`https://github.com/Predidit/media-kit` @ `83b7ca63772856e1ea0158916177e136f7b7b0be`（`media_kit/hook/native_bundles.json`、`media_kit/doc/native_assets.md`、`media_kit_video/android/src/main/java/.../VideoOutput.java`）
- fork 二进制：`https://github.com/Predidit/libmpv-android-video-build`（main `depinfo.sh`：mpv 0.41.0、libplacebo、shaderc）、`https://github.com/Predidit/libmpv-darwin-build`（tag 0.6.8 `nix/packages/mk-pkg-mpv/default.nix:148,162`）
- mpv 手册：`https://mpv.io/manual/master/`（`--glsl-shaders`、`--vo`、`--gpu-context`、`--hwdec`、`--sub-font-provider`、`--sub-fonts-dir`、`mediacodec_embed`）
- Anime4K：`https://github.com/bloc97/Anime4K`（README 性能模型、`md/GLSL_Instructions_Advanced.md`）
- media_kit issues：#1469、#1378、#1391、#615、#1438、#1454、#1410、#966
- Flutter 3.47.8 本机 SDK：`packages/flutter_tools/lib/src/features.dart:205-212`（native assets 默认开启）、`lib/src/isolated/native_assets/macos/native_assets.dart:14`（targetMacOSVersion=13）
- 参照实现（只读）：`/tmp/kazumi`（pubspec.yaml:95-104、lib/pages/player/controller/player_playback_controller.dart:383-520、lib/utils/constants.dart:129-150、lib/pages/player/player_item.dart:857-870）

## 12. 不确定项（需 spike 或后续调研确认）

1. fork 的 macOS libmpv 仍是 mpv 0.36（无 libplacebo/Vulkan），**macOS 上不存在 gpu-next**；若后续要 macOS 侧更强超分，只能走 vo_gpu 的 glsl-shaders 或换二进制源（需另立调研）。
2. 骁龙 8xx 上 Anime4K M/VL 的真实帧预算无公开实测数据（官方数据来自 Vega64），S3 必须给出设备分档阈值。
3. fork 与 Flutter 3.47.8 + AGP/Gradle 版本的兼容性仅由 fork 文档自述（「Kazumi Android arm64 release 打包」），需在 CI 复现一次。
4. TrueHD/Atmos 在 Android 侧确认不可解（白名单无 truehd），但 DTS-HD MA 是否走 `dca` 全解需实测。
5. macOS 公证后 dylib 签名是否触发 library validation 拒绝，取决于 Flutter 重签链路，S6 给出结论。
