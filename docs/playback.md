# 播放指南

从媒体详情、分集列表或首页「继续观看」进入播放器。顶部可选音轨、字幕、视频超分，以及 Jellyfin / Emby 的播放质量；剧集可在播放器内打开分集列表。各服务器的播放和续播差异见[服务器功能对比](servers.md#功能对比)。

## 播放控制

- **键盘：** 空格播放或暂停，← / → 快退或快进，↑ / ↓ 调整音量，F 切换全屏，Esc 退出全屏。可在播放器菜单的「播放快捷键」分别设置快退和快进秒数，默认各 5 秒，可调范围为 1–600 秒。
- **Android 触屏手势：** 双击播放或暂停；横滑调整进度，左半侧竖滑调节播放器窗口亮度，右半侧竖滑调节音量。
- **带字幕截图：** 通过播放器菜单或 S 键截图；macOS 复制到剪贴板，Android 保存到系统相册，Windows 不提供此功能。

## 播放质量（Jellyfin / Emby）

播放器顶部的「播放质量」可选择「最高画质」（默认，优先直播放）或以下档位：

| 档位 | 视频高度上限 | 码率上限 |
| --- | ---: | ---: |
| 1080p | 1080 | 20 Mbps |
| 720p | 720 | 8 Mbps |
| 480p | 480 | 3 Mbps |
| 360p | 360 | 1 Mbps |

所选档位向服务器同时请求高度和码率上限。能在上限内直播放的源不必转码；超出限制时需由服务器协商可用的转码流，实际结果取决于片源、服务器及账号的转码权限。切换档位会结束当前会话，重新协商并尝试从当前位置播放。切集保留该次播放器使用的档位，重新进入播放器则恢复「最高画质」。手动选择的音轨和字幕不随换档保留；直播放失败后不会自动重试转码，可尝试降低档位。

退出、切集或换档时，客户端会尝试在上报停止后清理服务端转码任务；已协商但未成功进入播放的会话也会尝试清理。

## 缓冲容量

「设置 → 常规 → 缓冲容量」可选「标准」32 MiB（默认）、「较大」128 MiB 或「大」256 MiB，控制前向预读上限；后向缓存上限固定为 32 MiB。设置在下次打开视频、切集或切换播放质量时生效。增大缓冲可能缓解短时网络波动，但无法弥补持续带宽不足；启用磁盘缓存时，也会增加临时磁盘占用。

## Anime4K 视频超分

在播放器顶部的「视频超分」中选择「效率模式」「质量模式」或「关闭超分」（默认）。这是本机的画面处理，不改变服务器传输画质，也不能替代服务端转码。出现卡顿时可改用效率模式或关闭超分。macOS 在启用超分且系统提供利用率计数时可显示 GPU 用量；该数值是整机 GPU 用量，不是播放器单独的占用。

## 字幕

字幕菜单可选「自动选择」、指定轨道或「关闭字幕」。自动策略优先简体中文（含简中双语），其次是不区分简繁的中文，再次是繁体中文；同一级别优先 ASS / SSA。看不到「字幕样式」时，当前轨道可能为 ASS / SSA 或位图字幕：这些格式由原生播放器渲染，普通文本字幕（如 SRT / VTT）才提供应用样式设置。服务器是否提供外挂字幕见[功能对比](servers.md#功能对比)；渲染机制、验收范围及测试见 [ASS / SSA 原生字幕](ass-subtitles.md)。

## 可选联调

从仓库根目录运行，先按 [Jellyfin 联调环境](../tool/jellyfin-test/README.md)或 [Emby 联调环境](../tool/emby-test/README.md)生成相应的测试配置文件。将 `DEVICE_ID` 换成可访问测试服务器的设备 ID。画质测试请在与 Docker 容器同主机的桌面端运行（如 macOS 或 Linux）：测试进程会调用 `docker top` 检查转码任务，容器名称须保留为 `sakuga-jellyfin-test` 和 `sakuga-emby-test`。画质测试可同时传入两份配置；只测试其中一个服务时，可省略另一份配置。缓冲测试仅需要 Jellyfin。

```sh
fvm flutter test integration_test/transcode_quality_test.dart -d DEVICE_ID \
  --dart-define-from-file=tool/jellyfin-test/results/live-config.json \
  --dart-define-from-file=tool/emby-test/results/live-config.json

fvm flutter test integration_test/playback_buffer_test.dart -d DEVICE_ID \
  --dart-define-from-file=tool/jellyfin-test/results/live-config.json
```

- [画质集成测试](../integration_test/transcode_quality_test.dart)：验证直播放、切换转码流后的续播、高度上限协商和服务端转码任务清理。
- [缓冲集成测试](../integration_test/playback_buffer_test.dart)：用 Jellyfin 直播放片源和真实 libmpv 比较 32 MiB 与 128 MiB 设置下的缓存量；具体缓存时长取决于码率和片源大小。
