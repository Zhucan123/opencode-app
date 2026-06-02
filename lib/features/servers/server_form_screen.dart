import 'package:code_app/core/storage/server_config_store.dart';
import 'package:code_app/features/servers/server_provider.dart';
import 'package:file_picker/file_picker.dart';
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
  late final TextEditingController _pemKeyController;
  late final TextEditingController _opencodePortController;
  late final TextEditingController _workingDirController;
  late final TextEditingController _opencodePathController;
  late SshAuthType _authType;
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
    _pemKeyController = TextEditingController(text: server?.pemKey ?? '');
    _opencodePortController = TextEditingController(text: '${server?.opencodePort ?? 4096}');
    _workingDirController = TextEditingController(text: server?.workingDirectory ?? '');
    _opencodePathController = TextEditingController(text: server?.opencodePath ?? '');
    _authType = server?.authType ?? SshAuthType.password;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _hostController.dispose();
    _userController.dispose();
    _portController.dispose();
    _passwordController.dispose();
    _pemKeyController.dispose();
    _opencodePortController.dispose();
    _workingDirController.dispose();
    _opencodePathController.dispose();
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
              keyboardType: TextInputType.url,
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
            const SizedBox(height: 20),
            Text('认证方式', style: Theme.of(context).textTheme.labelMedium),
            const SizedBox(height: 8),
            SegmentedButton<SshAuthType>(
              segments: const [
                ButtonSegment(
                  value: SshAuthType.password,
                  label: Text('密码'),
                  icon: Icon(Icons.lock_outline),
                ),
                ButtonSegment(
                  value: SshAuthType.pemKey,
                  label: Text('PEM 私钥'),
                  icon: Icon(Icons.key_outlined),
                ),
              ],
              selected: {_authType},
              onSelectionChanged: (selected) {
                setState(() => _authType = selected.first);
              },
            ),
            const SizedBox(height: 16),
            if (_authType == SshAuthType.password)
              TextFormField(
                controller: _passwordController,
                decoration: const InputDecoration(labelText: '密码'),
                obscureText: true,
                validator: _authType == SshAuthType.password ? _requiredValidator : null,
              )
            else
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextFormField(
                    controller: _pemKeyController,
                    decoration: const InputDecoration(
                      labelText: 'PEM 私钥内容',
                      hintText: '-----BEGIN RSA PRIVATE KEY-----\n...',
                      alignLabelWithHint: true,
                    ),
                    maxLines: 6,
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                    validator: _authType == SshAuthType.pemKey ? _requiredValidator : null,
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: _pickPemFile,
                    icon: const Icon(Icons.file_open_outlined, size: 18),
                    label: const Text('从文件选择 .pem'),
                  ),
                ],
              ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _opencodePortController,
              decoration: const InputDecoration(labelText: 'OpenCode 端口'),
              keyboardType: TextInputType.number,
              validator: _portValidator,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _workingDirController,
              decoration: const InputDecoration(
                labelText: '工作目录（可选）',
                hintText: '例：/home/ubuntu/my-project',
                prefixIcon: Icon(Icons.folder_outlined),
              ),
              keyboardType: TextInputType.url,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _opencodePathController,
              decoration: const InputDecoration(
                labelText: 'opencode 安装路径（可选）',
                hintText: '例：/home/ubuntu/.opencode/bin/opencode',
                prefixIcon: Icon(Icons.terminal_outlined),
                helperText: '留空则自动从 PATH 查找',
              ),
              keyboardType: TextInputType.url,
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

  Future<void> _pickPemFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.any,
      allowMultiple: false,
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;
    final file = result.files.first;
    final bytes = file.bytes;
    if (bytes == null) return;
    final content = String.fromCharCodes(bytes).trim();
    if (!content.contains('-----BEGIN') && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('所选文件不是有效的 PEM 格式')),
      );
      return;
    }
    _pemKeyController.text = content;
  }

  String? _requiredValidator(String? value) {
    if (value == null || value.trim().isEmpty) return '此项不能为空';
    return null;
  }

  String? _portValidator(String? value) {
    final port = int.tryParse(value?.trim() ?? '');
    if (port == null || port <= 0 || port > 65535) return '请输入有效端口';
    return null;
  }

  Future<void> _saveServer() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSaving = true);
    try {
      final config = ServerConfig(
        id: widget.initialServer?.id ?? '',
        name: _nameController.text.trim(),
        host: _hostController.text.trim(),
        sshPort: int.parse(_portController.text.trim()),
        username: _userController.text.trim(),
        opencodePort: int.parse(_opencodePortController.text.trim()),
        authType: _authType,
        password: _authType == SshAuthType.password ? _passwordController.text : '',
        pemKey: _authType == SshAuthType.pemKey ? _pemKeyController.text.trim() : '',
        workingDirectory: _workingDirController.text.trim(),
        opencodePath: _opencodePathController.text.trim(),
        lastConnected: widget.initialServer?.lastConnected,
      );
      await ref.read(serverListProvider.notifier).saveServer(config);
      if (mounted) context.pop();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error.toString())),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }
}
