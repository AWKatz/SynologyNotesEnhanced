export '../core/services/auth_service.dart' show AuthService;
export '../core/api/api_exception.dart' show ApiException;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/synology_session.dart';
import '../core/api/api_exception.dart';
import '../core/api/synology_api_client.dart' show SessionTokens;
import '../core/services/auth_service.dart';
import '../core/services/session_persistence_service.dart';

class SessionNotifier extends StateNotifier<SynologySession?> {
  SessionNotifier([super.initialSession]);

  Future<SessionTokens?>? _reauthInFlight;
  String? _expiryMessage;

  /// Why the session was ended without the user signing out, if it was —
  /// shown once by the login screen. Reading it clears it.
  String? takeExpiryMessage() {
    final m = _expiryMessage;
    _expiryMessage = null;
    return m;
  }

  Future<void> setSession(SynologySession session) async {
    state = session;
    await SessionPersistenceService.saveSession(session);
  }

  /// Signs in again in the background with the saved password after the NAS
  /// reported the SID as expired/invalid (it timed out, DSM restarted, or the
  /// phone changed networks and DSM rejected the SID from the new IP).
  ///
  /// Concurrent callers share one login. A caller whose [staleSid] has
  /// already been replaced gets the current tokens straight back.
  ///
  /// Returns null if re-login isn't possible. If that's because the saved
  /// credentials no longer work (or none are saved), the session is ended so
  /// the app returns to the login screen with an explanation; if it's just a
  /// network failure, the session is kept so a later sync can retry.
  Future<SessionTokens?> reauthenticate(String? staleSid) {
    final current = state;
    if (current == null) return Future.value(null);
    if (staleSid != null && current.sid != staleSid) {
      return Future.value((sid: current.sid, synoToken: current.synoToken));
    }
    return _reauthInFlight ??=
        _reauth(current).whenComplete(() => _reauthInFlight = null);
  }

  Future<SessionTokens?> _reauth(SynologySession current) async {
    final creds = await SessionPersistenceService.restoreCredentials();
    if (creds == null ||
        creds.password.isEmpty ||
        creds.username != current.username) {
      debugPrint('[session] SID expired; no saved password to re-login with');
      await _expire('Your NAS session expired. Sign in again to keep '
          'syncing (turn on "Save credentials" to stay signed in).');
      return null;
    }

    try {
      final fresh = await AuthService.login(
        host: current.host,
        port: current.port,
        useHttps: current.useHttps,
        username: current.username,
        password: creds.password,
        alternateBaseUrl: current.alternateBaseUrl,
        deviceId: current.deviceId,
      );
      // The user may have signed out while this was in flight.
      if (state == null) return null;
      final updated = current.withTokens(
        sid: fresh.sid,
        synoToken: fresh.synoToken,
        deviceId: fresh.deviceId,
      );
      debugPrint('[session] re-login succeeded for ${current.username}');
      state = updated;
      await SessionPersistenceService.saveSession(updated);
      return (sid: updated.sid, synoToken: updated.synoToken);
    } on ApiException catch (e) {
      debugPrint('[session] re-login failed: $e');
      if (e.code == -1) return null; // offline — keep the session for later
      final needsOtp = e.code == 403 || e.code == 405 || e.code == 404;
      await _expire(needsOtp
          ? 'Your NAS session expired. Sign in again with your '
              'two-factor code to keep syncing.'
          : 'Your NAS session expired and signing in again failed '
              '(${e.message}). Please sign in.');
      return null;
    }
  }

  Future<void> _expire(String message) async {
    if (state == null) return;
    _expiryMessage = message;
    state = null;
    await SessionPersistenceService.clearSession();
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
