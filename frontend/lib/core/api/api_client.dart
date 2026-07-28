import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:frontend/core/debug/app_debug_logger.dart';
import 'package:frontend/core/error/api_exception.dart';

const apiBaseUrl = String.fromEnvironment('API_BASE_URL', defaultValue: '/api');

class ApiClient {
  ApiClient({Dio? dio})
    : _dio =
          dio ??
          Dio(
            BaseOptions(
              baseUrl: _effectiveBaseUrl,
              connectTimeout: const Duration(seconds: 10),
              receiveTimeout: const Duration(seconds: 60),
              contentType: Headers.jsonContentType,
            ),
          );

  final Dio _dio;
  String? authToken;

  Future<Map<String, Object?>> get(String path) => _request('GET', path);

  Future<Map<String, Object?>> post(
    String path, {
    Map<String, Object?> body = const {},
  }) {
    return _request('POST', path, body: body);
  }

  Future<Map<String, Object?>> patch(
    String path, {
    Map<String, Object?> body = const {},
  }) {
    return _request('PATCH', path, body: body);
  }

  Future<Map<String, Object?>> delete(String path) => _request('DELETE', path);

  Future<Map<String, Object?>> _request(
    String method,
    String path, {
    Map<String, Object?> body = const {},
  }) async {
    final headers = <String, Object?>{};
    if (authToken != null) {
      headers['Authorization'] = 'Bearer $authToken';
    }

    try {
      final response = await _dio.request<Object?>(
        path,
        data: method == 'GET' ? null : body,
        options: Options(method: method, headers: headers),
      );
      AppDebugLogger.log(
        'API $method $path -> ${response.statusCode} ${_shortData(response.data)}',
      );
      return (response.data as Map?)?.cast<String, Object?>() ??
          <String, Object?>{};
    } on DioException catch (error) {
      final data = error.response?.data;
      final code = data is Map ? data['error'] as String? : null;
      AppDebugLogger.log(
        'API $method $path failed'
        ' status=${error.response?.statusCode}'
        ' type=${error.type}'
        ' data=${_shortData(error.response?.data)}',
        error: error.message,
        stackTrace: error.stackTrace,
      );
      throw ApiException(_errorMessage(code));
    } catch (error, stackTrace) {
      AppDebugLogger.log(
        'API $method $path unexpected failure',
        error: error,
        stackTrace: stackTrace,
      );
      rethrow;
    }
  }
}

String _shortData(Object? value) {
  final text = value.toString();
  if (text.length <= 1200) {
    return text;
  }
  return '${text.substring(0, 1200)}...';
}

String get _effectiveBaseUrl {
  if (kIsWeb ||
      apiBaseUrl.startsWith('http://') ||
      apiBaseUrl.startsWith('https://')) {
    return apiBaseUrl;
  }
  return 'http://localhost:8080$apiBaseUrl';
}

String _errorMessage(String? code) {
  return switch (code) {
    'invalid_credentials' => 'Неверный email или пароль.',
    'unauthorized' => 'Сессия истекла. Войдите заново.',
    'invalid_user_payload' => 'Заполните имя, email и пароль от 8 символов.',
    'email_already_exists' => 'Пользователь с таким email уже есть.',
    'cannot_deactivate_last_admin' =>
      'Нельзя заблокировать себя или последнего admin.',
    'invalid_source_payload' => 'Заполните название, тип и корректный URL.',
    _ => code ?? 'Ошибка API.',
  };
}
