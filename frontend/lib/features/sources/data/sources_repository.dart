import 'package:frontend/core/api/api_client.dart';
import 'package:frontend/features/sources/domain/source.dart';
import 'package:frontend/features/sources/domain/source_test_result.dart';

class SourcesRepository {
  SourcesRepository(this._api);

  final ApiClient _api;

  Future<List<Source>> list() async {
    final json = await _api.get('/sources');
    return ((json['items'] as List?) ?? [])
        .map((item) => Source.fromJson(item as Map<String, Object?>))
        .toList();
  }

  Future<void> create({
    required String name,
    required String type,
    required String baseUrl,
    required String token,
    required String backupNamespace,
  }) async {
    await _api.post(
      '/sources',
      body: {
        'name': name,
        'type': type,
        'baseUrl': baseUrl,
        'token': token,
        'backupNamespace': backupNamespace,
      },
    );
  }

  Future<SourceTestResult> test(String id) async {
    return SourceTestResult.fromJson(await _api.post('/sources/$id/test'));
  }

  Future<void> update({
    required String id,
    required String name,
    required String type,
    required String baseUrl,
    required String token,
    required String backupNamespace,
  }) async {
    await _api.patch(
      '/sources/$id',
      body: <String, Object?>{
        'name': name,
        'type': type,
        'baseUrl': baseUrl,
        'token': token,
        'backupNamespace': backupNamespace,
      },
    );
  }

  Future<void> delete(String id) => _api.delete('/sources/$id');
}
