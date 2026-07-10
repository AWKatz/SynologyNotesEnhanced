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

  // Called after a successful login. Always saves connection details + SID.
  static Future<void> saveSession(SynologySession session) async {
    await Future.wait([
      _storage.write(key: _keyHost, value: session.host),
      _storage.write(key: _keyPort, value: session.port.toString()),
      _storage.write(key: _keyHttps, value: session.useHttps.toString()),
      _storage.write(key: _keyUsername, value: session.username),
      _storage.write(key: _keySid, value: session.sid),
      _storage.write(key: _keySynoToken, value: session.synoToken ?? ''),
      _storage.write(key: _keyMode, value: 'nas'),
    ]);
  }

  // Additionally saves the password so the login form can be pre-filled.
  static Future<void> saveCredentials(SavedCredentials creds) async {
    await Future.wait([
      _storage.write(key: _keyHost, value: creds.host),
      _storage.write(key: _keyPort, value: creds.port.toString()),
      _storage.write(key: _keyHttps, value: creds.useHttps.toString()),
      _storage.write(key: _keyUsername, value: creds.username),
      _storage.write(key: _keyPassword, value: creds.password),
      _storage.write(key: _keyRememberMe, value: 'true'),
    ]);
  }

  // Clears the saved password and remember-me flag without touching the SID.
  static Future<void> clearSavedCredentials() async {
    await Future.wait([
      _storage.delete(key: _keyPassword),
      _storage.delete(key: _keyRememberMe),
    ]);
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
    if (host == null || host.isEmpty) return null;
    final sid = await _storage.read(key: _keySid) ?? '';
    if (sid.isEmpty) return null;
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
    await Future.wait([
      _storage.delete(key: _keySid),
      _storage.delete(key: _keySynoToken),
    ]);
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
