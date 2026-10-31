import 'package:ford/src/model/chapter.dart';
import 'package:ford/src/model/chapter_format.dart';
import 'package:ford/src/model/segment.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('serialize/parse', () {
    test('round trip keeps everything', () {
      final ch = Chapter([
        Segment(id: 'title', source: 'Chapter one', target: 'Első fejezet'),
        Segment(
          id: 'a1',
          source: 'Hello | world <b>',
          target: 'Szia világ',
          remark: 'first\nsecond',
        ),
        Segment(id: 'a2'),
        Segment(id: 'a3', source: '> looks like a mark', target: '! also'),
      ]);
      final text = ChapterFormat.serialize(ch);
      final parsed = ChapterFormat.parse(text);
      expect(parsed.warnings, isEmpty);
      expect(parsed.chapter.segments, ch.segments);
      expect(ChapterFormat.serialize(parsed.chapter), text);
    });

    test('canonical layout', () {
      final ch = Chapter([
        Segment(id: 'a1', source: 'S', target: 'T', remark: 'R'),
        Segment(id: 'a2', source: 'S2'),
      ]);
      expect(
        ChapterFormat.serialize(ch),
        '@ a1\n< S\n> T\n! R\n'
        '\n'
        '@ a2\n< S2\n>\n',
      );
    });

    test('line breaks in paragraphs are flattened on save', () {
      final ch = Chapter([Segment(id: 'a', source: 'x\ny', target: 'p\r\nq')]);
      final parsed = ChapterFormat.parse(ChapterFormat.serialize(ch));
      expect(parsed.chapter.segments.single.source, 'x y');
      expect(parsed.chapter.segments.single.target, 'p q');
    });

    test('tolerates CRLF, BOM, comments, extra blank lines, no space', () {
      const text = '\uFEFF# comment\r\n\r\n\r\n@ a\r\n<S\r\n>T\r\n\r\n';
      final parsed = ChapterFormat.parse(text);
      expect(parsed.warnings, isEmpty);
      expect(parsed.chapter.segments, [Segment(id: 'a', source: 'S', target: 'T')]);
    });

    test('missing and duplicate ids are repaired with warnings', () {
      const text = '< no id\n>\n\n@ x\n< one\n\n@ x\n< two\n';
      final parsed = ChapterFormat.parse(text);
      final segs = parsed.chapter.segments;
      expect(segs.map((s) => s.source), ['no id', 'one', 'two']);
      expect(segs.map((s) => s.id).toSet().length, 3);
      expect(segs[1].id, 'x');
      expect(parsed.warnings, hasLength(2));
    });

    test('id line without blank line starts a new block', () {
      const text = '@ a\n< one\n@ b\n< two\n';
      final parsed = ChapterFormat.parse(text);
      expect(parsed.chapter.segments.map((s) => s.id), ['a', 'b']);
    });

    test('unknown lines are kept as remark', () {
      const text = '@ a\n< S\nstray text\n';
      final parsed = ChapterFormat.parse(text);
      expect(parsed.chapter.segments.single.remark, 'stray text');
      expect(parsed.warnings, hasLength(1));
    });

    test('empty file gives empty chapter', () {
      expect(ChapterFormat.parse('').chapter.isEmpty, isTrue);
      expect(ChapterFormat.serialize(Chapter([])), '');
    });
  });
}

