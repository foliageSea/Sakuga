# Jellyfin 10.10.7 测试服实测记录

> **历史调研。** 环境、版本、结论与建议均以调研时点为准；当前使用与开发步骤见[文档索引](../README.md)。

> 时间：2026-10-26 · 测试服：`http://110.42.96.64:44762` · 凭据只放本地环境变量，不写入仓库
> 目的：验证 Sakuga 的 10.8–10.10 兼容基线、认证头、PlaybackInfo 与增强播放可用性。

## 0. 结论

1. 服务端版本 **10.10.7**（`GET /System/Info/Public`），符合“兼容 10.8–10.10”的目标。
2. **`Authorization: MediaBrowser` 与 `X-Emby-Token` 都可用**；客户端统一用 Authorization 头，10.x 保留 X-Emby-Token 回退即可覆盖 10.8–10.10 与 12.x。
3. 测试库为“番剧”，共 51 个条目；样本覆盖 mp4/h264/aac、mkv/h264/aac、mkv/hevc/aac，以及 ASS/SRT 多字幕。
4. 用 mpv 全能力 DeviceProfile 调 `POST /Items/{id}/PlaybackInfo`，mkv/h264/aac 返回 `SupportsDirectPlay=true` 且无 `TranscodingUrl`，**直连路径成立**。
5. `MediaStream.DeliveryUrl` 自带 `api_key` 查询参数；客户端应剥离并改用请求头，避免 token 进入日志/反代。
6. 该测试服 **未生成 Trickplay 与 MediaSegments**（`Trickplay={}`、`MediaSegments` 空）；相关 UI 必须做降级，验收前需让服务器生成。

## 1. 认证

```http
GET /System/Info/Public
```
→ `{"ServerName":"2d7cb0f1451d","Version":"10.10.7","ProductName":"Jellyfin Server",...}`

```http
GET /Users
Authorization: MediaBrowser Token="<token>", Client="Sakuga", Device="Probe", DeviceId="probe-1", Version="0.0.1"
```
→ 200，返回用户列表（用户 `foliage`，Id `c337bd3056c44169a24d366f7d7c80a0`）。

```http
GET /Users
X-Emby-Token: <token>
```
→ 200，说明 10.10 仍接受旧头，可作为兼容回退。

## 2. 浏览

```http
GET /UserViews?userId=<uid>
```
→ 一个视图：`番剧 / tvshows / 28e774baf8f2fd279e7d58da9890a7d2`。

```http
GET /Items?userId=<uid>&recursive=true&includeItemTypes=Movie,Episode&limit=5&fields=MediaSources,MediaStreams,UserData,Chapters,Trickplay
```
→ 51 条；样本：

| 名称 | 容器 | 视频 | 音频 | 字幕 |
| --- | --- | --- | --- | --- |
| 共犯 | mp4 | h264 | aac (jpn) | — |
| 没有未实现损失最棒了～♥ | mkv | h264 | aac (jpn) | subrip/ass 多语言 |
| 伤痕什么的，不想让人看见 | mkv | hevc | aac (jpn) | ass (chi) |
| 在超市后面独自学习的一人 | mp4 | h264 | aac (jpn) | Data (bin_data) |

## 3. 播放协商

请求（节选）：

```http
POST /Items/09d94eeb307f22579219d3714324674e/PlaybackInfo?userId=<uid>
Content-Type: application/json

{
  "UserId": "<uid>",
  "MaxStreamingBitrate": 120000000,
  "EnableDirectPlay": true,
  "EnableDirectStream": true,
  "EnableTranscoding": true,
  "DeviceProfile": { "Name": "Sakuga-mpv", "DirectPlayProfiles": [...], "TranscodingProfiles": [...], "SubtitleProfiles": [...] }
}
```

响应：

- `PlaySessionId` 正常返回；`ErrorCode` 为空。
- `MediaSources[0]`：`Container=mkv`，`SupportsDirectPlay=true`，`SupportsDirectStream=true`，`SupportsTranscoding=true`，`TranscodingUrl=null`。
- `DefaultAudioStreamIndex=1`；`DefaultSubtitleStreamIndex=null`。
- 字幕 `DeliveryUrl` 形如：
  `/Videos/<id>/<mediaSourceId>/Subtitles/2/0/Stream.srt?api_key=<token>`
  → 客户端应去掉 `api_key`，用请求头加载。

## 4. 增强播放可用性

| 功能 | 结果 |
| --- | --- |
| Chapters | 样本 `Chapters=[]`（未生成章节） |
| Trickplay | `Trickplay={}`；`GET /Videos/{id}/Trickplay/320/tiles.m3u8` → 404 |
| MediaSegments | `GET /MediaSegments/{id}` → `Items=[]` |
| 字幕 | 多 ASS/SRT 轨道存在；`DeliveryUrl` 可用 |

→ Trickplay/片头片尾功能在测试服上无法验收；需要：
1. 在服务器生成 Trickplay（Dashboard → 媒体库 → Trickplay）或
2. 用本地 Jellyfin Docker + 预生成数据；或
3. 先验收降级（无缩略图时只显示时间气泡；无 MediaSegments 时不显示跳过按钮）。

## 5. 对计划的修正

- 计划基线从“12.3 stable”改为 **10.8–10.10（10.10.7 实测）**；12.x 作为可选适配。
- 认证统一 `Authorization: MediaBrowser`，10.x 回退 `X-Emby-Token`。
- 字幕 URL 必须剥离 `api_key`。
- M1 验收可直接用该测试服；M4 的 Trickplay/MediaSegments 验收需另备数据。
