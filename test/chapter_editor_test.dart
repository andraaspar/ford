import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ford/src/editing/chapter_autosaver.dart';
import 'package:ford/src/editing/chapter_editor.dart';
import 'package:ford/src/model/chapter.dart';
import 'package:ford/src/model/chapter_format.dart';
import 'package:ford/src/model/segment.dart';

Chapter _sample() => Chapter([
  Segment(id: 't', source: 'Title', target: 'Cím'),
  Segment(id: 'a', source: 'One two', target: 'Egy', remark: 'r'),
  Segment(id: 'b', source: 'Three', target: 'Három'),
]);

void main() {
  group('undo', () {
    var now = DateTime(2026);
    late ChapterEditor editor;

    setUp(() {
      now = DateTime(2026);
      editor = ChapterEditor(_sample(), clock: () => now);
    });

    test('typing in one cell without a pause is one step', () {
      editor.setText('a', Field.target, 'Egy k');
      now = now.add(const Duration(milliseconds: 500));
      editor.setText('a', Field.target, 'Egy ke');

      editor.undo();

      expect(editor.chapter.segments[1].target, 'Egy');
      expect(editor.canUndo, isFalse);
    });

    test('a pause or another cell starts a new step', () {
      editor.setText('a', Field.target, 'x');
      now = now.add(const Duration(seconds: 2));
      editor.setText('a', Field.target, 'xy');
      editor.setText('b', Field.target, 'z');

      editor.undo();
      expect(editor.chapter.segments[2].target, 'Három');
      editor.undo();
      expect(editor.chapter.segments[1].target, 'x');
      editor.undo();
      expect(editor.chapter.segments[1].target, 'Egy');
    });

    test('redo restores, and a new edit drops the redo history', () {
      editor.setText('a', Field.target, 'x');
      editor.undo();
      editor.redo();
      expect(editor.chapter.segments[1].target, 'x');

      editor.undo();
      editor.setText('b', Field.target, 'y');
      expect(editor.canRedo, isFalse);
    });

    test('row operations undo as one step each', () {
      editor.activate('a', Field.source, offset: 3);
      editor.splitAtCaret();
      expect(editor.chapter.length, 4);

      editor.undo();

      expect(editor.chapter.segments, _sample().segments);
    });

    test('undo moves an active cell to the restored text', () {
      editor.activate('a', Field.target, offset: 3);
      editor.setText('a', Field.target, 'Egy kettő');
      editor.activate('b', Field.source);

      editor.undo();

      expect(editor.active?.rowId, 'a');
      expect(editor.active?.field, Field.target);
      expect(editor.active?.offset, 3);
    });

    test('undo leaves editing closed if it was closed', () {
      editor.setText('a', Field.target, 'x');
      editor.undo();
      expect(editor.active, isNull);
    });
  });

  group('row operations', () {
    late ChapterEditor editor;

    setUp(() => editor = ChapterEditor(_sample()));

    test('split moves the caret to the start of the new row', () {
      editor.activate('a', Field.source, offset: 3);
      editor.splitAtCaret();

      final created = editor.chapter.segments[2];
      expect(editor.chapter.segments[1].source, 'One');
      expect(created.source, 'two');
      expect(editor.active?.rowId, created.id);
      expect(editor.active?.field, Field.source);
      expect(editor.active?.offset, 0);
    });

    test('a remark can\'t be split', () {
      editor.activate('a', Field.remark);
      editor.splitAtCaret();
      expect(editor.chapter.length, 3);
    });

    test('deleting the active row closes it; the title row stays', () {
      editor.activate('a', Field.source);
      editor.delete('a');
      expect(editor.active, isNull);
      expect(editor.chapter.indexOfId('a'), -1);

      editor.delete('t');
      expect(editor.chapter.indexOfId('t'), 0);
    });

    test('joining into the active row keeps it active', () {
      editor.activate('b', Field.target);
      editor.joinWithNext('a');
      expect(editor.active?.rowId, 'a');
      expect(editor.active?.offset, 'Egy Három'.length);
    });
  });

  group('firstChange', () {
    test('finds the field and the place in the text', () {
      final after = _sample().updateSegment(
        1,
        _sample().segments[1].copyWith(target: 'Egyik'),
      );
      final change = firstChange(_sample(), after)!;
      expect(change.rowId, 'a');
      expect(change.field, Field.target);
      expect(change.offset, 3);
    });

    test('has no field when rows were added or removed', () {
      expect(firstChange(_sample(), _sample().delete(2))?.field, isNull);
      expect(firstChange(_sample(), _sample().delete(1))?.rowId, 'b');
      expect(firstChange(_sample(), _sample()), isNull);
    });
  });

  group('ChapterAutosaver', () {
    late Directory dir;
    late File file;
    late ChapterEditor editor;
    late ChapterAutosaver saver;

    setUp(() {
      dir = Directory.systemTemp.createTempSync('ford_save_');
      file = File('${dir.path}/01.txt')..writeAsStringSync('original');
      editor = ChapterEditor(_sample());
      saver = ChapterAutosaver(
        editor,
        file,
        delay: const Duration(milliseconds: 20),
      );
    });
    tearDown(() {
      saver.dispose();
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    });

    test('leaves the file alone until something is edited', () async {
      editor.activate('a', Field.source);
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(file.readAsStringSync(), 'original');
      expect(saver.isUpToDate, isTrue);
    });

    test('saves after the delay, leaving no temp file behind', () async {
      editor.setText('a', Field.target, 'Egyik');
      expect(saver.isUpToDate, isFalse);

      await Future<void>.delayed(const Duration(milliseconds: 80));

      final saved = ChapterFormat.parse(file.readAsStringSync());
      expect(saved.chapter.segments[1].target, 'Egyik');
      expect(saver.isUpToDate, isTrue);
      expect(dir.listSync().map((e) => e.path), [file.path]);
    });

    test('flush saves at once, including edits made meanwhile', () async {
      editor.setText('a', Field.target, 'first');
      final flushing = saver.flush();
      editor.setText('a', Field.target, 'second');
      await flushing;

      final saved = ChapterFormat.parse(file.readAsStringSync());
      expect(saved.chapter.segments[1].target, 'second');
    });

    test('reports a failed save and recovers on retry', () async {
      final path = dir.path;
      dir.deleteSync(recursive: true);
      editor.setText('a', Field.target, 'x');
      await saver.flush();
      expect(saver.error, isNotNull);
      expect(saver.isUpToDate, isFalse);

      Directory(path).createSync();
      await saver.flush();
      expect(saver.error, isNull);
      expect(saver.isUpToDate, isTrue);
    });
  });
}
