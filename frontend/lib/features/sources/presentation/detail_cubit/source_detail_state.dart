part of 'source_detail_cubit.dart';

enum SourceDetailStatus { initial, loading, ready, failure }

class SourceDetailState extends Equatable {
  const SourceDetailState({
    this.status = SourceDetailStatus.initial,
    this.data,
    this.error,
  });

  final SourceDetailStatus status;
  final SourceRuntimeData? data;
  final String? error;

  SourceDetailState copyWith({
    SourceDetailStatus? status,
    SourceRuntimeData? data,
    String? error,
  }) {
    return SourceDetailState(
      status: status ?? this.status,
      data: data ?? this.data,
      error: error,
    );
  }

  @override
  List<Object?> get props => <Object?>[status, data, error];
}
