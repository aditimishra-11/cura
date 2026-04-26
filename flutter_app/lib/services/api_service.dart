import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class ApiService {
  static const _baseUrlKey   = 'api_base_url';
  static const _userEmailKey = 'user_email';
  static const _defaultUrl   = 'https://knowledge-assistant-enmb.onrender.com';

  static Future<String> getBaseUrl() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_baseUrlKey) ?? _defaultUrl;
  }

  static Future<void> setBaseUrl(String url) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_baseUrlKey, url.trimRight().replaceAll(RegExp(r'/$'), ''));
  }

  static Future<String?> getUserEmail() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_userEmailKey);
  }

  static Future<void> setUserEmail(String email) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_userEmailKey, email);
  }

  static Future<void> clearUserEmail() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_userEmailKey);
  }

  // ── Chat ─────────────────────────────────────────────────────────────────

  static Future<MessageResult> sendMessage(
    String message, {
    List<Map<String, dynamic>> history = const [],
  }) async {
    final base      = await getBaseUrl();
    final userEmail = await getUserEmail();
    final response  = await http.post(
      Uri.parse('$base/message'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'message': message,
        'history': history,
        if (userEmail != null) 'user_email': userEmail,
      }),
    ).timeout(const Duration(seconds: 60));

    if (response.statusCode != 200) {
      final detail = jsonDecode(response.body)['detail'] ?? 'Unknown error';
      throw Exception(detail);
    }
    return MessageResult.fromJson(jsonDecode(response.body));
  }

  static Future<StatusResult> status() async {
    final base     = await getBaseUrl();
    final response = await http.get(Uri.parse('$base/status'))
        .timeout(const Duration(seconds: 30));
    if (response.statusCode != 200) throw Exception('Status fetch failed');
    return StatusResult.fromJson(jsonDecode(response.body));
  }

  static Future<DigestResult?> fetchDigest() async {
    final base     = await getBaseUrl();
    final response = await http.get(Uri.parse('$base/digest'))
        .timeout(const Duration(seconds: 10));
    if (response.statusCode != 200) return null;
    final data = jsonDecode(response.body);
    if (data['available'] != true) return null;
    return DigestResult.fromJson(data);
  }

  // ── Library ───────────────────────────────────────────────────────────────

  static Future<LibraryResult> fetchItems({
    int limit  = 20,
    int offset = 0,
    String? intent,
  }) async {
    final base = await getBaseUrl();
    final uri  = Uri.parse('$base/items').replace(queryParameters: {
      'limit':  '$limit',
      'offset': '$offset',
      if (intent != null) 'intent': intent,
    });
    final response = await http.get(uri).timeout(const Duration(seconds: 30));
    if (response.statusCode != 200) throw Exception('Failed to load library');
    return LibraryResult.fromJson(jsonDecode(response.body));
  }

  static Future<SavedItem> fetchItem(String id) async {
    final base     = await getBaseUrl();
    final response = await http.get(Uri.parse('$base/items/$id'))
        .timeout(const Duration(seconds: 10));
    if (response.statusCode != 200) throw Exception('Item not found');
    return SavedItem.fromJson(jsonDecode(response.body));
  }

  static Future<SavedItem> updateItem(
    String id, {
    String? userNote,
    String? remindAt,
  }) async {
    final base  = await getBaseUrl();
    final body  = <String, dynamic>{};
    if (userNote != null) body['user_note'] = userNote;
    if (remindAt != null) body['remind_at'] = remindAt;

    final response = await http.patch(
      Uri.parse('$base/items/$id'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(body),
    ).timeout(const Duration(seconds: 10));
    if (response.statusCode != 200) throw Exception('Update failed');
    return SavedItem.fromJson(jsonDecode(response.body));
  }

  // ── Reminders ─────────────────────────────────────────────────────────────

  static Future<List<SavedItem>> fetchReminders() async {
    final base      = await getBaseUrl();
    final userEmail = await getUserEmail();

    final uri = Uri.parse('$base/reminders').replace(queryParameters: {
      if (userEmail != null) 'user_email': userEmail,
    });

    final response = await http.get(uri).timeout(const Duration(seconds: 30));
    if (response.statusCode != 200) throw Exception('Failed to load reminders');
    final data = jsonDecode(response.body);
    return (data['reminders'] as List)
        .map((j) => SavedItem.fromJson(j))
        .toList();
  }

  // ── Google Calendar auth ──────────────────────────────────────────────────

  static Future<GoogleAuthStatus> googleStatus() async {
    final base      = await getBaseUrl();
    final userEmail = await getUserEmail();
    if (userEmail == null) return GoogleAuthStatus(connected: false, email: null);

    final response = await http.get(
      Uri.parse('$base/auth/google/status').replace(
        queryParameters: {'user_email': userEmail},
      ),
    ).timeout(const Duration(seconds: 15));
    if (response.statusCode != 200) throw Exception('Failed to fetch Google status');
    return GoogleAuthStatus.fromJson(jsonDecode(response.body));
  }

  static Future<GoogleAuthStatus> connectGoogle({
    required String serverAuthCode,
    required String email,
  }) async {
    final base     = await getBaseUrl();
    final response = await http.post(
      Uri.parse('$base/auth/google'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'server_auth_code': serverAuthCode, 'email': email}),
    ).timeout(const Duration(seconds: 30));
    if (response.statusCode != 200) {
      final detail = jsonDecode(response.body)['detail'] ?? 'Google auth failed';
      throw Exception(detail);
    }
    // Persist email so all subsequent calls are per-user
    await setUserEmail(email);
    return GoogleAuthStatus.fromJson(jsonDecode(response.body));
  }

  static Future<void> disconnectGoogle() async {
    final base      = await getBaseUrl();
    final userEmail = await getUserEmail();
    final response  = await http.delete(
      Uri.parse('$base/auth/google').replace(
        queryParameters: userEmail != null ? {'user_email': userEmail} : null,
      ),
    ).timeout(const Duration(seconds: 15));
    if (response.statusCode != 200) throw Exception('Failed to disconnect Google');
    await clearUserEmail();
  }

  // ── Device registration ───────────────────────────────────────────────────

  static Future<void> registerDevice(String fcmToken) async {
    final base      = await getBaseUrl();
    final userEmail = await getUserEmail();
    await http.post(
      Uri.parse('$base/register-device'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'fcm_token': fcmToken,
        if (userEmail != null) 'user_email': userEmail,
      }),
    ).timeout(const Duration(seconds: 10));
  }
}

