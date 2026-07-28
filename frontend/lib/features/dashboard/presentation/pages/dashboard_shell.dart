import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:frontend/core/api/api_client.dart';
import 'package:frontend/core/design/app_breakpoints.dart';
import 'package:frontend/core/design/app_colors.dart';
import 'package:frontend/core/design/app_spacing.dart';
import 'package:frontend/features/audit/presentation/cubit/audit_cubit.dart';
import 'package:frontend/features/auth/presentation/cubit/auth_cubit.dart';
import 'package:frontend/features/dashboard/presentation/cubit/dashboard_cubit.dart';
import 'package:frontend/features/settings/presentation/cubit/settings_cubit.dart';
import 'package:frontend/features/snapshots/presentation/cubit/snapshots_cubit.dart';
import 'package:frontend/features/sources/presentation/cubit/sources_cubit.dart';
import 'package:frontend/features/users/presentation/cubit/users_cubit.dart';
import 'package:frontend/shared/widgets/app_button.dart';
import 'package:frontend/shared/widgets/app_text_field.dart';
import 'package:frontend/shared/widgets/scrollable_page_frame.dart';
import 'package:go_router/go_router.dart';

class DashboardShell extends StatelessWidget {
  const DashboardShell({
    required this.location,
    required this.child,
    super.key,
  });

  final String location;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return _DashboardFrame(location: location, child: child);
  }
}

class _DashboardFrame extends StatefulWidget {
  const _DashboardFrame({required this.location, required this.child});

  final String location;
  final Widget child;

  @override
  State<_DashboardFrame> createState() => _DashboardFrameState();
}

