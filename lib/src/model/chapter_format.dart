import 'chapter.dart';
import 'ids.dart';
import 'segment.dart';

/// Chapter file format (one block per segment, blocks separated by blank
/// lines):
///
/// ```
/// @ k3f9a
/// < Source paragraph.
/// > Target paragraph.
/// ! Remark line (optional, may repeat).
/// ```
///
/// Lines starting with `#` are comments and are ignored.
class ChapterFormat {
  static const sourceMark = '<';
  static const targetMark = '>';
  static const remarkMark = '!';
  static const idMark = '@';
  static const commentMark = '#';

  /// Serializes [chapter] in the canonical layout. Output always ends with a
  /// single newline and uses `\n` line endings.
  static String serialize(Chapter chapter) {
    final b = StringBuffer();
    var first = true;
    for (final s in chapter.segments) {
      if (!first) b.write('\n');
      first = false;
      b.write('$idMark ${s.id}\n');
      b.write(_line(sourceMark, _oneLine(s.source)));
      b.write(_line(targetMark, _oneLine(s.target)));
      if (s.hasRemark) {
        for (final r in s.remark.split('\n')) {
          b.write(_line(remarkMark, r));
        }
      }
    }
    return b.toString();
  }

  static String _line(String mark, String text) =>
      text.isEmpty ? '$mark\n' : '$mark $text\n';

  static String _oneLine(String s) =>
      s.replaceAll(RegExp(r'[\r\n]+'), ' ');

  /// Parses chapter file [content]. Never throws: problems are collected in
  /// [ParseResult.warnings] and the best possible chapter is returned.
  static ParseResult parse(String content) {
    final warnings = <String>[];
    final segments = <Segment>[];
    final taken = <String>{};

    String? id;
    String? source;
    String? target;
    final remark = <String>[];
    var blockStart = 0;
    var inBlock = false;

    void flush() {
      if (!inBlock) return;
      var segId = id;
      if (segId == null || !isValidId(segId)) {
        segId = newId(taken);
        warnings.add('Line $blockStart: missing id, assigned "$segId".');
      } else if (taken.contains(segId)) {
        final fresh = newId(taken);
        warnings.add(
          'Line $blockStart: duplicate id "$segId", replaced with "$fresh".',
        );
        segId = fresh;
      }
      taken.add(segId);
      segments.add(
        Segment(
          id: segId,
          source: source ?? '',
          target: target ?? '',
          remark: remark.join('\n'),
        ),
      );
      id = null;
      source = null;
      target = null;
      remark.clear();
      inBlock = false;
    }

    var text = content;
    if (text.startsWith('\uFEFF')) text = text.substring(1);
    final lines = text.split(RegExp(r'\r\n|\r|\n'));

    for (var i = 0; i < lines.length; i++) {
      final lineNo = i + 1;
      final line = lines[i];
      if (line.trim().isEmpty) {
        flush();
        continue;
      }
      if (line.startsWith(commentMark)) continue;

      final mark = line[0];
      final value = _value(line);

      if (!inBlock) {
        inBlock = true;
        blockStart = lineNo;
      }

      switch (mark) {
        case idMark:
          if (id != null || source != null || target != null) {
            // A new id inside a block: treat it as the start of a new block.
            flush();
            inBlock = true;
            blockStart = lineNo;
          }
          id = value.trim();
        case sourceMark:
          if (source != null) {
            warnings.add('Line $lineNo: second source line, appended.');
            source = [source!, value].where((s) => s.isNotEmpty).join(' ');
          } else {
            source = value;
          }
        case targetMark:
          if (target != null) {
            warnings.add('Line $lineNo: second target line, appended.');
            target = [target!, value].where((s) => s.isNotEmpty).join(' ');
          } else {
            target = value;
          }
        case remarkMark:
          remark.add(value);
        default:
          warnings.add('Line $lineNo: unrecognized line, kept as remark.');
          remark.add(line);
      }
    }
    flush();
    return ParseResult(Chapter(segments), warnings);
  }

  /// Text after the one-character mark, minus one separating space.
  static String _value(String line) {
    final rest = line.substring(1);
    return rest.startsWith(' ') ? rest.substring(1) : rest;
  }
}

class ParseResult {
  ParseResult(this.chapter, this.warnings);
  final Chapter chapter;
  final List<String> warnings;
}

