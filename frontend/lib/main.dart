import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:frontend/core/api/api_client.dart';
import 'package:frontend/core/debug/app_debug_logger.dart';
import 'package:frontend/core/routing/app_router.dart';
import 'package:frontend/core/theme/app_theme.dart';
import 'package:frontend/features/audit/data/audit_repository.dart';
import 'package:frontend/features/audit/presentation/cubit/audit_cubit.dart';
import 'package:frontend/features/auth/data/auth_repository.dart';
import 'package:frontend/features/auth/presentation/cubit/auth_cubit.dart';
import 'package:frontend/features/dashboard/data/dashboard_repository.dart';
import 'package:frontend/features/dashboard/presentation/cubit/dashboard_cubit.dart';
import 'package:frontend/features/settings/data/settings_repository.dart';
import 'package:frontend/features/settings/presentation/cubit/settings_cubit.dart';
import 'package:frontend/features/snapshots/data/snapshots_repository.dart';
import 'package:frontend/features/snapshots/presentation/cubit/snapshots_cubit.dart';
import 'package:frontend/features/sources/data/sources_repository.dart';
import 'package:frontend/features/sources/presentation/cubit/sources_cubit.dart';
import 'package:frontend/features/users/data/users_repository.dart';
import 'package:frontend/features/users/presentation/cubit/users_cubit.dart';
import 'package:go_router/go_router.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  usePathUrlStrategy();
  GoRouter.optionURLReflectsImperativeAPIs = true;
  FlutterError.onError = (FlutterErrorDetails details) {
    FlutterError.presentError(details);
    AppDebugLogger.log(
      'Flutter error',
      error: details.exception,
      stackTrace: details.stack,
    );
  };
  PlatformDispatcher.instance.onError = (Object error, StackTrace stackTrace) {
    AppDebugLogger.log(
      'Uncaught platform error',
      error: error,
      stackTrace: stackTrace,
    );
    return false;
  };
  runApp(const NeoTelecomApp());
}

class NeoTelecomApp extends StatelessWidget {
  const NeoTelecomApp({super.key});

  @override
  Widget build(BuildContext context) {
    return RepositoryProvider<ApiClient>(
      create: (_) => ApiClient(),
      child: MultiRepositoryProvider(
        providers: <RepositoryProvider<dynamic>>[
          RepositoryProvider<AuthRepository>(
            create: (context) => AuthRepository(context.read<ApiClient>()),
          ),
          RepositoryProvider<DashboardRepository>(
            create: (context) => DashboardRepository(context.read<ApiClient>()),
          ),
          RepositoryProvider<SourcesRepository>(
            create: (context) => SourcesRepository(context.read<ApiClient>()),
          ),
          RepositoryProvider<UsersRepository>(
            create: (context) => UsersRepository(context.read<ApiClient>()),
          ),
          RepositoryProvider<AuditRepository>(
            create: (context) => AuditRepository(context.read<ApiClient>()),
          ),
          RepositoryProvider<SettingsRepository>(
            create: (context) => SettingsRepository(context.read<ApiClient>()),
          ),
          RepositoryProvider<SnapshotsRepository>(
            create: (context) => SnapshotsRepository(context.read<ApiClient>()),
          ),
        ],
        child: MultiBlocProvider(
          providers: <BlocProvider<dynamic>>[
            BlocProvider<AuthCubit>(
              create: (context) =>
                  AuthCubit(context.read<AuthRepository>())..restore(),
            ),
            BlocProvider<DashboardCubit>(
              create: (context) =>
                  DashboardCubit(context.read<DashboardRepository>())..load(),
            ),
            BlocProvider<SourcesCubit>(
              create: (context) =>
                  SourcesCubit(context.read<SourcesRepository>())..load(),
            ),
            BlocProvider<UsersCubit>(
              create: (context) =>
                  UsersCubit(context.read<UsersRepository>())..load(),
            ),
            BlocProvider<AuditCubit>(
              create: (context) =>
                  AuditCubit(context.read<AuditRepository>())..load(),
            ),
            BlocProvider<SettingsCubit>(
              create: (context) =>
                  SettingsCubit(context.read<SettingsRepository>())..load(),
            ),
            BlocProvider<SnapshotsCubit>(
              create: (context) =>
                  SnapshotsCubit(context.read<SnapshotsRepository>())..load(),
            ),
          ],
          child: const _RouterApp(),
        ),
      ),
    );
  }
}

class _RouterApp extends StatelessWidget {
  const _RouterApp();

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'NeoTelecom',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      routerConfig: createAppRouter(context),
    );
  }
}
