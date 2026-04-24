import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:crypto/crypto.dart';

/// Local cache for audio analysis results keyed by audio fingerprint.
/// Provides instant replay of last analysis without re-running.
class AudioCacheService {
  static const String _prefix = 'audio_analysis_';
  static const Duration _cacheValidity = Duration(days: 7);

  /// Compute SHA256 fingerprint of audio bytes for cache key.
  static String fingerprintBytes(List<int> bytes) {
    return sha256.convert(bytes).toString();
  }

  /// Get cached analysis result if available and valid.
  static Future<Map<String, dynamic>?> getCachedAnalysis(
    String audioFingerprint,
  ) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = '$_prefix$audioFingerprint';
      final cached = prefs.getString(key);

      if (cached == null) return null;

      final decoded = jsonDecode(cached) as Map<String, dynamic>?;
      if (decoded == null) return null;

      final timestamp =
          DateTime.tryParse(decoded['_cached_at'] as String? ?? '');
      if (timestamp == null) {
        // Invalid timestamp, clear stale entry
        await prefs.remove(key);
        return null;
      }

      final age = DateTime.now().difference(timestamp);
      if (age > _cacheValidity) {
        // Expired, clear it
        await prefs.remove(key);
        return null;
      }

      // Return cached result without timestamp marker
      final result = Map<String, dynamic>.from(decoded);
      result.remove('_cached_at');
      return result;
    } catch (e) {
      // Silently fail on cache read
      return null;
    }
  }

  /// Store analysis result in cache.
  static Future<void> cacheAnalysis(
    String audioFingerprint,
    Map<String, dynamic> result,
  ) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = '$_prefix$audioFingerprint';
      final withTimestamp = Map<String, dynamic>.from(result);
      withTimestamp['_cached_at'] = DateTime.now().toIso8601String();
      await prefs.setString(key, jsonEncode(withTimestamp));
    } catch (e) {
      // Silently fail on cache write
    }
  }

  /// Clear all cached analyses.
  static Future<void> clearAllCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final keys = prefs.getKeys().where((k) => k.startsWith(_prefix));
      for (final key in keys) {
        await prefs.remove(key);
      }
    } catch (e) {
      // Silently fail
    }
  }

  /// Clear specific cached analysis.
  static Future<void> clearCacheFor(String audioFingerprint) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = '$_prefix$audioFingerprint';
      await prefs.remove(key);
    } catch (e) {
      // Silently fail
    }
  }
}
