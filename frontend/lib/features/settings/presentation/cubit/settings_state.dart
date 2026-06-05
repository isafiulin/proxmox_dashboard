part of 'settings_cubit.dart';

enum SettingsStatus { idle, loading, ready, failure }

class SettingsState extends Equatable {
  const SettingsState({required this.status, required this.settings});

  factory SettingsState.initial() => SettingsState(
    status: SettingsStatus.idle,
    settings: SystemSettings.defaults(),
  );

  final SettingsStatus status;
  final SystemSettings settings;

  SettingsState copyWith({SettingsStatus? status, SystemSettings? settings}) {
    return SettingsState(
      status: status ?? this.status,
      settings: settings ?? this.settings,
    );
  }

  @override
  List<Object?> get props => <Object?>[status, settings];
}
