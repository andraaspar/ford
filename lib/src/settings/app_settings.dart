import 'package:shared_preferences/shared_preferences.dart';

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

/// Settings local to this device; they are not synced with the book.
class AppSettings {
  AppSettings(this._prefs);

  static Future<AppSettings> load() async =>
      AppSettings(await SharedPreferences.getInstance());

  static const _bookPathKey = 'bookPath';
  static const _lastChapterPrefix = 'lastChapter:';
  static const _positionPrefix = 'position:';

  final SharedPreferences _prefs;

  String? get bookPath => _prefs.getString(_bookPathKey);

  Future<void> setBookPath(String? path) => path == null
      ? _prefs.remove(_bookPathKey)
      : _prefs.setString(_bookPathKey, path);

  String? lastChapter(String bookPath) =>
      _prefs.getString('$_lastChapterPrefix$bookPath');

  Future<void> setLastChapter(String bookPath, String fileName) =>
      _prefs.setString('$_lastChapterPrefix$bookPath', fileName);

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
}
