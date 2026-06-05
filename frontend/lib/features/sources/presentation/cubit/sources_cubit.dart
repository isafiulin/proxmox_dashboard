import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:frontend/core/error/api_exception.dart';
import 'package:frontend/features/sources/data/sources_repository.dart';
import 'package:frontend/features/sources/domain/source.dart';
import 'package:frontend/features/sources/domain/source_test_result.dart';

part 'sources_state.dart';

class SourcesCubit extends Cubit<SourcesState> {
  SourcesCubit(this._repository) : super(const SourcesState());

  final SourcesRepository _repository;

  Future<void> load() async {
    emit(state.copyWith(status: SourcesStatus.loading));
    try {
      emit(
        SourcesState(
          status: SourcesStatus.ready,
          items: await _repository.list(),
        ),
      );
    } on ApiException catch (error) {
      emit(state.copyWith(status: SourcesStatus.failure, error: error.message));
    } catch (_) {
      emit(
        state.copyWith(
          status: SourcesStatus.failure,
          error: 'Не удалось загрузить источники.',
        ),
      );
    }
  }

  Future<void> create({
    required String name,
    required String type,
    required String baseUrl,
    required String token,
  }) async {
    await _repository.create(
      name: name,
      type: type,
      baseUrl: baseUrl,
      token: token,
    );
    await load();
  }

  Future<SourceTestResult> test(String id) async {
    final SourceTestResult result = await _repository.test(id);
    await load();
    return result;
  }

  Future<void> update({
    required String id,
    required String name,
    required String type,
    required String baseUrl,
    required String token,
  }) async {
    await _repository.update(
      id: id,
      name: name,
      type: type,
      baseUrl: baseUrl,
      token: token,
    );
    await load();
  }

  Future<void> remove(String id) async {
    await _repository.delete(id);
    await load();
  }
}
