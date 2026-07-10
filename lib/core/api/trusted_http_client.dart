import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

/// Returns an HTTP client that accepts self-signed and hostname-mismatched
/// certificates. Necessary for local NAS devices that ship with certificates
/// issued for a domain name (e.g. *.synology.me) but are accessed via LAN IP.
http.Client createTrustingClient() {
  final inner = HttpClient()
    ..badCertificateCallback = (cert, host, port) => true;
  return IOClient(inner);
}
