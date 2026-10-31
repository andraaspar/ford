import '../folders/folder_tree.dart';
import '../model/chapter.dart';
import '../model/chapter_format.dart';
import '../model/segment.dart';

/// Which parts of a row a search looks at.
enum SearchScope {
  all([Field.source, Field.target, Field.remark]),
  source([Field.source]),
  target([Field.target]),
  remarks([Field.remark]);

  const SearchScope(this.fields);

  final List<Field> fields;
}

/// An exact substring search: accents always count, and letter case counts only
/// with [matchCase]. The text isn't trimmed, so spaces in it count too.
class SearchQuery {
  SearchQuery(this.text, {this.matchCase = false, this.scope = SearchScope.all})
    : _needle = matchCase ? text : text.toLowerCase();

  final String text;
  final bool matchCase;
  final SearchScope scope;
  final String _needle;

  /// Where this query starts in [text]. Matches don't overlap.
  ///
  /// Offsets found in lowercased text apply to the original too, because Dart
  /// maps each character to exactly one character on the platforms this app
  /// runs on. That's also why `ß` and `SS` don't match, which suits an exact
  /// search.
  Iterable<int> startsIn(String text) sync* {
    if (_needle.isEmpty) return;
    final haystack = matchCase ? text : text.toLowerCase();
    var start = haystack.indexOf(_needle);
    while (start >= 0) {
      yield start;
      start = haystack.indexOf(_needle, start + _needle.length);
    }
  }

  /// Every match in [chapter], in reading order.
  List<SearchHit> hitsIn(ChapterEntry entry, Chapter chapter) => [
    for (final (index, row) in chapter.segments.indexed)
      for (final field in scope.fields)
        for (final start in startsIn(row.field(field)))
          SearchHit(
            chapter: entry,
            rowId: row.id,
            rowIndex: index,
            field: field,
            text: row.field(field),
            start: start,
            end: start + _needle.length,
          ),
  ];
}

/// One occurrence of the search text.
class SearchHit {
  const SearchHit({
    required this.chapter,
    required this.rowId,
    required this.rowIndex,
    required this.field,
    required this.text,
    required this.start,
    required this.end,
  });

  final ChapterEntry chapter;
  final String rowId;

  /// Finds the row if its ID doesn't hold: a file with a missing ID gets a new
  /// random one each time it's read, until it's saved.
  final int rowIndex;

  final Field field;

  /// The whole text of the field.
  final String text;
  final int start;
  final int end;
}

/// What came of searching some chapters.
class SearchResults {
  const SearchResults({
    required this.hits,
    required this.searched,
    required this.unreadable,
  });

  final List<SearchHit> hits;

  /// How many chapters were looked through.
  final int searched;

  /// The chapters that couldn't be read, so that nobody takes a missing result
  /// to mean the text isn't there.
  final List<ChapterEntry> unreadable;

  int get chaptersWithHits => {for (final hit in hits) hit.chapter.path}.length;
}

/// Searches [chapters] in order, reading them from disk, except the ones in
/// [open] (by path), whose edits may not be saved yet. Stops early once
/// [isCancelled] says so; the result is then incomplete.
Future<SearchResults> searchChapters(
  Iterable<ChapterEntry> chapters,
  SearchQuery query, {
  Map<String, Chapter> open = const {},
  bool Function()? isCancelled,
}) async {
  final hits = <SearchHit>[];
  final unreadable = <ChapterEntry>[];
  var searched = 0;
  for (final entry in chapters) {
    if (isCancelled?.call() ?? false) break;
    searched++;
    try {
      final chapter =
          open[entry.path] ??
          ChapterFormat.parse(await entry.file.readAsString()).chapter;
      hits.addAll(query.hitsIn(entry, chapter));
    } on Object {
      unreadable.add(entry);
    }
  }
  return SearchResults(hits: hits, searched: searched, unreadable: unreadable);
}

/// A short piece of text around a match, on one line.
typedef Snippet = ({String text, int start, int end});

/// Cuts [hit]'s text down to the match and about [context] characters on each
/// side of it.
Snippet snippetOf(SearchHit hit, {int context = 40}) {
  final text = hit.text;
  var from = hit.start - context;
  var to = hit.end + context;
  // Never cuts a character made of two code units in half.
  if (from > 0 && _isLowSurrogate(text.codeUnitAt(from))) from--;
  if (to < text.length && _isLowSurrogate(text.codeUnitAt(to))) to++;
  final cutStart = from > 0;
  final cutEnd = to < text.length;
  if (!cutStart) from = 0;
  if (!cutEnd) to = text.length;
  final lead = cutStart ? '…' : '';
  final shown = text.substring(from, to).replaceAll('\n', ' ');
  return (
    text: '$lead$shown${cutEnd ? '…' : ''}',
    start: lead.length + hit.start - from,
    end: lead.length + hit.end - from,
  );
}

bool _isLowSurrogate(int codeUnit) => codeUnit & 0xFC00 == 0xDC00;
