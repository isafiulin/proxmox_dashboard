import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:frontend/core/error/api_exception.dart';
import 'package:frontend/features/sources/data/source_data_repository.dart';
import 'package:frontend/features/sources/domain/source.dart';

part 'source_detail_state.dart';

class SourceDetailCubit extends Cubit<SourceDetailState> {
  SourceDetailCubit(this._repository) : super(const SourceDetailState());

  final SourceDataRepository _repository;

  Future<void> load(Source source) async {
    emit(state.copyWith(status: SourceDetailStatus.loading));
    try {
      emit(
        SourceDetailState(
          status: SourceDetailStatus.ready,
          data: await _repository.load(source),
        ),
      );
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
