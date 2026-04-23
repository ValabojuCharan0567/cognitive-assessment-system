import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';

class GoogleSignInService {
  GoogleSignInService._();

  static const String _webClientId = String.fromEnvironment(
    'GOOGLE_WEB_CLIENT_ID',
    defaultValue: '',
  );

  static const String _serverClientId = String.fromEnvironment(
    'GOOGLE_SERVER_CLIENT_ID',
    defaultValue: '',
  );

  static bool _initialized = false;

  static GoogleSignIn get instance => GoogleSignIn.instance;

  static String get webClientId => _webClientId;

  static Future<void> ensureInitialized() async {
    if (_initialized) return;

    await instance.initialize(
      clientId:
          (kIsWeb && _webClientId.trim().isNotEmpty) ? _webClientId.trim() : null,
      serverClientId:
          _serverClientId.trim().isNotEmpty ? _serverClientId.trim() : null,
    );
    _initialized = true;
  }

  static Future<GoogleSignInAccount?> restoreSession() async {
    final future = instance.attemptLightweightAuthentication();
    if (future == null) return null;
    return await future;
  }

  static Future<GoogleSignInAccount> signIn() async {
    return await instance.authenticate();
  }

  static Future<void> signOut() async {
    await instance.signOut();
  }
}
