import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class ApiService {
  static const _baseUrlKey = 'api_base_url';
  static const _defaultUrl = 'https://knowledge-assistant-enmb.onrender.com';

  static Future<String> getBaseUrl() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_baseUrlKey) ?? _defaultUrl;
  }

  static Future<void> setBaseUrl(String url) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_baseUrlKey, url.trimRight().replaceAll(RegExp(r'/$'), ''));
  }

  // Unified endpoint — handles URL, query, or mixed URL+text
  static Future<MessageResult> sendMessage(String message) async {
    final base = await getBaseUrl();
    final response = await http.post(
      Uri.parse('$base/message'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'message': message}),
    ).timeout(const Duration(seconds: 45));

    if (response.statusCode != 200) {
      final detail = jsonDecode(response.body)['detail'] ?? 'Unknown error';
      throw Exception(detail);
    }
    return MessageResult.fromJson(jsonDecode(response.body));
  }

  static Future<StatusResult> status() async {
    final base = await getBaseUrl();
    final response = await http.get(Uri.parse('$base/status'))
        .timeout(const Duration(seconds: 10));
    if (response.statusCode != 200) throw Exception('Status fetch failed');
    return StatusResult.fromJson(jsonDecode(response.body));
  }

  static Future<DigestResult?> fetchDigest() async {
    final base = await getBaseUrl();
    final response = await http.get(Uri.parse('$base/digest'))
        .timeout(const Duration(seconds: 10));
    if (response.statusCode != 200) return null;
    final data = jsonDecode(response.body);
    if (data['available'] != true) return null;
    return DigestResult.fromJson(data);
  }
}

class MessageResult {
  final String response;
  final String mode;

  MessageResult({required this.response, required this.mode});

  factory MessageResult.fromJson(Map<String, dynamic> json) =>
      MessageResult(response: json['response'], mode: json['mode']);
}

class StatusResult {
  final int total;
  final Map<String, int> byIntent;

  StatusResult({required this.total, required this.byIntent});

  factory StatusResult.fromJson(Map<String, dynamic> json) => StatusResult(
        total: json['total'],
        byIntent: Map<String, int>.from(json['by_intent']),
      );
}

class DigestResult {
  final String message;

  DigestResult({required this.message});

  factory DigestResult.fromJson(Map<String, dynamic> json) =>
      DigestResult(message: json['message']);
}
