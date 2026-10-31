import 'package:ford/src/model/chapter.dart';
import 'package:ford/src/model/segment.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Chapter sample() => Chapter([
        Segment(id: 't', source: 'Title', target: 'Cím'),
        Segment(id: 'a', source: 'One two', target: 'Egy kettő', remark: 'r1'),
        Segment(id: 'b', source: 'Three', target: 'Három', remark: 'r2'),
      ]);

  group('split', () {
    test('source side: tail goes to new row, other side empty', () {
      final ch = sample().split(1, Side.source, 3);
      expect(ch.length, 4);
      expect(ch.segments[1], Segment(id: 'a', source: 'One', target: 'Egy kettő', remark: 'r1'));
      expect(ch.segments[2].source, 'two');
      expect(ch.segments[2].target, '');
      expect(ch.segments[2].remark, '');
      expect(ch.segments[3].id, 'b');
      expect(ch.ids.length, 4);
    });

    test('target side', () {
      final ch = sample().split(1, Side.target, 4);
      expect(ch.segments[1].target, 'Egy');
      expect(ch.segments[1].source, 'One two');
      expect(ch.segments[2].target, 'kettő');
      expect(ch.segments[2].source, '');
    });

    test('offset at end creates empty new row; offset is clamped', () {
      final ch = sample().split(2, Side.source, 999);
      expect(ch.segments[2].source, 'Three');
      expect(ch.segments[3].source, '');
    });
  });

  group('join', () {
    test('joins both sides with a space, remarks with newline', () {
      final ch = sample().joinWithNext(1);
      expect(ch.length, 2);
      expect(
        ch.segments[1],
        Segment(id: 'a', source: 'One two Three', target: 'Egy kettő Három', remark: 'r1\nr2'),
      );
    });

    test('empty parts add no stray separators', () {
      final ch = Chapter([
        Segment(id: 'a', source: 'X', target: ''),
        Segment(id: 'b', source: '', target: 'Y'),
      ]).joinWithNext(0);
      expect(ch.segments.single, Segment(id: 'a', source: 'X', target: 'Y'));
    });

    test('split then join restores the text', () {
      final orig = sample();
      final back = orig.split(1, Side.source, 3).joinWithNext(1);
      expect(back.segments, orig.segments);
    });

    test('joining the last row throws', () {
      expect(() => sample().joinWithNext(2), throwsRangeError);
    });
  });

  test('insert and delete', () {
    final ch = sample().insertEmpty(1);
    expect(ch.length, 4);
    expect(ch.segments[1].source, '');
    expect(ch.delete(1).segments, sample().segments);
  });

  test('title', () {
    expect(sample().title, 'Title');
    expect(Chapter([Segment(id: 'x', target: 'Cím')]).title, 'Cím');
    expect(Chapter([]).title, isNull);
  });
}

