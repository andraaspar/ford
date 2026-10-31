import 'package:ford/src/import/markdown_table_importer.dart';
import 'package:ford/src/model/natural_sort.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('imports the Obsidian sample', () {
    const md = '| chapter title | fejezetcím | |\n'
        '| - | - | - |\n'
        '| First paragraph | Első bekezdés| Megjegyzés|\n';
    final r = MarkdownTableImporter.import(md);
    expect(r.warnings, isEmpty);
    final s = r.chapter.segments;
    expect(s, hasLength(2));
    expect(s[0].source, 'chapter title');
    expect(s[0].target, 'fejezetcím');
    expect(s[0].remark, '');
    expect(s[1].source, 'First paragraph');
    expect(s[1].target, 'Első bekezdés');
    expect(s[1].remark, 'Megjegyzés');
    expect(r.chapter.title, 'chapter title');
    expect(s[0].id, isNot(s[1].id));
  });

  test('two-column rows, escaped pipes, alignment separators', () {
    const md = '| a | b |\n|:---|---:|\n| x \\| y | z |\n';
    final s = MarkdownTableImporter.import(md).chapter.segments;
    expect(s.map((e) => e.source), ['a', 'x | y']);
    expect(s[1].target, 'z');
    expect(s[1].remark, '');
  });

  test('non-table lines and <br> produce warnings', () {
    const md = '# Heading\n\n| a | b<br>c | r1<br/>r2 |\n';
    final r = MarkdownTableImporter.import(md);
    expect(r.warnings, hasLength(2));
    expect(r.chapter.segments.single.target, 'b c');
    expect(r.chapter.segments.single.remark, 'r1\nr2');
  });

  test('extra cells go to remark', () {
    final r = MarkdownTableImporter.import('| a | b | c | d |\n');
    expect(r.chapter.segments.single.remark, 'c\nd');
    expect(r.warnings, hasLength(1));
  });

  test('blank rows are kept as break rows', () {
    const md = '| T | C | |\n| - | - | - |\n| a | b | |\n| | | |\n| | | |\n| c | d | |\n';
    final s = MarkdownTableImporter.import(md).chapter.segments;
    expect(s.map((e) => e.source), ['T', 'a', '', '', 'c']);
  });

  group('quote artifact repair (real samples from 11.md)', () {
    test('closing quote on next row', () {
      const md = '| When I lay down. | "Amikor ledőltem. |\n'
          '| " | |\n'
          '| Next. | Következő. | |\n';
      final r = MarkdownTableImporter.import(md);
      final s = r.chapter.segments;
      expect(s.map((e) => e.target), ['Amikor ledőltem.', 'Következő.']);
      expect(r.warnings.single, contains('line 2'));
    });

    test('closing quote after a blank one-cell row', () {
      const md = '| The false Thecla. | "Akkor hát eljött. |\n'
          '| |\n'
          '| " | |\n';
      final r = MarkdownTableImporter.import(md);
      expect(r.chapter.segments.single.target, 'Akkor hát eljött.');
      expect(r.warnings.single, contains('line 2, 3'));
    });

    test('balanced quotes and quotes without closing row are left alone', () {
      const md = '| a | "quoted" text |\n| b | "open |\n| c | d |\n';
      final s = MarkdownTableImporter.import(md).chapter.segments;
      expect(s.map((e) => e.target), ['"quoted" text', '"open', 'd']);
    });
  });

  test('trailing <br> is removed', () {
    final r = MarkdownTableImporter.import('| a | igazzá teszi.<br> | |\n');
    expect(r.chapter.segments.single.target, 'igazzá teszi.');
  });

  test('natural sort', () {
    final names = ['10.md', '2.md', '1.md', '22.md', '3.md'];
    names.sort(naturalCompare);
    expect(names, ['1.md', '2.md', '3.md', '10.md', '22.md']);
  });
}

