import '../api/nas_address.dart';
import '../api/synology_api_client.dart';
import '../../models/synology_session.dart';

class AuthService {
  /// Queries the NAS for supported authentication types for [username].
  /// Tries [alternateBaseUrl] too if the primary address can't be reached.
  static Future<List<String>> authTypes({
    required String host,
    required int port,
    required bool useHttps,
    required String username,
    String? alternateBaseUrl,
  }) async {
    final client = _client(host, port, useHttps, alternateBaseUrl);
    return client.authTypes(account: username);
  }

  /// Logs in to the NAS and returns a [SynologySession] containing the SID.
  /// Throws [ApiException] on authentication failure.
  ///
  /// [deviceId] is a trusted-device token from an earlier login; with it DSM
  /// skips the OTP prompt. [rememberDevice] asks DSM for such a token (worth
  /// doing whenever an OTP code is supplied).
  static Future<SynologySession> login({
    required String host,
    required int port,
    required bool useHttps,
    required String username,
    required String password,
    String? otpCode,
    String? alternateBaseUrl,
    String? deviceId,
    bool rememberDevice = false,
  }) async {
    final client = _client(host, port, useHttps, alternateBaseUrl);

    final sid = await client.login(
      account: username,
      passwd: password,
      otpCode: otpCode,
      deviceId: deviceId,
      rememberDevice: rememberDevice,
    );

    return SynologySession(
      host: host,
      port: port,
      useHttps: useHttps,
      username: username,
      sid: sid,
      synoToken: client.synoToken,
      alternateBaseUrl: alternateBaseUrl,
      deviceId: client.deviceId,
    );
  }

  /// Logs out of the NAS. Swallows errors (best-effort).
  static Future<void> logout(SynologySession session) async {
    try {
      final urls = session.baseUrls;
      final client = SynologyApiClient.withSid(urls.first, session.sid,
          synoToken: session.synoToken, fallbackBaseUrls: urls.skip(1).toList());
      await client.logout();
    } catch (_) {}
  }

  static SynologyApiClient _client(
      String host, int port, bool useHttps, String? alternateBaseUrl) {
    final primary =
        NasAddress(host: host, port: port, useHttps: useHttps).baseUrl;
    return SynologyApiClient(primary, fallbackBaseUrls: [
      if (alternateBaseUrl != null && alternateBaseUrl.isNotEmpty)
        alternateBaseUrl,
    ]);
  }
}
