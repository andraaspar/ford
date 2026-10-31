import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import '../folders/folder_tree.dart';

/// Where the reader was in a chapter: the row at the top of the view, and how
/// far that row's top edge sits from the top of the view, as a fraction of the
/// view's height (negative when the row is partly scrolled off).
///
/// Stored by row ID so it survives rows being added or removed above it.
class ReadingPosition {
  const ReadingPosition(this.rowId, this.alignment);

  final String rowId;
  final double alignment;
}

/// Settings local to this device; they are not synced with the files.
class AppSettings {
  AppSettings(this._prefs);

  static Future<AppSettings> load() async =>
      AppSettings(await SharedPreferences.getInstance());

  // Keeps its earlier name, so that devices remember the folder they had chosen.
  static const _rootPathKey = 'bookPath';
  static const _lastChapterPrefix = 'lastChapter:';
  static const _positionPrefix = 'position:';

  final SharedPreferences _prefs;

  String? get rootPath => _prefs.getString(_rootPathKey);

  Future<void> setRootPath(String? path) => path == null
      ? _prefs.remove(_rootPathKey)
      : _prefs.setString(_rootPathKey, path);

  /// The last chapter read under [rootPath], as a path relative to it.
  String? lastChapter(String rootPath) =>
      _prefs.getString('$_lastChapterPrefix$rootPath');

  Future<void> setLastChapter(String rootPath, String relativePath) =>
      _prefs.setString('$_lastChapterPrefix$rootPath', relativePath);

  ReadingPosition? position(String chapterPath) {
    final stored = _prefs.getStringList('$_positionPrefix$chapterPath');
    if (stored == null || stored.length != 2) return null;
    final alignment = double.tryParse(stored[1]);
    return alignment == null ? null : ReadingPosition(stored[0], alignment);
  }

  Future<void> setPosition(String chapterPath, ReadingPosition position) =>
      _prefs.setStringList('$_positionPrefix$chapterPath', [
        position.rowId,
        position.alignment.toString(),
      ]);

  /// Makes saved positions and last-read chapters follow files and folders that
  /// moved (old path to new path).
  Future<void> relocate(Map<String, String> moves) async {
    final positions = <String, List<String>>{};
    for (final key in _keysWith(_positionPrefix)) {
      final path = key.substring(_positionPrefix.length);
      final moved = movedPath(path, moves);
      final stored = _prefs.getStringList(key);
      if (moved == null || stored == null) continue;
      positions[moved] = stored;
      await _prefs.remove(key);
    }
    for (final MapEntry(key: path, value: stored) in positions.entries) {
      await _prefs.setStringList('$_positionPrefix$path', stored);
    }
    for (final key in _keysWith(_lastChapterPrefix)) {
      final root = key.substring(_lastChapterPrefix.length);
      final stored = _prefs.getString(key);
      if (stored == null) continue;
      final moved = movedPath(p.join(root, stored), moves);
      if (moved != null) {
        await _prefs.setString(key, p.relative(moved, from: root));
      }
    }
  }

  /// Drops what's saved about a deleted file or folder.
  Future<void> forget(String path) async {
    bool gone(String other) => other == path || p.isWithin(path, other);
    for (final key in _keysWith(_positionPrefix)) {
      if (gone(key.substring(_positionPrefix.length))) await _prefs.remove(key);
    }
    for (final key in _keysWith(_lastChapterPrefix)) {
      final root = key.substring(_lastChapterPrefix.length);
      final stored = _prefs.getString(key);
      if (stored != null && gone(p.join(root, stored))) {
        await _prefs.remove(key);
      }
    }
  }

  List<String> _keysWith(String prefix) =>
      _prefs.getKeys().where((k) => k.startsWith(prefix)).toList();
}
