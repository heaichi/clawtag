# 爪札 ClawTag 🐾 —— 数据不出手机的宠物日记

<p align="center">
  <img src="docs/assets/logo.png" width="112" alt="爪札 ClawTag">
</p>

<p align="center">
  <a href="https://github.com/heaichi/clawtag/releases"><img src="https://img.shields.io/github/v/release/heaichi/clawtag?style=flat-square&label=release" alt="Release"></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-green?style=flat-square" alt="License: MIT"></a>
  <img src="https://img.shields.io/badge/platform-Android%20%7C%20iOS-3DDC84?style=flat-square" alt="Android 与 iOS">
  <a href="https://flutter.dev"><img src="https://img.shields.io/badge/Flutter-3.44-02569B?style=flat-square&logo=flutter" alt="Flutter 3.44"></a>
</p>

<p align="center"><a href="README.en.md">English</a> · 中文</p>

爪札是一款本地优先、完全离线的宠物日记 App（Android / iOS）。它记录你和宠物相处的日常：宠物档案、图文爪札、护理提醒与用药疗程。界面是 Flutter，底层是本地 SQLite，中间没有别的东西。

**数据不出手机。** 没有账号、没有登录、没有同步、没有统计。爪札知道的一切都存在设备本地的数据库与文件目录里；不上传、不回传，数据唯一的出口是你自己执行的导出。

## 安装

**Android** —— 到 [Releases](https://github.com/heaichi/clawtag/releases) 下载最新 APK 安装即可，需要 Android 7.0（API 24）及以上；发布的包是 armv7 + arm64 通用单包。

**iOS** —— 暂未上架 App Store，请从源码构建（见下），Xcode 工程在 `ios/`。

## 快速上手

1. **添加宠物** —— 照片、物种、生日、相识日期。
2. **写一篇爪札** —— 文字 + 最多 9 张照片或视频，可记心情、天气与标签。
3. **建一条提醒** —— 选疫苗、驱虫、体检等类型，再选日期。
4. **可选**：打开「用药疗程」，按医生要求的疗程逐次勾选喂药。

删掉的任何东西都会进「最近删除」，随时可以恢复。

## 功能

| | |
|---|---|
| 🐾 **宠物档案** | 照片、品种、生日、体重、相识日期，自动计算猫狗年龄阶段 |
| 📝 **图文爪札** | 每篇最多 9 张照片或视频，可记心情、天气与标签 |
| 🔔 **护理提醒** | 疫苗、驱虫、洗澡、体检或自定义，按周期循环提醒 |
| 💊 **用药疗程** | 一种药、一天多次、按处方天数坚持到底 |
| 🗑 **最近删除** | 提醒、爪札、宠物都能找回 |
| 🎬 **内置播放器** | 视频内嵌播放，支持横竖屏全屏 |
| 📤 **备份与恢复** | 导出含数据与照片的备份包，换机时导入即可 |
| 🌙 **深色模式** | 跟随系统，也可手动指定 |

## 实现要点

- **Flutter 3.44 / Dart 3.12**，一套代码同时构建 Android 与 iOS。
- **sqflite** —— 本地 SQLite 单库。迁移只增不删：表结构从不丢列，升级时把旧数据回填，更新永远不会让你的数据消失。
- **删除都是软删除**。记录保留历史，在「最近删除」里等你恢复或彻底删除。
- **完成从不自动发生**。提醒只有你确认才算完成；逾期项保留真实日期，并持续提醒。
- **通知完全本地**。系统允许时使用精确闹钟，不允许时自动退回非精确调度——权限缺失只会让提醒降级，不会让 App 出错。
- **没有后端**。应用不主动建立任何网络连接；第三方依赖仅限通知、取图、视频播放与权限。

## 隐私

- 所有记录存放在应用私有的 SQLite 数据库与文件目录中。
- 相机、相册、麦克风权限仅在你添加媒体时使用。
- 通知权限仅用于你自己创建的提醒。
- **卸载会删除数据**，重要的话请先导出备份。

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

release 签名读取 `android/key.properties`，该文件与 `*.jks` 均已忽略；未配置时退回 debug 签名。Fork 时请自行修改 `android/app/build.gradle.kts` 的 `applicationId` 与 iOS 工程的 Bundle Identifier。

## 目录结构

```
lib/
├── core/        数据库、主题、纯函数工具
├── screens/     宠物 / 爪札 / 提醒 / 我的 页面
├── widgets/     复用卡片与组件
└── services/    媒体、权限、通知调度
test/            单元 / 数据库 / 组件 / 布局测试
android/ ios/    平台工程
```

## 参与贡献

欢迎提 issue 与 PR。提 PR 前请确认 `flutter analyze` 无告警、`flutter test` 全绿——测试覆盖了数据库不变式（软删除、级联、迁移）以及各种屏幕宽度下的卡片布局。

## 许可

[MIT](LICENSE) © heaichi
