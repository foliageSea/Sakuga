# Sakuga

Sakuga 是 Jellyfin、Emby、飞牛影视和绿联影视的非官方客户端。它可以浏览和搜索媒体库、播放电影和剧集、从上次进度继续观看，并使用 Anime4K 在客户端改善动画画质。播放器基于 media_kit / libmpv。

## 下载与安装

到 [GitHub Releases](https://github.com/foliageSea/sakuga/releases) 选择适合设备的安装包；每个版本实际提供的文件以发布页为准。

| 平台 | 安装方式 |
| --- | --- |
| Android 8.0+（arm64-v8a） | 下载 `.apk` 并安装。若旧版 APK 使用不同的签名，不能直接覆盖；先[备份服务器配置](docs/servers.md)，再卸载旧版并安装。 |
| macOS 13+（Apple Silicon） | 打开 `.dmg`，把 Sakuga 拖到「应用程序」。当前打包流程不做 Developer ID 签名或 Apple 公证，下载的应用可能受到 Gatekeeper 限制。 |
| Windows 10/11（x64） | 有 `-setup.exe` 时可按提示安装（不需要管理员权限）；也可以解压整个 ZIP 后运行 `Sakuga.exe`，不要单独移动 EXE。libmpv 已随包提供；若系统提示缺少运行库，请安装[微软官方 Visual C++ Redistributable（x64）](https://aka.ms/vc14/vc_redist.x64.exe)。当前安装包和便携包未签名，可能触发 SmartScreen 提示。 |

Linux 仅用于[本地开发与验证](docs/development.md)，不提供正式安装包。

## 连接媒体服务器

1. 打开 Sakuga 的「设置 → 服务器」，添加服务器并选择类型。
2. 填写地址和认证信息，先「测试连接」，再「保存」。绿联影视需先在 NAS 上启用媒体库服务并创建专用账号；如使用自签名证书，请按[服务器指南](docs/servers.md)核对指纹。
3. 保存后回到首页或媒体库，即可浏览并播放内容。搜索入口在媒体库内；当前不支持离线下载。

Jellyfin 和 Emby 支持服务端转码、画质切换和外部字幕；飞牛影视和绿联影视以原画直播放为主。续播进度在 Jellyfin、Emby 和飞牛影视同步到服务器，绿联影视仅保存在本机。查看[完整功能对比、各服务器配置与迁移说明](docs/servers.md)。

## 文档

- [播放器指南](docs/playback.md)：画质、缓冲、字幕与平台差异。
- [本地开发与测试](docs/development.md)：SDK、运行、构建与联调入口。
- [打包与发布](docs/release.md)：Android 签名、macOS DMG、Windows 安装包和 GitHub Releases。
- [文档索引](docs/README.md)：技术专题、早期计划与调研记录。

## 许可与致谢

Sakuga 原创代码采用 [Apache License 2.0](LICENSE)。依赖、字体、着色器和图标继续适用各自条款，见[第三方许可与署名](THIRD_PARTY_NOTICES.md)。感谢 [Kazumi](https://github.com/Predidit/Kazumi) 的开发者和贡献者提供超分辨率实现参考。
