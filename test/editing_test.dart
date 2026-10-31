import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ford/src/book/book_folder.dart';
import 'package:ford/src/editing/chapter_editor.dart';
import 'package:ford/src/model/chapter.dart';
import 'package:ford/src/model/chapter_format.dart';
import 'package:ford/src/model/segment.dart';
import 'package:ford/src/settings/app_settings.dart';
import 'package:ford/src/ui/chapter_screen.dart';
import 'package:ford/src/ui/chapter_view.dart';
import 'package:shared_preferences/shared_preferences.dart';

Widget _app(ChapterEditor editor, {String? startAt}) => MaterialApp(
  home: Scaffold(
    body: ChapterView(
      editor: editor,
      initialPosition: startAt == null ? null : ReadingPosition(startAt, 0),
    ),
  ),
);

Chapter _longChapter() => Chapter([
  for (var i = 0; i < 200; i++)
    Segment(id: 'row$i', source: 'source $i', target: 'target $i'),
]);

ChapterEditor _editor(Chapter chapter, WidgetTester tester) {
  final editor = ChapterEditor(chapter);
  addTearDown(editor.dispose);
  return editor;
}

void main() {
  group('editing a cell', () {
    testWidgets('tapping opens a field without changing the row height', (
      tester,
    ) async {
      final editor = _editor(_longChapter(), tester);
      await tester.pumpWidget(_app(editor));
      final row = find.byType(RowTile).at(3);
      final before = tester.getRect(row);

      await tester.tap(find.text('target 3'));
      await tester.pump();

      expect(find.byType(TextField), findsOneWidget);
      expect(tester.getRect(row), before);
      expect(editor.active?.rowId, 'row3');
      expect(editor.active?.field, Field.target);
      expect(tester.testTextInput.isVisible, isTrue);
    });

    testWidgets('the caret lands where the text was tapped', (tester) async {
      final editor = _editor(_longChapter(), tester);
      await tester.pumpWidget(_app(editor));

      final text = find.text('source 3');
      final tapAt = tester.getTopLeft(text) + const Offset(0.5, 2);
      await tester.tapAt(tapAt);
      await tester.pump();
      expect(editor.active?.offset, 0);

      await tester.tap(find.text('target 5'));
      await tester.pump();
      await tester.tapAt(
        tester.getTopRight(find.text('source 7')) - const Offset(0.5, -2),
      );
      await tester.pump();
      expect(editor.active?.offset, 'source 7'.length);
    });

    testWidgets('typing updates the row', (tester) async {
      final editor = _editor(
        Chapter([Segment(id: 'a', source: 'One')]),
        tester,
      );
      await tester.pumpWidget(_app(editor));

      await tester.tapAt(
        tester.getTopRight(find.byType(RowTile)) + const Offset(-20, 5),
      );
      await tester.pump();
      await tester.enterText(find.byType(TextField), 'Egy');
      await tester.pump();

      expect(editor.chapter.segments.single.target, 'Egy');
    });

    testWidgets('Enter splits at the caret and moves to the new row', (
      tester,
    ) async {
      final editor = _editor(
        Chapter([
          Segment(id: 't', source: 'T'),
          Segment(id: 'a', source: 'One two', target: 'Egy', remark: 'r'),
        ]),
        tester,
      );
      await tester.pumpWidget(_app(editor));
      editor.activate('a', Field.source, offset: 3);
      await tester.pump();
      await tester.pump();

      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      await tester.pump();

      expect(editor.chapter.length, 3);
      expect(editor.chapter.segments[1].source, 'One');
      expect(editor.chapter.segments[1].remark, 'r');
      expect(editor.chapter.segments[2].source, 'two');
      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.controller!.text, 'two');
      expect(field.controller!.selection.baseOffset, 0);
      expect(field.focusNode!.hasFocus, isTrue);
      expect(tester.testTextInput.isVisible, isTrue);
      await tester.pump(const Duration(seconds: 1));
      expect(tester.takeException(), isNull);
    });

    testWidgets('line breaks in pasted text become spaces', (tester) async {
      final editor = _editor(_longChapter(), tester);
      await tester.pumpWidget(_app(editor));
      editor.activate('row1', Field.source);
      await tester.pump();

      await tester.enterText(find.byType(TextField), 'one\ntwo\r\nthree');
      await tester.pump();

      expect(editor.chapter.segments[1].source, 'one two three');
    });

    testWidgets('a remark keeps its line breaks, and can be added', (
      tester,
    ) async {
      final editor = _editor(_longChapter(), tester);
      await tester.pumpWidget(_app(editor));

      await tester.longPress(find.text('source 2'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add remark'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'one\ntwo');
      await tester.pump();

      expect(editor.chapter.segments[2].remark, 'one\ntwo');
    });

    testWidgets('undo updates the open field', (tester) async {
      final editor = _editor(_longChapter(), tester);
      await tester.pumpWidget(_app(editor));
      editor.activate('row1', Field.source);
      await tester.pump();
      await tester.enterText(find.byType(TextField), 'changed');
      await tester.pump();

      editor.undo();
      await tester.pump();

      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.controller!.text, 'source 1');
    });

    testWidgets('a blank row opens on the tapped side and stays a row while '
        'it has text', (tester) async {
      final editor = _editor(
        Chapter([
          Segment(id: 't', source: 'T', target: 'C'),
          Segment(id: 'gap'),
          Segment(id: 'a', source: 'One'),
        ]),
        tester,
      );
      await tester.pumpWidget(_app(editor));

      final gap = find.byType(RowTile).at(1);
      await tester.tapAt(tester.getTopRight(gap) + const Offset(-20, 7));
      await tester.pump();
      expect(editor.active?.field, Field.target);
      expect(tester.getSize(gap).height, greaterThan(RowTile.breakHeight));

      await tester.enterText(find.byType(TextField), 'x');
      editor.deactivate();
      await tester.pump();
      expect(find.text('x'), findsOneWidget);
      expect(tester.getSize(gap).height, greaterThan(RowTile.breakHeight));

      editor.activate('gap', Field.target);
      await tester.pump();
      await tester.enterText(find.byType(TextField), '');
      editor.deactivate();
      await tester.pump();
      expect(tester.getSize(gap).height, RowTile.breakHeight);
    });
  });

  group('the view stays put', () {
    String topVisibleTarget(WidgetTester tester) {
      final texts = find
          .textContaining('target ')
          .evaluate()
          .map((e) => (e.widget as Text).data!)
          .where((text) => tester.getTopLeft(find.text(text)).dy >= 0)
          .toList();
      texts.sort(
        (a, b) => tester
            .getTopLeft(find.text(a))
            .dy
            .compareTo(tester.getTopLeft(find.text(b)).dy),
      );
      return texts.first;
    }

    // Each operation gets the number of the top fully visible row, which must
    // not move. The operations differ in whether they touch the list's center
    // row, so each is tried right after opening at that row and after scrolling
    // away from it in both directions.
    final operations = <String, void Function(ChapterEditor, int)>{
      'split below': (e, top) {
        e.activate('row${top + 3}', Field.source);
        e.splitAtCaret();
      },
      'split at the top row': (e, top) {
        e.activate('row$top', Field.source);
        e.splitAtCaret();
      },
      'insert below': (e, top) =>
          e.insertBlank(e.chapter.indexOfId('row${top + 3}') + 1),
      'delete below': (e, top) => e.delete('row${top + 3}'),
      'join below': (e, top) => e.joinWithNext('row${top + 3}'),
      'insert above': (e, top) =>
          e.insertBlank(e.chapter.indexOfId('row${top - 3}')),
      'delete above': (e, top) => e.delete('row${top - 3}'),
      'join above': (e, top) => e.joinWithNext('row${top - 3}'),
      'split below and undo': (e, top) {
        e.activate('row${top + 3}', Field.source);
        e.splitAtCaret();
        e.undo();
      },
      'delete below and undo': (e, top) {
        e.delete('row${top + 3}');
        e.undo();
      },
    };

    for (final scrolled in const [0.0, -150.0, 150.0]) {
      for (final MapEntry(key: name, value: operation) in operations.entries) {
        testWidgets('$name, scrolled by $scrolled', (tester) async {
          final editor = _editor(_longChapter(), tester);
          await tester.pumpWidget(_app(editor, startAt: 'row100'));
          await tester.pump();
          if (scrolled != 0) {
            await tester.drag(
              find.text('source 103'),
              Offset(0, scrolled),
              warnIfMissed: false,
            );
            await tester.pumpAndSettle();
          }
          // Whichever row is at the top now is the one that must not move.
          final tracked = topVisibleTarget(tester);
          final before = tester.getTopLeft(find.text(tracked)).dy;

          operation(editor, int.parse(tracked.split(' ').last));
          await tester.pump();
          await tester.pump();

          expect(tester.getTopLeft(find.text(tracked)).dy, before);
          expect(tester.takeException(), isNull);
        });
      }
    }

    testWidgets('when the top row is deleted the next one takes its place', (
      tester,
    ) async {
      final editor = _editor(_longChapter(), tester);
      await tester.pumpWidget(_app(editor, startAt: 'row100'));
      await tester.pump();
      await tester.drag(find.text('source 103'), const Offset(0, -150));
      await tester.pumpAndSettle();
      final top = tester.getTopLeft(find.text('target 104')).dy;
      expect(top, lessThan(0));

      editor.delete('row104');
      await tester.pump();
      await tester.pump();

      expect(tester.getTopLeft(find.text('target 105')).dy, top);
    });

    testWidgets('opening a cell after scrolling up doesn\'t move anything, and '
        'keeps growth below it', (tester) async {
      final editor = _editor(_longChapter(), tester);
      await tester.pumpWidget(_app(editor, startAt: 'row100'));
      await tester.pump();
      await tester.drag(find.text('source 103'), const Offset(0, 200));
      await tester.pumpAndSettle();

      final cell = find.text('source 100');
      final before = tester.getTopLeft(cell).dy;
      await tester.tap(find.text('target 101'));
      await tester.pump();
      await tester.pump();
      expect(tester.getTopLeft(cell).dy, before);

      final field = find.byType(TextField);
      final fieldTop = tester.getTopLeft(field).dy;
      await tester.enterText(field, 'long text ' * 40);
      await tester.pump();
      await tester.pump();
      expect(tester.getTopLeft(cell).dy, before);
      expect(tester.getTopLeft(field).dy, closeTo(fieldTop, 1));
    });

    testWidgets('undo brings a change far away into sight', (tester) async {
      final editor = _editor(_longChapter(), tester);
      await tester.pumpWidget(_app(editor, startAt: 'row100'));
      await tester.pump();
      editor.setText('row3', Field.source, 'changed');
      await tester.pump();
      expect(find.text('changed'), findsNothing);

      editor.undo();
      await tester.pump();
      await tester.pump();

      expect(find.text('source 3'), findsOneWidget);
    });

    testWidgets('the open cell survives being scrolled away from', (
      tester,
    ) async {
      final editor = _editor(_longChapter(), tester);
      await tester.pumpWidget(_app(editor));
      await tester.tap(find.text('source 2'));
      await tester.pump();
      await tester.pump();

      await tester.drag(find.text('source 5'), const Offset(0, -3000));
      await tester.pumpAndSettle();

      expect(editor.active?.rowId, 'row2');
      expect(tester.testTextInput.isVisible, isTrue);
    });
  });

  group('row menu', () {
    Future<ChapterEditor> open(WidgetTester tester, String text) async {
      final editor = _editor(_longChapter(), tester);
      await tester.pumpWidget(_app(editor));
      await tester.longPress(find.text(text));
      await tester.pumpAndSettle();
      return editor;
    }

    testWidgets('joining asks first', (tester) async {
      final editor = await open(tester, 'source 1');

      await tester.tap(find.text('Join with next row'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(editor.chapter.length, 200);

      await tester.longPress(find.text('source 1'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Join with next row'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Join'));
      await tester.pumpAndSettle();
      expect(editor.chapter.segments[1].source, 'source 1 source 2');
    });

    testWidgets('inserts blank rows and deletes', (tester) async {
      final editor = await open(tester, 'source 1');

      await tester.tap(find.text('Insert blank row below'));
      await tester.pumpAndSettle();
      expect(editor.chapter.segments[2].source, '');

      await tester.longPress(find.text('source 1'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete row'));
      await tester.pumpAndSettle();
      expect(find.text('source 1'), findsNothing);
    });

    testWidgets('the title row can\'t be deleted or have a row above it', (
      tester,
    ) async {
      await open(tester, 'source 0');

      for (final label in ['Delete row', 'Insert blank row above']) {
        final tile = tester.widget<ListTile>(
          find.ancestor(of: find.text(label), matching: find.byType(ListTile)),
        );
        expect(tile.enabled, isFalse);
      }
    });

    testWidgets('an empty chapter offers a first row', (tester) async {
      final editor = _editor(Chapter([]), tester);
      await tester.pumpWidget(_app(editor));

      await tester.tap(find.text('Add a row'));
      await tester.pump();
      await tester.pump();

      expect(editor.chapter.length, 1);
      expect(find.byType(TextField), findsOneWidget);
    });
  });

  group('ChapterScreen', () {
    late Directory dir;
    late File file;
    late AppSettings settings;

    setUp(() async {
      dir = Directory.systemTemp.createTempSync('ford_edit_');
      file = File('${dir.path}/01.txt');
      file.writeAsStringSync(
        '@ a1b2c\n< Title\n> Cím\n\n@ d3e4f\n< Body\n> Szöveg\n',
      );
      SharedPreferences.setMockInitialValues({});
      settings = await AppSettings.load();
    });
    tearDown(() => dir.deleteSync(recursive: true));

    // Files are really read and written, which can't finish in the fake async
    // zone.
    Future<void> settle(WidgetTester tester, [Widget? widget]) async {
      await tester.runAsync(() async {
        if (widget != null) await tester.pumpWidget(widget);
        for (var i = 0; i < 8; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 20));
          await tester.pump(const Duration(milliseconds: 100));
        }
      });
    }

    Widget screen() => MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => ChapterScreen(
                  entry: ChapterEntry(file: file, title: null),
                  settings: settings,
                ),
              ),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );

    Future<void> openChapter(WidgetTester tester) async {
      await settle(tester, screen());
      await tester.tap(find.text('open'));
      await settle(tester);
    }

    testWidgets('Back closes the cell first, then saves and leaves', (
      tester,
    ) async {
      await openChapter(tester);
      await tester.tap(find.text('Szöveg'));
      await tester.pump();
      await tester.pump();
      await tester.enterText(find.byType(TextField), 'Más');
      await tester.pump();

      await tester.pageBack();
      await settle(tester);
      expect(find.byType(TextField), findsNothing);
      expect(find.text('Más'), findsOneWidget);

      await tester.pageBack();
      await settle(tester);
      expect(find.text('open'), findsOneWidget);
      final saved = ChapterFormat.parse(file.readAsStringSync());
      expect(saved.chapter.segments[1].target, 'Más');
    });

    testWidgets('the title in the app bar follows the title row', (
      tester,
    ) async {
      await openChapter(tester);
      await tester.tap(
        find.descendant(
          of: find.byType(RowTile).first,
          matching: find.text('Title'),
        ),
      );
      await tester.pump();
      await tester.pump();
      await tester.enterText(find.byType(TextField), 'New');
      await tester.pump();

      expect(
        find.descendant(of: find.byType(AppBar), matching: find.text('New')),
        findsOneWidget,
      );
    });

    testWidgets('Ctrl+Z undoes across cells and rows, Ctrl+Y redoes', (
      tester,
    ) async {
      await openChapter(tester);
      await tester.tap(find.text('Szöveg'));
      await tester.pump();
      await tester.pump();
      await tester.enterText(find.byType(TextField), 'Más');
      await tester.pump();
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      await tester.pump();

      Future<void> press(LogicalKeyboardKey key) async {
        await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
        await tester.sendKeyEvent(key);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
        await tester.pump();
        await tester.pump();
      }

      expect(find.byType(RowTile), findsNWidgets(3));
      await press(LogicalKeyboardKey.keyZ);
      expect(find.byType(RowTile), findsNWidgets(2));
      await press(LogicalKeyboardKey.keyZ);
      expect(find.text('Szöveg'), findsOneWidget);
      await press(LogicalKeyboardKey.keyY);
      expect(find.text('Szöveg'), findsNothing);
    });

    testWidgets('Escape finishes editing', (tester) async {
      await openChapter(tester);
      await tester.tap(find.text('Szöveg'));
      await tester.pump();
      await tester.pump();

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();

      expect(find.byType(TextField), findsNothing);
    });

    testWidgets('asks before leaving edits that can\'t be saved', (
      tester,
    ) async {
      await openChapter(tester);
      await tester.tap(find.text('Szöveg'));
      await tester.pump();
      await tester.pump();
      await tester.enterText(find.byType(TextField), 'Más');
      await tester.pump();
      await tester.tap(find.byTooltip('Finish editing'));
      await tester.pump();
      // A folder in place of the temp file makes every save fail.
      Directory('${dir.path}/.01.txt.tmp').createSync();

      await tester.pageBack();
      await settle(tester);
      expect(find.text('Leave without saving?'), findsOneWidget);

      await tester.tap(find.text('Stay'));
      await settle(tester);
      expect(find.text('Más'), findsOneWidget);
      expect(find.byTooltip('Can\'t save this chapter'), findsOneWidget);

      await tester.pageBack();
      await settle(tester);
      await tester.tap(find.text('Discard edits'));
      await settle(tester);
      expect(find.text('open'), findsOneWidget);
    });
  });
}
