import 'package:code_app/features/connection/connection_provider.dart';
import 'package:code_app/shared/router.dart';
import 'package:code_app/shared/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

void main() {
  runApp(const ProviderScope(child: OpenCodeApp()));
}

class OpenCodeApp extends ConsumerStatefulWidget {
  const OpenCodeApp({super.key});

  @override
  ConsumerState<OpenCodeApp> createState() => _OpenCodeAppState();
}

class _OpenCodeAppState extends ConsumerState<OpenCodeApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      final connections = ref.read(connectionRegistryProvider);
      for (final serverId in connections.keys) {
        ref.read(connectionProvider(serverId).notifier).healthCheckAndReconnect();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(appRouterProvider);

    return MaterialApp.router(
      title: 'opencode Mobile',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkTheme,
      routerConfig: router,
    );
  }
}
