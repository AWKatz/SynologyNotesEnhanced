import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'app.dart';
import 'models/synology_session.dart';
import 'providers/session_provider.dart';
import 'providers/app_mode_provider.dart';
import 'core/services/session_persistence_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  SynologySession? restoredSession;
  AppMode? restoredMode;

  try {
    restoredSession = await SessionPersistenceService.restoreSession();
    final modeStr = await SessionPersistenceService.restoreMode();
    if (restoredSession != null) {
      restoredMode = AppMode.nas;
    } else if (modeStr == 'local') {
      restoredMode = AppMode.local;
    }
  } catch (_) {}

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
