import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ford/src/editing/chapter_editor.dart';
import 'package:ford/src/folders/folder_tree.dart';
import 'package:ford/src/model/chapter.dart';
import 'package:ford/src/model/segment.dart';
import 'package:ford/src/search/text_search.dart';
import 'package:ford/src/settings/app_settings.dart';
import 'package:ford/src/ui/chapter_screen.dart';
import 'package:ford/src/ui/chapter_view.dart';
import 'package:ford/src/ui/folder_tree_screen.dart';
import 'package:ford/src/ui/search_screen.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

List<int> _starts(String needle, String text, {bool matchCase = false}) =>
    SearchQuery(needle, matchCase: matchCase).startsIn(text).toList();

void main() {
  // The screens really read files, which never finishes under the default
  // binding's fake clock.
  LiveTestWidgetsFlutterBinding.ensureInitialized().framePolicy =
      LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  group('SearchQuery', () {
    test('accents count', () {
      expect(_starts('ház', 'a ház és a haz'), [2]);
      expect(_starts('haz', 'a ház és a haz'), [11]);
      expect(_starts('ő', 'õ ö ő'), [4]);
    });

    test('case counts only when asked to', () {
      expect(_starts('ÁLOM', 'Az álom'), [3]);
      expect(_starts('ÁLOM', 'Az álom', matchCase: true), isEmpty);
      expect(_starts('álom', 'Az álom', matchCase: true), [3]);
    });

    test('finds each match once, without overlaps', () {
      expect(_starts('aa', 'aaaaa'), [0, 2]);
    });

    test('empty text finds nothing, and spaces count', () {
      expect(_starts('', 'abc'), isEmpty);
      expect(_starts(' a', 'a a'), [1]);
    });

    test('offsets hold for characters with unusual lowercase forms', () {
      const text = 'İß𐐀 Target';
      final start = _starts('target', text).single;

      expect(text.substring(start, start + 6), 'Target');
    });

    test('the scope decides which parts of a row count', () {
      final entry = ChapterEntry(file: File('a.txt'), title: 'A');
      final chapter = Chapter([
        Segment(id: 'r1', source: 'x', target: 'x', remark: 'one\nx'),
      ]);
      List<Field> fields(SearchScope scope) => SearchQuery(
        'x',
        scope: scope,
      ).hitsIn(entry, chapter).map((hit) => hit.field).toList();

      expect(fields(SearchScope.all), Field.values);
      expect(fields(SearchScope.source), [Field.source]);
      expect(fields(SearchScope.target), [Field.target]);
      expect(fields(SearchScope.remarks), [Field.remark]);
    });
  });

  group('snippetOf', () {
    SearchHit hit(String text, int start, int end) => SearchHit(
      chapter: ChapterEntry(file: File('a.txt'), title: 'A'),
      rowId: 'r1',
      rowIndex: 0,
      field: Field.source,
      text: text,
      start: start,
      end: end,
    );

    String marked(Snippet s) => s.text.substring(s.start, s.end);

    test('short text stays whole', () {
      final snippet = snippetOf(hit('a match here', 2, 7));

      expect(snippet.text, 'a match here');
      expect(marked(snippet), 'match');
    });

    test('long text is cut around the match', () {
      final text = '${'a' * 100}match${'b' * 100}';
      final snippet = snippetOf(hit(text, 100, 105), context: 5);

      expect(snippet.text, '…aaaaamatchbbbbb…');
      expect(marked(snippet), 'match');
    });

    test('line breaks become spaces, and offsets hold', () {
      final snippet = snippetOf(hit('one\ntwo', 4, 7));

      expect(snippet.text, 'one two');
      expect(marked(snippet), 'two');
    });

    test('never cuts a surrogate pair in half', () {
      final snippet = snippetOf(hit('a𐐀match𐐀b', 3, 8), context: 1);

      expect(snippet.text, '…𐐀match𐐀…');
      expect(marked(snippet), 'match');
    });
  });

  group('ChapterEditor.showMark', () {
    ChapterEditor editor() => ChapterEditor(
      Chapter([
        Segment(id: 'r1', source: 'one'),
        Segment(id: 'r2', source: 'two'),
      ]),
    );

    test('reveals the row and closes the active cell', () {
      final ed = editor()..activate('r1', Field.source);

      ed.showMark(const TextMark('r2', Field.source, 0, 3));

      expect(ed.active, isNull);
      expect(ed.mark?.rowId, 'r2');
      expect(ed.takeReveal()?.index, 1);
    });

    test('ignores a row that is gone', () {
      final ed = editor()..showMark(const TextMark('xx', Field.source, 0, 3));

      expect(ed.mark, isNull);
      expect(ed.takeReveal(), isNull);
    });

    test('opening a cell, editing and undoing clear the mark', () {
      const mark = TextMark('r1', Field.source, 0, 3);
      final ed = editor()..showMark(mark);
      ed.activate('r1', Field.source);
      expect(ed.mark, isNull);

      ed
        ..setText('r1', Field.source, 'changed')
        ..showMark(mark)
        ..undo();
      expect(ed.mark, isNull);

      ed
        ..showMark(mark)
        ..insertBlank(0);
      expect(ed.mark, isNull);
    });
  });

  group('searching files', () {
    late Directory dir;
    late AppSettings settings;

    setUp(() async {
      dir = Directory.systemTemp.createTempSync('ford_search_');
      SharedPreferences.setMockInitialValues({});
      settings = await AppSettings.load();
    });
    tearDown(() => dir.deleteSync(recursive: true));

    String path(String relative) => p.join(dir.path, relative);

    void write(String relative, String content) {
      File(path(relative))
        ..createSync(recursive: true)
        ..writeAsStringSync(content);
    }

    void chapter(String relative, String title, [String body = 'Plain body']) {
      write(relative, '@ title\n< $title\n>\n\n@ row01\n< $body\n> Fordítás\n');
    }

    Future<void> settle(WidgetTester tester, [Widget? widget]) async {
      if (widget != null) await tester.pumpWidget(widget);
      for (var i = 0; i < 6; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
        await tester.pump();
      }
    }

    Future<void> tapAndSettle(WidgetTester tester, Finder finder) async {
      await tester.tap(finder);
      await settle(tester);
    }

    Future<void> type(WidgetTester tester, String text) async {
      await tester.enterText(find.byType(TextField), text);
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await settle(tester);
    }

    /// A result in the list, as opposed to the search field holding the same text.
    Finder result(String text) =>
        find.descendant(of: find.byType(ListTile), matching: find.text(text));

    Widget treeScreen() => MaterialApp(
      home: FolderTreeScreen(
        rootPath: dir.path,
        settings: settings,
        onChangeRoot: () {},
      ),
    );

    /// The part of a row's cell that's marked, or null if none is.
    String? markedIn(WidgetTester tester, String wholeText) {
      final text = tester.widget<Text>(find.text(wholeText));
      final span = text.textSpan;
      if (span is! TextSpan) return null;
      for (final child in span.children ?? const <InlineSpan>[]) {
        if (child is TextSpan && child.style?.backgroundColor != null) {
          return child.text;
        }
      }
      return null;
    }

    test('reads chapters in order, and reports unreadable ones', () async {
      chapter('01.txt', 'One', 'needle');
      File(path('02.txt')).writeAsBytesSync([0xff, 0xfe, 0xff]);
      chapter('03.txt', 'Three', 'needle');
      final root = await FolderTree.load(dir.path);

      final results = await searchChapters(
        root.allChapters,
        SearchQuery('needle'),
      );

      expect(results.searched, 3);
      expect(results.hits.map((hit) => hit.chapter.fileName), [
        '01.txt',
        '03.txt',
      ]);
      expect(results.unreadable.single.fileName, '02.txt');
    });

    test('an open chapter is searched as it stands, not as saved', () async {
      chapter('01.txt', 'One', 'on disk');
      final root = await FolderTree.load(dir.path);

      final results = await searchChapters(
        root.allChapters,
        SearchQuery('edited'),
        open: {
          path('01.txt'): Chapter([Segment(id: 'row01', source: 'edited')]),
        },
      );

      expect(results.hits.single.text, 'edited');
    });

    testWidgets('finds a match from the tree and opens it, highlighted', (
      tester,
    ) async {
      chapter('01/00.txt', 'The Part');
      chapter('01/01.txt', 'Chapter One', 'A needle in hay');
      chapter('02.txt', 'Other');

      await settle(tester, treeScreen());
      await tapAndSettle(tester, find.byTooltip('Search'));
      await type(tester, 'NEEDLE');

      expect(find.text('1 match in 1 of 3 chapters'), findsOneWidget);
      expect(
        find.text('The Part · Chapter One · Source'),
        findsOneWidget,
        reason: 'a result names its folder and chapter',
      );

      await tapAndSettle(tester, find.text('A needle in hay'));

      expect(find.byType(ChapterView), findsOneWidget);
      expect(markedIn(tester, 'A needle in hay'), 'needle');
      expect(settings.lastChapter(dir.path), p.join('01', '01.txt'));

      await tester.pageBack();
      await settle(tester);
      expect(
        find.text('Chapter One'),
        findsOneWidget,
        reason: 'the tree shows the chapter that was opened',
      );
    });

    testWidgets('match case and the scope narrow the results', (tester) async {
      write(
        '01.txt',
        '@ title\n< Title\n>\n\n@ row01\n< word\n> Word\n! WORD\n',
      );

      await settle(tester, treeScreen());
      await tapAndSettle(tester, find.byTooltip('Search'));
      await type(tester, 'word');
      expect(find.text('3 matches in 1 of 1 chapter'), findsOneWidget);

      await tapAndSettle(tester, find.text('Match case'));
      expect(find.text('1 match in 1 of 1 chapter'), findsOneWidget);
      expect(find.text('Title · Source'), findsOneWidget);

      await tapAndSettle(tester, find.text('Target'));
      expect(find.text('No matches in 1 chapter'), findsOneWidget);

      await tapAndSettle(tester, find.text('Match case'));
      await tapAndSettle(tester, find.text('Remarks'));
      expect(find.text('Title · Remark'), findsOneWidget);
    });

    testWidgets('search in a folder includes nested folders, not the rest', (
      tester,
    ) async {
      chapter('01/00.txt', 'The Part', 'needle');
      chapter('01/02/03.txt', 'Deep', 'needle');
      chapter('04/00.txt', 'Elsewhere', 'needle');

      await settle(tester, treeScreen());
      await tester.longPress(find.text('The Part'));
      await settle(tester);
      await tapAndSettle(tester, find.text('Search in this folder'));
      await type(tester, 'needle');

      expect(find.text('2 matches in 2 of 2 chapters'), findsOneWidget);
    });

    testWidgets('the target picker chooses what is searched', (tester) async {
      chapter('01.txt', 'One', 'needle');
      chapter('02.txt', 'Two', 'needle');

      await settle(tester, treeScreen());
      await tapAndSettle(tester, find.byTooltip('Search'));
      await type(tester, 'needle');
      expect(find.text('2 matches in 2 of 2 chapters'), findsOneWidget);

      await tapAndSettle(tester, find.text('Choose…'));
      await tapAndSettle(tester, find.text('Two'));
      await tapAndSettle(tester, find.text('Use these'));

      expect(find.text('Chosen: 1'), findsOneWidget);
      expect(find.text('1 match in 1 of 1 chapter'), findsOneWidget);
      expect(find.text('Two · Source'), findsOneWidget);
    });

    group('from a chapter', () {
      late SearchSession session;

      setUp(() => session = SearchSession());

      Widget chapterApp() => MaterialApp(
        home: ChapterScreen(
          entry: ChapterEntry(file: File(path('01.txt')), title: 'One'),
          rootPath: dir.path,
          settings: settings,
          search: session,
        ),
      );

      testWidgets('a match in this chapter scrolls to it and marks it', (
        tester,
      ) async {
        write(
          '01.txt',
          '@ title\n< One\n>\n\n'
              '${[for (var i = 0; i < 200; i++) '@ r$i\n< row $i\n> sor $i\n'].join('\n')}',
        );

        await settle(tester, chapterApp());
        expect(find.text('row 150'), findsNothing);

        await tapAndSettle(tester, find.byTooltip('Search'));
        await type(tester, 'row 150');
        await tapAndSettle(tester, result('row 150'));

        expect(markedIn(tester, 'row 150'), 'row 150');

        await tapAndSettle(tester, find.text('row 150'));
        expect(
          find.text('row 150'),
          findsNothing,
          reason: 'opening the cell turns the text into a field',
        );
      });

      testWidgets('finds edits that are not saved yet', (tester) async {
        chapter('01.txt', 'One');

        await settle(tester, chapterApp());
        await tapAndSettle(tester, find.text('Plain body'));
        await tester.enterText(find.byType(TextField), '​Fresh edit');
        await tapAndSettle(tester, find.byTooltip('Finish editing'));
        await tapAndSettle(tester, find.byTooltip('Search'));
        await type(tester, 'fresh');

        expect(find.text('Fresh edit'), findsOneWidget);
        await tester.pageBack();
        await settle(tester);
      });

      testWidgets('a match in another chapter leaves with it, saved first', (
        tester,
      ) async {
        chapter('01.txt', 'One');
        chapter('02.txt', 'Two', 'needle');
        SearchHit? popped;

        await settle(
          tester,
          MaterialApp(
            home: Builder(
              builder: (context) => TextButton(
                child: const Text('Open'),
                onPressed: () async {
                  popped = await Navigator.of(context).push<SearchHit>(
                    MaterialPageRoute(
                      builder: (_) => ChapterScreen(
                        entry: ChapterEntry(
                          file: File(path('01.txt')),
                          title: 'One',
                        ),
                        rootPath: dir.path,
                        settings: settings,
                        search: session,
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        );
        await tapAndSettle(tester, find.text('Open'));
        await tapAndSettle(tester, find.text('Plain body'));
        await tester.enterText(find.byType(TextField), '​Edited');
        await tapAndSettle(tester, find.byTooltip('Finish editing'));
        await tapAndSettle(tester, find.byTooltip('Search'));
        await tapAndSettle(tester, find.text('Root folder'));
        await type(tester, 'needle');
        await tapAndSettle(tester, result('needle'));

        expect(popped?.chapter.fileName, '02.txt');
        expect(File(path('01.txt')).readAsStringSync(), contains('< Edited'));
      });

      testWidgets('coming back finds the search as it was', (tester) async {
        chapter('01.txt', 'One', 'needle');

        await settle(tester, chapterApp());
        await tapAndSettle(tester, find.byTooltip('Search'));
        await type(tester, 'needle');
        await tapAndSettle(tester, result('needle'));
        await tapAndSettle(tester, find.byTooltip('Search'));

        expect(
          tester.widget<TextField>(find.byType(TextField)).controller?.text,
          'needle',
        );
        expect(find.text('1 match in 1 of 1 chapter'), findsOneWidget);
        expect(
          find.text('One · Source'),
          findsOneWidget,
          reason: 'results show again',
        );
        await tester.pageBack();
        await settle(tester);
      });
    });

    testWidgets('a match opened elsewhere keeps one chapter screen', (
      tester,
    ) async {
      chapter('01.txt', 'One', 'first');
      chapter('02.txt', 'Two', 'needle');
      await settings.setLastChapter(dir.path, '01.txt');

      await settle(tester, treeScreen());
      expect(find.text('first'), findsOneWidget);

      await tapAndSettle(tester, find.byTooltip('Search'));
      await tapAndSettle(tester, find.text('Root folder'));
      await type(tester, 'needle');
      await tapAndSettle(tester, result('needle'));
      await settle(tester);

      expect(markedIn(tester, 'needle'), 'needle');
      expect(settings.lastChapter(dir.path), '02.txt');

      await tester.pageBack();
      await settle(tester);
      expect(find.byType(ChapterView), findsNothing);
      expect(find.byType(FolderTreeScreen), findsOneWidget);
    });

    testWidgets('fits a narrow phone with the keyboard up', (tester) async {
      chapter('01/00.txt', 'A rather long name for a folder of chapters');
      tester.view
        ..physicalSize = const Size(320, 300)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await settle(tester, treeScreen());
      await tapAndSettle(tester, find.byTooltip('Search'));
      await type(tester, 'Plain');

      expect(tester.takeException(), isNull);
      expect(find.text('Plain body'), findsOneWidget);
    });
  });
}
