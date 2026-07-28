import 'dart:convert';
import 'dart:io';

class TelegramBotClient {
  TelegramBotClient({HttpClient? httpClient})
      : _httpClient = httpClient ?? HttpClient();

  final HttpClient _httpClient;

  Future<void> sendMessage({
    required String token,
    required String chatId,
    required String message,
  }) async {
    try {
      final request = await _httpClient
          .postUrl(Uri.https('api.telegram.org', '/bot$token/sendMessage'))
          .timeout(const Duration(seconds: 10));
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode(<String, Object?>{
        'chat_id': chatId,
        'text': message,
        'parse_mode': 'HTML',
        'disable_web_page_preview': true,
      }));
      final response =
          await request.close().timeout(const Duration(seconds: 10));
      final body = await utf8.decoder.bind(response).join();
      final decoded = body.isEmpty ? null : jsonDecode(body);
      final accepted = response.statusCode == HttpStatus.ok &&
          decoded is Map &&
          decoded['ok'] == true;
      if (!accepted) throw const TelegramException('telegram_send_failed');
    } on TelegramException {
      rethrow;
    } on Object {
      throw const TelegramException('telegram_send_failed');
    }
  }
}

class TelegramException implements Exception {
  const TelegramException(this.code);

  final String code;
}
