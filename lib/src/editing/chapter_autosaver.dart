import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../folders/atomic_write.dart';
import '../model/chapter.dart';
import '../model/chapter_format.dart';
import 'chapter_editor.dart';

/// Writes the chapter to its file shortly after each edit.
///
/// A failed save keeps the edit in memory, reports it through [error], and is
/// tried again on the next edit or [flush].
class ChapterAutosaver extends ChangeNotifier {
  ChapterAutosaver(
    this._editor,
    this._file, {
    this.delay = const Duration(seconds: 1),
  }) : _saved = _editor.chapter {
    _editor.addListener(_onEditorChanged);
  }

  final ChapterEditor _editor;
  final File _file;
  final Duration delay;

  Chapter _saved;
  Timer? _timer;
  Future<void>? _writing;
  Object? _error;

  /// Why the last save failed, if it did.
  Object? get error => _error;

  /// Whether the file holds the latest edits.
  bool get isUpToDate => identical(_editor.chapter, _saved);

  void _onEditorChanged() {
    if (isUpToDate) return;
    _timer?.cancel();
    _timer = Timer(delay, flush);
  }

  /// Saves now, if needed, and completes when the file is up to date or the
  /// save failed.
  Future<void> flush() {
    _timer?.cancel();
    return _writing ??= _writeUntilCurrent().whenComplete(
      () => _writing = null,
    );
  }

  Future<void> _writeUntilCurrent() async {
    // More edits may arrive during a write; those need another one.
    while (!isUpToDate) {
      final chapter = _editor.chapter;
      try {
        await writeAtomically(_file, ChapterFormat.serialize(chapter));
      } on Object catch (e) {
        _error = e;
        notifyListeners();
        return;
      }
      _saved = chapter;
      if (_error != null) {
        _error = null;
        notifyListeners();
      }
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _editor.removeListener(_onEditorChanged);
    super.dispose();
  }
}
