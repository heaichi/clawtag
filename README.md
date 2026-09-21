# 爪札 · ClawTag

> 本地优先、完全离线的宠物日记 App。数据只存在你自己的手机上，不联网、不上传、无账号。

<p align="center">
  <em>A local-first, fully offline pet diary app for Android & iOS.</em><br>
  <em>Your data never leaves your phone — no account, no cloud, no tracking.</em>
</p>

## 功能

| 模块 | 内容 |
|---|---|
| 🐾 宠物档案 | 多宠物：照片、品种、生日、体重、相识日期；列表与详情显示年龄阶段（猫狗分幼年/成年/老年） |
| 📝 图文爪札 | 标题 + 内容 + 最多 9 张照片/视频、心情、天气、标签；纯媒体爪札允许空标题/空内容；详情页媒体支持全屏左右滑动 |
| 🎬 视频播放 | 自动播放、常驻进度条、点击滑出 B 站风格控制条（播放/暂停、进度拖拽、时间、横竖屏全屏） |
| 🔔 智能提醒 | 疫苗 / 驱虫 / 洗澡 / 美容 / 体检 / 自定义；周期重复、精确闹钟本地通知（标题含宠物名与第 N 次） |
| 💊 用药疗程 | 一条药 =「每天 1~4 次 × 连续 N 天」；卡片显示「第 N/M 天 · 今日 X/Y 次 · 下次 HH:mm」；点开可勾选服药；漏服留痕不静默；通知按次推送、只滚动排未来 7 天 |
| 🗑 最近删除 | 提醒 / 爪札 / 宠物的软删除与恢复、撤销、彻底删除；级联删除与联动恢复 |
| 👤 我的 | 数据统计、深色模式、标签管理、数据导出（JSON） |
| 🔮 宠物算命 | 规划中，独立目录 `lib/fortune/`（暂未创建） |

## 技术栈

- Flutter 3.44 / Dart 3.12
- sqflite（本地 SQLite，版本化迁移，只增不删 + 旧数据回填）
- Provider（状态管理）、flutter_local_notifications（本地通知）、image_picker / video_player
- 无后端、无网络请求（除应用商店/系统组件自身）

## 构建与运行

```bash
flutter pub get
flutter analyze          # 必须 0 issues
flutter test             # 单元 + 组件测试，必须全绿

# 日常迭代：真机 Debug 热重载（改代码按 r 秒级生效，不升版本号）
flutter run -d <serial>

# 发布/验收：出包 + 覆盖安装
scripts\build.bat        # 只出 arm64 单包（最快）
scripts\build.bat full   # 分发包：arm64 + armeabi-v7a
adb install -r <apk>     # 覆盖安装，保留数据
```

- 版本号唯一来源是 `pubspec.yaml` 的 `version:`（`x.y.z+N`，N = versionCode）；`build.bat` 会自动递增并同步 `lib/core/utils/version.dart`。
- release 签名需自备：在 `android/key.properties` 指向你自己的 keystore（该文件与 `*.jks` 均已在 `.gitignore` 中，不会入库）。没有配置时会退回 debug 签名。
- 更新安装务必用 `adb install -r` 覆盖，**不要卸载**（卸载会清空数据库与照片）。

## 项目结构

```
lib/
├── main.dart / app.dart            入口与根组件
├── core/
│   ├── database/app_database.dart  sqflite 单例 + 版本化迁移
│   ├── theme/                      设计 token / 主题 / 深色模式
│   └── utils/                      路由、格式化、SnackBar、UUID、年龄、用药疗程纯函数
├── screens/                        宠物 / 爪札 / 提醒 / 我的 + 最近删除 + 标签管理
├── widgets/                        卡片与复用组件
└── services/                       图片、权限、提醒调度
test/                               单元 / 数据库 / 组件 / 布局测试
android/ · ios/                     平台工程
scripts/                            版本号与打包脚本
```

## 设计原则

1. **本地优先**：所有数据在设备本地 SQLite；无账号、无上传、无统计 SDK。
2. **数据不丢**：数据库迁移只增不删，旧数据回填；删除一律软删 + 最近删除可恢复。
3. **完成由人确认**：提醒不做任何自动完成；逾期如实显示「已逾期 N 天」。
4. **异常降级**：通知/媒体等集成点异常一律 catch 后降级，不阻塞核心记录流程。

## 隐私

- 应用不收集、不上传任何个人数据；导出的 JSON 由用户自行保管。
- 相机/相册/麦克风权限仅用于拍摄与选择爪札媒体；通知权限仅用于提醒。

## 许可

MIT License，见 [LICENSE](LICENSE)。

## 说明

- 仓库名 `clawtag` 只是英文标识（GitHub 不便用中文）；应用内显示名仍为「爪札」。
- Fork 后请自行修改 `android/app/build.gradle.kts` 的 `applicationId` 与 iOS Bundle Identifier，避免与官方包名冲突。
