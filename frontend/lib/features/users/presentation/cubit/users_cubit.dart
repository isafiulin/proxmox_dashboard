import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:frontend/core/error/api_exception.dart';
import 'package:frontend/features/auth/domain/app_user.dart';
import 'package:frontend/features/users/data/users_repository.dart';

part 'users_state.dart';

class UsersCubit extends Cubit<UsersState> {
  UsersCubit(this._repository) : super(const UsersState());

  final UsersRepository _repository;

  Future<void> load() async {
    emit(state.copyWith(status: UsersStatus.loading));
    try {
      emit(
        UsersState(status: UsersStatus.ready, items: await _repository.list()),
      );
    } on ApiException catch (error) {
      emit(state.copyWith(status: UsersStatus.failure, error: error.message));
    } on Object {
      emit(
        state.copyWith(
          status: UsersStatus.failure,
          error: 'Не удалось загрузить пользователей.',
        ),
      );
    }
  }

  Future<void> create({
    required String displayName,
    required String email,
    required String password,
  }) async {
    await _repository.create(
      displayName: displayName,
      email: email,
      password: password,
    );
    await load();
  }

  Future<void> activate(String id) async {
    await _repository.activate(id);
    await load();
  }

  Future<void> deactivate(String id) async {
    await _repository.deactivate(id);
    await load();
  }
}
