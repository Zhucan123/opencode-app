# 🎯 发布 Release (release)

当用户想要发版、打 Tag 或发布 release 时，请使用此 Skill。

## 📋 执行步骤

1. **确定版本号**：
   - 检查用户是否明确提供了版本号（如 1.0.2）。
   - **如果用户没有提供版本号**：请使用 `bash` 工具执行 `git tag --sort=-v:refname | head -n 1` 获取当前最新的 tag（例如 `v1.0.0`）。然后**自动将最后一位（Patch 号）加 1**，得出新的版本号（例如 `v1.0.1`）。
   - **规范化版本号**：确保最终使用的版本号带有 `v` 前缀（如 `v1.0.1`）。

2. **执行发版操作**：
   使用 `bash` 工具执行以下命令：
   ```bash
   git tag <版本号>
   git push origin <版本号>
   ```

3. **通知用户**：
   告知用户操作已成功（如果自动递增了版本号，请说明从旧版本升级到了哪个新版本），并提醒他们去 GitHub Actions 页面查看正在运行的自动发版流程。附上项目 Releases 页面的链接提醒用户去下载（`https://github.com/Zhucan123/opencode-app/releases`）。

## ⚠️ 注意事项
- 严禁手动修改代码中的版本号文件（如 `pubspec.yaml`），除非用户主动要求。
- `git tag` 只是打标签，发版的核心动作是通过 push 标签触发 `.github/workflows/release.yml` 的 Action 完成的。