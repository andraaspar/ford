import 'ids.dart';
import 'segment.dart';

/// An ordered list of segments. Immutable: every operation returns a new
/// [Chapter].
///
/// By convention the first segment is the chapter title pair.
class Chapter {
  Chapter(List<Segment> segments) : segments = List.unmodifiable(segments);

  final List<Segment> segments;

  int get length => segments.length;
  bool get isEmpty => segments.isEmpty;

  Set<String> get ids => {for (final s in segments) s.id};

  int indexOfId(String id) => segments.indexWhere((s) => s.id == id);

  /// Display name for chapter lists: the source title, falling back to the
  /// target title.
  String? get title {
    if (segments.isEmpty) return null;
    final first = segments.first;
    if (first.source.trim().isNotEmpty) return first.source.trim();
    if (first.target.trim().isNotEmpty) return first.target.trim();
    return null;
  }

  Chapter _replace(int start, int end, Iterable<Segment> replacement) {
    final list = [...segments]..replaceRange(start, end, replacement);
    return Chapter(list);
  }

  Chapter updateSegment(int index, Segment segment) =>
      _replace(index, index + 1, [segment]);

  /// Inserts an empty segment at [index] (0..length).
  Chapter insertEmpty(int index) =>
      _replace(index, index, [Segment(id: newId(ids))]);

  Chapter delete(int index) => _replace(index, index + 1, const []);

  /// Splits the text on [side] of segment [index] at [offset].
  ///
  /// The text before the cursor stays in the current segment; a new segment is
  /// inserted right after it holding the text after the cursor on [side] and
  /// an empty cell on the other side. The remark stays with the original row.
  /// Whitespace at the cut is trimmed on both halves.
  Chapter split(int index, Side side, int offset) {
    final seg = segments[index];
    final text = seg.text(side);
    final cut = offset.clamp(0, text.length);
    final head = text.substring(0, cut).trimRight();
    final tail = text.substring(cut).trimLeft();
    final created = Segment(id: newId(ids)).withText(side, tail);
    return _replace(index, index + 1, [seg.withText(side, head), created]);
  }

  /// Merges segment [index] with segment `index + 1`: source, target and remark
  /// are each concatenated (texts with a space, remarks with a line break).
  /// Empty parts are skipped so no stray separators are added.
  Chapter joinWithNext(int index) {
    if (index < 0 || index + 1 >= segments.length) {
      throw RangeError('No segment after index $index to join with.');
    }
    final a = segments[index];
    final b = segments[index + 1];
    String join(String x, String y, String sep) =>
        [x, y].where((s) => s.isNotEmpty).join(sep);
    final merged = a.copyWith(
      source: join(a.source, b.source, ' '),
      target: join(a.target, b.target, ' '),
      remark: join(a.remark, b.remark, '\n'),
    );
    return _replace(index, index + 2, [merged]);
  }
}

