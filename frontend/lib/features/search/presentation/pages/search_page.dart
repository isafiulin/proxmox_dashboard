import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:frontend/core/api/api_client.dart';
import 'package:frontend/features/sources/data/source_data_repository.dart';
import 'package:frontend/features/sources/domain/backup_analysis.dart';
import 'package:frontend/features/sources/domain/source.dart';
import 'package:frontend/features/sources/presentation/cubit/sources_cubit.dart';
import 'package:frontend/shared/widgets/app_card.dart';
import 'package:frontend/shared/widgets/app_text_field.dart';
import 'package:frontend/shared/widgets/async_state_view.dart';
import 'package:frontend/shared/widgets/empty_state.dart';
import 'package:frontend/shared/widgets/page_header.dart';
import 'package:frontend/shared/widgets/status_chip.dart';
import 'package:go_router/go_router.dart';

class SearchPage extends StatefulWidget {
  const SearchPage({super.key});

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  final TextEditingController _controller = TextEditingController();
  String _query = '';
  String _sourcesKey = '';
  Future<List<_SearchItem>>? _itemsFuture;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<SourcesCubit, SourcesState>(
      builder: (BuildContext context, SourcesState state) {
        if (state.status == SourcesStatus.loading && state.items.isEmpty) {
          return const LoadingStateView();
        }
        final sourcesKey = identityHashCode(state.items).toString();
        if (_itemsFuture == null || _sourcesKey != sourcesKey) {
          _sourcesKey = sourcesKey;
          _itemsFuture = _load(context, state.items);
        }
        return FutureBuilder<List<_SearchItem>>(
          future: _itemsFuture,
          builder:
              (
                BuildContext context,
                AsyncSnapshot<List<_SearchItem>> snapshot,
              ) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const LoadingStateView();
                }
                if (snapshot.hasError) {
                  return ErrorStateView(message: snapshot.error.toString());
                }
                final items = _filter(snapshot.data ?? const <_SearchItem>[]);
                final nodes = items
                    .where((item) => item.kind == _SearchKind.node)
                    .toList();
                final guests = items
                    .where((item) => item.kind == _SearchKind.guest)
                    .toList();
                final backups = items
                    .where(
                      (item) =>
                          item.kind == _SearchKind.backupGroup ||
                          item.kind == _SearchKind.orphanBackup,
                    )
                    .toList();
                final sourceItems = items
                    .where((item) => item.kind == _SearchKind.source)
                    .toList();
                return DefaultTabController(
                  length: 5,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      const PageHeader(
                        title: 'Поиск',
                        subtitle:
                            'VM, node, source, backup group и orphan backup',
                      ),
                      const SizedBox(height: 16),
                      AppCard(
                        child: AppTextField(
                          controller: _controller,
                          label:
                              'Имя, VMID, node, source, datastore, namespace',
                          prefixIcon: Icons.search,
                          onChanged: (String value) =>
                              setState(() => _query = value),
                        ),
                      ),
                      const SizedBox(height: 16),
                      AppCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            TabBar(
                              isScrollable: true,
                              tabs: <Widget>[
                                Tab(text: 'Все (${items.length})'),
                                Tab(text: 'Ноды (${nodes.length})'),
                                Tab(text: 'VM/LXC (${guests.length})'),
                                Tab(text: 'Backups (${backups.length})'),
                                Tab(text: 'Sources (${sourceItems.length})'),
                              ],
                            ),
                            const SizedBox(height: 12),
                            SizedBox(
                              height: 560,
                              child: TabBarView(
                                children: <Widget>[
                                  _SearchResults(items: items),
                                  _SearchResults(items: nodes),
                                  _SearchResults(items: guests),
                                  _SearchResults(items: backups),
                                  _SearchResults(items: sourceItems),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
        );
      },
    );
  }

  Future<List<_SearchItem>> _load(
    BuildContext context,
    List<Source> sources,
  ) async {
    final repository = SourceDataRepository(context.read<ApiClient>());
    final items = <_SearchItem>[];
    final deployedGuests = <Map<String, Object?>>[];
    for (final source in sources) {
      items.add(
        _SearchItem(
          kind: _SearchKind.source,
          sourceId: source.id,
          sourceName: source.name,
          node: '',
          title: source.name,
          subtitle: '${source.type} · ${source.baseUrl}',
          status: source.status,
        ),
      );
    }
    for (final source in sources.where(
      (Source item) => item.type == 'proxmox_ve',
    )) {
      final data = await repository.loadProxmoxVe(source.id);
      final namespaces = backupNamespacesFromStorageConfig(
        data.storageConfig,
        manualNamespace: source.backupNamespace,
      );
      for (final node in data.nodes) {
        final nodeName = node['node']?.toString() ?? '';
        if (nodeName.isEmpty) {
          continue;
        }
        items.add(
          _SearchItem(
            kind: _SearchKind.node,
            sourceId: source.id,
            sourceName: source.name,
            node: nodeName,
            title: nodeName,
            subtitle: source.name,
            status: node['status']?.toString() ?? 'unknown',
          ),
        );
      }
      for (final guest in data.vmResources.where(_isGuest)) {
        final guestType = guest['type']?.toString() ?? '';
        final vmid = guest['vmid']?.toString() ?? '';
        final node = guest['node']?.toString() ?? '';
        final name = guest['name']?.toString() ?? '';
        if (guestType.isEmpty || vmid.isEmpty || node.isEmpty) {
          continue;
        }
        deployedGuests.add(<String, Object?>{
          ...guest,
          'backupNamespaces': namespaces.isEmpty
              ? <String>[source.backupNamespace]
              : namespaces.toList(),
        });
        items.add(
          _SearchItem(
            kind: _SearchKind.guest,
            sourceId: source.id,
            sourceName: source.name,
            node: node,
            guestType: guestType,
            vmid: vmid,
            title: name.isEmpty ? '$guestType/$vmid' : name,
            subtitle: '${source.name} · $node · $guestType/$vmid',
            status: guest['status']?.toString() ?? 'unknown',
          ),
        );
      }
    }
    final seenBackupGroups = <String>{};
    for (final source in sources.where(
      (item) => item.type == 'proxmox_backup',
    )) {
      final data = await repository.loadProxmoxBackup(source.id);
      for (final snapshot in data.snapshots) {
        final type = snapshot['backup-type']?.toString() ?? '';
        final id = snapshot['backup-id']?.toString() ?? '';
        final datastore = snapshot['datastore']?.toString() ?? '';
        final namespace = snapshotNamespace(snapshot);
        final key =
            '${source.id}\u0001$datastore\u0001$namespace\u0001$type\u0001$id';
        if (type.isEmpty || id.isEmpty || !seenBackupGroups.add(key)) {
          continue;
        }
        final deployed = deployedGuests.any((guest) {
          final guestType = guest['type'] == 'lxc' ? 'ct' : 'vm';
          return guestType == type &&
              guest['vmid']?.toString() == id &&
              guestBackupNamespaces(guest).contains(namespace);
        });
        items.add(
          _SearchItem(
            kind: deployed ? _SearchKind.backupGroup : _SearchKind.orphanBackup,
            sourceId: source.id,
            sourceName: source.name,
            node: '',
            title: '$type/$id',
            subtitle:
                '${source.name} · $datastore · ${namespace.isEmpty ? 'root' : namespace}',
            status: deployed ? 'backup' : 'orphan',
          ),
        );
      }
    }
    items.sort((left, right) => left.title.compareTo(right.title));
    return items;
  }

  List<_SearchItem> _filter(List<_SearchItem> items) {
    final query = _query.trim().toLowerCase();
    if (query.isEmpty) {
      return items;
    }
    return items.where((item) => item.searchText.contains(query)).toList();
  }
}

class _SearchResults extends StatelessWidget {
  const _SearchResults({required this.items});

  final List<_SearchItem> items;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return const EmptyState(
        icon: Icons.search_off_outlined,
        text: 'Совпадений пока нет.',
      );
    }
    return ListView.separated(
      itemCount: items.length,
      separatorBuilder: (BuildContext context, int index) =>
          const Divider(height: 1),
      itemBuilder: (BuildContext context, int index) {
        final item = items[index];
        return ListTile(
          leading: Icon(switch (item.kind) {
            _SearchKind.node => Icons.hub_outlined,
            _SearchKind.guest => Icons.developer_board_outlined,
            _SearchKind.source => Icons.dns_outlined,
            _SearchKind.backupGroup => Icons.backup_outlined,
            _SearchKind.orphanBackup => Icons.link_off_outlined,
          }),
          title: Text(item.title),
          subtitle: Text(item.subtitle),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              StatusChip(status: item.status),
              const SizedBox(width: 8),
              const Icon(Icons.chevron_right),
            ],
          ),
          onTap: () {
            if (item.kind == _SearchKind.node) {
              context.go(
                '/sources/${item.sourceId}/nodes/'
                '${Uri.encodeComponent(item.node)}',
              );
              return;
            }
            if (item.kind != _SearchKind.guest) {
              context.go('/sources/${item.sourceId}');
              return;
            }
            final query = item.title.isEmpty
                ? ''
                : '?name=${Uri.encodeQueryComponent(item.title)}';
            context.go(
              '/sources/${item.sourceId}/guests/${item.guestType}/'
              '${Uri.encodeComponent(item.node)}/${item.vmid}$query',
            );
          },
        );
      },
    );
  }
}

class _SearchItem {
  const _SearchItem({
    required this.kind,
    required this.sourceId,
    required this.sourceName,
    required this.node,
    required this.title,
    required this.subtitle,
    required this.status,
    this.guestType = '',
    this.vmid = '',
  });

  final _SearchKind kind;
  final String sourceId;
  final String sourceName;
  final String node;
  final String title;
  final String subtitle;
  final String status;
  final String guestType;
  final String vmid;

  String get searchText {
    return <String>[
      sourceName,
      node,
      title,
      subtitle,
      guestType,
      vmid,
      kind.name,
    ].join(' ').toLowerCase();
  }
}

enum _SearchKind { node, guest, backupGroup, orphanBackup, source }

bool _isGuest(Map<String, Object?> item) {
  return item['type'] == 'qemu' || item['type'] == 'lxc';
}
