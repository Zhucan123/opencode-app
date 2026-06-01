import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:code_app/core/storage/server_config_store.dart';
import 'package:dartssh2/dartssh2.dart';

enum SshConnectionStage {
  sshHandshake,
  authentication,
  startingOpencode,
  establishingTunnel,
}

class SshConnectionException implements Exception {
  const SshConnectionException(this.message);

  final String message;

  @override
  String toString() => message;
}

class ManagedSshConnection {
  ManagedSshConnection({
    required this.client,
    required this.opencodeSession,
    required this.localServer,
    required this.localPort,
    required StreamSubscription<Socket> acceptSubscription,
    required List<StreamSubscription<dynamic>> logSubscriptions,
  })  : _acceptSubscription = acceptSubscription,
        _logSubscriptions = logSubscriptions;

  final SSHClient client;
  final SSHSession opencodeSession;
  final ServerSocket localServer;
  final int localPort;
  final StreamSubscription<Socket> _acceptSubscription;
  final List<StreamSubscription<dynamic>> _logSubscriptions;

  Future<void> close() async {
    await _acceptSubscription.cancel();
    for (final subscription in _logSubscriptions) {
      await subscription.cancel();
    }
    await localServer.close();
    try {
      // 先发 TERM，再发 KILL 确保 bash 子进程 opencode 也被杀掉
      opencodeSession.kill(SSHSignal.TERM);
      await Future<void>.delayed(const Duration(milliseconds: 300));
      opencodeSession.kill(SSHSignal.KILL);
    } catch (_) {
      // 忽略远端会话已结束的情况。
    }
    client.close();
  }
}

class OpencodeSshClient {
  Future<ManagedSshConnection> connect({
    required ServerConfig server,
    required int localPort,
    void Function(SshConnectionStage stage)? onStageChanged,
  }) async {
    onStageChanged?.call(SshConnectionStage.sshHandshake);
    final socket = await SSHSocket.connect(server.host, server.sshPort);

    final client = SSHClient(
      socket,
      username: server.username,
      onPasswordRequest: server.authType == SshAuthType.password
          ? () => server.password
          : null,
      identities: server.authType == SshAuthType.pemKey && server.pemKey.isNotEmpty
          ? SSHKeyPair.fromPem(server.pemKey)
          : null,
      onVerifyHostKey: (_, __) => true,
      keepAliveInterval: const Duration(seconds: 30),
    );

    onStageChanged?.call(SshConnectionStage.authentication);
    await client.authenticated;

    onStageChanged?.call(SshConnectionStage.startingOpencode);
    final stdoutBuffer = StringBuffer();
    final stderrBuffer = StringBuffer();
    // 补全常见安装路径（bun/npm/go/local），再 source .bashrc，确保非交互 SSH 也能找到 opencode
    final launchCmd = 'export PATH="\$HOME/.opencode/bin:\$HOME/.bun/bin:\$HOME/.local/bin:\$HOME/go/bin:\$HOME/.npm-global/bin:/usr/local/bin:\$PATH"; '
        'source \$HOME/.bashrc 2>/dev/null || true; '
        'exec opencode serve --port ${server.opencodePort}';  // exec 替换 bash 进程，SIGTERM/SIGKILL 直接打到 opencode
    final session = await client.execute('bash -l -c \'$launchCmd\'');
    final stdoutSubscription = session.stdout
        .cast<List<int>>()
        .transform(utf8.decoder)
        .listen(stdoutBuffer.write);
    final stderrSubscription = session.stderr
        .cast<List<int>>()
        .transform(utf8.decoder)
        .listen(stderrBuffer.write);

    var exitedEarly = false;
    unawaited(session.done.then((_) {
      exitedEarly = true;
    }));

    // 等待 opencode 进程有时间报错后再判断是否早退（2s 以防服务器延迟响应）
    await Future<void>.delayed(const Duration(milliseconds: 2000));
    if (exitedEarly) {
      final stderr = stderrBuffer.toString().trim();
      final stdout = stdoutBuffer.toString().trim();
      final detail = stderr.isNotEmpty ? stderr : stdout;
      client.close();
      throw SshConnectionException(
        detail.isEmpty ? '远端 opencode 服务启动后立即退出。' : '远端 opencode 启动失败：$detail',
      );
    }

    String? tunnelError;
    onStageChanged?.call(SshConnectionStage.establishingTunnel);
    final localServer = await ServerSocket.bind(InternetAddress.loopbackIPv4, localPort);
    final acceptSubscription = localServer.listen((socket) async {
      try {
        final forward = await client.forwardLocal('localhost', server.opencodePort);
        unawaited(
          socket.cast<List<int>>().pipe(forward.sink).catchError((_) {}),
        );
        unawaited(
          forward.stream.cast<List<int>>().pipe(socket).catchError((_) {}),
        );
      } catch (e) {
        tunnelError = e.toString();
        socket.destroy();
      }
    });

    await _waitForOpencode(
      localPort,
      stdoutBuffer: stdoutBuffer,
      stderrBuffer: stderrBuffer,
      tunnelErrorGetter: () => tunnelError,
    );

    return ManagedSshConnection(
      client: client,
      opencodeSession: session,
      localServer: localServer,
      localPort: localPort,
      acceptSubscription: acceptSubscription,
      logSubscriptions: [stdoutSubscription, stderrSubscription],
    );
  }

  Future<void> _waitForOpencode(
    int localPort, {
    int maxAttempts = 30,
    required StringBuffer stdoutBuffer,
    required StringBuffer stderrBuffer,
    required String? Function() tunnelErrorGetter,
  }) async {
    // 先等 opencode 进程有足够时间监听端口
    await Future<void>.delayed(const Duration(seconds: 2));

    for (var i = 0; i < maxAttempts; i++) {
      final success = await _tryHealthCheck(localPort);
      if (success) return;
      await Future<void>.delayed(const Duration(milliseconds: 800));
    }

    final out = stdoutBuffer.toString().trim();
    final err = stderrBuffer.toString().trim();
    final tunnelErr = tunnelErrorGetter();
    final parts = <String>[
      if (err.isNotEmpty) '服务器stderr: $err',
      if (out.isNotEmpty) '服务器stdout: $out',
      if (tunnelErr != null) '隧道错误: $tunnelErr',
    ];
    throw SshConnectionException(
      parts.isNotEmpty
          ? '等待 opencode 启动超时。\n${parts.join('\n')}'
          : '等待 opencode 启动超时，请确认服务器上已安装 opencode 且在 PATH 中（可 SSH 登录后执行 opencode serve --port 4096 验证）。',
    );
  }

  Future<bool> _tryHealthCheck(int localPort) async {
    final httpClient = HttpClient();
    httpClient.connectionTimeout = const Duration(seconds: 3);
    try {
      await () async {
        final request = await httpClient.get('127.0.0.1', localPort, '/session');
        final response = await request.close();
        await response.drain<void>();
      }().timeout(const Duration(seconds: 5));
      // 成功完成 = opencode 已就绪
      return true;
    } catch (_) {
      return false;
    } finally {
      httpClient.close(force: true);
    }
  }
}
