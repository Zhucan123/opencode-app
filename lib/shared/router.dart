import 'package:code_app/core/storage/server_config_store.dart';
import 'package:code_app/features/chat/chat_screen.dart';
import 'package:code_app/features/connection/connecting_screen.dart';
import 'package:code_app/features/servers/server_form_screen.dart';
import 'package:code_app/features/servers/server_list_screen.dart';
import 'package:code_app/features/sessions/session_list_screen.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

final appRouterProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(
        path: '/',
        builder: (context, state) => const ServerListScreen(),
      ),
      GoRoute(
        path: '/servers/new',
        builder: (context, state) => ServerFormScreen(
          initialServer: state.extra is ServerConfig ? state.extra as ServerConfig : null,
        ),
      ),
      GoRoute(
        path: '/servers/:serverId/connecting',
        builder: (context, state) {
          return ConnectingScreen(serverId: state.pathParameters['serverId']!);
        },
      ),
      GoRoute(
        path: '/servers/:serverId/sessions',
        builder: (context, state) {
          return SessionListScreen(serverId: state.pathParameters['serverId']!);
        },
      ),
      GoRoute(
        path: '/servers/:serverId/sessions/:sessionId/chat',
        builder: (context, state) {
          return ChatScreen(
            serverId: state.pathParameters['serverId']!,
            sessionId: state.pathParameters['sessionId']!,
          );
        },
      ),
    ],
  );
});
