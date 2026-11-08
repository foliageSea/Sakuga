# Jellyfin API 与 Flutter 客户端生态调研（Jeffyfin 后端接入）

> 调研时间 2026-10-26。结论均可核查：OpenAPI 路径、官方发布说明、jellyfin-web 源码行号、pub.dev 元数据。
> 前提修正：**Jellyfin 当前 stable 已是 12.3（2026-10-23 发布）**，不是 10.10。10.11 起废弃、12.0 起移除了一批老认证方式与路由（§9），直接决定 HTTP 层怎么写。

## 0. 结论摘要（对开发计划影响最大的 7 条）

1. **不要用 `api_key` 查询参数**（12.0 已移除）。唯一推荐：`Authorization: MediaBrowser Token="…", Client="…", Device="…", DeviceId="…", Version="…"`；头不可用时才用 `ApiKey` 查询参数（§2.2）。mpv 支持全局请求头，所以 token 可以不进 URL。
2. **mpv 全能力直连是默认路径**：只调一次 `POST /Items/{id}/PlaybackInfo`，DeviceProfile 声明"几乎全支持"；`SupportsDirectPlay` 为真走 `/Videos/{id}/stream?static=true`，否则**原样使用服务器返回的 `TranscodingUrl`**（12.x 已把 HLS 控制器从规范隐藏，自己拼 master.m3u8 有风险）。
3. **Jellyfin 没有 refresh token**：`AuthenticationResult` 只有 `AccessToken`，401 只能重新登录，不要设计"静默刷新"（§2.4）。
4. **deviceId 必须按用户唯一**：服务端一个 deviceId 只允许一个 token；多用户同机必须 `deviceId = hash(设备ID + 用户名)`，否则后登录者顶掉前者（官方 gist）。
5. **进度上报用 `/Sessions/Playing*`，不要用 `/PlayingItems/*`**（10.11 废弃、12.0 移除）；间隔参考 jellyfin-web 的 10 秒。
6. **Dart 有可用 SDK**：`dart_jellyfin` 0.3.1（2026-10-11，BSD-3，对齐 Jellyfin 12.2，覆盖 PlaybackInfo/DeviceProfile/Trickplay/SyncPlay/WebSocket）是唯一活跃完整选项，可作主依赖或 fork 基线；`jellyfin_dart` 停在 10.11 生成版（2025-10-22），不建议。
7. **兼容矩阵要覆盖 10.8 / 10.9 / 10.10 / 12.x**：视图与用户数据端点在 10.9 发生迁移（`/Users/{userId}/Views` → `/UserViews` 等），建议做"版本探测 + 路由降级"，不要写死一套。

## 1. 规范来源

| 用途 | URL |
|---|---|
| 当前 stable 规范（今天 = 12.3.0，1.9MB） | https://api.jellyfin.org/openapi/jellyfin-openapi-stable.json |
| 按版本取（10.8.13 / 10.9.11 / 10.10.7 均实测 200） | `https://api.jellyfin.org/openapi/stable/jellyfin-openapi-{version}.json` |
| 下一代（今天 = 13.0.0） | https://api.jellyfin.org/openapi/jellyfin-openapi-unstable.json |
| 认证方式权威说明（官方维护者 gist） | https://gist.github.com/nielsvanvelzen/ea047d9028f676185832e51ffaf12a6f |
| 12.0 发布说明（含 Client Development Changes） | https://jellyfin.org/posts/jellyfin-release-12.0 |
| 10.11 发布说明 | https://jellyfin.org/posts/jellyfin-release-10.11.0 |

建议把版本化 JSON 下载进仓库，用 `openapi-generator`/`json_serializable` 生成模型。**只信规范里列出的端点**——12.0 原话："if an endpoint is not listed in the OpenAPI specification it should not be used"。
时间刻度（`releases.atom` 实测）：10.11.0 = 2025-10-19，12.0 = 2026-09-07，12.2 = 2026-10-05，12.3 = 2026-10-23。

## 2. 认证

