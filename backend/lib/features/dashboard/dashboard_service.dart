import 'package:neotelecom_backend/core/store/app_store.dart';

class DashboardService {
  DashboardService(this._store);

  final AppStore _store;

  Map<String, Object?> summary() => {
        'sources': _store.sources.length,
        'nodes': 0,
        'guests': 0,
        'criticalAlerts': 0,
        'users': _store.users.where((user) => user.isActive).length,
        'message': 'Sources and users API is running',
      };
}
