# Linux 端支持记录

> **历史调研。** 环境、版本、结论与建议均以调研时点为准；当前使用与开发步骤见[文档索引](../README.md)。

> 日期：2026-10-26 · 环境：WSL2 Ubuntu 24.04 x86_64 / Flutter 3.47.6 / GTK3 可用
> 结论：**Linux 已作为本地开发/验证平台接入**，可构建并播放；**不作为正式发布目标**。

## 1. 工程接入

- 已加回 `linux/` runner（`flutter create --platforms=linux --project-name sakuga .`）。
- Linux runner 设置：
  - 窗口标题 `Sakuga`；
  - `fl_dart_project_set_enable_impeller(project, FALSE)`，与 macOS/Android 的关闭 Impeller 基线一致。
- 构建：

```sh
fvm flutter build linux --debug
```

结果：`✓ Built build/linux/x64/debug/bundle/sakuga`。

## 2. 系统依赖

media_kit 的 bundled libmpv 依赖系统多媒体库；WSL2 最小镜像需要：

```sh
sudo apt install libva2 libva-drm2 libva-x11-2 libva-wayland2 libvdpau1 \
  libpulse0 libsndfile1 libasyncns0 libxss1 libxv1
```

普通 Ubuntu 桌面通常已安装其中大部分。

## 3. 运行与播放验证

WSLg 下用 X11 + 软件 GL：

```sh
GDK_BACKEND=x11 LIBGL_ALWAYS_SOFTWARE=1 ./build/linux/x64/debug/bundle/sakuga
```

开发播放验证（使用无需凭据的本地测试流；`--dart-define` 的值可能进入构建产物）：

```sh
fvm flutter build linux --debug \
  --dart-define=DEV_START_ROUTE=/player \
  --dart-define=DEV_MEDIA_URL='<direct-play-url>'

GDK_BACKEND=x11 LIBGL_ALWAYS_SOFTWARE=1 ./build/linux/x64/debug/bundle/sakuga
```

实测日志：

```text
DEV_PLAYER url=...
DEV_PLAYING false
DEV_POSITION 0
DEV_PLAYING true
VideoOutput.Resize {width: 1920, height: 1080}
DEV_POSITION 41
...
DEV_POSITION 1335
```

说明：

- `MediaKit.ensureInitialized()` 成功；
- `VideoController` 创建纹理并输出 1920×1080；
- 播放位置持续推进，播放链路可用；
- 默认 Wayland/EGL 组合在 WSLg 下会 segfault（`media_kit: VideoOutput: Got engine EGL display (GLES2)`），改用 X11 + 软件 GL 后稳定。

## 4. 范围与限制

- Linux 仅用于本地开发/验证：不打包 deb/AppImage，不做商店分发。
- 窗口/快捷键/媒体键/打包/测试矩阵不在 v1 范围；后续要正式支持需单独立项。
- `flutter test` 在 WSL 上仍受 media_kit native assets 编译问题阻塞（与 Linux 运行无关）。
- 不要把测试服 token 写入仓库或构建参数。按[当前开发指南](../development.md)使用无凭据的测试流。
