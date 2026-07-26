import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/api/synology_api_client.dart';
import '../core/services/note_station_service.dart';
import 'session_provider.dart';

/// Provides a [SynologyApiClient] wired to the active session.
/// Returns null when not logged in.
final apiClientProvider = Provider<SynologyApiClient?>((ref) {
  final session = ref.watch(sessionProvider);
  if (session == null) return null;
  return SynologyApiClient.withSid(session.baseUrl, session.sid,
      synoToken: session.synoToken);
});

/// Provides the [NoteStationService], or null when not logged in.
final noteStationServiceProvider = Provider<NoteStationService?>((ref) {
  final client = ref.watch(apiClientProvider);
  if (client == null) return null;
  return NoteStationService(client);
});

/// The short-lived download ticket (`tid`) inline note images need (see
/// [SynologyApiClient.noteImageUri]/[SynologyApiClient.grantDownloadTicket]).
/// Fetched once per session and cached here — every image in every note
/// reuses it rather than granting a fresh ticket per image.
final noteImageTidProvider = FutureProvider<String?>((ref) async {
  final client = ref.watch(apiClientProvider);
  if (client == null) return null;
  return client.grantDownloadTicket(
    api: 'SYNO.NoteStation.Note',
    methods: ['download'],
  );
});
