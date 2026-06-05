import 'package:frontend/core/api/api_client.dart';
import 'package:frontend/features/snapshots/domain/data_snapshot.dart';

class SnapshotsRepository {
  SnapshotsRepository(this._api);

  final ApiClient _api;

  Future<List<DataSnapshot>> latest({String? sourceId}) async {
    final path = sourceId == null
        ? '/data-snapshots'
        : '/data-snapshots?sourceId=${Uri.encodeQueryComponent(sourceId)}';
    final json = await _api.get(path);
    return ((json['items'] as List?) ?? <Object?>[])
        .whereType<Map>()
        .map((item) => DataSnapshot.fromJson(item.cast<String, Object?>()))
        .toList();
  }

  Future<void> collectNow() => _api.post('/data-snapshots/collect');
}
