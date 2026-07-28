import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:frontend/core/routing/go_router_refresh_stream.dart';
import 'package:frontend/features/audit/presentation/pages/audit_page.dart';
import 'package:frontend/features/auth/presentation/cubit/auth_cubit.dart';
import 'package:frontend/features/auth/presentation/pages/login_page.dart';
import 'package:frontend/features/auth/presentation/pages/splash_page.dart';
import 'package:frontend/features/dashboard/presentation/pages/backup_health_page.dart';
import 'package:frontend/features/dashboard/presentation/pages/backup_missing_vm_page.dart';
import 'package:frontend/features/dashboard/presentation/pages/backup_policy_page.dart';
import 'package:frontend/features/dashboard/presentation/pages/backup_redundancy_page.dart';
import 'package:frontend/features/dashboard/presentation/pages/backup_schedule_page.dart';
import 'package:frontend/features/dashboard/presentation/pages/collection_metrics_page.dart';
import 'package:frontend/features/dashboard/presentation/pages/dashboard_shell.dart';
import 'package:frontend/features/dashboard/presentation/pages/hardware_health_page.dart';
import 'package:frontend/features/dashboard/presentation/pages/node_health_page.dart';
import 'package:frontend/features/dashboard/presentation/pages/overview_page.dart';
import 'package:frontend/features/dashboard/presentation/pages/pbs_health_page.dart';
import 'package:frontend/features/dashboard/presentation/pages/pbs_verify_page.dart';
import 'package:frontend/features/dashboard/presentation/pages/vm_health_page.dart';
import 'package:frontend/features/search/presentation/pages/search_page.dart';
import 'package:frontend/features/sources/presentation/pages/guest_detail_page.dart';
import 'package:frontend/features/sources/presentation/pages/node_detail_page.dart';
import 'package:frontend/features/sources/presentation/pages/source_detail_page.dart';
import 'package:frontend/features/sources/presentation/pages/sources_page.dart';
import 'package:frontend/features/users/presentation/pages/users_page.dart';
import 'package:go_router/go_router.dart';

GoRouter createAppRouter(BuildContext context) {
  final AuthCubit authCubit = context.read<AuthCubit>();

  return GoRouter(
    initialLocation: '/',
    refreshListenable: GoRouterRefreshStream(authCubit.stream),
    redirect: (BuildContext context, GoRouterState state) {
      final bool loggedIn = authCubit.state.user != null;
      final bool loggingIn = state.matchedLocation == '/login';
      final bool checkingAuth = state.matchedLocation == '/splash';

      if (authCubit.state.status == AuthStatus.loading) {
        return checkingAuth ? null : '/splash';
      }

      if (!loggedIn) {
        return loggingIn ? null : '/login';
      }
      if (loggingIn || checkingAuth) {
        return '/';
      }
      return null;
    },
    routes: <RouteBase>[
      GoRoute(
        path: '/splash',
        pageBuilder: (BuildContext context, GoRouterState state) =>
            _noTransitionPage(state, const SplashPage()),
      ),
      GoRoute(
        path: '/login',
        pageBuilder: (BuildContext context, GoRouterState state) =>
            _noTransitionPage(state, const LoginPage()),
      ),
      ShellRoute(
        builder: (BuildContext context, GoRouterState state, Widget child) {
          return DashboardShell(location: state.matchedLocation, child: child);
        },
        routes: <RouteBase>[
          GoRoute(
            path: '/',
            pageBuilder: (BuildContext context, GoRouterState state) =>
                _noTransitionPage(state, const OverviewPage()),
          ),
          GoRoute(
            path: '/backup-health',
            pageBuilder: (BuildContext context, GoRouterState state) =>
                _noTransitionPage(state, const BackupHealthPage()),
          ),
          GoRoute(
            path: '/backup-schedule',
            pageBuilder: (BuildContext context, GoRouterState state) =>
                _noTransitionPage(state, const BackupSchedulePage()),
          ),
          GoRoute(
            path: '/backup-policy',
            pageBuilder: (BuildContext context, GoRouterState state) =>
                _noTransitionPage(state, const BackupPolicyPage()),
          ),
          GoRoute(
            path: '/backup-redundancy',
            pageBuilder: (BuildContext context, GoRouterState state) =>
                _noTransitionPage(state, const BackupRedundancyPage()),
          ),
          GoRoute(
            path: '/backup-missing-vm',
            pageBuilder: (BuildContext context, GoRouterState state) =>
                _noTransitionPage(state, const BackupMissingVmPage()),
          ),
          GoRoute(
            path: '/pbs-health',
            pageBuilder: (BuildContext context, GoRouterState state) =>
                _noTransitionPage(state, const PbsHealthPage()),
          ),
          GoRoute(
            path: '/pbs-verify',
            pageBuilder: (BuildContext context, GoRouterState state) =>
                _noTransitionPage(state, const PbsVerifyPage()),
          ),
          GoRoute(
            path: '/node-health',
            pageBuilder: (BuildContext context, GoRouterState state) =>
                _noTransitionPage(state, const NodeHealthPage()),
          ),
          GoRoute(
            path: '/vm-health',
            pageBuilder: (BuildContext context, GoRouterState state) =>
                _noTransitionPage(state, const VmHealthPage()),
          ),
          GoRoute(
            path: '/hardware-health',
            pageBuilder: (BuildContext context, GoRouterState state) =>
                _noTransitionPage(state, const HardwareHealthPage()),
          ),
          GoRoute(
            path: '/collection-metrics',
            pageBuilder: (BuildContext context, GoRouterState state) =>
                _noTransitionPage(state, const CollectionMetricsPage()),
          ),
          GoRoute(
            path: '/sources',
            pageBuilder: (BuildContext context, GoRouterState state) =>
                _noTransitionPage(state, const SourcesPage()),
          ),
          GoRoute(
            path: '/search',
            pageBuilder: (BuildContext context, GoRouterState state) =>
                _noTransitionPage(state, const SearchPage()),
          ),
          GoRoute(
            path: '/sources/:sourceId',
            pageBuilder: (BuildContext context, GoRouterState state) =>
                _noTransitionPage(
                  state,
                  SourceDetailPage(sourceId: state.pathParameters['sourceId']!),
                ),
          ),
          GoRoute(
            path: '/sources/:sourceId/nodes/:node',
            pageBuilder: (BuildContext context, GoRouterState state) =>
                _noTransitionPage(
                  state,
                  NodeDetailPage(
                    sourceId: state.pathParameters['sourceId']!,
                    node: state.pathParameters['node']!,
                  ),
                ),
          ),
          GoRoute(
            path: '/sources/:sourceId/guests/:guestType/:node/:vmid',
            pageBuilder: (BuildContext context, GoRouterState state) =>
                _noTransitionPage(
                  state,
                  GuestDetailPage(
                    sourceId: state.pathParameters['sourceId']!,
                    guestType: state.pathParameters['guestType']!,
                    node: state.pathParameters['node']!,
                    vmid: state.pathParameters['vmid']!,
                    name: state.uri.queryParameters['name'] ?? '',
                  ),
                ),
          ),
          GoRoute(
            path: '/users',
            pageBuilder: (BuildContext context, GoRouterState state) =>
                _noTransitionPage(state, const UsersPage()),
          ),
          GoRoute(
            path: '/audit',
            pageBuilder: (BuildContext context, GoRouterState state) =>
                _noTransitionPage(state, const AuditPage()),
          ),
        ],
      ),
    ],
  );
}

Page<void> _noTransitionPage(GoRouterState state, Widget child) {
  return NoTransitionPage<void>(key: state.pageKey, child: child);
}
