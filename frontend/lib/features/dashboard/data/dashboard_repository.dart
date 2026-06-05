import 'package:frontend/core/api/api_client.dart';
import 'package:frontend/features/dashboard/domain/dashboard_summary.dart';

class DashboardRepository {
  DashboardRepository(this._api);

  final ApiClient _api;

  Future<DashboardSummary> summary() async {
    return DashboardSummary.fromJson(await _api.get('/dashboard/summary'));
  }
}
