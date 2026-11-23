# 第三方许可与署名

Sakuga 原创代码采用 [Apache License 2.0](LICENSE)。第三方代码、依赖、字体、着色器、图标及其他素材不因此改用 Apache-2.0；它们继续适用各自的许可和使用条款。

## 代码与资源

| 组件 | 许可、署名与来源 |
| --- | --- |
| Anime4K GLSL 着色器 | MIT，Copyright © 2019 bloc97。见[随附的许可全文](assets/shaders/LICENSE)与各着色器文件中的声明。 |
| MiSans Regular | 小米科技有限责任公司。见[小米 MiSans 官方下载页及字体许可](https://hyperos.mi.com/font/download)。本仓库包含字体文件，应用也会将其打包；公开仓库前须核对当前字体文件的来源、许可版本、原文件再分发和应用嵌入条件。免费使用不等于已确认这两种再分发权利。 |
| media_kit / media_kit_video | MIT。当前锁定 [Predidit/media-kit 的提交 83b7ca6](https://github.com/Predidit/media-kit/tree/83b7ca63772856e1ea0158916177e136f7b7b0be)，见其[许可证](https://github.com/Predidit/media-kit/blob/83b7ca63772856e1ea0158916177e136f7b7b0be/LICENSE)。Dart 包的 MIT 许可不覆盖构建时下载的原生库。 |
| Flutter、Forui 等依赖 | 依赖和版本见 [pubspec.yaml](pubspec.yaml) 与 [pubspec.lock](pubspec.lock)；分发时保留各依赖随附的许可和版权声明。 |
| 媒体服务图标 | 仅用于标识所支持的服务。Sakuga 不是这些服务的官方客户端，项目许可证不授予第三方标识的使用权；公开分发前应核对各图标的来源和品牌使用条款。 |

## 实现参考

超分辨率实现参考了 [Kazumi](https://github.com/Predidit/Kazumi) 的做法，感谢其开发者与贡献者。Kazumi 自身采用 GPL-3.0，本致谢不替代其许可证，也不对 Kazumi 代码重新授权。

## APK 与 DMG 中的原生库

[锁定的原生资源清单](https://github.com/Predidit/media-kit/blob/83b7ca63772856e1ea0158916177e136f7b7b0be/media_kit/hook/native_bundles.json)指向以下构建：

| 平台 | 固定的上游构建 | 已核对 |
| --- | --- | --- |
| Android arm64 | [Predidit/libmpv-android-video-build v1.3.1](https://github.com/Predidit/libmpv-android-video-build/tree/v1.3.1) | [mpv 构建配方](https://github.com/Predidit/libmpv-android-video-build/blob/v1.3.1/buildscripts/scripts/mpv.sh)指定 `-Dgpl=false`。 |
| macOS Apple Silicon | [Predidit/libmpv-darwin-build 0.6.8](https://github.com/Predidit/libmpv-darwin-build/tree/0.6.8) | [mpv 构建配方](https://github.com/Predidit/libmpv-darwin-build/blob/0.6.8/nix/packages/mk-pkg-mpv/default.nix)指定 `-Dgpl=false`。 |

这两处旗标仅说明 mpv 的构建配置，不能证明整套原生库的许可证或二进制分发合规。公开分发安装包前，按实际 APK 和 DMG 核对 FFmpeg、libmpv 及随附库的具体版本、构建选项、补丁和适用许可；随包提供所需声明和许可全文，并按适用条款提供对应源码、构建材料及满足替换或重新链接的要求。本清单不代替随包声明或对应源码。
