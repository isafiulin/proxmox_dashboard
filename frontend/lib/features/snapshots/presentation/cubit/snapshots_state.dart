part of 'snapshots_cubit.dart';

enum SnapshotsStatus { idle, loading, ready, failure }

class SnapshotsState extends Equatable {
  const SnapshotsState({
    this.status = SnapshotsStatus.idle,
    this.items = const <DataSnapshot>[],
  });

  final SnapshotsStatus status;
  final List<DataSnapshot> items;

  SnapshotsState copyWith({
    SnapshotsStatus? status,
    List<DataSnapshot>? items,
  }) {
    return SnapshotsState(
      status: status ?? this.status,
      items: items ?? this.items,
    );
  }

  @override
  List<Object?> get props => <Object?>[status, items];
}
