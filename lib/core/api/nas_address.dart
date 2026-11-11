/// A parsed NAS address: scheme + host + port.
class NasAddress {
  final String host;
  final int port;
  final bool useHttps;

  const NasAddress({
    required this.host,
    required this.port,
    required this.useHttps,
  });

  /// `scheme://host:port` with no trailing slash. Built through [Uri] so an
  /// IPv6 literal host is bracketed correctly (`https://[fd00::2]:5001`).
  String get baseUrl =>
      Uri(scheme: useHttps ? 'https' : 'http', host: host, port: port)
          .toString();

  /// Parses whatever a user typed into an address field, e.g.
  ///   `192.168.0.42`
  ///   `mynas.synology.me:5001`
  ///   `https://mynas.synology.me:5001/`
  ///   `https://mynas.synology.me` (port falls back to [defaultPort], or to
  ///                               DSM's 5000/5001 if the scheme changed it)
  ///
  /// An explicit scheme/port in [input] overrides [defaultHttps]/[defaultPort].
  /// Any path, query or fragment is ignored (DSM's API lives at the root).
  /// Returns null when no usable host can be extracted.
  static NasAddress? parse(
    String input, {
    required bool defaultHttps,
    required int defaultPort,
  }) {
    var text = input.trim();
    if (text.isEmpty) return null;

    final schemeMatch = RegExp(r'^([a-zA-Z][a-zA-Z0-9+.-]*)://').firstMatch(text);
    bool? explicitHttps;
    if (schemeMatch != null) {
      final scheme = schemeMatch.group(1)!.toLowerCase();
      if (scheme != 'http' && scheme != 'https') return null;
      explicitHttps = scheme == 'https';
    } else {
      text = '${defaultHttps ? 'https' : 'http'}://$text';
    }

    final Uri uri;
    try {
      uri = Uri.parse(text);
    } on FormatException {
      return null;
    }
    if (uri.host.isEmpty || uri.host.contains(' ')) return null;

    final useHttps = explicitHttps ?? defaultHttps;
    int port;
    if (uri.hasPort) {
      port = uri.port;
    } else if (explicitHttps != null && explicitHttps != defaultHttps &&
        (defaultPort == 5000 || defaultPort == 5001)) {
      // e.g. toggle says HTTP/5000 but they pasted an https:// URL → 5001.
      port = useHttps ? 5001 : 5000;
    } else {
      port = defaultPort;
    }
    if (port < 1 || port > 65535) return null;

    return NasAddress(host: uri.host, port: port, useHttps: useHttps);
  }
}
