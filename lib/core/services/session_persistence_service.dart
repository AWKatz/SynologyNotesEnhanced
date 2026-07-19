import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../../models/synology_session.dart';

class SavedCredentials {
  final String host;
  final int port;
  final bool useHttps;
  final String username;
  final String password;

  const SavedCredentials({
    required this.host,
    required this.port,
    required this.useHttps,
    required this.username,
    required this.password,
  });
}

class SessionPersistenceService {
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  static const _keyHost = 'nas_host';
  static const _keyPort = 'nas_port';
  static const _keyHttps = 'nas_https';
  static const _keyUsername = 'nas_username';
  static const _keySid = 'nas_sid';
  static const _keySynoToken = 'nas_syno_token';
  static const _keyMode = 'app_mode';
  static const _keyPassword = 'nas_password';
  static const _keyRememberMe = 'nas_remember_me';

  // Writes are sequential, not `Future.wait`-parallel: the Windows backend
  // (DPAPI/file-based) races when hit with concurrent writes and silently
  // drops some of them (observed: 7 concurrent writes in saveSession left
  // `host`/`sid` unset while `mode` "won" the race) — one write at a time
  // avoids that entirely.
  static Future<void> _writeAll(Map<String, String> entries) async {
    for (final entry in entries.entries) {
      await _storage.write(key: entry.key, value: entry.value);
    }
  }

  static Future<void> _deleteKeys(List<String> keys) async {
    for (final key in keys) {
      await _storage.delete(key: key);
    }
  }

  // Called after a successful login. Always saves connection details + SID.
  static Future<void> saveSession(SynologySession session) async {
    try {
      await _writeAll({
        _keyHost: session.host,
        _keyPort: session.port.toString(),
        _keyHttps: session.useHttps.toString(),
        _keyUsername: session.username,
        _keySid: session.sid,
        _keySynoToken: session.synoToken ?? '',
        _keyMode: 'nas',
      });
      // Read the SID straight back to confirm the write actually landed —
      // catches silent write failures rather than trusting `write()` didn't
      // throw.
      final readBack = await _storage.read(key: _keySid);
      debugPrint('[session] saveSession: wrote sid for ${session.username}@'
          '${session.host}, read-back ${readBack == session.sid ? 'OK' : 'MISMATCH ("$readBack")'}');
    } catch (e, st) {
      debugPrint('[session] saveSession threw: $e\n$st');
      rethrow;
    }
  }

  // Additionally saves the password so the login form can be pre-filled.
  static Future<void> saveCredentials(SavedCredentials creds) async {
    await _writeAll({
      _keyHost: creds.host,
      _keyPort: creds.port.toString(),
      _keyHttps: creds.useHttps.toString(),
      _keyUsername: creds.username,
      _keyPassword: creds.password,
      _keyRememberMe: 'true',
    });
  }

  // Clears the saved password and remember-me flag without touching the SID.
  static Future<void> clearSavedCredentials() async {
    await _deleteKeys([_keyPassword, _keyRememberMe]);
  }

  static Future<SavedCredentials?> restoreCredentials() async {
    final remember = await _storage.read(key: _keyRememberMe);
    if (remember != 'true') return null;
    final host = await _storage.read(key: _keyHost);
    if (host == null || host.isEmpty) return null;
    return SavedCredentials(
      host: host,
      port: int.tryParse(await _storage.read(key: _keyPort) ?? '') ?? 5000,
      useHttps: (await _storage.read(key: _keyHttps)) == 'true',
      username: await _storage.read(key: _keyUsername) ?? '',
      password: await _storage.read(key: _keyPassword) ?? '',
    );
  }

  static Future<SynologySession?> restoreSession() async {
    final host = await _storage.read(key: _keyHost);
    if (host == null || host.isEmpty) {
      debugPrint('[session] restoreSession: no host in storage — nothing saved');
      return null;
    }
    final sid = await _storage.read(key: _keySid) ?? '';
    if (sid.isEmpty) {
      debugPrint('[session] restoreSession: host="$host" present but sid missing/empty');
      return null;
    }
    final token = await _storage.read(key: _keySynoToken);
    return SynologySession(
      host: host,
      port: int.tryParse(await _storage.read(key: _keyPort) ?? '') ?? 5000,
      useHttps: (await _storage.read(key: _keyHttps)) == 'true',
      username: await _storage.read(key: _keyUsername) ?? '',
      sid: sid,
      synoToken: (token == null || token.isEmpty) ? null : token,
    );
  }

  // On logout: only wipe the SID. Connection details + remembered password stay
  // so the login form can be pre-filled on the next sign-in.
  static Future<void> clearSession() async {
    await _deleteKeys([_keySid, _keySynoToken]);
  }

  static Future<void> saveMode(String mode) async {
    await _storage.write(key: _keyMode, value: mode);
  }

  static Future<String?> restoreMode() async {
    return _storage.read(key: _keyMode);
  }

  static Future<void> clearAll() async {
    await _storage.deleteAll();
  }
}
