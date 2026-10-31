import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ford/src/editing/chapter_editor.dart';
import 'package:ford/src/folders/folder_ops.dart';
import 'package:ford/src/folders/folder_tree.dart';
import 'package:ford/src/model/chapter.dart';
import 'package:ford/src/model/chapter_format.dart';
import 'package:ford/src/model/segment.dart';
import 'package:ford/src/settings/app_settings.dart';
import 'package:ford/src/ui/chapter_screen.dart';
import 'package:ford/src/ui/chapter_view.dart';
import 'package:ford/src/ui/search_screen.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

Chapter _chapter(String prefix, int rows) => Chapter([
  Segment(id: '${prefix}t', source: '$prefix title'),
  for (var i = 1; i <= rows; i++)
    Segment(id: '$prefix$i', source: '$prefix$i src', target: '$prefix$i tgt'),
]);

List<String> _ids(Chapter chapter) =>
    chapter.segments.map((s) => s.id).toList();

void main() {
  // The screen test below really reads and writes files, which never finishes
  // under the default binding's fake clock.
  LiveTestWidgetsFlutterBinding.ensureInitialized().framePolicy =
      LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  group('Chapter.insertRows', () {
    test('rows keep their IDs and text', () {
      final next = _chapter('a', 1).insertRows(1, [
        Segment(id: 'x', source: 's', target: 't', remark: 'r'),
      ]);

      expect(_ids(next), ['at', 'x', 'a1']);
      expect(next.segments[1].remark, 'r');
    });

    test('an ID already in the chapter is replaced', () {
      final next = _chapter(
        'a',
        1,
      ).insertRows(2, [Segment(id: 'a1', source: 'moved')]);

      expect(next.ids, hasLength(3));
      expect(next.segments[2].source, 'moved');
      expect(next.segments[2].id, isNot('a1'));
    });
  });

  group('reordering', () {
    List<String> order(Chapter chapter) => _ids(chapter);

    test('blocks move past one neighbour and stop at the edge', () {
      final chapter = _chapter('a', 5);
      expect(order(chapter.moveRowsUp({'a2', 'a3', 'a5'})), [
        'at',
        'a2',
        'a3',
        'a1',
        'a5',
        'a4',
      ]);
      expect(order(chapter.moveRowsDown({'a1', 'a2', 'a5'})), [
        'at',
        'a3',
        'a1',
        'a2',
        'a4',
        'a5',
      ]);
      expect(order(chapter.moveRowsUp({'at', 'a1'})), order(chapter));
      expect(order(chapter.moveRowsDown({'a5'})), order(chapter));
    });

    test('a row can move above the title and become it', () {
      final next = _chapter('a', 2).moveRowsUp({'a1'});
      expect(next.title, 'a1 src');
    });

    test('rows come together after the chosen row, or at the very top', () {
      final chapter = _chapter('a', 5);
      expect(order(chapter.moveRowsAfter({'a1', 'a3'}, 'a4')), [
        'at',
        'a2',
        'a4',
        'a1',
        'a3',
        'a5',
      ]);
      expect(order(chapter.moveRowsAfter({'a3', 'a5'}, null)), [
        'a3',
        'a5',
        'at',
        'a1',
        'a2',
        'a4',
      ]);
    });

    test('the editor keeps the selection, and undo reverses each step', () {
      final editor = ChapterEditor(_chapter('a', 3));
      editor.startSelecting('a3');
      expect(editor.canMoveSelectedDown, isFalse);

      editor.moveSelectedUp();
      editor.moveSelectedUp();
      expect(_ids(editor.chapter), ['at', 'a3', 'a1', 'a2']);
      expect(editor.isSelected('a3'), isTrue);

      editor.undo();
      expect(_ids(editor.chapter), ['at', 'a1', 'a3', 'a2']);
      editor.undo();
      expect(_ids(editor.chapter), ['at', 'a1', 'a2', 'a3']);
    });

    test('nothing to do adds no undo step', () {
      final editor = ChapterEditor(_chapter('a', 2));
      editor.startSelecting('at');
      editor.moveSelectedUp();
      editor.moveSelectedAfter(null);
      expect(editor.canUndo, isFalse);

      editor.toggleSelected('a1');
      editor.toggleSelected('a2');
      editor.moveSelectedAfter(null);
      expect(_ids(editor.chapter), ['at', 'a1', 'a2']);
      expect(editor.canUndo, isFalse);
    });
  });

  group('selecting rows', () {
    late ChapterEditor editor;

    setUp(() => editor = ChapterEditor(_chapter('a', 5)));

    test('the title row can be selected', () {
      editor.startSelecting('at');
      editor.toggleSelected('a2');
      expect(editor.selectedRows.map((s) => s.id), ['at', 'a2']);
    });

    test('removing the title row makes the next row the title', () {
      editor.startSelecting('at');
      editor.removeSelectedAfterMove();
      expect(editor.chapter.title, 'a1 src');
    });

    test('every row can go', () {
      editor.startSelecting('at');
      editor.selectRangeTo('a5');
      editor.removeSelectedAfterMove();
      expect(editor.chapter.isEmpty, isTrue);
    });

    test('starting closes the active cell', () {
      editor.activate('a1', Field.source);
      editor.startSelecting('a2');
      expect(editor.active, isNull);
    });

    test('rows come out in chapter order', () {
      editor.startSelecting('a3');
      editor.toggleSelected('a1');
      expect(editor.selectedRows.map((s) => s.id), ['a1', 'a3']);
    });

    test('deselecting the last row ends selecting', () {
      editor.startSelecting('a3');
      editor.toggleSelected('a3');
      expect(editor.isSelecting, isFalse);
    });

    test('a range goes either way', () {
      editor.startSelecting('a2');
      editor.selectRangeTo('a4');
      expect(editor.selectedRows.map((s) => s.id), ['a2', 'a3', 'a4']);

      editor.clearSelection();
      editor.startSelecting('a2');
      editor.selectRangeTo('at');
      expect(editor.selectedRows.map((s) => s.id), ['at', 'a1', 'a2']);
    });

    test('undo drops rows that no longer exist from the selection', () {
      editor.insertBlank(1);
      final blank = editor.chapter.segments[1].id;
      editor.startSelecting(blank);
      editor.toggleSelected('a1');

      editor.undo();

      expect(editor.selectedRows.map((s) => s.id), ['a1']);
    });

    test('removing moved rows ends the undo history', () {
      editor.delete('a5');
      editor.startSelecting('a1');
      editor.selectRangeTo('a2');

      editor.removeSelectedAfterMove();

      expect(_ids(editor.chapter), ['at', 'a3', 'a4']);
      expect(editor.isSelecting, isFalse);
      expect(editor.canUndo, isFalse);
      expect(editor.canRedo, isFalse);
    });
  });

  group('files', () {
    late Directory dir;
    late AppSettings settings;

    setUp(() async {
      dir = Directory.systemTemp.createTempSync('ford_move_');
      SharedPreferences.setMockInitialValues({});
      settings = await AppSettings.load();
    });
    tearDown(() => dir.deleteSync(recursive: true));

    File write(String name, Chapter chapter) =>
        File(p.join(dir.path, name))
          ..writeAsStringSync(ChapterFormat.serialize(chapter));

    Chapter read(File file) =>
        ChapterFormat.parse(file.readAsStringSync()).chapter;

    group('FolderOps.insertRows', () {
      final rows = [
        Segment(id: 'x', source: 'x'),
        Segment(id: 'y', source: 'y'),
      ];

      test('goes after the given row', () async {
        final file = write('01.txt', _chapter('b', 2));
        await FolderOps.insertRows(file, rows, afterRowId: 'bt');
        expect(_ids(read(file)), ['bt', 'x', 'y', 'b1', 'b2']);
      });

      test('goes before the title without a row', () async {
        final file = write('01.txt', _chapter('b', 1));
        await FolderOps.insertRows(file, rows);
        expect(_ids(read(file)), ['x', 'y', 'bt', 'b1']);
      });

      test('goes to the end if the row has gone', () async {
        final file = write('01.txt', _chapter('c', 1));
        await FolderOps.insertRows(file, rows, afterRowId: 'gone');
        expect(_ids(read(file)), ['ct', 'c1', 'x', 'y']);
      });

      test('an empty chapter gets a blank title row first', () async {
        final file = write('01.txt', Chapter([]));
        await FolderOps.insertRows(file, rows);

        final chapter = read(file);
        expect(chapter.length, 3);
        expect(chapter.title, isNull);
        expect(chapter.segments[1].source, 'x');
      });

      test('a moved title becomes the title of an empty chapter', () async {
        final file = write('01.txt', Chapter([]));
        await FolderOps.insertRows(file, rows, firstIsTitle: true);

        expect(_ids(read(file)), ['x', 'y']);
      });

      test('a file that can\'t be read fails', () async {
        final missing = File(p.join(dir.path, 'missing.txt'));
        await expectLater(
          FolderOps.insertRows(missing, rows),
          throwsA(isA<FileSystemException>()),
        );
        expect(missing.existsSync(), isFalse);
      });
    });

    group('the whole move', () {
      late File from;
      late File to;

      Future<void> settle(WidgetTester tester, [Widget? widget]) async {
        if (widget != null) await tester.pumpWidget(widget);
        for (var i = 0; i < 8; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 100));
          await tester.pump();
        }
      }

      Future<void> tap(WidgetTester tester, Finder finder) async {
        await tester.tap(finder);
        await settle(tester);
      }

      /// Selects a2 and either a3 or, with [withTitle], the title row.
      Future<void> startMoving(
        WidgetTester tester, {
        String folder = '',
        bool withTitle = false,
      }) async {
        Directory(p.join(dir.path, folder)).createSync(recursive: true);
        from = write(p.join(folder, '01.txt'), _chapter('a', 4));
        to = write(p.join(folder, '02.txt'), _chapter('b', 2));
        await settle(
          tester,
          MaterialApp(
            home: ChapterScreen(
              search: SearchSession(),
              entry: ChapterEntry(file: from, title: 'a title'),
              rootPath: dir.path,
              settings: settings,
            ),
          ),
        );
        await tester.longPress(find.text('a2 src'));
        await settle(tester);
        await tap(tester, find.text('Select rows'));
        expect(find.text('1 selected'), findsOneWidget);
        // While selecting, the row itself takes the gesture, not its text.
        await tester.tap(
          withTitle
              ? find.descendant(
                  of: find.byType(RowTile),
                  matching: find.text('a title'),
                )
              : find.text('a3 src'),
          warnIfMissed: false,
        );
        await settle(tester);
        expect(find.text('2 selected'), findsOneWidget);
        await tap(tester, find.byTooltip('Move to another chapter'));
      }

      testWidgets('moves the rows between the two files', (tester) async {
        await startMoving(tester);
        // The current chapter is shown, but can't be chosen.
        await tap(tester, find.text('a title'));
        expect(find.text('Move 2 rows to'), findsOneWidget);

        await tap(tester, find.text('b title'));
        await tap(tester, find.text('b1 src'));
        expect(find.textContaining('after "b1 src"'), findsOneWidget);
        await tap(tester, find.text('Move'));
        await settle(tester);

        expect(_ids(read(to)), ['bt', 'b1', 'a2', 'a3', 'b2']);
        expect(read(to).segments[2].target, 'a2 tgt');
        expect(_ids(read(from)), ['at', 'a1', 'a4']);
        expect(find.text('a2 src'), findsNothing);
        expect(find.byType(RowTile), findsNWidgets(3));
        expect(find.textContaining('Moved 2 rows'), findsOneWidget);
        final undo = tester.widget<IconButton>(
          find.widgetWithIcon(IconButton, Icons.undo),
        );
        expect(undo.onPressed, isNull);
      });

      testWidgets('the title row moves, and the confirmation says so', (
        tester,
      ) async {
        await startMoving(tester, withTitle: true);
        await tap(tester, find.text('b title'));
        await tap(tester, find.text('b1 src'));
        expect(
          find.textContaining('"a1 src" becomes its title'),
          findsOneWidget,
        );
        await tap(tester, find.text('Move'));
        await settle(tester);

        expect(_ids(read(to)), ['bt', 'b1', 'at', 'a2', 'b2']);
        expect(_ids(read(from)), ['a1', 'a3', 'a4']);
        expect(read(from).title, 'a1 src');
      });

      testWidgets('moving the first file\'s title warns about the folder', (
        tester,
      ) async {
        await startMoving(tester, folder: 'part', withTitle: true);
        await tap(tester, find.text('b title'));
        await tap(tester, find.text('At the end'));

        expect(find.text('This renames a folder'), findsOneWidget);
        expect(
          find.textContaining('"a title" would show as "a1 src"'),
          findsOneWidget,
        );

        await tap(tester, find.text('Cancel'));
        expect(_ids(read(from)), ['at', 'a1', 'a2', 'a3', 'a4']);
        expect(find.text('2 selected'), findsOneWidget);
      });

      testWidgets('at the start, rows go before the title and say so', (
        tester,
      ) async {
        await startMoving(tester);
        await tap(tester, find.text('b title'));
        await tap(tester, find.text('At the start'));
        expect(find.textContaining('before the title'), findsOneWidget);
        expect(
          find.textContaining('"a2 src" becomes that chapter\'s title'),
          findsOneWidget,
        );
        await tap(tester, find.text('Move'));
        await settle(tester);

        expect(_ids(read(to)), ['a2', 'a3', 'bt', 'b1', 'b2']);
        expect(read(to).title, 'a2 src');
        expect(_ids(read(from)), ['at', 'a1', 'a4']);
      });

      testWidgets('at the start of a folder\'s first file, it warns', (
        tester,
      ) async {
        await startMoving(tester, folder: 'part');
        // This becomes the folder's first file.
        File(p.join(dir.path, 'part', '00.txt'))
            .writeAsStringSync(ChapterFormat.serialize(_chapter('c', 1)));
        await tester.pageBack();
        await settle(tester);
        await tap(tester, find.byTooltip('Move to another chapter'));
        // The folder's row shows this title too.
        await tap(tester, find.text('00.txt'));
        await tap(tester, find.text('At the start'));

        expect(find.text('This renames a folder'), findsOneWidget);
        expect(
          find.textContaining('"c title" would show as "a2 src"'),
          findsOneWidget,
        );
      });

      testWidgets('rows move within the chapter, and the file follows', (
        tester,
      ) async {
        await startMoving(tester);
        await tester.pageBack();
        await settle(tester);

        await tap(tester, find.byTooltip('Move within this chapter'));
        expect(find.text('a2 src'), findsNothing);
        await tap(tester, find.text('a4 src'));
        expect(find.text('2 selected'), findsOneWidget);

        await tap(tester, find.byTooltip('Move within this chapter'));
        await tap(tester, find.text('At the start'));
        await tester.pump(const Duration(seconds: 2));
        await Future<void>.delayed(const Duration(milliseconds: 1500));
        await settle(tester);

        expect(_ids(read(from)), ['a2', 'a3', 'at', 'a1', 'a4']);
      });

      testWidgets('cancelling leaves both files and the selection', (
        tester,
      ) async {
        await startMoving(tester);
        await tap(tester, find.text('b title'));
        await tap(tester, find.text('At the end'));
        await tap(tester, find.text('Cancel'));

        expect(_ids(read(to)), ['bt', 'b1', 'b2']);
        expect(_ids(read(from)), ['at', 'a1', 'a2', 'a3', 'a4']);
        expect(find.text('2 selected'), findsOneWidget);
      });
    });
  });
}
