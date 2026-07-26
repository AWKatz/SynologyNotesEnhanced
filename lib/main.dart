import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'app.dart';
import 'models/synology_session.dart';
import 'providers/session_provider.dart';
import 'providers/app_mode_provider.dart';
import 'core/services/session_persistence_service.dart';

/// Trusts self-signed/hostname-mismatched certs for Dart's built-in
/// NetworkImage/HttpClient usage — same rationale as
/// core/api/trusted_http_client.dart's createTrustingClient(), but that
/// client only covers this app's own SynologyApiClient calls. Inline note
/// images render via flutter_widget_from_html_core's HtmlWidget, which
/// loads `<img>` tags through NetworkImage/dart:io HttpClient directly, a
/// third network stack (alongside SynologyApiClient and the rich editor's
/// WebView, which has its own equivalent fix — see
/// RichHtmlEditor.onReceivedServerTrustAuthRequest) that silently failed
/// to load images against a LAN-IP-accessed NAS without this.
class _TrustingHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    return super.createHttpClient(context)
      ..badCertificateCallback = (cert, host, port) => true;
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = _TrustingHttpOverrides();

  SynologySession? restoredSession;
  AppMode? restoredMode;

  try {
    restoredSession = await SessionPersistenceService.restoreSession();
    final modeStr = await SessionPersistenceService.restoreMode();
    debugPrint(
        '[startup] restoreSession=${restoredSession == null ? 'null' : '${restoredSession.username}@${restoredSession.host} sid=${restoredSession.sid.isEmpty ? '(empty)' : '(present)'}'} restoreMode=$modeStr');
    if (restoredSession != null) {
      restoredMode = AppMode.nas;
    } else if (modeStr == 'local') {
      restoredMode = AppMode.local;
    }
  } catch (e, st) {
    debugPrint('[startup] session restore threw: $e\n$st');
  }

  runApp(
    ProviderScope(
      overrides: [
        if (restoredSession != null)
          sessionProvider.overrideWith(
            (ref) => SessionNotifier(restoredSession),
          ),
        if (restoredMode != null)
          appModeProvider.overrideWith((ref) => restoredMode),
      ],
      child: const SynologyNoteApp(),
    ),
  );
}
