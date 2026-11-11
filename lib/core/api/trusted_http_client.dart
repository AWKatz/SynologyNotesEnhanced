import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

/// How long to wait for a TCP/TLS connection before giving up. Without this,
/// an unreachable address (a LAN IP while on cellular, or a DDNS name whose
/// IPv6 record is firewalled) hangs until the OS gives up — often over a
/// minute — before [SynologyApiClient] can fail over to another address.
const nasConnectionTimeout = Duration(seconds: 8);

/// Returns an HTTP client that accepts self-signed and hostname-mismatched
/// certificates. Necessary for local NAS devices that ship with certificates
/// issued for a domain name (e.g. *.synology.me) but are accessed via LAN IP.
http.Client createTrustingClient() {
  final inner = HttpClient()
    ..connectionTimeout = nasConnectionTimeout
    ..badCertificateCallback = (cert, host, port) => true;
  return IOClient(inner);
}