### 2.1 用户名密码登录
`POST /Users/AuthenticateByName`（10.10.7 与 12.3.0 规范均存在，operationId `AuthenticateUserByName`）

请求体 `AuthenticateUserByName` 只有两个字段：
```json
{ "Username": "alice", "Pw": "secret" }
```
响应 `AuthenticationResult`（**没有顶层 UserId**）：
```json
{ "User": { "Id": "8f2c…", "Name": "alice", "ServerId": "d5b1…", "Policy": {…} },
  "SessionInfo": { "Id": "…", "DeviceId": "…", "Client": "Jeffyfin", "PlayState": {…} },
  "AccessToken": "0381cf931f9e42d79fb9c89f729167df", "ServerId": "d5b1…" }
```
落地：`userId = body.User.Id`，`token = body.AccessToken`。baseUrl + token + userId + serverId + deviceId 构成"服务器档案"，多服务器/多用户就是档案列表。
登录请求本身也要带客户端信息头：`Authorization: MediaBrowser Client="Jeffyfin", Device="MacBook Pro", DeviceId="<hash>", Version="0.1.0"`。

### 2.2 鉴权传输（12.0 是分水岭）
- 首选：`Authorization: MediaBrowser Token="…", Client="…", Device="…", DeviceId="…", Version="…"`（键大小写敏感、值必须双引号、建议 URL 编码）。
- 备用：查询参数 `ApiKey=<token>`（官方："仅当头不可能时"，且不要与头同时用）。
- **12.0 已移除**：查询 `api_key`、头 `X-Emby-Token` / `X-MediaBrowser-Token` / `X-Emby-Authorization`；同时删除 `/emby/`、`/mediabrowser/` 前缀路由。依赖它们的旧库在 12.x 上会 401。
- mpv 侧可用 `--http-header-fields=Authorization: MediaBrowser Token="…", Client="Jeffyfin", Device="Mac", DeviceId="…", Version="0.1.0"`，对 HLS 播放列表内所有请求生效 → **Jeffyfin 不需要把 token 放进 URL**（也避免反代日志泄露）；Flutter 的 `Image.network(headers:)` 同理。

### 2.3 Quick Connect（可选，TV/输入不便场景）
```text
POST /QuickConnect/Initiate                     → QuickConnectResult{Secret, Code, Authenticated:false}
GET  /QuickConnect/Connect?secret=…             → 轮询到 Authenticated:true（未授权时 404）
POST /Users/AuthenticateWithQuickConnect        body {"Secret":"…"} → AuthenticationResult
```
schema：`QuickConnectResult{Authenticated,Secret,Code,DeviceId,DeviceName,AppName,AppVersion,DateAdded}`、`QuickConnectDto{Secret required}`。**12.0 删除了 `GET /QuickConnect/Initiate`**（原为 POST 别名）→ 只用 POST。

### 2.4 Token 生命周期与 401
- 无 refresh token → 长期 access token，只能 `POST /Sessions/Logout` 主动失效。
- 401 处理：拦截器标记该档案失效 → 引导重登；**不要**自动重试登录循环（会撞 deviceId 单 token 限制）。
- 项目存储策略：token、API 密钥、baseUrl、userId、deviceId、用户名统一使用 `shared_preferences` 持久化到服务器档案，供“最近服务器”列表及会话恢复；密码不持久化。

## 3. 浏览

| 目的 | 端点（12.3.0 规范实测） | 关键参数 |
|---|---|---|
| 首页分区 | `GET /UserViews` | `userId, includeExternalContent` |
| 列表/搜索/筛选 | `GET /Items` | `userId, parentId, recursive, includeItemTypes, excludeItemTypes, filters, sortBy, sortOrder, fields, startIndex, limit, searchTerm, ids, imageTypeLimit, enableImages, enableUserData, enableTotalRecordCount` |
| 详情 | `GET /Items/{itemId}` | `userId, fields` |
| 剧集 | `GET /Shows/{seriesId}/Episodes` | `userId, season, seasonId, isMissing, adjacentTo, fields` |
| 相似 / 人物 / 建议 | `GET /Items/{itemId}/Similar`、`GET /Persons`、`GET /Search/Hints` | `limit, fields` / `searchTerm` / `searchTerm(必填)` |
| 用户数据 | `GET /UserItems/{itemId}/UserData` | `userId` |
| 已看 / 收藏 | `POST` 或 `DELETE` `/UserPlayedItems/{itemId}`、`/UserFavoriteItems/{itemId}` | `userId, datePlayed` |
| 图片 | `GET /Items/{itemId}/Images/{imageType}/{imageIndex}` | `maxWidth, maxHeight, quality, tag, fillWidth` |
| 主题曲 | `GET /Items/{itemId}/ThemeMedia` | `userId, inheritFromParent` |

