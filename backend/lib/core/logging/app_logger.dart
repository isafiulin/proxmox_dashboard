import 'dart:convert';
import 'dart:io';

class AppLogger {
  const AppLogger({this.enabled = true});

  final bool enabled;

  void info(String event, Map<String, Object?> fields) {
    _write('info', event, fields);
  }

  void warning(String event, Map<String, Object?> fields) {
    _write('warning', event, fields);
  }

  void error(
    String event,
    Map<String, Object?> fields, {
    Object? error,
    StackTrace? stackTrace,
  }) {
    _write('error', event, <String, Object?>{
      ...fields,
      if (error != null) 'error': error.toString(),
      if (stackTrace != null) 'stackTrace': stackTrace.toString(),
    });
  }

  void _write(String level, String event, Map<String, Object?> fields) {
    if (!enabled) {
      return;
    }
    stderr.writeln(
      jsonEncode(<String, Object?>{
        'time': DateTime.now().toUtc().toIso8601String(),
        'level': level,
        'event': event,
        ...fields,
      }),
    );
  }
}
