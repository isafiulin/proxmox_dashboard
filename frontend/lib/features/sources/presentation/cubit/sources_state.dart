part of 'sources_cubit.dart';

enum SourcesStatus { initial, loading, ready, failure }

class SourcesState extends Equatable {
  const SourcesState({
    this.status = SourcesStatus.initial,
    this.items = const [],
    this.error,
  });

  final SourcesStatus status;
  final List<Source> items;
  final String? error;

  SourcesState copyWith({
    SourcesStatus? status,
    List<Source>? items,
    String? error,
  }) {
    return SourcesState(
      status: status ?? this.status,
      items: items ?? this.items,
      error: error,
    );
  }

  @override
  List<Object?> get props => [status, items, error];
}
