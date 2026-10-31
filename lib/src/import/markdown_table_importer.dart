import '../model/chapter.dart';
import '../model/ids.dart';
import '../model/segment.dart';

/// Converts an Obsidian Markdown file containing a 3-column table
/// (source | target | remark) into a [Chapter].
///
/// - The table header row is the chapter title pair and becomes the first
///   segment. The `| - | - | - |` separator row is skipped.
/// - Blank rows are kept: they are paragraph / section breaks.
/// - Spreadsheet paste artifacts are repaired: a cell that opens a `"` quote
///   whose closing quote landed on a later row of its own (`| " | |`) has the
///   opening quote removed and the artifact rows dropped.
class MarkdownTableImporter {
  static final _separatorRow = RegExp(r'^\|?(\s*:?-+:?\s*\|)*\s*:?-+:?\s*\|?$');
  static final _br = RegExp(r'<br\s*/?>', caseSensitive: false);

  /// How many rows after an opening quote are searched for the closing one.
  static const _quoteLookahead = 3;

  static ImportResult import(String content) {
    final warnings = <String>[];

    var text = content;
    if (text.startsWith('\uFEFF')) text = text.substring(1);
    final lines = text.split(RegExp(r'\r\n|\r|\n'));

    // 1. Collect table rows as cell lists.
    final rows = <_Row>[];
    for (var i = 0; i < lines.length; i++) {
      final lineNo = i + 1;
      final line = lines[i].trim();
      if (line.isEmpty) continue;
      if (!line.startsWith('|')) {
        warnings.add('Line $lineNo: not a table row, skipped: "$line"');
        continue;
      }
      if (_separatorRow.hasMatch(line)) continue;
      rows.add(_Row(lineNo, splitRow(line)));
    }

    // 2. Repair quote artifacts.
    _repairQuotes(rows, warnings);

    // 3. Build segments.
    final segments = <Segment>[];
    final taken = <String>{};
    for (final row in rows) {
      final cells = row.cells;
      if (cells.length > 3) {
        warnings.add(
          'Line ${row.lineNo}: ${cells.length} cells, extra cells added to remark.',
        );
      }
      String cell(int n) => n < cells.length ? cells[n] : '';

      var source = cell(0);
      var target = cell(1);
      final remark = [
        for (var n = 2; n < cells.length; n++) cells[n].replaceAll(_br, '\n'),
      ].where((c) => c.trim().isNotEmpty).join('\n').trim();

      if (_br.hasMatch(source) || _br.hasMatch(target)) {
        warnings.add('Line ${row.lineNo}: <br> in paragraph replaced with a space.');
        source = source.replaceAll(_br, ' ').trim();
        target = target.replaceAll(_br, ' ').trim();
      }

      final id = newId(taken);
      taken.add(id);
      segments.add(
        Segment(id: id, source: source, target: target, remark: remark),
      );
    }
    return ImportResult(Chapter(segments), warnings);
  }

  static bool _isBlank(_Row r) => r.cells.every((c) => c.isEmpty);

  static bool _isClosingQuote(_Row r) =>
      r.cells.isNotEmpty &&
      r.cells.first == '"' &&
      r.cells.skip(1).every((c) => c.isEmpty);

  static void _repairQuotes(List<_Row> rows, List<String> warnings) {
    for (var i = 0; i < rows.length; i++) {
      final row = rows[i];
      for (var c = 0; c < row.cells.length; c++) {
        final cell = row.cells[c];
        // Only an unbalanced opening quote can be an artifact.
        if (!cell.startsWith('"') || '"'.allMatches(cell).length.isEven) {
          continue;
        }
        // Look for the closing-quote row, allowing blank rows in between.
        int? close;
        for (var j = i + 1; j < rows.length && j <= i + _quoteLookahead; j++) {
          if (_isClosingQuote(rows[j])) {
            close = j;
            break;
          }
          if (!_isBlank(rows[j])) break;
        }
        if (close == null) continue;
        row.cells[c] = cell.substring(1).trimLeft();
        final dropped = [for (var k = i + 1; k <= close; k++) rows[k].lineNo];
        rows.removeRange(i + 1, close + 1);
        warnings.add(
          'Line ${row.lineNo}: removed stray opening quote and '
          'artifact row(s) at line ${dropped.join(', ')}.',
        );
        break;
      }
    }
  }

  /// Splits a table row into trimmed cells, honouring `\|` escapes. The
  /// leading and trailing pipes are optional.
  static List<String> splitRow(String row) {
    var s = row.trim();
    if (s.startsWith('|')) s = s.substring(1);
    if (s.endsWith('|') && !s.endsWith(r'\|')) {
      s = s.substring(0, s.length - 1);
    }
    final cells = <String>[];
    final current = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      final c = s[i];
      if (c == r'\' && i + 1 < s.length && s[i + 1] == '|') {
        current.write('|');
        i++;
      } else if (c == '|') {
        cells.add(current.toString().trim());
        current.clear();
      } else {
        current.write(c);
      }
    }
    cells.add(current.toString().trim());
    return cells;
  }
}

class _Row {
  _Row(this.lineNo, this.cells);
  final int lineNo;
  final List<String> cells;
}

class ImportResult {
  ImportResult(this.chapter, this.warnings);
  final Chapter chapter;
  final List<String> warnings;
}
