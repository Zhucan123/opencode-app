# 🎯 发布 Release (release)

当用户想要发版、打 Tag 或发布 release 时，请使用此 Skill。

## 📋 执行步骤

1. **确定版本号**：检查用户是否提供了版本号（如 1.0.2）。如果没有提供，请先询问用户希望发布的版本号（建议使用语义化版本规则，例如：主版本.次版本.修订号）。
2. **规范化版本号**：确保版本号带有 `v` 前缀。如果用户说 `1.0.2`，你需要将其格式化为 `v1.0.2`。
3. **执行发版操作**：
   使用 `bash` 工具执行以下命令：
   ```bash
   git tag <版本号>
   git push origin <版本号>
   ```
4. **通知用户**：告知用户操作已成功，并提醒他们去 GitHub Actions 页面查看正在运行的 `Publish Release APK` 自动发版流程。附上项目 Releases 页面的链接提醒用户去下载（例如：`https://github.com/Zhucan123/opencode-app/releases`）。

## ⚠️ 注意事项
- 不要去修改代码版本号文件（如 `pubspec.yaml` 里的版本号），除非用户明确要求一并修改。
- `git tag` 只是打标签，发版的核心动作是通过 push 标签触发 `.github/workflows/release.yml` 的 Action 完成的。