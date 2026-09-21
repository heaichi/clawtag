# 参与开发（Contributing）

欢迎一起开发爪札（ClawTag）。这份文档是新协作者需要知道的最小规则集。

## 环境

- Flutter **3.44** / Dart **3.12**（`flutter --version` 确认）
- Android SDK（构建 Android），JDK 17+（Gradle 需要）
- 无需后端、无需任何密钥即可编译运行

```bash
git clone https://github.com/heaichi/clawtag.git
cd clawtag
flutter pub get
flutter analyze     # 必须 0 issues
flutter test        # 必须全绿
flutter run -d <device>
```

发布构建（可选）：`scripts/build.bat`（仅 arm64）/ `scripts/build.bat full`（armv7 + arm64 通用包）。
签名读取 `android/key.properties`，没有就自动退回 debug 签名——**不要提交任何 keystore 或 key.properties**。

## 硬性规则

1. **提交前 `flutter analyze` 0 issues、`flutter test` 全绿**；二者任一不过的 PR 不会被合并。
2. **数据层改动必须带回归测试**（`test/core/database/`）：软删除、级联、迁移这些地方历史上出过多次真 bug。
3. **数据库迁移只增不删**：只能加列/加表，并且要给旧数据回填默认值；改完把 `AppDatabase.VERSION` +1 并在 `_migrations` 追加一条。
4. **删除一律软删**：删提醒/爪札/宠物都进「最近删除」，可恢复；不要写物理删除（除非是用户明确选择的「彻底删除」）。
5. **完成必须由人确认**：提醒没有任何自动完成；逾期如实显示、不静默顺延。
6. **集成点异常一律 catch 降级**：通知、相机、文件等失败只提示，不能阻塞记录主流程。
7. **本地优先**：不引入网络请求、统计 SDK 或云端账号；数据只存在设备本地。
8. 新增独立功能请**独立成目录**，不要污染宠物/爪札/提醒/我的四条主流程。

## UI 约定

- 表单行统一用「框内灰色标签 + 内容」（见 `lib/screens/reminder_editor_screen.dart` 的 `_inlineField`），不要用会压在边框上的浮动 label。
- 卡片改动请跑 `test/widgets/layout_test.dart`（360/411/480 三种宽度 × 深/浅色），它会直接抓出溢出。
- 卡片/列表里的数字口径要写清楚（例如「已完成次数」不含待办），避免读者误读。

## 分支与 PR

```bash
git checkout -b feat/your-feature
# ... 开发、自测 ...
git commit -m "feat(模块): 一句话说明"
git push -u origin feat/your-feature
# 然后在 GitHub 上开 PR
```

- `main` 保持随时可发布：PR 合并前请确保 CI 级别的两条命令（analyze/test）在本地通过。
- 提交信息建议 `feat(模块): …` / `fix(模块): …` / `docs: …`，用中文描述即可。
- 大改动请先开 issue 说清动机与范围，避免白做。

## 版本号

`pubspec.yaml` 的 `version: x.y.z+N` 是唯一来源（`N` = Android versionCode，只增不减）；
`scripts/build.bat` 会自动递增并同步 `lib/core/utils/version.dart`，**不要手改 `version.dart`**。

## 不要提交

`android/key.properties`、`*.jks`、`android/local.properties`、`build/`、`*.log`、任何个人路径或密钥（`.gitignore` 已覆盖，请勿强行 `-f` 添加）。

## 许可

贡献的代码按仓库的 [MIT](LICENSE) 许可发布。
