# 🎯 发布 Release (release)

当用户想要发版、打 Tag 或发布 release 时，请使用此 Skill。

## 📋 执行步骤

1. **确定版本号**：
   - 检查用户是否明确提供了版本号（如 1.0.2）。
   - **如果用户没有提供版本号**：请使用 `bash` 工具执行 `git tag --sort=-v:refname | head -n 1` 获取当前最新的 tag（例如 `v1.0.0`）。然后**自动将最后一位（Patch 号）加 1**，得出新的版本号（例如 `v1.0.1`）。
   - **规范化版本号**：注意区别带有 `v` 前缀的 Tag（如 `v1.0.1`）和不带 `v` 前缀的纯数字版本号（如 `1.0.1`）。

2. **同步修改 Flutter 应用版本号 (pubspec.yaml)**：
   - 读取 `pubspec.yaml` 文件，找到 `version:` 字段（格式通常为 `version: 1.0.0+1`）。
   - 将加号 `+` 前面的版本号替换为最新的纯数字版本号（如 `1.0.1`）。
   - 将加号 `+` 后面的构建号（Build Number）加 1。
   - 使用 `edit` 工具修改并保存 `pubspec.yaml`。

3. **提交代码并执行发版**：
   使用 `bash` 工具执行以下命令：
   ```bash
   git add pubspec.yaml
   git commit -m "chore: bump version to v<纯数字版本号>"
   git push origin main
   git tag v<纯数字版本号>
   git push origin v<纯数字版本号>
   ```

4. **通知用户**：
   告知用户应用版本已更新并成功发版（说明从旧版本升级到了哪个新版本）。提醒他们去 GitHub Actions 页面查看正在运行的自动发版流程，并附上项目 Releases 页面的链接提醒用户去下载（`https://github.com/Zhucan123/opencode-app/releases`）。

## ⚠️ 注意事项
- 必须确保 `pubspec.yaml` 的修改和 `git tag` 的标签严格对应。
- `git tag` 只是打标签，发版的核心动作是通过 push 标签触发 `.github/workflows/release.yml` 的 Action 完成的。