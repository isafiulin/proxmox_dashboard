import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:frontend/core/error/api_exception.dart';
import 'package:frontend/features/dashboard/data/dashboard_repository.dart';
import 'package:frontend/features/dashboard/domain/dashboard_summary.dart';

part 'dashboard_state.dart';

class DashboardCubit extends Cubit<DashboardState> {
  DashboardCubit(this._repository) : super(const DashboardState());

  final DashboardRepository _repository;

  Future<void> load() async {
    emit(state.copyWith(status: DashboardStatus.loading));
    try {
      emit(
        DashboardState(
          status: DashboardStatus.ready,
          summary: await _repository.summary(),
        ),
      );
    } on ApiException catch (error) {
      emit(
        state.copyWith(status: DashboardStatus.failure, error: error.message),
      );
    } catch (_) {
      emit(
        state.copyWith(
          status: DashboardStatus.failure,
          error: 'Не удалось загрузить dashboard.',
        ),
      );
    }
  }
}
