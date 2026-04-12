import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class SessionService {
  static const String _emailKey = 'session_email';
  static const String _displayNameKey = 'session_display_name';
  static const String _childJsonKey = 'session_selected_child';

  Future<void> saveUserSession({
    required String email,
    String? displayName,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_emailKey, email.trim());
    if (displayName != null && displayName.trim().isNotEmpty) {
      await prefs.setString(_displayNameKey, displayName.trim());
    }
  }

  Future<Map<String, String>> readUserSession() async {
    final prefs = await SharedPreferences.getInstance();
    return {
      'email': prefs.getString(_emailKey) ?? '',
      'display_name': prefs.getString(_displayNameKey) ?? '',
    };
  }

  Future<void> saveSelectedChild(Map<String, dynamic> child) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_childJsonKey, jsonEncode(child));
  }

  Future<Map<String, dynamic>?> readSelectedChild() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_childJsonKey);
    if (raw == null || raw.isEmpty) return null;
    final decoded = jsonDecode(raw);
    if (decoded is Map<String, dynamic>) return decoded;
    if (decoded is Map) return Map<String, dynamic>.from(decoded);
    return null;
  }

  Future<void> clearSession() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_emailKey);
    await prefs.remove(_displayNameKey);
    await prefs.remove(_childJsonKey);
  }
}
