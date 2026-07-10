export '../core/services/auth_service.dart' show AuthService;
export '../core/api/api_exception.dart' show ApiException;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/synology_session.dart';
import '../core/services/auth_service.dart';
import '../core/services/session_persistence_service.dart';

class SessionNotifier extends StateNotifier<SynologySession?> {
  SessionNotifier([super.initialSession]);

  Future<void> setSession(SynologySession session) async {
    state = session;
    await SessionPersistenceService.saveSession(session);
  }

  Future<void> logout() async {
    final current = state;
    state = null;
    await SessionPersistenceService.clearSession();
    if (current != null) {
      await AuthService.logout(current);
    }
  }

  void clearSession() => state = null;
}

final sessionProvider =
    StateNotifierProvider<SessionNotifier, SynologySession?>(
  (ref) => SessionNotifier(),
);

final isLoggedInProvider = Provider<bool>((ref) {
  return ref.watch(sessionProvider) != null;
});
