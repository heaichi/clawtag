<div align="center">

# 爪札 · ClawTag

**本地优先、完全离线的宠物日记 App（Android / iOS）。**

数据只存在你自己的手机上——无账号、无云端、无追踪。

[English](README.md)

</div>

---

## 功能

- **宠物档案** —— 照片、品种、生日、体重、相识日期，自动计算猫狗年龄阶段。
- **图文爪札** —— 每篇最多 9 张照片或视频，可记心情、天气与标签。
- **智能提醒** —— 疫苗、驱虫、洗澡、体检或自定义，本地通知按时提醒。
- **用药疗程** —— 按疗程记录多天的用药，每次喂药逐次勾选。
- **最近删除** —— 误删可恢复：提醒、爪札、宠物都能找回。
- **数据导出** —— 一键导出为属于你自己的 JSON 文件。
- **深色模式**，依赖精简、无广告无内购。

## 安装

到 [Releases](https://github.com/heaichi/clawtag/releases) 下载最新 APK 安装即可，需要 Android 7.0（API 24）及以上。

## 从源码构建

```bash
flutter pub get
flutter analyze          # 必须 0 issues
flutter test             # 单元 / 数据库 / 组件 / 布局测试
flutter run -d <device>  # Debug 构建 + 热重载
```

发布构建：

```bash
scripts/build.bat        # 仅 arm64（最快）
scripts/build.bat full   # 通用包：armv7 + arm64
```

release 签名读取 `android/key.properties`，该文件与 `*.jks` 均已忽略；未配置时退回 debug 签名。

## 技术栈

| | |
|---|---|
| 框架 | Flutter 3.44 / Dart 3.12 |
| 存储 | sqflite（SQLite），版本化、只增不删的迁移 |
| 状态 | Provider |
| 平台能力 | flutter_local_notifications、image_picker、video_player、permission_handler |

无后端、无统计 SDK、无第三方网络请求。

## 隐私

- 所有记录都保存在设备本地：应用私有目录下的 SQLite 数据库与媒体文件。
- 相机、相册、麦克风权限仅在你添加媒体时使用。
- 通知权限仅用于你自己创建的提醒。
- 卸载应用会同时删除数据，请先导出备份。

## 目录结构

```
lib/
├── core/        数据库、主题、纯函数工具
├── screens/     宠物 / 爪札 / 提醒 / 我的 页面
├── widgets/     复用卡片与组件
└── services/    媒体、权限、通知调度
test/            单元 / 数据库 / 组件 / 布局测试
```

## 参与贡献

欢迎提 issue 与 PR。请保持 `flutter analyze` 无告警、`flutter test` 全绿。

## 许可

[MIT](LICENSE)
