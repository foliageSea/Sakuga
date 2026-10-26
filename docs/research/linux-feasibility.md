# Linux 端可行性验证

> 日期：2026-10-26 · 环境：WSL2 Ubuntu 24.04 x86_64 / Flutter 3.47.6 / GTK3 可用
> 结论：**可以构建并运行，但当前 v1 不作为正式目标平台，工程里没有 linux/ runner。**

## 1. 验证方法

在 `/tmp/sakuga_linux_probe` 复制当前工程（排除 build/.git/.dart_tool），然后：

```sh
fvm flutter create --platforms=linux --project-name sakuga .
fvm flutter pub get
fvm flutter build linux --debug
```

结果：

```text
✓ Built build/linux/x64/debug/bundle/sakuga
```

说明：

- Forui / material_ui / window_manager / media_kit_video / share_plus / file_selector 等依赖均有 Linux 实现。
- media_kit fork 的 `native_bundles.json` 包含 `linux_x64` / `linux_arm64`，构建期会下载 libmpv。
- `flutter build linux` 不受 `flutter test` 在 WSL 上的 native assets 编译问题影响。

## 2. 运行验证

在 WSLg 下直接启动 bundle：

```sh
cd build/linux/x64/debug/bundle
./sakuga
```

应用窗口能创建（Impeller OpenGLESSDF），但 `MediaKit.ensureInitialized()` 因缺少系统多媒体库失败：

```text
Failed to load dynamic library 'libmpv.so.2':
libva-drm.so.2: cannot open shared object file
```

补齐后依次暴露：

| 缺失库 | Ubuntu 包 |
| --- | --- |
| `libva.so.2` / `libva-drm.so.2` | `libva2`、`libva-drm2` |
| `libva-x11.so.2` | `libva-x11-2` |
| `libva-wayland.so.2` | `libva-wayland2` |
| `libvdpau.so.1` | `libvdpau1` |
| `libpulse.so.0` / `libpulsecommon-16.1.so` | `libpulse0` |
| `libsndfile.so.1` | `libsndfile1` |
| `libasyncns.so.0` | `libasyncns0` |
| `libXss.so.1` | `libxss1` |
| `libXv.so.1` | `libxv1` |

普通 Ubuntu 桌面通常已安装这些；WSL2 最小镜像没有。安装命令：

```sh
sudo apt install libva2 libva-drm2 libva-x11-2 libva-wayland2 libvdpau1 \
  libpulse0 libsndfile1 libasyncns0 libxss1 libxv1
```

本机没有 sudo，无法完成全链路运行验证；上述为逐项 `ldd` 得到的缺失列表。

## 3. 当前工程的差距

| 项 | 状态 |
| --- | --- |
| Linux runner | 当前仓库已删除 `linux/`，需要 `flutter create --platforms=linux` 加回 |
| 构建 | 已验证通过 |
| 播放 | media_kit 支持 Linux；需补齐系统多媒体库后验证 |
| 窗口 | `window_manager` 支持 Linux；自绘标题栏已有 Linux 分支（非 macOS 的红黄绿按钮） |
| 快捷键 | 已有 macOS 键盘方案，Linux 可复用，但菜单栏/媒体键需另做 |
| 打包 | 未做 deb/AppImage/Flatpak |
| 测试 | `flutter test` 在 WSL 上仍受 media_kit native assets 阻塞 |
| 发布 | 不在 v1 范围 |

## 4. 建议

- **作为本地开发/调试平台**：成本低，推荐。加回 `linux/`，文档列出系统依赖即可。
- **作为正式第三平台**：需要补 Linux 窗口/快捷键/媒体键、打包、系统依赖说明、测试矩阵，并更新计划范围。

若只是“能在 Linux 上跑起来看 UI/播放”，按第 2 节安装依赖并加回 runner 即可。
