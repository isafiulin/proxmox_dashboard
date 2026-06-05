part of 'auth_cubit.dart';

enum AuthStatus { idle, loading, authenticated, failure }

class AuthState extends Equatable {
  const AuthState({this.status = AuthStatus.idle, this.user, this.error});

  final AuthStatus status;
  final AppUser? user;
  final String? error;

  AuthState copyWith({AuthStatus? status, AppUser? user, String? error}) {
    return AuthState(
      status: status ?? this.status,
      user: user ?? this.user,
      error: error,
    );
  }

  @override
  List<Object?> get props => [status, user, error];
}
