import 'package:code_app/shared/theme.dart';
import 'package:flutter/material.dart';

class HelpScreen extends StatelessWidget {
  const HelpScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('使用说明')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 40),
        children: const [
          _Section(
            icon: Icons.rocket_launch_outlined,
            title: '快速开始',
            steps: [
              _Step('安装 opencode', '在你的服务器上运行：\ncurl -fsSL https://opencode.ai/install | sh'),
              _Step('添加服务器', '点击首页右下角 + 按钮，填写 SSH 连接信息'),
              _Step('连接', '点击服务器卡片开始连接，App 会自动启动 opencode serve'),
              _Step('开始对话', '连接成功后选择会话，直接发送消息'),
            ],
          ),
          SizedBox(height: 28),
          _Section(
            icon: Icons.settings_outlined,
            title: '服务器配置',
            steps: [
              _Step('认证方式', '支持密码和 PEM 私钥两种方式，私钥可从文件选择'),
              _Step('工作目录', '指定 opencode 工作的项目目录，留空则使用默认目录'),
              _Step('opencode 路径', '如 opencode 不在 PATH 中，可手动指定可执行文件路径\n例：/home/ubuntu/.opencode/bin/opencode'),
              _Step('端口', 'opencode 默认端口 4096，多台服务器会自动分配不同本地端口'),
            ],
          ),
          SizedBox(height: 28),
          _Section(
            icon: Icons.chat_outlined,
            title: '对话界面',
            steps: [
              _Step('模式选择', '输入框左侧可切换 build / plan 等模式\n• build：默认模式，可执行命令和修改文件\n• plan：只规划不执行，适合复杂任务拆解'),
              _Step('模型切换', '点击模式按钮右侧可选择 AI 模型（需服务器配置了对应 API key）'),
              _Step('下拉刷新', '对话列表下拉可手动刷新消息'),
            ],
          ),
          SizedBox(height: 28),
          _Section(
            icon: Icons.help_outline,
            title: '常见问题',
            steps: [
              _Step('连接超时', '检查服务器是否已安装 opencode，或在服务器配置中指定 opencode 路径'),
              _Step('端口被占用', '重新连接时 App 会自动清理上次残留的进程'),
              _Step('收不到消息', '检查网络连接，App 会在断线后自动重连 SSE 事件流'),
              _Step('模型不显示', '该服务器的 opencode 版本可能较旧，或未配置 API Provider key'),
            ],
          ),
          SizedBox(height: 28),
          _LinkSection(),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({
    required this.icon,
    required this.title,
    required this.steps,
  });

  final IconData icon;
  final String title;
  final List<_Step> steps;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 18, color: AppColors.accent),
            const SizedBox(width: 8),
            Text(
              title,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: AppColors.accent,
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        ...steps.map((step) => _StepTile(step: step)),
      ],
    );
  }
}

class _Step {
  const _Step(this.title, this.content);
  final String title;
  final String content;
}

class _StepTile extends StatelessWidget {
  const _StepTile({required this.step});
  final _Step step;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              step.title,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
            ),
            const SizedBox(height: 4),
            Text(
              step.content,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColors.textMuted,
                    height: 1.5,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LinkSection extends StatelessWidget {
  const _LinkSection();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '相关链接',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
          ),
          const SizedBox(height: 8),
          _LinkRow(icon: Icons.public, label: 'opencode 官网', url: 'https://opencode.ai'),
          _LinkRow(icon: Icons.code, label: 'GitHub 仓库', url: 'https://github.com/Zhucan123/opencode-app'),
          _LinkRow(icon: Icons.privacy_tip_outlined, label: '隐私政策', url: 'https://zhucan123.github.io/opencode-app/privacy.html'),
        ],
      ),
    );
  }
}

class _LinkRow extends StatelessWidget {
  const _LinkRow({required this.icon, required this.label, required this.url});
  final IconData icon;
  final String label;
  final String url;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 14, color: AppColors.textMuted),
          const SizedBox(width: 8),
          Text(
            label,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppColors.accent,
                ),
          ),
          const SizedBox(width: 4),
          Text(
            url,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  fontSize: 10,
                ),
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}
