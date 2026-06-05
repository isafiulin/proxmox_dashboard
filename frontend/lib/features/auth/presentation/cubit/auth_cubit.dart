import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:frontend/core/error/api_exception.dart';
import 'package:frontend/features/auth/data/auth_repository.dart';
import 'package:frontend/features/auth/domain/app_user.dart';

part 'auth_state.dart';

class AuthCubit extends Cubit<AuthState> {
  AuthCubit(this._repository)
    : super(const AuthState(status: AuthStatus.loading));

  final AuthRepository _repository;

  Future<void> restore() async {
    emit(state.copyWith(status: AuthStatus.loading));
    try {
      final session = await _repository.restore();
      if (session == null) {
        emit(const AuthState());
        return;
      }
      emit(AuthState(status: AuthStatus.authenticated, user: session.user));
    } on ApiException {
      await _repository.clearSession();
      emit(const AuthState());
    } catch (_) {
      await _repository.clearSession();
      emit(const AuthState());
    }
  }

  Future<void> login(String email, String password) async {
    emit(state.copyWith(status: AuthStatus.loading));
    try {
      final session = await _repository.login(email, password);
      emit(AuthState(status: AuthStatus.authenticated, user: session.user));
    } on ApiException catch (error) {
      emit(state.copyWith(status: AuthStatus.failure, error: error.message));
    } catch (_) {
      emit(
        state.copyWith(
          status: AuthStatus.failure,
          error: 'Не удалось подключиться к backend API.',
        ),
      );
    }
  }

  Future<void> logout() async {
    await _repository.logout();
    emit(const AuthState());
  }

  Future<void> updateProfile({required String displayName}) async {
    final user = await _repository.updateProfile(displayName: displayName);
    emit(AuthState(status: AuthStatus.authenticated, user: user));
  }
}
