import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

/// Picks the pre-composed splash artwork for the current platform. These
/// are full-bleed, fixed-resolution renders (not icons) — see the three
/// splash_*.png files in assets/icons/ — so they're shown here via a
/// Flutter-side overlay with BoxFit.cover rather than through
/// flutter_native_splash, which only supports Android/iOS/Web and only
/// knows how to center a small icon on a solid color, not stretch/crop a
/// full scene. Android reuses the phone render; Linux/web get no overlay
/// (native splash / background color only).
String? _splashAssetForPlatform() {
  if (kIsWeb) return null;
  if (Platform.isAndroid || Platform.isIOS) {
    return 'assets/icons/splash_iphone_x.png';
  }
  if (Platform.isMacOS) return 'assets/icons/splash_macos.png';
  if (Platform.isWindows) return 'assets/icons/splash_windows.png';
  return null;
}

/// Wraps [child] with the branded splash render full-screen for a beat
/// after first launch, fading out into the real UI — a second, Flutter-side
/// splash that picks up where the native one (icon on solid color) leaves
/// off, since only this layer can show the full mockup art. Meant to sit in
/// MaterialApp.router's `builder`, so it wraps every route uniformly and
/// only ever plays once per app launch (its State survives rebuilds there).
class AppSplashOverlay extends StatefulWidget {
  final Widget child;

  const AppSplashOverlay({super.key, required this.child});

  @override
  State<AppSplashOverlay> createState() => _AppSplashOverlayState();
}

class _AppSplashOverlayState extends State<AppSplashOverlay> {
  static const _holdDuration = Duration(milliseconds: 900);
  static const _fadeDuration = Duration(milliseconds: 300);

  late final String? _asset = _splashAssetForPlatform();
  bool _visible = true;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    if (_asset != null) {
      _timer = Timer(_holdDuration, () {
        if (mounted) setState(() => _visible = false);
      });
    } else {
      _visible = false;
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_asset == null) return widget.child;

    return Stack(
      children: [
        widget.child,
        Positioned.fill(
          child: IgnorePointer(
            ignoring: !_visible,
            child: AnimatedOpacity(
              opacity: _visible ? 1 : 0,
              duration: _fadeDuration,
              curve: Curves.easeOut,
              child: Image.asset(_asset, fit: BoxFit.cover),
            ),
          ),
        ),
      ],
    );
  }
}
