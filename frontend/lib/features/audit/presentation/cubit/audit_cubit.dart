import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:frontend/core/error/api_exception.dart';
import 'package:frontend/features/audit/data/audit_repository.dart';
import 'package:frontend/features/audit/domain/audit_event.dart';

part 'audit_state.dart';

class AuditCubit extends Cubit<AuditState> {
  AuditCubit(this._repository) : super(const AuditState());

  final AuditRepository _repository;

  Future<void> load() async {
    emit(state.copyWith(status: AuditStatus.loading));
    try {
      emit(
        AuditState(
          status: AuditStatus.ready,
          items: await _repository.latest(),
        ),
      );
    } on ApiException catch (error) {
      emit(state.copyWith(status: AuditStatus.failure, error: error.message));
    } on Object {
      emit(
        state.copyWith(
          status: AuditStatus.failure,
          error: 'Не удалось загрузить аудит.',
        ),
      );
    }
  }
}