// ── Models ────────────────────────────────────────────────────────────────────

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
        total:    json['total'],
        byIntent: Map<String, int>.from(json['by_intent']),
      );
}

class DigestResult {
  final String message;

  DigestResult({required this.message});

  factory DigestResult.fromJson(Map<String, dynamic> json) =>
      DigestResult(message: json['message']);
}

class SavedItem {
  final String id;
  final String url;
  final String? title;
  final String? summary;
  final String intent;
  final List<String> tags;
  final String? source;
  final String createdAt;
  final String? remindAt;
  final String? userNote;
  final bool reminderSent;

  SavedItem({
    required this.id,
    required this.url,
    this.title,
    this.summary,
    required this.intent,
    required this.tags,
    this.source,
    required this.createdAt,
    this.remindAt,
    this.userNote,
    required this.reminderSent,
  });

  factory SavedItem.fromJson(Map<String, dynamic> j) => SavedItem(
        id:           j['id'] ?? '',
        url:          j['url'] ?? '',
        title:        j['title'],
        summary:      j['summary'],
        intent:       j['intent'] ?? 'reference',
        tags:         List<String>.from(j['tags'] ?? []),
        source:       j['source'],
        createdAt:    j['created_at'] ?? '',
        remindAt:     j['remind_at'],
        userNote:     j['user_note'],
        reminderSent: j['reminder_sent'] ?? false,
      );

  String get displayTitle {
    if (title != null && title!.isNotEmpty) return title!;
    try {
      final host = Uri.parse(url).host;
      return host.replaceFirst('www.', '');
    } catch (_) {
      return url;
    }
  }
}

class LibraryResult {
  final List<SavedItem> items;
  final int offset;
  final int count;

  LibraryResult({required this.items, required this.offset, required this.count});

  factory LibraryResult.fromJson(Map<String, dynamic> json) => LibraryResult(
        items:  (json['items'] as List).map((j) => SavedItem.fromJson(j)).toList(),
        offset: json['offset'] ?? 0,
        count:  json['count']  ?? 0,
      );
}

class GoogleAuthStatus {
  final bool connected;
  final String? email;

  GoogleAuthStatus({required this.connected, this.email});

  factory GoogleAuthStatus.fromJson(Map<String, dynamic> json) =>
      GoogleAuthStatus(
        connected: json['connected'] ?? false,
        email:     json['email'],
      );
}
