import 'package:code_app/core/storage/server_config_store.dart';
import 'package:code_app/features/servers/server_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class ServerFormScreen extends ConsumerStatefulWidget {
  const ServerFormScreen({super.key, this.initialServer});

  final ServerConfig? initialServer;

  @override
  ConsumerState<ServerFormScreen> createState() => _ServerFormScreenState();
}

class _ServerFormScreenState extends ConsumerState<ServerFormScreen> {
  late final GlobalKey<FormState> _formKey;
  late final TextEditingController _nameController;
  late final TextEditingController _hostController;
  late final TextEditingController _userController;
  late final TextEditingController _portController;
  late final TextEditingController _passwordController;
  late final TextEditingController _opencodePortController;
  bool _isSaving = false;

  bool get _isEditing => widget.initialServer != null;

  @override
  void initState() {
    super.initState();
    final server = widget.initialServer;
    _formKey = GlobalKey<FormState>();
    _nameController = TextEditingController(text: server?.name ?? '');
    _hostController = TextEditingController(text: server?.host ?? '');
    _userController = TextEditingController(text: server?.username ?? '');
    _portController = TextEditingController(text: '${server?.sshPort ?? 22}');
    _passwordController = TextEditingController(text: server?.password ?? '');
    _opencodePortController = TextEditingController(text: '${server?.opencodePort ?? 4096}');
  }

  @override
  void dispose() {
    _nameController.dispose();
    _hostController.dispose();
    _userController.dispose();
    _portController.dispose();
    _passwordController.dispose();
    _opencodePortController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_isEditing ? '编辑服务器' : '新建服务器')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            TextFormField(
              controller: _nameController,
              decoration: const InputDecoration(labelText: '名称'),
              validator: _requiredValidator,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _hostController,
              decoration: const InputDecoration(labelText: '主机地址'),
              validator: _requiredValidator,
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  flex: 2,
                  child: TextFormField(
                    controller: _userController,
                    decoration: const InputDecoration(labelText: '用户名'),
                    validator: _requiredValidator,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: TextFormField(
                    controller: _portController,
                    decoration: const InputDecoration(labelText: 'SSH 端口'),
                    keyboardType: TextInputType.number,
                    validator: _portValidator,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _passwordController,
              decoration: const InputDecoration(labelText: '密码'),
              obscureText: true,
              validator: _requiredValidator,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _opencodePortController,
              decoration: const InputDecoration(labelText: 'OpenCode 端口'),
              keyboardType: TextInputType.number,
              validator: _portValidator,
            ),
            const SizedBox(height: 32),
            FilledButton(
              onPressed: _isSaving ? null : _saveServer,
              child: _isSaving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(_isEditing ? '保存修改' : '保存服务器'),
            ),
          ],
        ),
      ),
    );
  }

  String? _requiredValidator(String? value) {
    if (value == null || value.trim().isEmpty) {
      return '此项不能为空';
    }
    return null;
  }

  String? _portValidator(String? value) {
    final text = value?.trim() ?? '';
    final port = int.tryParse(text);
    if (port == null || port <= 0 || port > 65535) {
      return '请输入有效端口';
    }
    return null;
  }

  Future<void> _saveServer() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _isSaving = true;
    });

    try {
      final config = ServerConfig(
        id: widget.initialServer?.id ?? '',
        name: _nameController.text.trim(),
        host: _hostController.text.trim(),
        sshPort: int.parse(_portController.text.trim()),
        username: _userController.text.trim(),
        password: _passwordController.text,
        opencodePort: int.parse(_opencodePortController.text.trim()),
        lastConnected: widget.initialServer?.lastConnected,
      );
      await ref.read(serverListProvider.notifier).saveServer(config);
      if (mounted) {
        context.pop();
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error.toString())),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }
}
