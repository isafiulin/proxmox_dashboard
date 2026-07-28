import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:frontend/core/error/api_exception.dart';
import 'package:frontend/features/sources/data/source_data_repository.dart';
import 'package:frontend/features/sources/domain/source.dart';

part 'source_detail_state.dart';

class SourceDetailCubit extends Cubit<SourceDetailState> {
  SourceDetailCubit(this._repository) : super(const SourceDetailState());

  final SourceDataRepository _repository;

  Future<void> load(Source source, {bool refreshRedfish = false}) async {
    emit(state.copyWith(status: SourceDetailStatus.loading));
    try {
      final data =
          (source.type == 'redfish' || source.type == 'old_ilo2') &&
              refreshRedfish
          ? SourceRuntimeData(
              redfish: await _repository.loadRedfish(
                source.id,
                refresh: true,
                sourceType: source.type,
              ),
            )
          : await _repository.load(source);
      emit(SourceDetailState(status: SourceDetailStatus.ready, data: data));
    } on ApiException catch (error) {
      emit(
        state.copyWith(
          status: SourceDetailStatus.failure,
          error: error.message,
        ),
      );
    } on Object {
      emit(
        state.copyWith(
          status: SourceDetailStatus.failure,
          error: 'Не удалось загрузить данные источника.',
        ),
      );
    }
  }
}
