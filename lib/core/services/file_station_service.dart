import '../api/synology_api_client.dart';
import '../../models/file_station_entry.dart';

/// High-level service wrapping `SYNO.FileStation.*` — a core DSM API family,
/// distinct from (and unrelated to) `SYNO.NoteStation.*`. Used to let the
/// server-side .nsx export/import job (see NoteStationService's
/// startNotebookExport/startNotebookImport) browse NAS folders and actually
/// move the resulting file to/from this device, instead of requiring a
/// hand-typed NAS path with no way to transfer the file afterward.
///
/// FileStation is one of Synology's officially published Web APIs (unlike
/// NoteStation, which this project reverse-engineers from captured traffic),
/// so this is implemented from that published spec — still worth confirming
/// against a real NAS, since exact shapes can drift slightly across DSM
/// versions even for documented APIs.
class FileStationService {
  final SynologyApiClient _client;

  FileStationService(this._client);

  /// Top-level shared folders (e.g. "homes", "Downloads") — the roots of any
  /// folder browse.
  Future<List<FileStationEntry>> listShares() async {
    final data = await _client.callCore(
      api: 'SYNO.FileStation.List',
      version: 2,
      method: 'list_share',
    );
    final list = data['shares'] as List<dynamic>? ?? [];
    return list
        .map((j) => FileStationEntry.fromJson(j as Map<String, dynamic>))
        .toList();
  }

  /// Lists the contents of [path]. [directoriesOnly] restricts to
  /// subfolders (for a destination-folder picker); [namePattern] is a glob
  /// like `*.nsx` (for filtering to importable files).
  Future<List<FileStationEntry>> listFolder(
    String path, {
    bool directoriesOnly = false,
    String? namePattern,
  }) async {
    final data = await _client.callCore(
      api: 'SYNO.FileStation.List',
      version: 2,
      method: 'list',
      params: {
        'folder_path': path,
        if (directoriesOnly) 'filetype': 'dir',
        if (namePattern != null) 'pattern': namePattern,
      },
    );
    final list = data['files'] as List<dynamic>? ?? [];
    return list
        .map((j) => FileStationEntry.fromJson(j as Map<String, dynamic>))
        .toList();
  }

  /// Downloads the raw bytes of the file at [path] on the NAS — closes the
  /// "moving the exported file to this device" gap in the server-side
  /// export job (it only ever writes the file to a NAS folder, never
  /// transfers it anywhere). Returns bytes rather than writing to a local
  /// path itself so the caller can hand them to file_picker's save dialog
  /// the same way this app's own local .nsx export already does (needed
  /// for correct behavior across desktop vs. mobile — see settings_screen
  /// .dart's _NsxImportExportState._export).
  ///
  /// Unlike every other FileStation/NoteStation call here, `Download`
  /// returns the raw file bytes directly rather than the usual
  /// `{success, data}` JSON envelope, so this bypasses [callCore] and hits
  /// the endpoint the same way [SynologyApiClient.downloadUri] does for
  /// NoteStation attachments.
  Future<List<int>> downloadFile({required String path}) async {
    final query = <String, String>{
      'api': 'SYNO.FileStation.Download',
      'version': '2',
      'method': 'download',
      'path': path,
      'mode': 'download',
      if (_client.sid != null) '_sid': _client.sid!,
      if (_client.synoToken != null) 'SynoToken': _client.synoToken!,
    };
    final uri = Uri.parse('${_client.baseUrl}/webapi/entry.cgi')
        .replace(queryParameters: query);
    return _client.fetchBytes(uri);
  }

  /// Uploads a local file onto the NAS at [remoteFolderPath]/[fileName] —
  /// closes the other half of the "move to/from this device" gap: the
  /// server-side import job only ever reads a file that's already on the
  /// NAS, so a `.nsx` the user has locally (e.g. from this app's own local
  /// NsxCodec export) needs to land there first.
  Future<void> uploadFile({
    required String remoteFolderPath,
    required String fileName,
    required List<int> bytes,
  }) async {
    await _client.callCoreMultipart(
      api: 'SYNO.FileStation.Upload',
      version: 2,
      method: 'upload',
      fields: {
        'path': remoteFolderPath,
        'create_parents': true,
        'overwrite': true,
      },
      fileFieldName: 'file',
      fileBytes: bytes,
      fileName: fileName,
    );
  }
}
