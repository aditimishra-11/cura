import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class ApiService {
  static const _baseUrlKey = 'api_base_url';
  static const _defaultUrl = 'http://10.0.2.2:8000'; // Android emulator localhost

  static Future<String> getBaseUrl() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_baseUrlKey) ?? _defaultUrl;
  }

  static Future<void> setBaseUrl(String url) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_baseUrlKey, url.trimRight().replaceAll(RegExp(r'/$'), ''));
  }

  static Future<IngestResult> ingest(String url) async {
    final base = await getBaseUrl();
    final response = await http.post(
      Uri.parse('$base/ingest'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'url': url}),
    ).timeout(const Duration(seconds: 30));

    if (response.statusCode != 200) {
      final detail = jsonDecode(response.body)['detail'] ?? 'Unknown error';
      throw Exception(detail);
    }
    return IngestResult.fromJson(jsonDecode(response.body));
  }

  static Future<QueryResult> query(String message) async {
    final base = await getBaseUrl();
    final response = await http.post(
      Uri.parse('$base/query'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'message': message}),
    ).timeout(const Duration(seconds: 30));

    if (response.statusCode != 200) {
      throw Exception('Query failed: ${response.statusCode}');
    }
    return QueryResult.fromJson(jsonDecode(response.body));
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

class IngestResult {
  final String summary;
  final String intent;
  final List<String> tags;

  IngestResult({required this.summary, required this.intent, required this.tags});

  factory IngestResult.fromJson(Map<String, dynamic> json) => IngestResult(
        summary: json['summary'],
        intent: json['intent'],
        tags: List<String>.from(json['tags']),
      );
}

class QueryResult {
  final String response;
  final String mode;

  QueryResult({required this.response, required this.mode});

  factory QueryResult.fromJson(Map<String, dynamic> json) =>
      QueryResult(response: json['response'], mode: json['mode']);
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
