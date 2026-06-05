part of 'users_cubit.dart';

enum UsersStatus { initial, loading, ready, failure }

class UsersState extends Equatable {
  const UsersState({
    this.status = UsersStatus.initial,
    this.items = const <AppUser>[],
    this.error,
  });

  final UsersStatus status;
  final List<AppUser> items;
  final String? error;

  UsersState copyWith({
    UsersStatus? status,
    List<AppUser>? items,
    String? error,
  }) {
    return UsersState(
      status: status ?? this.status,
      items: items ?? this.items,
      error: error,
    );
  }

  @override
  List<Object?> get props => <Object?>[status, items, error];
}