- `filters` 枚举 `ItemFilter`：`IsFolder, IsNotFolder, IsUnplayed, IsPlayed, IsFavorite, IsResumable, Likes, Dislikes, IsFavoriteOrLikes`。
- `fields` 中与项目相关：`Chapters, Trickplay, MediaSources, MediaStreams, Overview, People, Genres, ProviderIds, PrimaryImageAspectRatio, Path`。
- 图片必须带 `tag=<ImageTags[type]>`，否则缓存无法失效；`imageType` 常用 `Primary, Backdrop, Logo, Thumb, Banner`。
- 示例（继续观看）：`GET /Items?userId={uid}&recursive=true&includeItemTypes=Movie,Episode&filters=IsResumable&sortBy=DatePlayed&sortOrder=Descending&fields=MediaSources&imageTypeLimit=1&limit=24`
- 响应 `BaseItemDtoQueryResult{Items[], TotalRecordCount, StartIndex}`；`BaseItemDto` 关键字段：`Id, Name, Type, SeriesId, SeasonId, IndexNumber, ParentIndexNumber, RunTimeTicks, UserData{PlaybackPositionTicks,Played,IsFavorite}, ImageTags{Primary}, BackdropImageTags[], MediaSources[]`。

**10.8 → 10.9 端点迁移（必须兼容）**：`/Users/{userId}/Views`→`/UserViews?userId=`；`/Users/{userId}/FavoriteItems/{id}`→`/UserFavoriteItems/{id}?userId=`；`/Users/{userId}/PlayedItems/{id}`→`/UserPlayedItems/{id}?userId=`；用户数据→`/UserItems/{itemId}/UserData`。依据：`spec-10.8.13.json`(338 paths) 与 `spec-10.9.11.json`(308 paths) 的 paths 键差异。实现：用 `GET /System/Info/Public` 的 `Version` 判主版本，<10.9 走旧路由。

## 4. 播放协商（最关键）

### 4.1 请求 / 4.2 响应
`POST /Items/{itemId}/PlaybackInfo`，query 与 body 同名字段（query 优先）：
```http
POST /Items/{itemId}/PlaybackInfo?userId={uid}&startTimeTicks=0&maxStreamingBitrate=120000000
     &mediaSourceId=…&audioStreamIndex=1&subtitleStreamIndex=3
     &enableDirectPlay=true&enableDirectStream=true&enableTranscoding=true
```
body `PlaybackInfoDto`：`UserId, MaxStreamingBitrate, StartTimeTicks, AudioStreamIndex, SubtitleStreamIndex, MaxAudioChannels, MediaSourceId, LiveStreamId, DeviceProfile, EnableDirectPlay, EnableDirectStream, EnableTranscoding, AllowVideoStreamCopy, AllowAudioStreamCopy, AlwaysBurnInSubtitleWhenTranscoding`。
响应 `PlaybackInfoResponse{MediaSources[], PlaySessionId, ErrorCode(NotAllowed|NoCompatibleStream|RateLimitExceeded)}`。
`MediaSourceInfo` 要读的：`Id, Container, Bitrate, RunTimeTicks, SupportsDirectPlay, SupportsDirectStream, SupportsTranscoding, TranscodingUrl, TranscodingSubProtocol(http|hls), TranscodingContainer, DefaultAudioStreamIndex, DefaultSubtitleStreamIndex, MediaStreams[], RequiredHttpHeaders`。
`MediaStream`：`Index, Type(Audio|Video|Subtitle|EmbeddedImage), Codec, Language, IsDefault, IsForced, IsExternal, IsTextSubtitleStream, SupportsExternalStream, DeliveryMethod(Encode|Embed|External|Hls|Drop), DeliveryUrl, Width/Height, Channels, VideoRangeType`。
**`MediaStream.DeliveryUrl` 是服务器拼好的字幕地址**，比自己拼 `/Videos/{id}/{msId}/Subtitles/{index}/Stream.{format}` 更稳。

