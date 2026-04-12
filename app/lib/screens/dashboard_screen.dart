import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'dart:async';
import '../services/api_service.dart';
import '../services/session_service.dart';
import '../theme/app_design.dart';
import 'auth_screen.dart';
import 'child_dashboard_screen.dart';

class DashboardScreen extends StatefulWidget {
  static const routeName = '/dashboard';
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen>
    with WidgetsBindingObserver {
  final _api = ApiService();
  final _session = SessionService();
  bool _loading = true;
  String? _error;
  List<dynamic> _children = [];
  static GoogleSignIn? _googleSignInSingleton;
  static const String _webClientId = String.fromEnvironment(
    'GOOGLE_WEB_CLIENT_ID',
    defaultValue: '',
  );
  static const String _serverClientId = String.fromEnvironment(
    'GOOGLE_SERVER_CLIENT_ID',
    defaultValue: '',
  );
  late final GoogleSignIn _googleSignIn =
      _googleSignInSingleton ??= GoogleSignIn(
    scopes: const <String>['email'],
    clientId:
        (kIsWeb && _webClientId.trim().isNotEmpty) ? _webClientId.trim() : null,
    serverClientId:
        _serverClientId.trim().isNotEmpty ? _serverClientId.trim() : null,
  );

  // 🚀 Auto-logout on inactivity
  static const int _inactivityTimeoutSeconds = 300; // 5 minutes
  Timer? _inactivityTimer;
  AppLifecycleState? _lastLifecycleState;

  bool get _isCurrentRoute {
    final route = ModalRoute.of(context);
    return route?.isCurrent ?? false;
  }

  int? _ageFromDob(dynamic dobValue) {
    if (dobValue == null) return null;
    final dobStr = dobValue.toString();
    final parts = dobStr.split('-');
    if (parts.length != 3) return null;
    final year = int.tryParse(parts[0]);
    final month = int.tryParse(parts[1]);
    final day = int.tryParse(parts[2]);
    if (year == null || month == null || day == null) return null;
    final dob = DateTime(year, month, day);
    final now = DateTime.now();
    int age = now.year - dob.year;
    if (now.month < dob.month ||
        (now.month == dob.month && now.day < dob.day)) {
      age -= 1;
    }
    return age;
  }

  @override
  void initState() {
    super.initState();
    // Monitor app lifecycle for auto-logout
    WidgetsBinding.instance.addObserver(this);
    // Start inactivity timer
    _resetInactivityTimer();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!mounted || !_isCurrentRoute || _lastLifecycleState == state) {
      return;
    }
    _lastLifecycleState = state;

    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _inactivityTimer?.cancel();
    } else if (state == AppLifecycleState.resumed) {
      _resetInactivityTimer();
    }
  }

  void _resetInactivityTimer() {
    _inactivityTimer?.cancel();
    _inactivityTimer = Timer(
      const Duration(seconds: _inactivityTimeoutSeconds),
      () async {
        await _logout();
      },
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _inactivityTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final email = ModalRoute.of(context)!.settings.arguments as String;
    _load(email);
  }

  Future<void> _load(String email) async {
    try {
      await _session.saveUserSession(email: email);
      final children = await _api.getChildrenForParent(email);
      setState(() {
        _children = children;
        _error = null;
      });
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _logout() async {
    try {
      await _googleSignIn.signOut();
    } catch (_) {}
    await _session.clearSession();
    if (!mounted) return;
    Navigator.pushNamedAndRemoveUntil(
      context,
      AuthScreen.routeName,
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final email = ModalRoute.of(context)!.settings.arguments as String;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Select Child Account'),
        actions: [
          IconButton(
            tooltip: 'Sign out — start fresh',
            onPressed: _logout,
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: Padding(
        padding: AppDesign.pagePadding,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? SelectableText(_error!,
                    style: const TextStyle(color: Colors.redAccent))
                : _children.isEmpty
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                              'No child profile found for this account.'),
                          const SizedBox(height: 8),
                          const Text('Please create a child profile first.'),
                          const Spacer(),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton(
                              onPressed: () {
                                Navigator.pushNamed(
                                  context,
                                  '/child-profile',
                                  arguments: email,
                                );
                              },
                              child: const Text('Create Child Profile'),
                            ),
                          ),
                        ],
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Select a child account:'),
                          const SizedBox(height: 8),
                          Expanded(
                            child: ListView.builder(
                              itemCount: _children.length,
                              itemBuilder: (ctx, i) {
                                final c = _children[i] as Map<String, dynamic>;
                                final computedAge = _ageFromDob(c['dob']);
                                final ageText = computedAge?.toString() ??
                                    (c['age']?.toString() ?? '-');
                                return Card(
                                  child: ListTile(
                                    title: Text(c['name'] ?? 'Child'),
                                    subtitle: Text('Age: $ageText'
                                        '${c['gender'] != null ? ' · ${c['gender']}' : ''}'),
                                    trailing: const Icon(Icons.chevron_right),
                                    onTap: () async {
                                      await _session.saveSelectedChild(c);
                                      if (!context.mounted) return;
                                      Navigator.pushNamed(
                                        context,
                                        ChildDashboardScreen.routeName,
                                        arguments: c,
                                      );
                                    },
                                  ),
                                );
                              },
                            ),
                          ),
                        ],
                      ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          Navigator.pushNamed(
            context,
            '/child-profile',
            arguments: email,
          );
        },
        tooltip: 'Add Child Profile',
        child: const Icon(Icons.add),
      ),
    );
  }
}
