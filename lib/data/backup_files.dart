import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Where exported backups are kept on disk.
///
/// A local-first app has no server to restore from, so the export has to land
/// somewhere the user can actually reach: a plain, readable `.json` file in the
/// app's documents directory that a file manager, a sync folder or a cable can
/// pick up.
class BackupFileStore {
  const BackupFileStore({this.directoryOverride});

  /// Used by tests to point the store at a temporary directory instead of the
  /// platform's documents directory.
  final Directory? directoryOverride;

  static const folderName = 'backups';

  Future<Directory> directory() async {
    final base = directoryOverride ?? await getApplicationDocumentsDirectory();
    final folder = Directory(p.join(base.path, folderName));
    if (!folder.existsSync()) await folder.create(recursive: true);
    return folder;
  }

  /// Writes [json] to a timestamped file and returns it.
  Future<File> write(String json, {DateTime? now}) async {
    final folder = await directory();
    final stamp = (now ?? DateTime.now())
        .toIso8601String()
        .replaceAll(':', '-')
        .split('.')
        .first;
    return File(p.join(folder.path, 'pocket-ledger-$stamp.json'))
        .writeAsString(json, flush: true);
  }

  /// Existing backups, newest first.
  Future<List<File>> list() async {
    final folder = await directory();
    final files = folder
        .listSync()
        .whereType<File>()
        .where((file) => file.path.endsWith('.json'))
        .toList();
    return files..sort((a, b) => b.path.compareTo(a.path));
  }
}
