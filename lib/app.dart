import 'dart:math' show min;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'providers/app_mode_provider.dart';
import 'providers/theme_provider.dart';
import 'screens/login_screen.dart';
import 'screens/home_screen.dart';
import 'screens/settings_screen.dart';
import 'theme/app_theme.dart';

// Bridges Riverpod auth state into a ChangeNotifier so GoRouter can use
// refreshListenable — the router is created once and redirect is re-evaluated
// on auth changes without destroying navigation history.
class _AuthChangeNotifier extends ChangeNotifier {
  bool _isAuthenticated;

  _AuthChangeNotifier(this._isAuthenticated);

  bool get isAuthenticated => _isAuthenticated;

  void update(bool value) {
    if (_isAuthenticated == value) return;
    _isAuthenticated = value;
    notifyListeners();
  }
}

final _authNotifierProvider =
    ChangeNotifierProvider<_AuthChangeNotifier>((ref) {
  final notifier = _AuthChangeNotifier(ref.read(isAuthenticatedProvider));
  ref.listen<bool>(isAuthenticatedProvider, (_, next) => notifier.update(next));
  return notifier;
});

// Slide-from-left transition used for both login and settings panels.
Widget _slideFromLeft(
  BuildContext context,
  Animation<double> animation,
  Animation<double> secondaryAnimation,
  Widget child,
) {
  return SlideTransition(
    position: Tween<Offset>(
      begin: const Offset(-1, 0),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic)),
    child: child,
  );
}

// Constrains [child] to a left-anchored panel. When [dismissible] is true,
// tapping the transparent right area pops the current route.
class _PanelPage extends StatelessWidget {
  final Widget child;
  final bool dismissible;
  final double maxWidth;

  const _PanelPage({
    required this.child,
    this.dismissible = false,
    this.maxWidth = 380.0,
  });

  @override
  Widget build(BuildContext context) {
    final width = min(maxWidth, MediaQuery.sizeOf(context).width * 0.92);

    return Stack(
      children: [
        if (dismissible)
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => Navigator.of(context).pop(),
              child: const ColoredBox(color: Colors.transparent),
            ),
          ),
        Align(
          alignment: Alignment.centerLeft,
          child: SizedBox(
            width: width,
            height: double.infinity,
            child: Material(
              elevation: 0,
              color: Theme.of(context).colorScheme.surface,
              child: child,
            ),
          ),
        ),
      ],
    );
  }
}

final routerProvider = Provider<GoRouter>((ref) {
  // ref.read so this provider is created once; refreshListenable handles updates.
  final authNotifier = ref.read(_authNotifierProvider);

  return GoRouter(
    initialLocation: '/login',
    refreshListenable: authNotifier,
    redirect: (context, state) {
      final going = state.matchedLocation;
      final authed = authNotifier.isAuthenticated;
      if (!authed && going != '/login') return '/login';
      // Allow authenticated users to reach /login when force=true is set,
      // e.g. when switching to NAS mode from Settings.
      if (authed && going == '/login') {
        if (state.uri.queryParameters['force'] == 'true') return null;
        return '/home';
      }
      return null;
    },
    routes: [
      GoRoute(
        path: '/login',
        pageBuilder: (context, state) => CustomTransitionPage(
          opaque: false,
          barrierColor: Colors.black54,
          barrierDismissible: false,
          child: const _PanelPage(child: LoginScreen()),
          transitionsBuilder: _slideFromLeft,
        ),
      ),
      GoRoute(
        path: '/home',
        builder: (context, state) => const HomeScreen(),
      ),
      GoRoute(
        path: '/settings',
        pageBuilder: (context, state) => CustomTransitionPage(
          opaque: false,
          barrierColor: Colors.black54,
          barrierDismissible: false,
          child: const _PanelPage(
            dismissible: true,
            maxWidth: 480,
            child: SettingsScreen(),
          ),
          transitionsBuilder: _slideFromLeft,
        ),
      ),
    ],
  );
});

class SynologyNoteApp extends ConsumerWidget {
  const SynologyNoteApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);
    final themeMode = ref.watch(themeModeProvider);
    final accent = ref.watch(accentColorProvider) ?? AppTheme.defaultSeed;

    return MaterialApp.router(
      title: 'Synology Notes Enhanced',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(accent),
      darkTheme: AppTheme.dark(accent),
      themeMode: themeMode,
      routerConfig: router,
    );
  }
}
