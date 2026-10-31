import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ford/src/book/book_folder.dart';
import 'package:ford/src/model/chapter.dart';
import 'package:ford/src/model/segment.dart';
import 'package:ford/src/settings/app_settings.dart';
import 'package:ford/src/ui/chapter_list_screen.dart';
import 'package:ford/src/ui/chapter_view.dart';
import 'package:ford/src/ui/folder_picker_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

Widget _app(Widget child) => MaterialApp(home: Scaffold(body: child));

Chapter _longChapter() => Chapter([
  for (var i = 0; i < 200; i++)
    Segment(id: 'row$i', source: 'source $i', target: 'target $i'),
]);

void main() {
  group('ChapterView', () {
    testWidgets('shows both sides, remarks and short break rows', (
      tester,
    ) async {
      await tester.pumpWidget(
        _app(
          ChapterView(
            chapter: Chapter([
              Segment(id: 'title', source: 'Title', target: 'Cím'),
              Segment(id: 'gap01'),
              Segment(id: 'row01', source: 'One', target: 'Egy', remark: 'Hm'),
            ]),
          ),
        ),
      );

      expect(find.text('Title'), findsOneWidget);
      expect(find.text('Cím'), findsOneWidget);
      expect(find.text('💬 Hm'), findsOneWidget);
      final gap = tester.getSize(find.byType(RowTile).at(1));
      expect(gap.height, RowTile.breakHeight);
    });

    testWidgets('tapping a remark collapses it to one line', (tester) async {
      await tester.pumpWidget(
        _app(
          ChapterView(
            chapter: Chapter([
              Segment(id: 'row01', source: 'One', remark: 'first\nsecond'),
            ]),
          ),
        ),
      );
      final remark = find.textContaining('first');
      final expanded = tester.getSize(remark).height;

      await tester.tap(remark);
      await tester.pump();

      expect(tester.getSize(remark).height, lessThan(expanded));
    });

    testWidgets('restores the saved row and reports new positions', (
      tester,
    ) async {
      ReadingPosition? reported;
      await tester.pumpWidget(
        _app(
          ChapterView(
            chapter: _longChapter(),
            initialPosition: const ReadingPosition('row100', 0),
            onPositionChanged: (p) => reported = p,
          ),
        ),
      );
      await tester.pump();

      expect(find.text('source 100'), findsOneWidget);
      expect(find.text('source 0'), findsNothing);
      expect(reported?.rowId, 'row100');

      await tester.drag(find.text('source 103'), const Offset(0, -150));
      await tester.pumpAndSettle();

      expect(reported?.rowId, isNot('row100'));
    });

    testWidgets('starts at the top when the saved row no longer exists', (
      tester,
    ) async {
      await tester.pumpWidget(
        _app(
          ChapterView(
            chapter: _longChapter(),
            initialPosition: const ReadingPosition('gone', -0.1),
          ),
        ),
      );
      expect(find.text('source 0'), findsOneWidget);
    });
  });

  group('FolderPickerScreen', () {
    late Directory dir;

    setUp(() => dir = Directory.systemTemp.createTempSync('ford_picker_'));
    tearDown(() => dir.deleteSync(recursive: true));

    Future<void> pumpPicker(WidgetTester tester) async {
      // The picker lists real folders, which never finishes in the test's fake
      // async zone, so it has to start inside runAsync.
      await tester.runAsync(() async {
        await tester.pumpWidget(
          MaterialApp(home: FolderPickerScreen(initialPath: dir.path)),
        );
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pump();
    }

    testWidgets('opens a folder that has no subfolders', (tester) async {
      File('${dir.path}/01.txt').writeAsStringSync('@ a1b2c\n< T\n>\n');

      await pumpPicker(tester);

      expect(find.text(dir.path), findsOneWidget);
      expect(find.text('1 chapter file here'), findsOneWidget);
    });

    testWidgets('lists subfolders in natural order', (tester) async {
      Directory('${dir.path}/10').createSync();
      Directory('${dir.path}/2').createSync();

      await pumpPicker(tester);

      final two = tester.getTopLeft(find.text('2'));
      final ten = tester.getTopLeft(find.text('10'));
      expect(two.dy, lessThan(ten.dy));
      expect(find.text('0 chapter files here'), findsOneWidget);
    });
  });

  group('ChapterListScreen', () {
    late Directory dir;
    late AppSettings settings;

    setUp(() async {
      dir = Directory.systemTemp.createTempSync('ford_list_');
      for (final n in ['01', '02']) {
        File('${dir.path}/$n.txt').writeAsStringSync(
          '@ a1b2c\n< Title $n\n> Cím $n\n\n@ d3e4f\n< Body $n\n> Szöveg $n\n',
        );
      }
      SharedPreferences.setMockInitialValues({});
      settings = await AppSettings.load();
    });
    tearDown(() => dir.deleteSync(recursive: true));

    // Files are really read here, which can't finish in the fake async zone.
    Future<void> settle(WidgetTester tester, [Widget? widget]) async {
      await tester.runAsync(() async {
        if (widget != null) await tester.pumpWidget(widget);
        for (var i = 0; i < 8; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 20));
          await tester.pump(const Duration(milliseconds: 100));
        }
      });
    }

    Widget list() => MaterialApp(
      home: ChapterListScreen(
        book: BookFolder(dir.path),
        settings: settings,
        onChangeBook: () {},
      ),
    );

    testWidgets('stays on the list when no chapter was read yet', (
      tester,
    ) async {
      await settle(tester, list());

      expect(find.text('Title 01'), findsOneWidget);
      expect(find.text('Body 01'), findsNothing);
    });

    testWidgets('reopens the last chapter, and back shows the list', (
      tester,
    ) async {
      await settings.setLastChapter(dir.path, '02.txt');

      await settle(tester, list());
      expect(find.text('Body 02'), findsOneWidget);

      await tester.pageBack();
      await settle(tester);

      expect(find.text('Body 02'), findsNothing);
      expect(find.text('01.txt'), findsOneWidget);
    });

    testWidgets('stays on the list when the last chapter is gone', (
      tester,
    ) async {
      await settings.setLastChapter(dir.path, '99.txt');

      await settle(tester, list());

      expect(find.text('Title 01'), findsOneWidget);
    });

    testWidgets('stays on the list when the last chapter is unreadable', (
      tester,
    ) async {
      File('${dir.path}/02.txt').writeAsBytesSync([0xFF, 0xFE, 0xFF]);
      await settings.setLastChapter(dir.path, '02.txt');

      await settle(tester, list());

      expect(find.text('Title 01'), findsOneWidget);
    });
  });

  testWidgets('ChapterView keeps the last row clear of the system bar', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(padding: EdgeInsets.only(bottom: 48)),
          child: Scaffold(
            body: ChapterView(
              chapter: _longChapter(),
              initialPosition: const ReadingPosition('row199', 0),
            ),
          ),
        ),
      ),
    );
    await tester.drag(find.text('source 199'), const Offset(0, -2000));
    await tester.pumpAndSettle();

    final viewportBottom = tester.getBottomLeft(find.byType(Scaffold)).dy;
    final lastRowBottom = tester.getBottomLeft(find.byType(RowTile).last).dy;
    expect(lastRowBottom, lessThanOrEqualTo(viewportBottom - 48));
  });

  group('BookFolder', () {
    late Directory dir;

    setUp(() => dir = Directory.systemTemp.createTempSync('ford_book_'));
    tearDown(() => dir.deleteSync(recursive: true));

    test('lists chapters in natural order, skipping other files', () async {
      for (final name in [
        '10.txt',
        '2.txt',
        '2.sync-conflict-20261031-120000-ABC.txt',
        '.hidden.txt',
        'notes.md',
      ]) {
        File('${dir.path}/$name').writeAsStringSync('@ a1b2c\n< T $name\n>\n');
      }

      final chapters = await BookFolder(dir.path).listChapters();

      expect(chapters.map((c) => c.fileName), ['2.txt', '10.txt']);
      expect(chapters.first.title, 'T 2.txt');
    });

    test('keeps an unreadable file in the list, with an error', () async {
      File('${dir.path}/01.txt').writeAsBytesSync([0xFF, 0xFE, 0xFF]);

      final chapters = await BookFolder(dir.path).listChapters();

      expect(chapters.single.error, isNotNull);
      expect(chapters.single.title, isNull);
    });
  });

  test('AppSettings keeps the reading position per chapter', () async {
    SharedPreferences.setMockInitialValues({});
    final settings = await AppSettings.load();

    await settings.setPosition('/b/01.txt', const ReadingPosition('x', -0.25));

    expect(settings.position('/b/01.txt')?.rowId, 'x');
    expect(settings.position('/b/01.txt')?.alignment, -0.25);
    expect(settings.position('/b/02.txt'), isNull);
  });
}
