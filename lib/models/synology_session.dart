import '../core/api/nas_address.dart';

class SynologySession {
  final String host;
  final int port;
  final bool useHttps;
  final String username;
  final String sid;
  // CSRF token from login (enable_syno_token=yes); null if DSM didn't issue one.
  final String? synoToken;

  /// Optional second address for the same NAS (e.g. LAN IP as [host] and a
  /// DDNS name here, or vice versa), as a full base URL. Requests fail over
  /// to it when [baseUrl] can't be reached.
  final String? alternateBaseUrl;

  /// DSM "trusted device" token (see SynologyApiClient.deviceId). Lets an
  /// account with 2FA sign in again in the background without an OTP code.
  final String? deviceId;

  const SynologySession({
    required this.host,
    required this.port,
    required this.useHttps,
    required this.username,
    required this.sid,
    this.synoToken,
    this.alternateBaseUrl,
    this.deviceId,
  });

  String get baseUrl =>
      NasAddress(host: host, port: port, useHttps: useHttps).baseUrl;

  /// Every address this session may use, primary first.
  List<String> get baseUrls => [
        baseUrl,
        if (alternateBaseUrl != null &&
            alternateBaseUrl!.isNotEmpty &&
            alternateBaseUrl != baseUrl)
          alternateBaseUrl!,
      ];

  String get apiBase => '$baseUrl/webapi';

  /// Identifies which NAS/account this session talks to, ignoring the
  /// SID/token — those are refreshed in place by a background re-login
  /// without needing to rebuild the API client and everything above it.
  String get connectionKey => '$username@${baseUrls.join('|')}';

  /// Same connection, fresh credentials from a re-login.
  SynologySession withTokens({
    required String sid,
    required String? synoToken,
    String? deviceId,
  }) =>
      SynologySession(
        host: host,
        port: port,
        useHttps: useHttps,
        username: username,
        sid: sid,
        synoToken: synoToken,
        alternateBaseUrl: alternateBaseUrl,
        deviceId: deviceId ?? this.deviceId,
      );
}
