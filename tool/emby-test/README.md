# 本地 Emby 联调环境

使用官方 ARM64 Emby 4.9.3.0 容器，镜像已固定到 digest。HTTP 端口仅绑定本机回环地址，媒体目录以只读方式挂载；配置、令牌、密码和影视文件均已加入 Git 忽略。

## 访问

- Web 管理/播放页面：http://127.0.0.1:18096
- Sakuga 服务器类型：Emby
- Sakuga 服务器地址：http://127.0.0.1:18096
- 测试账号：sakuga
- 测试密码：SakugaTest-2026!
- 安全连接（HTTPS）：关闭

该账号是普通用户，不具备管理员权限。管理员为 sakuga-admin，其随机密码与本地会话保存在被忽略、权限为 0600 的 session.json 中。无需管理员账号即可在 Sakuga 浏览和播放测试媒体。

## 启停与初始化

在项目根目录运行：

~~~sh
docker compose -f tool/emby-test/compose.yaml up -d
python3 tool/emby-test/setup.py
~~~

初始化脚本只连接固定的本机测试端口，首次创建管理员和测试用户、电影/剧集媒体库，后续执行保留账号并触发扫描。媒体下载和授权说明见 [MEDIA.md](MEDIA.md)。

停止服务但保留配置和媒体：

~~~sh
docker compose -f tool/emby-test/compose.yaml down
~~~

媒体库目录：media/Movies、media/TV。Emby 看到的容器路径分别是 /media/Movies、/media/TV。

## 真实客户端联调

~~~sh
fvm flutter drive --driver=test_driver/integration_test.dart \
  --target=integration_test/emby_server_test.dart \
  --dart-define-from-file=tool/emby-test/results/live-config.json -d macos
~~~

测试使用项目实际 EmbyAuthService、EmbyClient、media_kit/libmpv，覆盖普通账号登录、媒体库/搜索/筛选、电影/季/集、图片、原生视频播放、续播起点、暂停拖动、外部字幕 HTTP 读取和原生加载、播放会话回报、进度写回、继续观看、已看/未看。运行后保留两分钟进度供手动检查。

运行该测试会将 macOS debug 产物暂时替换为测试入口。恢复正常应用产物：

~~~sh
fvm flutter build macos --debug -t lib/main.dart
~~~

Android 实机通过局域网访问需另行修改端口绑定；当前配置只提供本机测试。Emby Connect、直播与动态媒体源不属于本环境的验收范围。
