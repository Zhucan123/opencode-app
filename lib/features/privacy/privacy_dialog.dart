import 'package:code_app/shared/theme.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

class PrivacyDialog extends StatelessWidget {
  const PrivacyDialog({super.key});

  Future<void> _launchUrl(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.card,
      title: const Text('服务协议与隐私保护指引'),
      content: SingleChildScrollView(
        child: RichText(
          text: TextSpan(
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: AppColors.textPrimary,
                ),
            children: [
              const TextSpan(
                text: 'opencode Mobile 是一个原生的 Flutter 移动应用，通过 SSH 隧道连接你的私人服务器。',
              ),
              const TextSpan(text: '\n\n'),
              const TextSpan(
                text: '• 应用功能：帮助你在手机上使用 opencode AI 编程助手，与 AI 对话、审批权限。\n',
              ),
              const TextSpan(
                text: '• 数据安全：你的 SSH 密钥、服务器配置、对话历史等所有敏感数据都存储在你的手机本地，加密保存于系统密钥库。\n',
              ),
              const TextSpan(
                text: '• 通信隐私：应用与 opencode 的所有通信都通过 SSH 隧道进行，完全私密。\n',
              ),
              const TextSpan(
                text: '• 无云同步：我们不收集、不上传任何个人数据到云服务器。',
              ),
              const TextSpan(text: '\n\n'),
              const TextSpan(
                text: '详细的隐私保护指引请阅读',
              ),
              TextSpan(
                text: '《隐私政策》',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: AppColors.accent,
                      decoration: TextDecoration.underline,
                      decorationColor: AppColors.accent,
                    ),
                recognizer: TapGestureRecognizer()
                  ..onTap = () => _launchUrl('https://zhucan123.github.io/opencode-app/privacy.html'),
              ),
              const TextSpan(
                text: '。',
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('不同意并退出'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('同意'),
        ),
      ],
    );
  }
}
