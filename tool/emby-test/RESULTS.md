# Emby 真实联调结果

验证日期：2026-11-08（Asia/Shanghai）。服务器为官方 emby/embyserver_arm64v8 镜像，版本 **4.9.3.0**，固定镜像 digest 见 [compose.yaml](compose.yaml)。运行平台：Apple Silicon macOS，Docker Desktop linux/arm64。测试使用非管理员账号 sakuga。

## 已通过

实际执行 [原生集成测试](../../integration_test/emby_server_test.dart)，使用应用的 EmbyAuthService、EmbyClient 与 media_kit/libmpv，而非模拟接口。

- 用户名密码登录，查询本人用户信息及电影/剧集媒体库，无需枚举管理员用户列表。
- 媒体分页、类型/分类/年份筛选、搜索、最近添加、随机推荐、电影详情、季/集下钻，以及认证图片读取。
- Big Buck Bunny（MP4，9:56）、Color Sweep（MP4，6:06）、Orbit Grid（MKV，6:06）全部真实播放，视频输出为 320×180。
- 每个视频从 30 秒开始播放，确认时间前进，暂停后拖动到两分钟。
- 每个视频的中英文外部字幕均通过 HTTP 实际读取并在原生播放器加载；MKV 的内封 SubRip 字幕同时成功由 Emby 提供提取流，共三个可提取文本字幕流。
- 播放开始、进度、停止回报；显式写回两分钟位置后，重新读取详情获得 120 秒，并可在继续观看列表找到对应媒体。
- 标记已看后重新读取为已看；取消已看后重新读取为未看。
- 测试结束为三个视频保留两分钟续播进度，方便手动检查。

原生测试输出：

~~~text
EMBY_LIVE_OK movie Big Buck Bunny: native playback, seek, 2 external subtitles, progress and watched state
EMBY_LIVE_OK episode Color Sweep: native playback, seek, 2 external subtitles, progress and watched state
EMBY_LIVE_OK episode Orbit Grid: native playback, seek, 3 external subtitles, progress and watched state
All tests passed.
~~~

## 联调发现并修复

初次真实测试中年份筛选收到 HTTP 404。Emby 4.9.3.0 已不提供此前按 Jellyfin 使用的 /Items/Filters；其自带 Web 客户端使用 /Years，并传入 ParentId、IncludeItemTypes、Recursive、EnableImages、EnableUserData 等范围参数，响应是 Items 中的 Name 字符串。已据真实响应修复 Emby 适配分支并更新单元回归测试，Jellyfin 原接口保留。

## 资源与边界

资源共约 73.37 MB。Blender 完整短片使用 CC BY 3.0 并保留片尾；两集原创测试视频、测试字幕和几何海报为 CC0。精确来源、授权、时长、编码、文件路径和哈希见 [MEDIA.md](MEDIA.md)。中英文字幕是明确标记的测试文字，不是电影官方台词翻译。

本次实际播放使用直接播放链路，未强制验证视频转码、Emby Connect、直播、动态媒体源或 Android 真机。原生测试验证字幕请求和加载成功，不宣称已人工检查每条字幕的视觉排版。服务仅绑定本机回环端口；访问账号与启停命令见 [README.md](README.md)。
