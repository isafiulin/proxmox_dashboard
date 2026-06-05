import 'package:flutter/foundation.dart';

const appDebugLogs = bool.fromEnvironment('APP_DEBUG_LOGS', defaultValue: true);

class AppDebugLogger {
  const AppDebugLogger._();

  static void log(String message, {Object? error, StackTrace? stackTrace}) {
    if (!appDebugLogs) {
      return;
    }
    debugPrint('[NeoTelecom] $message');
    if (error != null) {
      debugPrint('[NeoTelecom] error: $error');
    }
    if (stackTrace != null) {
      debugPrint('[NeoTelecom] stackTrace:\n$stackTrace');
    }
  }
}
