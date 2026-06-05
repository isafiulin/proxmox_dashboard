import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:frontend/features/snapshots/data/snapshots_repository.dart';
import 'package:frontend/features/snapshots/domain/data_snapshot.dart';

part 'snapshots_state.dart';

class SnapshotsCubit extends Cubit<SnapshotsState> {
  SnapshotsCubit(this._repository) : super(const SnapshotsState());

  final SnapshotsRepository _repository;

  Future<void> load() async {
    emit(state.copyWith(status: SnapshotsStatus.loading));
    try {
      emit(
        SnapshotsState(
          status: SnapshotsStatus.ready,
          items: await _repository.latest(),
        ),
      );
    } catch (_) {
      emit(state.copyWith(status: SnapshotsStatus.failure));
    }
  }

  Future<void> collectNow() async {
    await _repository.collectNow();
    await load();
  }
}
