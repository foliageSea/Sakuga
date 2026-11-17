# ASS / SSA 原生字幕

## 实现

播放器启用锁定 media_kit 的 libass 后端。ASS/SSA 和位图字幕由 mpv 绘制；SRT/VTT 等普通文本仍使用应用字幕层，保留字号、阴影、背景和位置设置。原生字幕时隐藏普通文本层和播放器菜单中的样式入口，避免重复字幕或无效设置。

- 使用 `sub-ass-override=no` 尊重字幕原始样式，开启 `embeddedfonts` 以使用容器字体附件。
- Android 初始化提供 MiSans 字体资产及字体 family；播放前继续配置已落地的字体目录。单一回退字体不保证恢复缺失专用字体的原始外观。
- 自动选轨和外部字幕通过实际 mpv sid/codec 判断渲染方式；元数据尚未就绪时保守保留原生渲染。
- 字幕查询串行执行，后续切换、切集和销毁使旧查询失效。
- 「自动」交给 mpv 重新选轨，不是「恢复关闭前的字幕」，也没有额外实现 ASS 优先策略；同一视频有 ASS 与 SRT/VTT 时，重新选择自动可能改选普通文本轨道。需要保留特效时，请明确选择菜单中的 ASS/SSA 轨道。
- 原生字幕截图使用 `includeLibassSubtitles=true`；普通文本截图保留视频帧与 Flutter 字幕合成。

## 自动验证

```sh
fvm flutter test test/player_subtitle_rendering_test.dart test/player_subtitles_test.dart test/player_screenshot_test.dart
```

原生集成测试无需媒体服务器，运行时生成黑色视频、带定位/颜色/移动效果及中日文字的 ASS，以及 SRT 字幕。它检查截图像素中的红色上部文本、绿色移动文本、无字幕帧，以及 ASS→关闭→重选同一条数字 ID 轨道（重复两次）、ASS→SRT→关闭字幕的切换。关闭后重选 ASS 时同时检查 `sid`、`sub-ass`、`sub-ass-override`、`sub-visibility`，确保原始样式恢复。它不能代替字体字形、复杂卡拉 OK 和真实番剧的人工验收。

```sh
fvm flutter test integration_test/player_ass_test.dart -d macos --dart-define=ASS_NATIVE_TEST=true
# Android：把 macos 换成 flutter devices 返回的设备 ID
```

WSL/Linux 使用现有的本地运行依赖及软件 GL：

```sh
LD_LIBRARY_PATH="$HOME/.cache/sakuga/linux-deps/root/usr/lib/x86_64-linux-gnu:$HOME/.cache/sakuga/linux-deps/root/usr/lib/x86_64-linux-gnu/pulseaudio${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}" \
GDK_BACKEND=x11 LIBGL_ALWAYS_SOFTWARE=1 \
fvm flutter test integration_test/player_ass_test.dart -d linux --dart-define=ASS_NATIVE_TEST=true
```

## 本次验证记录（2026-11-09）

- `flutter analyze --no-pub`：通过，无诊断。
- 8 个播放相关测试文件：61 项通过，包含 12 项新建渲染控制器测试。
- WSL/Linux 真实 libmpv 原生集成测试：通过（exit 0）。验证 ASS 原始颜色和上部定位、移动动画的像素位置变化、截图是否含原生字幕，以及切换普通 SRT / 关闭字幕。
- Android arm64 debug APK：构建通过；未连接 Android 真机。当前主机不支持 macOS 实测。
- 全量单元/组件测试：398 项通过、8 项失败。隔离导出未修改的 HEAD（`6be8ba7`）并使用同一依赖锁复跑对应三个测试文件，得到 26 项通过、相同 8 项失败：设置页溢出、macOS/Windows/Linux 鼠标及触控板滑动、媒体库 Hero 动画。因此这些为基线问题，本次未修复，也不把全量结果标记为通过。

## 关闭后重新启用排查（2026-11-17）

- 关闭后明确重选同一 ASS 轨道：WSL/Linux 真实 libmpv 测试通过，连续两次恢复后仍保留颜色、定位及原生渲染；没有复现字幕自身变成普通文本。
- 单元/组件测试 34 项通过，新增 ASS/SSA 有/无轨道元数据的关闭再开启回归，以及自动选中其他普通文本轨道的分流测试。
- 此次只增加测试与行为说明，未修改自动选轨语义或播放器运行逻辑；不能据此代替用户片源及 macOS/Android 的现场验证。

## 仍需目标设备人工验收

- macOS / Android 内封与外部 ASS、SSA；切换回 SRT/VTT 和关闭字幕。
- 中文、日文、MKV 内嵌专用字体、缺失字体回退。
- 定位、多行、多图层、动画、卡拉 OK；横竖屏、全屏、截图。
- Jellyfin / Emby 服务端转码后的字幕交付（若已被转为普通文本或烧录，客户端无法恢复丢失的 ASS 样式）。
