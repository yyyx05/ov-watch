# OV-Watch Android App

OV-Watch 的 Android 伴侣应用。当前阶段直接兼容手表已有的经典蓝牙
SPP 文本协议，不要求先修改 STM32 固件。

## 当前能力

- 获取已配对的经典蓝牙设备并连接 KT6368
- 发送 `OV`、`OV+SEND` 和 `OV+ST=yyyyMMddHHmmss`
- 解析步数、心率、环境温湿度和手表时间
- 自动轮询并用 SQLite 保存历史记录
- 健康总览、今日/7 天/30 天历史趋势、设备管理和调试日志界面
- 历史曲线按时间段聚合，原始采样在本机保留 90 天
- 进入设备页时检查 Android 蓝牙状态和“附近设备”权限
- 意外断线后指数退避自动重连（最多 5 次）
- App 进入后台时暂停轮询，返回前台后立即恢复
- 对固件尚未实现的 SpO2 明确显示为“待固件支持”

## 开发环境

蓝牙依赖要求 Flutter 3.44 或更新版本。本机当前工具链统一安装在 D 盘：

- Flutter：`D:\DevTools\flutter`
- JDK 21：`D:\DevTools\Java\jdk-21.0.12.1+1`
- Android SDK：`D:\DevTools\Android\Sdk`
- Pub/Gradle 缓存：`D:\DevTools\PubCache`、`D:\DevTools\GradleCache`

重新打开终端以读取已配置的用户环境变量，然后在本目录执行：

```powershell
flutter pub get
flutter analyze
flutter test
flutter build apk --debug
flutter run
```

若从 Codex Windows 受控终端构建时出现 `Unable to establish loopback
connection`，可仅为当前终端指定短临时目录后重试：

```powershell
$env:TEMP = 'D:\jtmp'
$env:TMP = 'D:\jtmp'
```

首次运行前，先在 Android 系统蓝牙设置中与 KT6368 配对。应用使用标准
SPP UUID，蓝牙权限由 `flutter_classic_bluetooth` 插件清单合并提供。

## 实施顺序

1. 现有协议连接、健康总览和本地历史（当前阶段）
2. 真机联调和后台长期运行验证（重连与前后台轮询已实现）
3. 手表设置、通知转发、天气和音乐控制
4. 协议 v1：稳定帧边界、请求序号、错误码和主动推送
5. OTA 升级：版本校验、用户确认、进度与失败恢复

OTA 放在最后，是因为升级中断可能让 APP 区不可启动，需要先把普通通信
和设备识别验证稳定。
