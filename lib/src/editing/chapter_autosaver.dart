import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../folders/atomic_write.dart';
import '../model/chapter.dart';
import '../model/chapter_format.dart';
import 'chapter_editor.dart';

/// The file changed on disk in a way that needs the user to decide what happens.
class DiskConflict {
  const DiskConflict(this.text);

  /// What the file now holds, or null if it's gone.
  final String? text;

  bool get isDeleted => text == null;
}

/// Writes the chapter to its file shortly after each edit, and follows changes
/// that others make to that file.
///
/// A save only replaces the text this class last saw in the file, so it never
/// overwrites a change it doesn't know about. If that change meets edits not
/// saved yet, or the file is gone, saving stops at [conflict] until the user has
/// chosen with [keepMine], [takeTheirs] or [saveMineAsCopy].
///
/// A failed save keeps the edit in memory, reports it through [error], and is
/// tried again on the next edit or [flush].
class ChapterAutosaver extends ChangeNotifier {
  ChapterAutosaver(
    this._editor,
    this._file, {
    required String this._diskText,
    this._warnings = const [],
    this.delay = const Duration(seconds: 1),
  }) : _saved = _editor.chapter {
    _editor.addListener(_onEditorChanged);
  }

  final ChapterEditor _editor;
  final File _file;
  final Duration delay;

  /// What the file held when last seen, or null if it was gone.
  String? _diskText;
  List<String> _warnings;

  /// The version the file holds, or null if the next save has to write anyway.
  Chapter? _saved;
  Timer? _timer;
  Future<void>? _writing;
  Future<void> _queue = Future.value();
  Object? _error;
  DiskConflict? _conflict;
  bool _disposed = false;

  /// Why the last save failed, if it did.
  Object? get error => _error;

  /// The change on disk waiting for the user's decision.
  DiskConflict? get conflict => _conflict;

  /// The repairs made while reading the version of the file last loaded.
  List<String> get warnings => _warnings;

  /// Whether the file holds the latest edits.
  bool get isUpToDate => identical(_editor.chapter, _saved);

  void _onEditorChanged() {
    if (isUpToDate) return;
    _timer?.cancel();
    _timer = Timer(delay, flush);
  }

  /// Runs jobs that touch the file one at a time, so that a check can't read the
  /// file halfway through a save.
  Future<void> _enqueue(Future<void> Function() job) {
    final run = _queue.then((_) => job());
    _queue = run.catchError((Object _) {});
    return run;
  }

  /// Saves now, if needed, and completes when the file is up to date, the save
  /// failed, or the file turned out to have changed.
  Future<void> flush() {
    _timer?.cancel();
    return _writing ??= _enqueue(_writeUntilCurrent)
        .whenComplete(() => _writing = null);
  }

  /// Looks at the file and acts on any change made to it.
  ///
  /// A file that can't be read right now is left for the next check.
  Future<void> checkDisk() => _enqueue(() async {
    if (_disposed || _conflict != null) return;
    final String? text;
    try {
      text = await _readDisk();
    } on FileSystemException {
      return;
    }
    if (!_disposed && _conflict == null && text != _diskText) {
      _onDiskChanged(text);
    }
  });

  Future<String?> _readDisk() async {
    try {
      return await _file.readAsString();
    } on PathNotFoundException {
      return null;
    }
  }

  void _onDiskChanged(String? text) {
    if (text == null) {
      _timer?.cancel();
      _conflict = const DiskConflict(null);
      notifyListeners();
      return;
    }
    final parsed = ChapterFormat.parse(text);
    if (listEquals(parsed.chapter.segments, _editor.chapter.segments)) {
      // The file now says what the editor says, so there's nothing to resolve.
      _timer?.cancel();
      _diskText = text;
      _saved = _editor.chapter;
      _warnings = parsed.warnings;
      notifyListeners();
    } else if (isUpToDate) {
      _load(text, parsed);
    } else {
      _timer?.cancel();
      _conflict = DiskConflict(text);
      notifyListeners();
    }
  }

  void _load(String text, ParseResult parsed) {
    _diskText = text;
    _warnings = parsed.warnings;
    _saved = parsed.chapter;
    _editor.replaceFromDisk(parsed.chapter);
    notifyListeners();
  }

  Future<void> _writeUntilCurrent() async {
    // More edits may arrive during a write; those need another one.
    while (!isUpToDate && _conflict == null) {
      final chapter = _editor.chapter;
      final String text;
      try {
        final found = await _readDisk();
        if (found != _diskText) {
          _onDiskChanged(found);
          continue;
        }
        if (found == null) await _file.parent.create(recursive: true);
        text = ChapterFormat.serialize(chapter);
        await writeAtomically(_file, text);
      } on Object catch (e) {
        _error = e;
        notifyListeners();
        return;
      }
      _diskText = text;
      _saved = chapter;
      if (_error != null) {
        _error = null;
        notifyListeners();
      }
    }
  }

  /// Resolves the conflict by writing the editor's version over the file, or
  /// back to where the file was if it's gone.
  Future<void> keepMine() {
    final conflict = _conflict;
    if (conflict == null) return Future.value();
    _conflict = null;
    _diskText = conflict.text;
    _saved = null;
    notifyListeners();
    return flush();
  }

  /// Resolves the conflict by loading the file, which ends the undo history.
  void takeTheirs() {
    final text = _conflict?.text;
    if (text == null) return;
    _conflict = null;
    _load(text, ChapterFormat.parse(text));
  }

  /// Resolves the conflict by writing the editor's version to a new file beside
  /// this one, then loading this one. Returns the new file's name.
  ///
  /// If writing the copy fails this throws, and the conflict stays.
  Future<String> saveMineAsCopy() async {
    final copy = await _freeCopyFile();
    await writeAtomically(copy, ChapterFormat.serialize(_editor.chapter));
    takeTheirs();
    return p.basename(copy.path);
  }

  /// The name sorts right after the original's, so the copy doesn't become the
  /// first file of the folder, which would change the folder's display name.
  Future<File> _freeCopyFile() async {
    final stem = p.withoutExtension(_file.path);
    final extension = p.extension(_file.path);
    var candidate = File('${stem}_copy$extension');
    for (var i = 2; await candidate.exists(); i++) {
      candidate = File('${stem}_copy$i$extension');
    }
    return candidate;
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _editor.removeListener(_onEditorChanged);
    super.dispose();
  }
}
