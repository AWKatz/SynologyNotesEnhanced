import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/api/synology_api_client.dart';
import '../core/services/file_station_service.dart';
import '../core/services/note_station_service.dart';
import 'session_provider.dart';

/// Provides a [SynologyApiClient] wired to the active session.
/// Returns null when not logged in.
///
/// Rebuilt only when the NAS/account changes ([SynologySession.connectionKey]),
/// not when a background re-login refreshes the SID — the new SID is pushed
/// into the existing client instead, so the repository and every provider
/// built on top of it aren't torn down mid-sync.
final apiClientProvider = Provider<SynologyApiClient?>((ref) {
  final key = ref.watch(sessionProvider.select((s) => s?.connectionKey));
  if (key == null) return null;
  final session = ref.read(sessionProvider)!;
  final notifier = ref.read(sessionProvider.notifier);
  final urls = session.baseUrls;

  final client = SynologyApiClient.withSid(
    urls.first,
    session.sid,
    synoToken: session.synoToken,
    fallbackBaseUrls: urls.skip(1).toList(),
    onSessionExpired: notifier.reauthenticate,
  );
  ref.listen(sessionProvider, (_, next) {
    if (next != null && next.connectionKey == key) {
      client.updateSession(sid: next.sid, synoToken: next.synoToken);
    }
  });
  return client;
});

/// Provides the [NoteStationService], or null when not logged in.
final noteStationServiceProvider = Provider<NoteStationService?>((ref) {
  final client = ref.watch(apiClientProvider);
  if (client == null) return null;
  return NoteStationService(client);
});

/// Provides the [FileStationService], or null when not logged in.
final fileStationServiceProvider = Provider<FileStationService?>((ref) {
  final client = ref.watch(apiClientProvider);
  if (client == null) return null;
  return FileStationService(client);
});

/// The short-lived download ticket (`tid`) inline note images need (see
/// [SynologyApiClient.noteImageUri]/[SynologyApiClient.grantDownloadTicket]).
/// Fetched once per session and cached here — every image in every note
/// reuses it rather than granting a fresh ticket per image. Re-fetched when
/// a background re-login replaces the SID (the old ticket dies with it).
final noteImageTidProvider = FutureProvider<String?>((ref) async {
  final client = ref.watch(apiClientProvider);
  ref.watch(sessionProvider.select((s) => s?.sid));
  if (client == null) return null;
  return client.grantDownloadTicket(
    api: 'SYNO.NoteStation.Note',
    methods: ['download'],
  );
});
