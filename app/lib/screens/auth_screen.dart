import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import '../services/api_service.dart';
import '../services/session_service.dart';
import '../theme/app_design.dart';
import 'dashboard_screen.dart';

class AuthScreen extends StatefulWidget {
  static const routeName = '/auth';
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _api = ApiService();
  final _session = SessionService();
  bool _isLoading = false;
  bool _restoringSession = true;
  String? _error;
  static GoogleSignIn? _googleSignInSingleton;
  static const String _webClientId = String.fromEnvironment(
    'GOOGLE_WEB_CLIENT_ID',
    defaultValue: '',
  );
  static const String _serverClientId = String.fromEnvironment(
    'GOOGLE_SERVER_CLIENT_ID',
    defaultValue: '',
  );
  late final GoogleSignIn _googleSignIn;

  @override
  void initState() {
    super.initState();
    _googleSignIn = _googleSignInSingleton ??= GoogleSignIn(
      scopes: <String>['email'],
      clientId:
          (kIsWeb && _webClientId.trim().isNotEmpty) ? _webClientId.trim() : null,
      serverClientId:
          _serverClientId.trim().isNotEmpty ? _serverClientId.trim() : null,
    );
    _bootstrapAuth();
  }

  /// Restore saved session when possible; otherwise show sign-in.
  ///
  /// After a server DB reset, a local email alone is not enough — the parent row
  /// must exist on the API. We use Google silent sign-in + [loginWithGoogle] so
  /// `/api/login/google` runs and upserts the user before opening the dashboard.
  Future<void> _bootstrapAuth() async {
    try {
      final session = await _session.readUserSession();
      final savedEmail = session['email']?.trim() ?? '';
      if (savedEmail.isEmpty) {
        if (mounted) setState(() => _restoringSession = false);
        return;
      }

      final account = await _googleSignIn.signInSilently();
      if (account == null) {
        await _session.clearSession();
        if (mounted) setState(() => _restoringSession = false);
        return;
      }

      final auth = await account.authentication;
      await _api.loginWithGoogle(
        idToken: auth.idToken,
        accessToken: auth.accessToken,
      );
      await _session.saveUserSession(
        email: account.email,
        displayName: account.displayName,
      );
      if (!mounted) return;
      Navigator.pushReplacementNamed(
        context,
        DashboardScreen.routeName,
        arguments: account.email,
      );
    } catch (e) {
      debugPrint('[AUTH] Session restore failed: $e');
      await _session.clearSession();
      if (mounted) setState(() => _restoringSession = false);
    }
  }

  /// Clear local session and Google cache so the next sign-in is a clean choice.
  Future<void> _startFreshWithAnotherAccount() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      await _session.clearSession();
      try {
        await _googleSignIn.signOut();
      } catch (_) {
        // Best-effort; user can still pick an account on next sign-in.
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  String _friendlyGoogleError(Object error) {
    if (error is PlatformException && error.code == 'sign_in_failed') {
      final details = (error.message ?? '').toLowerCase();
      if (details.contains('apiexception: 10')) {
        return 'Google sign-in config mismatch (ApiException 10).\n\n'
            'Fix in Google Cloud Console:\n'
            '1) Create Android OAuth client\n'
            '2) Package name: com.example.neuro_ai_cognitive_app\n'
            '3) SHA1: 6A:C6:CB:44:21:7A:32:56:46:90:66:45:72:7B:D3:6D:29:20:12:F9\n'
            '4) SHA256: C3:FF:4B:B0:F8:18:D4:57:A6:CD:DD:1C:2F:A7:76:EE:24:92:12:58:DD:78:BB:BA:2E:8A:A6:0A:DD:94:6E:D1\n\n'
            'Then uninstall and reinstall the app, and try Google sign-in again.';
      }
      if (details.contains('fedcm') ||
          details.contains('identitycredential') ||
          details.contains('origin') && details.contains('not allowed')) {
        return 'Google sign-in was blocked by the browser FedCM flow.\n\n'
            'For Flutter web, add your local origin (for example `http://localhost:<port>` and `http://127.0.0.1:<port>`) to the Google OAuth web client and run the app with:\n'
            '`--dart-define=GOOGLE_WEB_CLIENT_ID=<your-web-client-id>`';
      }
      if (details.contains('popup_closed') || details.contains('popup closed')) {
        return 'Google sign-in window was closed before completion. Please try again.';
      }
    }
    final message = error.toString().replaceFirst(RegExp(r'^Exception:\s*'), '');
    if (message.toLowerCase().contains('fedcm')) {
      return 'Google sign-in needs a valid web OAuth client for FedCM. Set `GOOGLE_WEB_CLIENT_ID` and allow your local web origin in Google Cloud Console.';
    }
    return message;
  }

  Future<void> _handleGoogleLogin() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      if (kIsWeb && _webClientId.trim().isEmpty) {
        throw Exception(
          'Google web sign-in requires `GOOGLE_WEB_CLIENT_ID` for the FedCM flow.',
        );
      }

      final account = await _googleSignIn.signIn();
      if (account == null) {
        throw Exception('Google sign-in was cancelled.');
      }

      final auth = await account.authentication;
      debugPrint('[DEBUG] Auth tokens - idToken: ${auth.idToken}, accessToken: ${auth.accessToken}');
      
      await _api.loginWithGoogle(
        idToken: auth.idToken,
        accessToken: auth.accessToken,
      );
      await _session.saveUserSession(
        email: account.email,
        displayName: account.displayName,
      );

      if (!mounted) return;
      Navigator.pushReplacementNamed(
        context,
        DashboardScreen.routeName,
        arguments: account.email,
      );
    } catch (e) {
      debugPrint('[ERROR] Google login failed: $e');
      final msg = _friendlyGoogleError(e);
      setState(() => _error = msg);
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _restoringSession = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Continue with Google')),
      body: Padding(
        padding: AppDesign.pagePadding,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Use your Google account to sign in.\nIf this Gmail has multiple child accounts, you can choose one after login.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            if (_isLoading || _restoringSession)
              const Center(child: CircularProgressIndicator())
            else ...[
              OutlinedButton.icon(
                onPressed: _handleGoogleLogin,
                icon: const Icon(Icons.g_mobiledata),
                label: const Text('Continue with Google'),
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: _isLoading ? null : _startFreshWithAnotherAccount,
                child: const Text('Sign out & use another account'),
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 12),
              SelectableText(_error!, style: const TextStyle(color: Colors.redAccent)),
            ],
          ],
        ),
      ),
    );
  }
}
