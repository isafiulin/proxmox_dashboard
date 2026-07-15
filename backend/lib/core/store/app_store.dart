import 'package:neotelecom_backend/features/collection/data_snapshot.dart';
import 'package:neotelecom_backend/features/settings/system_settings.dart';
import 'package:neotelecom_backend/features/sources/source.dart';
import 'package:neotelecom_backend/features/users/user.dart';

abstract interface class AppStore {
  List<User> get users;

  List<Source> get sources;

  List<Map<String, Object?>> get auditEvents;

  List<DataSnapshot> get dataSnapshots;

  SystemSettings get settings;

  Future<void> load();

  Future<void> save();

  Future<bool> checkHealth();
}