### 4.3 给 mpv 的 DeviceProfile（可直接落地）
参考 jellyfin-web `src/scripts/browserDeviceProfile.js`（https://raw.githubusercontent.com/jellyfin/jellyfin-web/master/src/scripts/browserDeviceProfile.js）：DirectPlay 组装 L782-798（`mp4,m4v`/`mkv`）；TranscodingProfiles L869 起，HLS 两条 L912-936(fMP4) 与 L938-960(TS)；SubtitleProfiles L1611-1650；CodecProfiles 的 AudioChannels/IsSecondaryAudio 条件 L1000-1070。
```json
{
  "Name": "Jeffyfin-mpv", "MaxStreamingBitrate": 120000000, "MaxStaticBitrate": 120000000,
  "DirectPlayProfiles": [
    { "Container": "mkv,webm,mp4,m4v,mov,ts,m2ts,avi,flv,3gp", "Type": "Video",
      "VideoCodec": "h264,hevc,av1,vp9,vp8,mpeg2video,mpeg4,vc1,msmpeg4",
      "AudioCodec": "aac,ac3,eac3,dts,truehd,flac,opus,vorbis,mp3,alac,pcm" },
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
要点：mpv 能吃 PGS/ASS，字幕全部 `External`（服务器只提取、不烧录），避免"字幕触发转码"（官方 Codec Support 文档明确字幕可能导致 Direct Stream 或烧录转码）；`MaxStreamingBitrate` 局域网设大，远端再下调；实测不支持某编码才从 DirectPlayProfiles 移除（一上来保守会永远转码）。

### 4.4 取流 URL
- 直连：`GET /Videos/{itemId}/stream?static=true&mediaSourceId={msId}&playSessionId={psid}`（`/Videos/{itemId}/stream.{container}` 为显式容器版本）。
- 转码/重封装：**`TranscodingUrl`（相对路径）+ baseUrl，原样使用**；dart_jellyfin README §18.2 原文："the server built it: use it as it is"。
- 外挂字幕：`GET /Videos/{itemId}/{mediaSourceId}/Subtitles/{index}/Stream.{format}`（`srt/ass/vtt/sup/sub`），或直接用 `DeliveryUrl`。
- 音频直连：`GET /Audio/{itemId}/stream?static=true`。

## 5. 进度与状态上报

| 端点 | body schema | operationId |
|---|---|---|
| `POST /Sessions/Playing` | `PlaybackStartInfo` | `ReportPlaybackStart` |
| `POST /Sessions/Playing/Progress` | `PlaybackProgressInfo` | `ReportPlaybackProgress` |
| `POST /Sessions/Playing/Stopped` | `PlaybackStopInfo` | `ReportPlaybackStopped` |

共同字段（PascalCase）：`ItemId, SessionId, MediaSourceId, PlaySessionId, PositionTicks, IsPaused, IsMuted, VolumeLevel, CanSeek, PlayMethod(Transcode|DirectStream|DirectPlay), RepeatMode(RepeatNone|RepeatAll|RepeatOne), PlaybackOrder, AudioStreamIndex, SubtitleStreamIndex, PlaybackStartTimeTicks, NowPlayingQueue`；Stop 另有 `Failed`。
```json
{ "ItemId": "8f2c…", "PlaySessionId": "3c0d…", "MediaSourceId": "8f2c…",
  "PositionTicks": 12340000000, "IsPaused": false, "IsMuted": false,
  "PlayMethod": "DirectPlay", "CanSeek": true, "RepeatMode": "RepeatNone", "VolumeLevel": 80 }
