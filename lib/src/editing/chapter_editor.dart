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

/// A piece of text to point out in a row, such as a search match.
class TextMark {
  const TextMark(this.rowId, this.field, this.start, this.end);

  final String rowId;
  final Field field;
  final int start;
  final int end;
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

/// The chapter being edited, with its undo history, the active cell and the
/// selected rows.
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
  final _selected = <String>{};

  Chapter _chapter;
  ActiveCell? _active;
  ChapterChange? _reveal;
  TextMark? _mark;
  (String, Field)? _typingCell;
  DateTime? _lastTyping;
  String? _selectionAnchor;

  Chapter get chapter => _chapter;
  ActiveCell? get active => _active;

  /// The text being pointed out. Any edit clears it, as its offsets could then
  /// be wrong.
  TextMark? get mark => _mark;
  bool get canUndo => _undo.isNotEmpty;
  bool get canRedo => _redo.isNotEmpty;

  /// The change made by the last undo or redo, for the view to bring into
  /// sight. Reading it clears it.
  ChapterChange? takeReveal() {
    final reveal = _reveal;
    _reveal = null;
    return reveal;
  }

  /// Points out [mark] and has the view bring it into sight, ending any editing
  /// or selecting. If its row is gone, nothing happens.
  void showMark(TextMark mark) {
    final index = _chapter.indexOfId(mark.rowId);
    if (index < 0) return;
    _mark = mark;
    _reveal = ChapterChange(index, mark.rowId, mark.field, mark.start);
    _active = null;
    _typingCell = null;
    _selected.clear();
    notifyListeners();
  }

