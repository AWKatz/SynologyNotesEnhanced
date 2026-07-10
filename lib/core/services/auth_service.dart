import '../api/synology_api_client.dart';
import '../../models/synology_session.dart';

class AuthService {
  /// Queries the NAS for supported authentication types for [username].
  static Future<List<String>> authTypes({
    required String host,
    required int port,
    required bool useHttps,
    required String username,
  }) async {
    final baseUrl = '${useHttps ? 'https' : 'http'}://$host:$port';
    final client = SynologyApiClient(baseUrl);

    return client.authTypes(account: username);
  }

  /// Logs in to the NAS and returns a [SynologySession] containing the SID.
  /// Throws [ApiException] on authentication failure.
  static Future<SynologySession> login({
    required String host,
    required int port,
    required bool useHttps,
    required String username,
    required String password,
    String? otpCode,
  }) async {
    final baseUrl = '${useHttps ? 'https' : 'http'}://$host:$port';
    final client = SynologyApiClient(baseUrl);

    final sid = await client.login(
        account: username, passwd: password, otpCode: otpCode);

    return SynologySession(
      host: host,
      port: port,
      useHttps: useHttps,
      username: username,
      sid: sid,
      synoToken: client.synoToken,
    );
  }

  /// Logs out of the NAS. Swallows errors (best-effort).
  static Future<void> logout(SynologySession session) async {
    try {
      final client = SynologyApiClient.withSid(session.baseUrl, session.sid,
          synoToken: session.synoToken);
      await client.logout();
    } catch (_) {}
  }
}