```
- **Ticks = 100ns**：`ticks = ms * 10000`，`秒 = ticks / 10_000_000`。
- 频率：jellyfin-web `src/components/playback/playbackmanager.js` L3351 `setInterval(onPlayerProgressInterval.bind(player), 10000)` → 10s；建议暂停/seek/退出立即补报。
- 失败容忍：三个端点均返回 **204 无 body**；上报 fire-and-forget，不阻塞 UI，失败最多重试 1 次；Stopped 用 `unawaited` 保证退出不卡。
- **`/PlayingItems/{itemId}`、`/PlayingItems/{itemId}/Progress` 是 10.11 起 deprecated 的旧接口，12.x 规范已不存在**（10.10.7 规范中 `OnPlaybackStart` 与 `ReportPlaybackStart` 并存）。
- 能力上报：`POST /Sessions/Capabilities/Full`，body `ClientCapabilitiesDto{PlayableMediaTypes, SupportedCommands[], SupportsMediaControl, SupportsPersistentIdentifier, DeviceProfile}`；登录后调一次，Dashboard 才会显示"可远程控制"。
- 10.11+ 服务端可能返回 **503 + `Retry-After`**（启动/重启中），HTTP 层按头重试。

## 6. 增强播放

| 功能 | 端点 / 字段 | 版本 |
|---|---|---|
| 进度条缩略图 | `fields=Trickplay` → `BaseItemDto.Trickplay` = `{"320":{Width,Height,TileWidth,TileHeight,ThumbnailCount,Interval,Bandwidth}}`；`GET /Videos/{itemId}/Trickplay/{width}/{index}.jpg?mediaSourceId=`；`GET /Videos/{itemId}/Trickplay/{width}/tiles.m3u8` | 10.9+ |
| 片头/片尾跳过 | `GET /MediaSegments/{itemId}?includeSegmentTypes=Intro,Outro` → `MediaSegmentDtoQueryResult{Items:[{Id,ItemId,Type,StartTicks,EndTicks}]}`，Type=`Unknown,Commercial,Preview,Recap,Outro,Intro` | **10.10+** |
| 章节 | `fields=Chapters` → `Chapters[]{StartPositionTicks,Name,ImageTag}` | 全版本 |
| SyncPlay | `/SyncPlay/New, Join, Leave, List, Ping, Ready, Buffering, Seek, Pause, Unpause, Stop, NextItem, PreviousItem, Queue, SetNewQueue, SetPlaylistItem, RemoveFromPlaylist, MovePlaylistItem, SetRepeatMode, SetShuffleMode, SetIgnoreWait`（22 条） | 10.8+ |
| 远程控制 | `GET /Sessions`→`SessionInfoDto[]{PlayState{PositionTicks,CanSeek,IsPaused,PlayMethod,VolumeLevel}}`；`POST /Sessions/{id}/Playing?playCommand=PlayNow&itemIds=`；`POST /Sessions/{id}/Playing/{command}`（Stop/Pause/Unpause/NextTrack/PreviousTrack/Seek/Rewind/FastForward/PlayPause）；`POST /Sessions/{id}/Message` | 全版本 |
| 离线下载 | `GET /Items/{itemId}/Download`（原文件流，需 Download 权限）；实践多用 `/Videos/{id}/stream?static=true` + Range 断点续传自管 | 全版本 |

SyncPlay 的实时命令依赖 WebSocket（`SessionsMessage`/`SyncPlayCommandMessage`/`GeneralCommandMessage`）。MVP 可不做，但架构上留"事件总线"位置。

## 7. 转码
- `TranscodingUrl` 常见参数（12.3.0 规范 `/Videos/{itemId}/master.m3u8` 的 query 列表，10.x 适用）：`MediaSourceId, DeviceId, PlaySessionId, VideoCodec, AudioCodec, VideoBitrate, AudioBitrate, MaxWidth/MaxHeight, StartTimeTicks, SubtitleStreamIndex, SubtitleMethod, SegmentContainer, SegmentLength, MinSegments, TranscodeReasons, Context=Streaming, EnableAdaptiveBitrateStreaming, EnableTrickplay, AlwaysBurnInSubtitleWhenTranscoding`。
- `TranscodeReasons`（schema `TranscodeReason`）可用于 UI 提示与降级诊断：`ContainerNotSupported, VideoCodecNotSupported, AudioCodecNotSupported, SubtitleCodecNotSupported, AudioIsExternal, VideoProfileNotSupported, VideoResolutionNotSupported, VideoBitDepthNotSupported, VideoFramerateNotSupported, AudioChannelsNotSupported, ContainerBitrateExceedsLimit, …`。
- HLS 形态：10.x 有 `/Videos/{id}/master.m3u8`、`main.m3u8`、`/Videos/{id}/hls/{playlistId}/stream.m3u8`；**12.0 "HLS controllers are hidden from the specification"**，12.3.0 规范只剩 `/Videos/{itemId}/stream` 与 `stream.{container}` → 更说明"只用服务器给的 TranscodingUrl"。
- fMP4 vs TS：`TranscodingProfiles` 里 `Container:'mp4'`+`Protocol:'hls'` 即 fMP4；mpv 两者都能播，TS 兼容性更好，fMP4 更利于 hevc/av1 与字幕轨。
- 会话清理：`DELETE /Videos/ActiveEncodings?deviceId=&playSessionId=`（10.10.7 规范存在，12.3.0 已隐藏）→ 停止播放/切换码率必须调，否则 ffmpeg 进程残留。
- 带宽自适应：初始 `MaxStreamingBitrate` 按网络类型 × 实测吞吐；降档时**重新 PlaybackInfo**（新 bitrate + `startTimeTicks=当前位置`），并先 DELETE 旧 ActiveEncodings。

## 8. 现有客户端与 Dart SDK 生态

| 项目 | 技术栈 | 可借鉴点 |
|---|---|---|
| **Finamp**（Flutter，音乐） | `chopper`+`json_annotation`+`get_it`+`riverpod`+`just_audio`/`audio_service`；API 层为仓库内自生成代码（非 pub 包） | 离线下载、多服务器档案、后台播放架构 |
| **Fladder**（Flutter，视频，最接近参考） | `chopper`+`freezed`+`riverpod`+`media_kit 1.2.2`/`media_kit_video 2.0.0` | 视频播放、字幕、播放器 UI；2026-09-06 仍有提交 |
| **Streamyfin**（RN/Expo） | `@jellyfin/sdk ^0.13.0` + expo 57 + react-query | 服务端 SDK 用法、Trickplay/下载产品化 |
| **Findroid**（Kotlin） | jellyfin-sdk-kotlin | 原生播放器与下载实现 |
| 官方 SDK | TS `@jellyfin/sdk` 1.0.2（npm，2026-10-23）、Kotlin、Swift | **官方没有 Dart SDK** |

Dart 包实测（pub.dev API，2026-10-26）：
| 包 | 最新版/日期 | 依赖 | 数据 | 评价 |
|---|---|---|---|---|
| `dart_jellyfin` | **0.3.1 / 2026-10-11** | `http, meta, web_socket_channel`（纯 Dart） | 30 天下载 534、7 likes、8 版本（2026-05 起） | 对齐 Jellyfin **12.2**；覆盖登录/Quick Connect/PlaybackInfo+DeviceProfile/Trickplay/MediaSegments/SyncPlay/下载/WebSocket/字幕 URL；BSD-3；单作者（风险） |
| `jellyfin_dart` | 0.1.2 / 2025-10-22 | `dio, equatable, json_annotation` | 30 天下载 319、1 like、3 版本（2 天内发完即停） | 由 **10.11** 规范生成，已过时，不建议 |

**自建分层建议（也可与 SDK 并存）**：
1. 传输层：`dio` + `AuthInterceptor`（注入 MediaBrowser 头、补 Client/Device/DeviceId/Version、401 回调、503+Retry-After 重试、日志脱敏）。
2. 会话层：`ServerProfile`(baseUrl/token/userId/serverId/deviceId) + 多服务器 store；deviceId 按用户派生。
3. 模型层：从版本化 OpenAPI 只生成用到的 schema（BaseItemDto 全量 100+ 字段太重），核心约 20 个模型手写或生成。
4. 播放层：`PlaybackCoordinator`（PlaybackInfo → 决策 → 起 mpv → 10s 上报 → 停止清理），与 UI 解耦。
5. 提速方案：直接依赖 `dart_jellyfin`，包在自己的 `JellyfinGateway` 接口后，便于日后替换/fork。

## 9. 服务端兼容（实测差异）

| 版本 | paths 数 | 关键差异 |
|---|---|---|
| 10.8.13 | 338 | 有 `/Users/{userId}/Views`、`/Users/{userId}/FavoriteItems/{itemId}`、`/Users/{userId}/PlayedItems/{itemId}`；**无** Trickplay、**无** MediaSegments、**无** `/UserViews` |
| 10.9.11 | 308 | 新增 `/UserViews`、`/UserItems/{itemId}/UserData`、`/UserPlayedItems`、`/UserFavoriteItems`、Trickplay；**无** MediaSegments |
| 10.10.7 | 309 | 新增 `/MediaSegments/{itemId}`、`/Items/{itemId}/CriticReviews` |
| 10.11.x | — | `/PlayingItems/*` 废弃；新增"禁用废弃认证方式"开关；503+`Retry-After`；移除 ARM32 |
| **12.0–12.3（当前 stable）** | 294 | 删 `/emby/`、`/mediabrowser/`；删 `api_key`/`X-Emby-Token`/`X-MediaBrowser-Token`/`X-Emby-Authorization`；`/PlayingItems/*` 移除；`GET /QuickConnect/Initiate` 移除；`POST /Users/{userId}/EasyPassword`、`GET /Items/{itemId}/CriticReviews` 等移除；HLS 控制器从规范隐藏；`GetItems` 改为异步且带 filters 时自动 recursive；`UserDto.HasPassword` 失效；Swashbuckle v10 → **SDK 需重新生成** |

Emby 注意：不要把 `/emby/` 前缀当兼容手段（12 已删），也不要依赖 Emby 特有语义；用 `GET /System/Info/Public`（`ProductName`、`Version`）做识别与版本分支。

## 10. 客户端 MVP 必需端点清单

| # | 端点 | 用途 | 优先级 |
|---|---|---|---|
| 1 | `GET /System/Info/Public` | 连服务器前探测/版本判断（免鉴权） | P0 |
| 2 | `POST /Users/AuthenticateByName` | 登录 | P0 |
| 3 | `GET /UserViews`（<10.9 降级 `/Users/{userId}/Views`） | 首页分区 | P0 |
| 4 | `GET /Items` | 列表/继续观看/筛选/搜索 | P0 |
| 5 | `GET /Items/{itemId}`、`GET /Shows/{seriesId}/Episodes` | 详情与剧集 | P0 |
| 6 | `GET /Items/{itemId}/Images/{imageType}/{imageIndex}` | 封面/背景 | P0 |
| 7 | `POST /Items/{itemId}/PlaybackInfo` | 播放协商（DeviceProfile） | P0 |
| 8 | `GET /Videos/{itemId}/stream?static=true` | 直连播放 | P0 |
| 9 | `POST /Sessions/Playing` / `/Progress` / `/Stopped` | 进度与"正在观看" | P0 |
| 10 | `DELETE /Videos/ActiveEncodings` | 转码会话清理（有转码就必须） | P1 |
| 11 | `POST /Sessions/Capabilities/Full` | 远程控制能力声明 | P1 |
| 12 | `POST /UserPlayedItems/{itemId}`、`POST /UserFavoriteItems/{itemId}`、`GET /UserItems/{itemId}/UserData` | 已看/收藏/单集状态 | P1 |
| 13 | `GET /Items/{itemId}/Similar`、`GET /Search/Hints` | 推荐与搜索建议 | P1 |
| 14 | `POST /QuickConnect/Initiate` + `GET /QuickConnect/Connect` + `POST /Users/AuthenticateWithQuickConnect` | 免密码登录 | P1 |
| 15 | `POST /Sessions/Logout` | 退出登录 | P1 |
| 16 | `fields=Trickplay` + `GET /Videos/{itemId}/Trickplay/{width}/{index}.jpg` | 进度条缩略图 | P2 |
| 17 | `GET /MediaSegments/{itemId}` | 跳过片头/片尾（10.10+） | P2 |
| 18 | `GET /Items/{itemId}/Download` | 离线下载 | P2 |
| 19 | `GET /Sessions`、`POST /Sessions/{id}/Playing` | 远程控制 | P3 |

## 11. 直连 / 转码决策树

```text
播放请求(itemId, startTicks, 用户音轨/字幕偏好)
1) POST /Items/{id}/PlaybackInfo  body: DeviceProfile(mpv), MaxStreamingBitrate, StartTimeTicks
   enableDirectPlay/DirectStream/Transcoding = true
   ├─ ErrorCode != null → 报错(NotAllowed/NoCompatibleStream/RateLimitExceeded)，终止
   └─ 选 MediaSources[Id==MediaSourceId || 0]，记下 PlaySessionId
2) 分支（按序）
   A. SupportsDirectPlay == true
      → GET {base}/Videos/{id}/stream?static=true&mediaSourceId={ms.Id}&playSessionId={psid}
        PlayMethod=DirectPlay
        ├─ 播放器报错(容器/编码) → 该组合加入本地黑名单，回到 1)
        └─ 成功 → 3)
   B. TranscodingUrl != null
      → {base}{TranscodingUrl}（原样，必要时补 startTimeTicks）
        PlayMethod = TranscodingSubProtocol=="hls" ? Transcode : DirectStream
        （TranscodeReasons 只含 ContainerNotSupported → 实为 DirectStream 重封装）
   C. SupportsDirectStream == true 且无 TranscodingUrl
      → {base}/Videos/{id}/stream?static=false&mediaSourceId=…&container=ts  PlayMethod=DirectStream
   D. 全失败 → 显式请求转码：PlaybackInfo(videoCodec=h264, audioCodec=aac, maxStreamingBitrate=8000000) → 走 B
3) 播放中
   ├─ 每 10s：POST /Sessions/Playing/Progress(PositionTicks, IsPaused, PlayMethod, VolumeLevel, CanSeek)
   ├─ 暂停/seek/切音轨字幕：立即补报 Progress（带新 Audio/SubtitleStreamIndex）
   ├─ 带宽不足：DELETE /Videos/ActiveEncodings(deviceId, playSessionId) → 重新 PlaybackInfo(更低 bitrate, startTimeTicks=当前)
   └─ 退出：POST /Sessions/Playing/Stopped(PositionTicks, Failed) + DELETE /Videos/ActiveEncodings
```

## 12. 不确定项 / 需实测

1. **`ApiKey` 查询参数大小写**：gist 写 `ApiKey`，ASP.NET 通常大小写不敏感，但 12.0 删的是 `api_key` —— 上线前在 12.x 实测。
2. **12.x 下 `/Videos/{id}/master.m3u8` 是否仍可用**：规范已隐藏，未实测；故本报告坚持"只用 TranscodingUrl"。
3. **mpv 对 PGS/DVDSub 外部字幕（`.sup`/`.sub`）兼容性**：macOS arm64 与 Android 各测一次；不行则改 `Method: Encode`（代价烧录转码）。
4. **10s 进度间隔是 jellyfin-web 约定，非规范要求**；Dashboard 显示延迟可降到 5s（注意写放大）。
5. **`dart_jellyfin` 未实际运行**（仅读 README/pub 元数据）：其 `DeviceProfile` 构造器能否表达 §4.3 的完整 mpv 能力待验证；不足则 fork。
6. 转码后的 **seek 行为**（HLS segment 级 seek）与 `TranscodeSeekInfo(Auto|Bytes)` 实际表现未实测。
