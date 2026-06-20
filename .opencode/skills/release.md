# 发布 Release (release)

当用户想要发版、打 Tag 或发布 release 时，使用此 Skill。

## 执行步骤

### 1. 读取最新 tag，计算新版本号

必须通过 git tag 确定版本号，**禁止**从 `pubspec.yaml` 读取版本号作为基准：

```bash
git tag --sort=-v:refname | head -n 1
```

输出示例：`v1.2.34`

- 取最后一位（Patch）加 1，得到新版本号：`1.2.35`
- 如果用户明确指定了版本号，直接使用用户指定的值

构建号规则：**构建号 = Patch 号**（如版本 `1.2.35` → 构建号 `35`）

### 2. 更新 pubspec.yaml 版本号

**必须用 `bash + python3` 修改**，禁止使用 `edit` 工具（系统权限 deny）：

```bash
python3 -c "
content = open('pubspec.yaml').read()
old_version = '<当前 version 行，如 version: 1.2.34+34>'
new_version = 'version: 1.2.35+35'
assert old_version in content, 'version line not found!'
content = content.replace(old_version, new_version)
open('pubspec.yaml', 'w').write(content)
print('done')
"
```

替换前先用 `grep 'version:' pubspec.yaml` 确认当前 version 行的完整内容。

### 3. 提交 + 打 tag + 推送

**顺序不能乱**，必须先 commit 再打 tag：

```bash
git add pubspec.yaml
git commit -m "chore: bump version to v<新版本号>"
git tag v<新版本号>
git push origin main
git push origin v<新版本号>
```

所有 git 命令必须加以下环境变量防止交互卡住：

```bash
export CI=true GIT_TERMINAL_PROMPT=0 GIT_PAGER=cat GIT_EDITOR=: DEBIAN_FRONTEND=noninteractive
```

### 4. 通知用户

- 说明从旧版本升级到了哪个新版本
- 提醒去 GitHub Actions 查看构建进度
- 附上 Releases 下载链接：`https://github.com/Zhucan123/opencode-app/releases`

## 注意事项

- **版本号基准必须来自 `git tag`**，不能信任 `pubspec.yaml` 里的当前值（可能因各种原因不同步）
- **`edit` 工具被系统权限 deny**，所有文件修改统一用 `bash + python3 -c`
- `pubspec.yaml` 的修改必须和 git tag 严格对应，不能多提交其他文件进 version bump commit
- tag push 会自动触发 `.github/workflows/release.yml` 构建 APK
