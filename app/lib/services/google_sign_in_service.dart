import 'package:google_sign_in/google_sign_in.dart';

class GoogleSignInService {
  GoogleSignInService._();

  static const String _serverClientId = String.fromEnvironment(
    'GOOGLE_SERVER_CLIENT_ID',
    defaultValue: '',
  );

  static bool _initialized = false;

  static GoogleSignIn get instance => GoogleSignIn.instance;

  static String get serverClientId => _serverClientId;

  static Future<void> ensureInitialized() async {
    if (_initialized) return;

    if (_serverClientId.trim().isEmpty) {
      throw Exception(
        'Android Google sign-in requires `GOOGLE_SERVER_CLIENT_ID` build-time config.\n'
        'Run the app with `--dart-define=GOOGLE_SERVER_CLIENT_ID=<your-server-client-id>`.',
      );
    }

    await instance.initialize(
      serverClientId: _serverClientId.trim(),
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