  void activate(String rowId, Field field, {int? offset}) {
    final index = _chapter.indexOfId(rowId);
    if (index < 0) return;
    _mark = null;
    final length = _chapter.segments[index].field(field).length;
    _active = ActiveCell(rowId, field, (offset ?? length).clamp(0, length));
    _typingCell = null;
    _selected.clear();
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
    _mark = null;
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

  /// Whether the active cell's row can merge into the row above it. Only source
  /// and target cells can do this, and the title row has nothing above it.
  bool get canMergeActiveWithPrevious {
    final active = _active;
    if (active == null || active.field.side == null) return false;
    return _chapter.indexOfId(active.rowId) > 0;
  }

  /// Whether merging also moves text the user isn't looking at: the other side
  /// of the active row.
  bool get activeMergeMovesOtherSide {
    final active = _active;
    if (active == null || active.field.side == null) return false;
    final index = _chapter.indexOfId(active.rowId);
    if (index < 0) return false;
    final other = active.field == Field.source ? Field.target : Field.source;
    return _chapter.segments[index].field(other).isNotEmpty;
  }

  /// Merges the active row into the row above it, with the caret where the two
  /// texts meet. The opposite of [splitAtCaret].
  void mergeActiveWithPrevious() {
    if (!canMergeActiveWithPrevious) return;
    final active = _active!;
    final index = _chapter.indexOfId(active.rowId);
    final previous = _chapter.segments[index - 1];
    final before = previous.field(active.field);
    final moved = _chapter.segments[index].field(active.field);
    final offset =
        before.length + (before.isNotEmpty && moved.isNotEmpty ? 1 : 0);
    _active = ActiveCell(previous.id, active.field, offset);
    _apply(_chapter.joinWithNext(index - 1));
  }

  /// Inserts a blank row (a break) at [index].
  void insertBlank(int index) => _apply(_chapter.insertEmpty(index));

  /// Deleting the title row makes the next row the title. Undo brings it back.
  void delete(String rowId) {
    final index = _chapter.indexOfId(rowId);
    if (index < 0) return;
    if (_active?.rowId == rowId) _active = null;
    _apply(_chapter.delete(index));
  }

  /// Whether rows are being selected, which replaces editing while it lasts.
  bool get isSelecting => _selected.isNotEmpty;

  int get selectedCount => _selected.length;

  bool isSelected(String rowId) => _selected.contains(rowId);

  /// The selected rows, in chapter order.
  List<Segment> get selectedRows =>
      _chapter.segments.where((s) => _selected.contains(s.id)).toList();

  /// The chapter as it would be without the selected rows.
  Chapter get chapterWithoutSelected => _chapter.deleteIds(_selected);

  /// Starts selecting, with [rowId] as the first selected row.
  void startSelecting(String rowId) {
    if (_chapter.indexOfId(rowId) < 0) return;
    _active = null;
    _typingCell = null;
    _selected
      ..clear()
      ..add(rowId);
    _selectionAnchor = rowId;
    notifyListeners();
  }

  /// Deselecting the last row ends selecting.
  void toggleSelected(String rowId) {
    if (_chapter.indexOfId(rowId) < 0) return;
    if (!_selected.remove(rowId)) _selected.add(rowId);
    _selectionAnchor = rowId;
    notifyListeners();
  }

  /// Adds all the rows from the last one tapped to [rowId].
  void selectRangeTo(String rowId) {
    final end = _chapter.indexOfId(rowId);
    if (end < 0) return;
    final anchor = _selectionAnchor;
    final found = anchor == null ? -1 : _chapter.indexOfId(anchor);
    final start = found < 0 ? end : found;
    final first = start < end ? start : end;
    final last = start < end ? end : start;
    for (var i = first; i <= last; i++) {
      _selected.add(_chapter.segments[i].id);
    }
    _selectionAnchor = rowId;
    notifyListeners();
  }

  void clearSelection() {
    if (_selected.isEmpty) return;
    _selected.clear();
    notifyListeners();
  }

  /// Whether any selected row has an unselected row above it.
  bool get canMoveSelectedUp {
    for (var i = 1; i < _chapter.length; i++) {
      if (_selected.contains(_chapter.segments[i].id) &&
          !_selected.contains(_chapter.segments[i - 1].id)) {
        return true;
      }
    }
    return false;
  }

  /// Whether any selected row has an unselected row below it.
  bool get canMoveSelectedDown {
    for (var i = 0; i < _chapter.length - 1; i++) {
      if (_selected.contains(_chapter.segments[i].id) &&
          !_selected.contains(_chapter.segments[i + 1].id)) {
        return true;
      }
    }
    return false;
  }

  void moveSelectedUp() {
    if (!canMoveSelectedUp) return;
    _reorder(_chapter.moveRowsUp(_selected), revealLast: false);
  }

  void moveSelectedDown() {
    if (!canMoveSelectedDown) return;
    _reorder(_chapter.moveRowsDown(_selected), revealLast: true);
  }

  /// Puts the selected rows together after the row with [afterRowId], or at the
  /// very start if that's null.
  void moveSelectedAfter(String? afterRowId) {
    if (_selected.isEmpty || _selected.length == _chapter.length) return;
    _reorder(_chapter.moveRowsAfter(_selected, afterRowId), revealLast: false);
  }

  /// Applies a new order and keeps the moved rows in sight, so that they can be
  /// moved on. Doesn't add an undo step if nothing changed.
  void _reorder(Chapter next, {required bool revealLast}) {
    if (firstChange(_chapter, next) == null) return;
    final moved = next.segments.where((s) => _selected.contains(s.id));
    final row = revealLast ? moved.last : moved.first;
    _reveal = ChapterChange(next.segments.indexOf(row), row.id, null, 0);
    _apply(next);
  }

  /// Removes the selected rows, which now live in another chapter's file. If
  /// the title row is one of them, the first row left becomes the title.
  ///
  /// Any earlier version in the undo history still has these rows, so going back
  /// to one would duplicate them. That's why the history ends here.
  void removeSelectedAfterMove() {
    if (_selected.isEmpty) return;
    _chapter = chapterWithoutSelected;
    _mark = null;
    _selected.clear();
    _active = null;
    _typingCell = null;
    _undo.clear();
    _redo.clear();
    notifyListeners();
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
    _mark = null;
    _reveal = change;
    _typingCell = null;
    _selected.retainWhere((id) => version.indexOfId(id) >= 0);

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
    _mark = null;
    _chapter = next;
    _redo.clear();
    notifyListeners();
  }

  void _remember() {
    _undo.add(_chapter);
    if (_undo.length > _maxUndo) _undo.removeAt(0);
  }
}
