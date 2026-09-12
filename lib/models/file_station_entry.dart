/// A single folder/file entry from `SYNO.FileStation.List` (`list`/
/// `list_share`) — used to build a NAS folder/file browser for the
/// server-side .nsx export/import job (see file_station_service.dart).
class FileStationEntry {
  final String name;
  final String path;
  final bool isDirectory;

  const FileStationEntry({
    required this.name,
    required this.path,
    required this.isDirectory,
  });

  factory FileStationEntry.fromJson(Map<String, dynamic> json) {
    return FileStationEntry(
      name: json['name'] as String? ?? '',
      path: json['path'] as String? ?? '',
      isDirectory: json['isdir'] as bool? ?? false,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is FileStationEntry && other.path == path;

  @override
  int get hashCode => path.hashCode;
}
