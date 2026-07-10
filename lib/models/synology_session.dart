class SynologySession {
  final String host;
  final int port;
  final bool useHttps;
  final String username;
  final String sid;
  // CSRF token from login (enable_syno_token=yes); null if DSM didn't issue one.
  final String? synoToken;

  const SynologySession({
    required this.host,
    required this.port,
    required this.useHttps,
    required this.username,
    required this.sid,
    this.synoToken,
  });

  String get baseUrl {
    final scheme = useHttps ? 'https' : 'http';
    return '$scheme://$host:$port';
  }

  String get apiBase => '$baseUrl/webapi';
}