class _DashboardFrameState extends State<_DashboardFrame> {
  bool _collapsed = false;
  Timer? _refreshTimer;
  int? _currentRefreshMinutes;
  DateTime? _lastRefreshedAt;
  bool _refreshing = false;
  bool _versionRequested = false;
  _AppVersionInfo? _versionInfo;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncRefreshTimer(
      context.read<SettingsCubit>().state.settings.collectionIntervalMinutes,
    );
    if (!_versionRequested) {
      _versionRequested = true;
      unawaited(_loadVersionInfo());
    }
  }

  Future<void> _loadVersionInfo() async {
    try {
      final json = await context.read<ApiClient>().get('/health');
      if (mounted) {
        setState(() => _versionInfo = _AppVersionInfo.fromJson(json));
      }
    } catch (_) {
      if (mounted) {
        setState(() => _versionInfo = const _AppVersionInfo.unavailable());
      }
    }
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  void _syncRefreshTimer(int minutes) {
    if (_currentRefreshMinutes == minutes) {
      return;
    }
    _currentRefreshMinutes = minutes;
    _refreshTimer?.cancel();
    _refreshTimer = Timer.periodic(Duration(minutes: minutes), (_) {
      if (!mounted) {
        return;
      }
      unawaited(_runRefresh());
    });
  }

  Future<void> _runRefresh() async {
    if (_refreshing) {
      return;
    }
    setState(() => _refreshing = true);
    try {
      await _refreshAll(context);
      if (mounted) {
        setState(() => _lastRefreshedAt = DateTime.now());
      }
    } finally {
      if (mounted) {
        setState(() => _refreshing = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<SettingsCubit, SettingsState>(
      listenWhen: (previous, current) =>
          previous.settings.collectionIntervalMinutes !=
          current.settings.collectionIntervalMinutes,
      listener: (BuildContext context, SettingsState state) =>
          _syncRefreshTimer(state.settings.collectionIntervalMinutes),
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          final bool compact = constraints.maxWidth < AppBreakpoints.compact;
          final bool showExpandedSidebar =
              !compact && constraints.maxWidth >= AppBreakpoints.wide;
          final bool collapsed = compact || _collapsed || !showExpandedSidebar;
          final Widget navigation = _SidebarNavigation(
            location: widget.location,
            collapsed: collapsed,
            versionInfo: _versionInfo,
            onNavigate: (String path) {
              if (compact) {
                Navigator.of(context).pop();
              }
              context.go(path);
            },
            onToggle: compact
                ? null
                : () => setState(() => _collapsed = !_collapsed),
          );

          return Scaffold(
            drawer: compact ? Drawer(child: navigation) : null,
            body: Row(
              children: <Widget>[
                if (!compact) navigation,
                Expanded(
                  child: Column(
                    children: <Widget>[
                      _TopBar(
                        title: _titleForLocation(widget.location),
                        compact: compact,
                        refreshing: _refreshing,
                        lastRefreshedAt: _lastRefreshedAt,
                        onRefresh: _runRefresh,
                      ),
                      Expanded(
                        child: ScrollablePageFrame(
                          padding: EdgeInsets.all(
                            compact ? AppSpacing.lg : AppSpacing.xl,
                          ),
                          child: widget.child,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.title,
    required this.compact,
    required this.refreshing,
    required this.lastRefreshedAt,
    required this.onRefresh,
  });

  final String title;
  final bool compact;
  final bool refreshing;
  final DateTime? lastRefreshedAt;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    final AuthState authState = context.watch<AuthCubit>().state;
    final SettingsState settingsState = context.watch<SettingsCubit>().state;

    return Container(
      height: 72,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: <Widget>[
          if (compact) ...<Widget>[
            Builder(
              builder: (BuildContext context) {
                return IconButton(
                  tooltip: 'Меню',
                  onPressed: () => Scaffold.of(context).openDrawer(),
                  icon: const Icon(Icons.menu),
                );
              },
            ),
            const SizedBox(width: AppSpacing.sm),
          ],
          Text(title, style: Theme.of(context).textTheme.headlineSmall),
          const Spacer(),
          if (!compact) ...<Widget>[
            const Icon(Icons.circle, size: 8, color: AppColors.success),
            const SizedBox(width: 6),
            Text(
              refreshing
                  ? 'Обновление...'
                  : 'Polling включен · ${_formatRefreshTime(lastRefreshedAt)}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(width: 16),
          ],
          _RefreshIntervalSelector(
            minutes: settingsState.settings.collectionIntervalMinutes,
            onChanged: (int minutes) =>
                context.read<SettingsCubit>().updateInterval(minutes),
          ),
          const SizedBox(width: 8),
          IconButton(
            tooltip: 'Обновить',
            onPressed: refreshing ? null : onRefresh,
            icon: refreshing
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh),
          ),
          const SizedBox(width: 12),
          if (!compact)
            TextButton.icon(
              onPressed: () => _editProfile(context),
              icon: const Icon(Icons.account_circle_outlined),
              label: Text(authState.user?.displayName ?? ''),
            )
          else
            IconButton(
              tooltip: 'Профиль',
              onPressed: () => _editProfile(context),
              icon: const Icon(Icons.account_circle_outlined),
            ),
          const SizedBox(width: 12),
          AppSecondaryButton(
            label: 'Выйти',
            icon: Icons.logout,
            onPressed: () => context.read<AuthCubit>().logout(),
          ),
        ],
      ),
    );
  }
}

Future<void> _editProfile(BuildContext context) async {
  final user = context.read<AuthCubit>().state.user;
  if (user == null) {
    return;
  }
  final controller = TextEditingController(text: user.displayName);
  final bool? saved = await showDialog<bool>(
    context: context,
    builder: (BuildContext dialogContext) {
      return AlertDialog(
        title: const Text('Мой профиль'),
        content: SizedBox(
          width: 420,
          child: AppTextField(
            controller: controller,
            label: 'Имя',
            autofillHints: const <String>[AutofillHints.name],
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => context.pop(false),
            child: const Text('Отмена'),
          ),
          AppPrimaryButton(
            label: 'Сохранить',
            icon: Icons.save_outlined,
            onPressed: () => context.pop(true),
          ),
        ],
      );
    },
  );
  if (saved == true && context.mounted) {
    await context.read<AuthCubit>().updateProfile(
      displayName: controller.text.trim(),
    );
  }
  controller.dispose();
}

class _SidebarNavigation extends StatelessWidget {
  const _SidebarNavigation({
    required this.location,
    required this.collapsed,
    required this.versionInfo,
    required this.onNavigate,
    required this.onToggle,
  });

  final String location;
  final bool collapsed;
  final _AppVersionInfo? versionInfo;
  final ValueChanged<String> onNavigate;
  final VoidCallback? onToggle;

  @override
  Widget build(BuildContext context) {
    final width = collapsed ? 84.0 : 248.0;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      width: width,
      color: AppColors.sidebar,
      child: SafeArea(
        child: Column(
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: collapsed
                  ? IconButton(
                      tooltip: onToggle == null
                          ? 'NeoTelecom'
                          : 'Развернуть меню',
                      color: AppColors.primary,
                      onPressed: onToggle,
                      icon: const Icon(Icons.dns_outlined),
                    )
                  : Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: <Widget>[
                        const Icon(
                          Icons.dns_outlined,
                          color: AppColors.primary,
                        ),
                        Text(
                          'NeoTelecom',
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(color: Colors.white),
                        ),
                        if (onToggle != null)
                          IconButton(
                            tooltip: 'Свернуть меню',
                            color: AppColors.sidebarMuted,
                            onPressed: onToggle,
                            icon: const Icon(Icons.menu),
                          ),
                      ],
                    ),
            ),
            Expanded(
              child: ListView(
                padding: EdgeInsets.zero,
                children: <Widget>[
                  for (final section in _navSections)
                    collapsed
                        ? _CollapsedSidebarSection(
                            section: section,
                            selectedPath: _selectedPath(location),
                            onNavigate: onNavigate,
                          )
                        : _ExpandedSidebarSection(
                            section: section,
                            selectedPath: _selectedPath(location),
                            onNavigate: onNavigate,
                          ),
                ],
              ),
            ),
            _VersionLabel(collapsed: collapsed, info: versionInfo),
            const SizedBox(height: AppSpacing.sm),
          ],
        ),
      ),
    );
  }
}

class _ExpandedSidebarSection extends StatelessWidget {
  const _ExpandedSidebarSection({
    required this.section,
    required this.selectedPath,
    required this.onNavigate,
  });

  final _NavSection section;
  final String selectedPath;
  final ValueChanged<String> onNavigate;

  @override
  Widget build(BuildContext context) {
    final selected = section.items.any((item) => item.path == selectedPath);
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        key: ValueKey('${section.label}:$selected'),
        initiallyExpanded: selected,
        maintainState: true,
        tilePadding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
        childrenPadding: const EdgeInsets.only(bottom: AppSpacing.xs),
        leading: Icon(
          section.icon,
          size: 20,
          color: selected ? Colors.white : AppColors.sidebarMuted,
        ),
        title: Text(
          section.label,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: selected ? Colors.white : AppColors.sidebarMuted,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
          ),
        ),
        iconColor: Colors.white,
        collapsedIconColor: AppColors.sidebarMuted,
        children: section.items
            .map(
              (item) => _SidebarItem(
                item: item,
                selected: selectedPath == item.path,
                collapsed: false,
                onTap: () => onNavigate(item.path),
              ),
            )
            .toList(),
      ),
    );
  }
}

class _CollapsedSidebarSection extends StatelessWidget {
  const _CollapsedSidebarSection({
    required this.section,
    required this.selectedPath,
    required this.onNavigate,
  });

  final _NavSection section;
  final String selectedPath;
  final ValueChanged<String> onNavigate;

  @override
  Widget build(BuildContext context) {
    final selected = section.items.any((item) => item.path == selectedPath);
    final color = selected ? Colors.white : AppColors.sidebarMuted;
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.xs,
      ),
      child: PopupMenuButton<String>(
        tooltip: section.label,
        offset: const Offset(64, 0),
        onSelected: onNavigate,
        itemBuilder: (context) => section.items
            .map(
              (item) => PopupMenuItem<String>(
                value: item.path,
                child: Row(
                  children: <Widget>[
                    Icon(item.icon, size: 20),
                    const SizedBox(width: AppSpacing.md),
                    Text(item.label),
                  ],
                ),
              ),
            )
            .toList(),
        child: Container(
          height: 44,
          decoration: BoxDecoration(
            color: selected ? AppColors.primary : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Center(child: Icon(section.icon, color: color, size: 21)),
        ),
      ),
    );
  }
}

class _VersionLabel extends StatelessWidget {
  const _VersionLabel({required this.collapsed, required this.info});

  final bool collapsed;
  final _AppVersionInfo? info;

  @override
  Widget build(BuildContext context) {
    final value = info;
    final text = value == null
        ? 'Версия загружается...'
        : 'Frontend ${value.frontendVersion}\n'
              'Backend ${value.backendVersion}\n'
              'Commit ${value.gitCommit}';
    if (collapsed) {
      return Tooltip(
        message: text,
        child: const Padding(
          padding: EdgeInsets.all(AppSpacing.md),
          child: Icon(
            Icons.info_outline,
            size: 18,
            color: AppColors.sidebarMuted,
          ),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      child: Text(
        text,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
          color: AppColors.sidebarMuted,
          height: 1.45,
        ),
      ),
    );
  }
}

class _AppVersionInfo {
  const _AppVersionInfo({
    required this.frontendVersion,
    required this.backendVersion,
    required this.gitCommit,
  });

  const _AppVersionInfo.unavailable()
    : frontendVersion = 'unknown',
      backendVersion = 'unavailable',
      gitCommit = 'unknown';

  factory _AppVersionInfo.fromJson(Map<String, Object?> json) {
    return _AppVersionInfo(
      frontendVersion: json['frontendVersion']?.toString() ?? 'unknown',
      backendVersion:
          json['backendVersion']?.toString() ??
          json['version']?.toString() ??
          'unknown',
      gitCommit: json['gitCommit']?.toString() ?? 'unknown',
    );
  }

  final String frontendVersion;
  final String backendVersion;
  final String gitCommit;
}

class _SidebarItem extends StatelessWidget {
  const _SidebarItem({
    required this.item,
    required this.selected,
    required this.collapsed,
    required this.onTap,
  });

  final _NavItem item;
  final bool selected;
  final bool collapsed;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? Colors.white : AppColors.sidebarMuted;
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.xs,
      ),
      child: Tooltip(
        message: collapsed ? item.label : '',
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onTap,
          child: Container(
            height: 44,
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
            decoration: BoxDecoration(
              color: selected ? AppColors.primary : Colors.transparent,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisAlignment: collapsed
                  ? MainAxisAlignment.center
                  : MainAxisAlignment.start,
              children: <Widget>[
                Icon(item.icon, color: color, size: 21),
                if (!collapsed) ...<Widget>[
                  const SizedBox(width: AppSpacing.md),
                  Text(
                    item.label,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: color,
                      fontWeight: selected ? FontWeight.w700 : null,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RefreshIntervalSelector extends StatelessWidget {
  const _RefreshIntervalSelector({
    required this.minutes,
    required this.onChanged,
  });

  final int minutes;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return DropdownButton<int>(
      value: <int>[5, 15, 30, 60].contains(minutes) ? minutes : 30,
      underline: const SizedBox.shrink(),
      borderRadius: BorderRadius.circular(8),
      items: const <DropdownMenuItem<int>>[
        DropdownMenuItem<int>(value: 5, child: Text('5 мин')),
        DropdownMenuItem<int>(value: 15, child: Text('15 мин')),
        DropdownMenuItem<int>(value: 30, child: Text('30 мин')),
        DropdownMenuItem<int>(value: 60, child: Text('1 час')),
      ],
      onChanged: (int? value) {
        if (value != null) {
          onChanged(value);
        }
      },
    );
  }
}

class _NavItem {
  const _NavItem({required this.path, required this.label, required this.icon});

  final String path;
  final String label;
  final IconData icon;
}

class _NavSection {
  const _NavSection({
    required this.label,
    required this.icon,
    required this.items,
  });

  final String label;
  final IconData icon;
  final List<_NavItem> items;
}

const List<_NavSection> _navSections = <_NavSection>[
  _NavSection(
    label: 'Главное',
    icon: Icons.dashboard_outlined,
    items: <_NavItem>[
      _NavItem(path: '/', label: 'Обзор', icon: Icons.dashboard_outlined),
      _NavItem(path: '/search', label: 'Поиск', icon: Icons.search),
    ],
  ),
  _NavSection(
    label: 'PVE',
    icon: Icons.hub_outlined,
    items: <_NavItem>[
      _NavItem(
        path: '/node-health',
        label: 'Node health',
        icon: Icons.hub_outlined,
      ),
      _NavItem(
        path: '/vm-health',
        label: 'VM health',
        icon: Icons.developer_board_outlined,
      ),
    ],
  ),
  _NavSection(
    label: 'Backup',
    icon: Icons.backup_outlined,
    items: <_NavItem>[
      _NavItem(
        path: '/backup-health',
        label: 'Backup health',
        icon: Icons.health_and_safety_outlined,
      ),
      _NavItem(
        path: '/backup-schedule',
        label: 'Backup schedule',
        icon: Icons.calendar_month_outlined,
      ),
      _NavItem(
        path: '/backup-policy',
        label: 'Backup policy',
        icon: Icons.policy_outlined,
      ),
      _NavItem(
        path: '/backup-redundancy',
        label: 'Backup redundancy',
        icon: Icons.security_outlined,
      ),
      _NavItem(
        path: '/backup-missing-vm',
        label: 'Backup missing VM',
        icon: Icons.manage_search_outlined,
      ),
      _NavItem(
        path: '/pbs-health',
        label: 'PBS health',
        icon: Icons.monitor_heart_outlined,
      ),
      _NavItem(
        path: '/pbs-verify',
        label: 'PBS verify state',
        icon: Icons.fact_check_outlined,
      ),
    ],
  ),
  _NavSection(
    label: 'Управление',
    icon: Icons.settings_outlined,
    items: <_NavItem>[
      _NavItem(
        path: '/collection-metrics',
        label: 'Collection metrics',
        icon: Icons.query_stats_outlined,
      ),
      _NavItem(
        path: '/sources',
        label: 'Источники',
        icon: Icons.storage_outlined,
      ),
      _NavItem(
        path: '/users',
        label: 'Пользователи',
        icon: Icons.people_outline,
      ),
      _NavItem(path: '/audit', label: 'Аудит', icon: Icons.fact_check_outlined),
    ],
  ),
  _NavSection(
    label: 'Оборудование',
    icon: Icons.developer_board_outlined,
    items: <_NavItem>[
      _NavItem(
        path: '/hardware-health',
        label: 'Hardware health',
        icon: Icons.developer_board_outlined,
      ),
    ],
  ),
];

Future<void> _refreshAll(BuildContext context) async {
  await Future.wait(<Future<void>>[
    context.read<DashboardCubit>().load(),
    context.read<SourcesCubit>().load(),
    context.read<UsersCubit>().load(),
    context.read<AuditCubit>().load(),
    context.read<SnapshotsCubit>().load(),
  ]);
}

String _formatRefreshTime(DateTime? value) {
  if (value == null) {
    return 'ожидает первого обновления';
  }
  String two(int number) => number.toString().padLeft(2, '0');
  return '${two(value.hour)}:${two(value.minute)}:${two(value.second)}';
}

String _selectedPath(String location) {
  if (location.startsWith('/sources')) {
    return '/sources';
  }
  return switch (location) {
    '/backup-health' => '/backup-health',
    '/backup-schedule' => '/backup-schedule',
    '/backup-policy' => '/backup-policy',
    '/backup-redundancy' => '/backup-redundancy',
    '/backup-missing-vm' => '/backup-missing-vm',
    '/pbs-health' => '/pbs-health',
    '/pbs-verify' => '/pbs-verify',
    '/node-health' => '/node-health',
    '/vm-health' => '/vm-health',
    '/hardware-health' => '/hardware-health',
    '/search' => '/search',
    '/collection-metrics' => '/collection-metrics',
    '/users' => '/users',
    '/audit' => '/audit',
    _ => '/',
  };
}

String _titleForLocation(String location) {
  if (location.startsWith('/sources/')) {
    return 'Источник';
  }
  return switch (location) {
    '/backup-health' => 'Backup health',
    '/backup-schedule' => 'Backup schedule',
    '/backup-policy' => 'Backup policy',
    '/backup-redundancy' => 'Backup redundancy',
    '/backup-missing-vm' => 'Backup missing VM',
    '/pbs-health' => 'PBS health',
    '/pbs-verify' => 'PBS verify state',
    '/node-health' => 'Node health',
    '/vm-health' => 'VM health',
    '/hardware-health' => 'Hardware health',
    '/search' => 'Поиск',
    '/collection-metrics' => 'Collection metrics',
    '/sources' => 'Источники',
    '/users' => 'Пользователи',
    '/audit' => 'Аудит',
    _ => 'Обзор',
  };
}
