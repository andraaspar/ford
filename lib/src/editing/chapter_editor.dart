import 'package:flutter/foundation.dart';

import '../model/chapter.dart';
import '../model/segment.dart';

/// The cell being edited, and where its caret is.
class ActiveCell {
  const ActiveCell(this.rowId, this.field, this.offset);

  final String rowId;
  final Field field;
  final int offset;
}

/// Where two versions of a chapter first differ.
class ChapterChange {
  const ChapterChange(this.index, this.rowId, this.field, this.offset);

  /// Index in the newer version.
  final int index;
  final String rowId;

  /// The differing field, or null when rows were added or removed here.
  final Field? field;
  final int offset;
}

/// Finds the first difference between [before] and [after], or null if they
/// have the same content.
ChapterChange? firstChange(Chapter before, Chapter after) {
  final common = before.length < after.length ? before.length : after.length;
  for (var i = 0; i < common; i++) {
    final a = before.segments[i];
    final b = after.segments[i];
    if (a == b) continue;
    if (a.id != b.id) return ChapterChange(i, b.id, null, 0);
    for (final field in Field.values) {
      final x = a.field(field);
      final y = b.field(field);
      if (x != y) return ChapterChange(i, b.id, field, _commonPrefix(x, y));
    }
  }
  if (before.length == after.length || after.isEmpty) return null;
  final index = common < after.length ? common : after.length - 1;
  return ChapterChange(index, after.segments[index].id, null, 0);
}

int _commonPrefix(String a, String b) {
  var i = 0;
  while (i < a.length && i < b.length && a.codeUnitAt(i) == b.codeUnitAt(i)) {
    i++;
  }
  return i;
}

/// The chapter being edited, with its undo history and the active cell.
///
/// Knows nothing about files or widgets. Every change to [chapter] notifies
/// listeners while the view still shows the old rows, so the view can keep its
/// scroll position whatever the change was.
class ChapterEditor extends ChangeNotifier {
  ChapterEditor(this._chapter, {DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  static const _maxUndo = 500;

  /// Typing in one cell with pauses shorter than this is one undo step.
  static const _typingGroupGap = Duration(milliseconds: 1500);

  final DateTime Function() _clock;
  final _undo = <Chapter>[];
  final _redo = <Chapter>[];

  Chapter _chapter;
  ActiveCell? _active;
  ChapterChange? _reveal;
  (String, Field)? _typingCell;
  DateTime? _lastTyping;

  Chapter get chapter => _chapter;
  ActiveCell? get active => _active;
  bool get canUndo => _undo.isNotEmpty;
  bool get canRedo => _redo.isNotEmpty;

  /// The change made by the last undo or redo, for the view to bring into
  /// sight. Reading it clears it.
  ChapterChange? takeReveal() {
    final reveal = _reveal;
    _reveal = null;
    return reveal;
  }

  void activate(String rowId, Field field, {int? offset}) {
    final index = _chapter.indexOfId(rowId);
    if (index < 0) return;
    final length = _chapter.segments[index].field(field).length;
    _active = ActiveCell(rowId, field, (offset ?? length).clamp(0, length));
    _typingCell = null;
    notifyListeners();
  }

  void deactivate() {
    if (_active == null) return;
    _active = null;
    _typingCell = null;
    notifyListeners();
  }

  /// Records the caret position. Nothing on screen depends on it, so listeners
  /// aren't notified.
  void moveCaret(int offset) {
    final active = _active;
    if (active != null) {
      _active = ActiveCell(active.rowId, active.field, offset);
    }
  }

  void setText(String rowId, Field field, String text) {
    final index = _chapter.indexOfId(rowId);
    if (index < 0) return;
    final segment = _chapter.segments[index];
    if (segment.field(field) == text) return;

    final now = _clock();
    final last = _lastTyping;
    final sameGroup =
        _typingCell == (rowId, field) &&
        last != null &&
        now.difference(last) < _typingGroupGap;
    if (!sameGroup) _remember();
    _typingCell = (rowId, field);
    _lastTyping = now;
    _chapter = _chapter.updateSegment(index, segment.withField(field, text));
    _redo.clear();
    notifyListeners();
  }

  /// Splits the active cell at the caret and moves the caret to the new row.
  /// Does nothing in a remark, which has no sides to split.
  void splitAtCaret() {
    final active = _active;
    final side = active?.field.side;
    if (active == null || side == null) return;
    final index = _chapter.indexOfId(active.rowId);
    if (index < 0) return;
    final next = _chapter.split(index, side, active.offset);
    _active = ActiveCell(next.segments[index + 1].id, active.field, 0);
    _apply(next);
  }

  bool canJoinWithNext(String rowId) {
    final index = _chapter.indexOfId(rowId);
    return index >= 0 && index + 1 < _chapter.length;
  }

  void joinWithNext(String rowId) {
    if (!canJoinWithNext(rowId)) return;
    final index = _chapter.indexOfId(rowId);
    final removedId = _chapter.segments[index + 1].id;
    final next = _chapter.joinWithNext(index);
    final active = _active;
    if (active != null && active.rowId == removedId) {
      final length = next.segments[index].field(active.field).length;
      _active = ActiveCell(rowId, active.field, length);
    }
    _apply(next);
  }

  /// Inserts a blank row (a break) at [index].
  void insertBlank(int index) => _apply(_chapter.insertEmpty(index));

  /// The title row can't be deleted: the next row would silently take over as
  /// the chapter's title.
  bool canDelete(String rowId) => _chapter.indexOfId(rowId) > 0;

  void delete(String rowId) {
    if (!canDelete(rowId)) return;
    if (_active?.rowId == rowId) _active = null;
    _apply(_chapter.delete(_chapter.indexOfId(rowId)));
  }

  void undo() {
    if (_undo.isEmpty) return;
    _redo.add(_chapter);
    _restore(_undo.removeLast());
  }

  void redo() {
    if (_redo.isEmpty) return;
    _undo.add(_chapter);
    _restore(_redo.removeLast());
  }

  void _restore(Chapter version) {
    final change = firstChange(_chapter, version);
    _chapter = version;
    _reveal = change;
    _typingCell = null;

    // An active cell follows the restored text, so the caret ends up where the
    // change is; otherwise editing stays closed.
    final active = _active;
    if (active != null) {
      final field = change?.field;
      if (change != null && field != null) {
        _active = ActiveCell(change.rowId, field, change.offset);
      } else if (version.indexOfId(active.rowId) < 0) {
        _active = null;
      }
    }
    notifyListeners();
  }

  void _apply(Chapter next) {
    _remember();
    _typingCell = null;
    _chapter = next;
    _redo.clear();
    notifyListeners();
  }

  void _remember() {
    _undo.add(_chapter);
    if (_undo.length > _maxUndo) _undo.removeAt(0);
  }
}
