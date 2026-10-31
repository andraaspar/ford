import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ford/src/editing/chapter_autosaver.dart';
import 'package:ford/src/editing/chapter_editor.dart';
import 'package:ford/src/folders/folder_tree.dart';
import 'package:ford/src/folders/root_watch.dart';
import 'package:ford/src/model/chapter.dart';
import 'package:ford/src/model/chapter_format.dart';
import 'package:ford/src/model/segment.dart';
import 'package:ford/src/settings/app_settings.dart';
import 'package:ford/src/ui/chapter_screen.dart';
import 'package:ford/src/ui/chapter_view.dart';
import 'package:ford/src/ui/folder_tree_screen.dart';
import 'package:ford/src/ui/search_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

String _text(List<(String, String)> rows) => ChapterFormat.serialize(
  Chapter([for (final (id, target) in rows) Segment(id: id, target: target)]),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory dir;
  late File file;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('ford_sync_');
    file = File('${dir.path}/01.txt');
  });
  tearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  group('ChapterEditor.replaceFromDisk', () {
    late ChapterEditor editor;

    setUp(() {
      editor = ChapterEditor(
        Chapter([
          Segment(id: 'a', target: 'long text'),
          Segment(id: 'b', target: 'B'),
        ]),
      );
    });
    tearDown(() => editor.dispose());

    test('ends the undo history and clears the mark', () {
      editor.setText('b', Field.target, 'edited');
      editor.showMark(const TextMark('a', Field.target, 0, 1));
      editor.replaceFromDisk(Chapter([Segment(id: 'a', target: 'new')]));

      expect(editor.chapter.segments.single.target, 'new');
      expect(editor.canUndo, isFalse);
      expect(editor.mark, isNull);
    });

    test('an open cell stays open with its caret inside the new text', () {
      editor.activate('a', Field.target, offset: 8);
      editor.replaceFromDisk(Chapter([Segment(id: 'a', target: 'new')]));
      expect(editor.active?.rowId, 'a');
      expect(editor.active?.offset, 3);
    });

    test('an open cell closes if its row is gone, and selection follows', () {
      editor.activate('a', Field.target);
      editor.replaceFromDisk(Chapter([Segment(id: 'b')]));
      expect(editor.active, isNull);

      editor.startSelecting('b');
      editor.replaceFromDisk(Chapter([Segment(id: 'c')]));
      expect(editor.isSelecting, isFalse);
    });
  });

  group('ChapterAutosaver with changes on disk', () {
    final original = _text([('a', 'one'), ('b', 'two')]);
    final theirs = _text([('a', 'theirs'), ('b', 'two')]);
    late ChapterEditor editor;
    late ChapterAutosaver saver;

    setUp(() {
      file.writeAsStringSync(original);
      editor = ChapterEditor(ChapterFormat.parse(original).chapter);
      saver = ChapterAutosaver(
        editor,
        file,
        diskText: original,
        delay: const Duration(days: 1),
      );
    });
    tearDown(() {
      saver.dispose();
      editor.dispose();
    });

    String target() => editor.chapter.segments.first.target;

    test('its own saves aren\'t a change', () async {
      editor.setText('a', Field.target, 'mine');
      await saver.flush();
      await saver.checkDisk();

      expect(saver.conflict, isNull);
      expect(editor.canUndo, isTrue);
      expect(target(), 'mine');
    });

    test('without unsaved edits, it reloads quietly', () async {
      file.writeAsStringSync('$theirs\n\n@ x\n< stray\n< line\n');
      await saver.checkDisk();

      expect(saver.conflict, isNull);
      expect(target(), 'theirs');
      expect(saver.isUpToDate, isTrue);
      expect(saver.warnings, isNotEmpty);

      // Reloading isn't an edit, so it's not written back.
      await saver.flush();
      expect(file.readAsStringSync(), contains('stray'));
    });

    test(
      'with unsaved edits, it asks, and saving leaves the file alone',
      () async {
        editor.setText('a', Field.target, 'mine');
        file.writeAsStringSync(theirs);

        await saver.checkDisk();
        expect(saver.conflict?.text, theirs);

        await saver.flush();
        expect(file.readAsStringSync(), theirs);
        expect(target(), 'mine');
      },
    );

    test('a save finds a change no check has seen yet', () async {
      editor.setText('a', Field.target, 'mine');
      file.writeAsStringSync(theirs);

      await saver.flush();

      expect(saver.conflict?.text, theirs);
      expect(file.readAsStringSync(), theirs);
    });

    test('the same rows arriving from elsewhere need no decision', () async {
      editor.setText('a', Field.target, 'theirs');
      file.writeAsStringSync(theirs);

      await saver.flush();

      expect(saver.conflict, isNull);
      expect(saver.isUpToDate, isTrue);
      expect(editor.canUndo, isTrue);
    });

    test('keep mine overwrites the file, undo still works', () async {
      editor.setText('a', Field.target, 'mine');
      file.writeAsStringSync(theirs);
      await saver.checkDisk();

      await saver.keepMine();

      expect(saver.conflict, isNull);
      expect(saver.isUpToDate, isTrue);
      expect(file.readAsStringSync(), contains('mine'));
      expect(editor.canUndo, isTrue);
    });

    test('keep mine asks again if the file changed yet again', () async {
      editor.setText('a', Field.target, 'mine');
      file.writeAsStringSync(theirs);
      await saver.checkDisk();
      final newer = _text([('a', 'newer')]);
      file.writeAsStringSync(newer);

      await saver.keepMine();

      expect(saver.conflict?.text, newer);
      expect(file.readAsStringSync(), newer);
    });

    test('take theirs drops the edits', () async {
      editor.setText('a', Field.target, 'mine');
      file.writeAsStringSync(theirs);
      await saver.checkDisk();

      saver.takeTheirs();

      expect(saver.conflict, isNull);
      expect(saver.isUpToDate, isTrue);
      expect(target(), 'theirs');
      expect(editor.canUndo, isFalse);
      expect(file.readAsStringSync(), theirs);
    });

    test('a copy goes to a free name that sorts after the original', () async {
      File('${dir.path}/01_copy.txt').writeAsStringSync('taken');
      editor.setText('a', Field.target, 'mine');
      file.writeAsStringSync(theirs);
      await saver.checkDisk();

      final name = await saver.saveMineAsCopy();

      expect(name, '01_copy2.txt');
      final copy = File('${dir.path}/$name').readAsStringSync();
      expect(copy, contains('mine'));
      expect(File('${dir.path}/01_copy.txt').readAsStringSync(), 'taken');
      expect(file.readAsStringSync(), theirs);
      expect(target(), 'theirs');
      expect(saver.conflict, isNull);

      final tree = await FolderTree.load(dir.path);
      expect(tree.chapters.first.fileName, '01.txt');
    });

    test('a deleted file is a question even without edits', () async {
      file.deleteSync();
      await saver.checkDisk();
      expect(saver.conflict?.isDeleted, isTrue);

      await saver.flush();
      expect(file.existsSync(), isFalse);

      await saver.keepMine();
      expect(saver.conflict, isNull);
      expect(file.existsSync(), isTrue);
      expect(saver.isUpToDate, isTrue);
    });

    test('keep mine brings back a deleted folder too', () async {
      dir.deleteSync(recursive: true);
      await saver.checkDisk();
      await saver.keepMine();
      expect(file.existsSync(), isTrue);
      expect(saver.error, isNull);
    });

    test('a file that can\'t be read is never overwritten', () async {
      file.writeAsBytesSync([0xff, 0xfe, 0x00, 0xc3]);
      editor.setText('a', Field.target, 'mine');

      await saver.checkDisk();
      expect(saver.conflict, isNull);

      await saver.flush();
      expect(saver.error, isNotNull);
      expect(file.readAsBytesSync(), [0xff, 0xfe, 0x00, 0xc3]);
    });
  });

  group('RootWatch', () {
    RootWatch watch({bool system = false}) {
      final watch = RootWatch(
        dir.path,
        interval: const Duration(days: 1),
        useSystemEvents: system,
      );
      addTearDown(watch.dispose);
      return watch;
    }

    void write(String relative) {
      File('${dir.path}/$relative')
        ..createSync(recursive: true)
        ..writeAsStringSync(relative);
    }

    test(
      'lists conflict copies at any depth, but not in hidden folders',
      () async {
        write('01.txt');
        write('a/b/02.sync-conflict-20261031-120000-ABC.txt');
        write('.stversions/03.sync-conflict-20261031-120000-ABC.txt');
        final w = watch();
        await w.scan();
        expect(w.conflictFiles, [
          'a/b/02.sync-conflict-20261031-120000-ABC.txt',
        ]);

        var notified = 0;
        w.addListener(() => notified++);
        await w.scan();
        expect(notified, 0);

        File('${dir.path}/a/b/02.sync-conflict-20261031-120000-ABC.txt')
            .deleteSync();
        await w.scan();
        expect(notified, 1);
        expect(w.conflictFiles, isEmpty);
      },
    );

    test('reports chapters and folders changing, and nothing else', () async {
      write('01.txt');
      final w = watch();
      await w.scan();
      var changes = 0;
      final subscription = w.changes.listen((_) => changes++);
      addTearDown(subscription.cancel);
      Future<void> scanned() async {
        await w.scan();
        await Future<void>.delayed(Duration.zero);
      }

      await scanned();
      expect(changes, 0);

      write('.01.txt.tmp');
      write('notes.md');
      write('01.sync-conflict-20261031-120000-ABC.txt');
      await scanned();
      expect(changes, 0);

      write('02.txt');
      await scanned();
      expect(changes, 1);

      File('${dir.path}/01.txt').writeAsStringSync('longer than it was');
      await scanned();
      expect(changes, 2);

      Directory('${dir.path}/folder').createSync();
      await scanned();
      expect(changes, 3);
    });

    test('hears about changes from the system', () async {
      write('01.txt');
      final w = watch(system: true);
      await w.scan();
      // The system's watch starts listening a moment after being created.
      await Future<void>.delayed(const Duration(milliseconds: 300));

      final change = w.changes.first.timeout(const Duration(seconds: 10));
      write('a/02.txt');
      await change;
    });

    test('a root that can\'t be read is left for the next scan', () async {
      write('01.sync-conflict-20261031-120000-ABC.txt');
      final w = watch();
      await w.scan();
      dir.deleteSync(recursive: true);
      await w.scan();
      expect(w.conflictFiles, hasLength(1));
    });
  });

  group('on screen', () {
    late AppSettings settings;
    late RootWatch rootWatch;

    final rows = [for (var i = 0; i < 60; i++) ('row$i', 'target $i')];

    setUp(() async {
      file.writeAsStringSync(_text(rows));
      SharedPreferences.setMockInitialValues({});
      settings = await AppSettings.load();
    });

    // Files are really read and written, which can't finish in the fake async
    // zone.
    Future<void> settle(WidgetTester tester, [Widget? widget]) async {
      await tester.runAsync(() async {
        if (widget != null) await tester.pumpWidget(widget);
        for (var i = 0; i < 20; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 20));
          await tester.pump(const Duration(milliseconds: 100));
        }
      });
    }

    Future<void> scan(WidgetTester tester) async {
      await tester.runAsync(rootWatch.scan);
      await settle(tester);
    }

    Future<void> startWatching(WidgetTester tester) async {
      await tester.runAsync(() async {
        rootWatch = RootWatch(
          dir.path,
          interval: const Duration(days: 1),
          useSystemEvents: false,
        );
        await rootWatch.scan();
      });
      addTearDown(rootWatch.dispose);
    }

    /// The tree's first chapter, as seen by an open chapter screen.
    Future<void> openChapter(WidgetTester tester) async {
      await startWatching(tester);
      await settle(
        tester,
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => ChapterScreen(
                      search: SearchSession(),
                      entry: ChapterEntry(file: file, title: null),
                      rootPath: dir.path,
                      settings: settings,
                      watch: rootWatch,
                    ),
                  ),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await settle(tester);
    }

    String changed(String target) {
      return _text([
        for (final (id, text) in rows) (id, id == 'row5' ? target : text),
      ]);
    }

    testWidgets('a change on disk shows up without moving the rows', (
      tester,
    ) async {
      await openChapter(tester);
      await tester.drag(find.text('target 5'), const Offset(0, -100));
      await tester.pump();
      final row = find.text('target 8');
      final top = tester.getTopLeft(row).dy;

      // A new row above, and a change in one that's visible.
      final next = Chapter([
        Segment(id: 'new', target: 'added'),
        for (final (id, text) in rows)
          Segment(id: id, target: id == 'row9' ? 'from elsewhere' : text),
      ]);
      file.writeAsStringSync(ChapterFormat.serialize(next));
      await scan(tester);

      expect(find.text('from elsewhere'), findsOneWidget);
      expect(find.byType(AlertDialog), findsNothing);
      expect(tester.getTopLeft(row).dy, top);
    });

    testWidgets('a cell being read stays open when its text changes', (
      tester,
    ) async {
      await openChapter(tester);
      await tester.tap(find.text('target 5'));
      await tester.pump();
      await tester.pump();

      file.writeAsStringSync(changed('from elsewhere'));
      await scan(tester);

      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.controller!.text, '​from elsewhere');
    });

    Future<void> makeConflict(WidgetTester tester) async {
      await openChapter(tester);
      await tester.tap(find.text('target 5'));
      await tester.pump();
      await tester.pump();
      await tester.enterText(find.byType(TextField), 'mine');
      await tester.pump();
      file.writeAsStringSync(changed('theirs'));
      await scan(tester);
    }

    testWidgets('keep mine replaces the file, and editing goes on', (
      tester,
    ) async {
      await makeConflict(tester);
      expect(find.text('This chapter changed elsewhere'), findsOneWidget);
      expect(file.readAsStringSync(), contains('theirs'));

      await tester.tap(find.text('Keep mine'));
      await settle(tester);

      expect(find.byType(AlertDialog), findsNothing);
      expect(file.readAsStringSync(), contains('mine'));
      expect(file.readAsStringSync(), isNot(contains('theirs')));
      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.controller!.text, '​mine');
      expect(field.focusNode!.hasFocus, isTrue);
    });

    testWidgets('take theirs shows the other version', (tester) async {
      await makeConflict(tester);

      await tester.tap(find.text('Take theirs'));
      await settle(tester);

      expect(find.byType(AlertDialog), findsNothing);
      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.controller!.text, '​theirs');
      expect(file.readAsStringSync(), contains('theirs'));
    });

    testWidgets('save mine as a copy keeps both', (tester) async {
      await makeConflict(tester);

      await tester.tap(find.text('Save mine as a copy'));
      await settle(tester);

      expect(find.byType(AlertDialog), findsNothing);
      expect(
        find.text('Your version was saved as 01_copy.txt'),
        findsOneWidget,
      );
      final copy = File('${dir.path}/01_copy.txt').readAsStringSync();
      expect(copy, contains('mine'));
      expect(file.readAsStringSync(), contains('theirs'));
    });

    testWidgets('the prompt can\'t be dismissed by accident, and Back stays', (
      tester,
    ) async {
      await makeConflict(tester);

      await tester.tapAt(const Offset(1, 1));
      await settle(tester);
      expect(find.text('This chapter changed elsewhere'), findsOneWidget);

      final dialogContext = tester.element(find.byType(AlertDialog));
      await Navigator.of(dialogContext).maybePop();
      await settle(tester);
      expect(find.text('This chapter changed elsewhere'), findsOneWidget);
    });

    testWidgets('Back with a change waiting asks instead of leaving', (
      tester,
    ) async {
      await openChapter(tester);
      await tester.tap(find.text('target 5'));
      await tester.pump();
      await tester.pump();
      await tester.enterText(find.byType(TextField), 'mine');
      await tester.pump();
      await tester.tap(find.byTooltip('Finish editing'));
      await tester.pump();
      file.writeAsStringSync(changed('theirs'));

      await tester.pageBack();
      await settle(tester);

      expect(find.text('This chapter changed elsewhere'), findsOneWidget);
      expect(find.text('Leave without saving?'), findsNothing);
      expect(file.readAsStringSync(), contains('theirs'));

      await tester.tap(find.text('Keep mine'));
      await settle(tester);
      await tester.pageBack();
      await settle(tester);
      expect(find.text('open'), findsOneWidget);
      expect(file.readAsStringSync(), contains('mine'));
    });

    testWidgets('a change waits while something is open on top', (
      tester,
    ) async {
      await openChapter(tester);
      await tester.longPress(find.text('target 5'));
      await tester.pumpAndSettle();
      expect(find.text('Delete row'), findsOneWidget);

      file.writeAsStringSync(changed('from elsewhere'));
      await scan(tester);
      Navigator.of(tester.element(find.text('Delete row'))).pop();
      await settle(tester);
      await settle(tester);

      expect(find.text('from elsewhere'), findsOneWidget);
    });

    testWidgets('a deleted file can be written again', (tester) async {
      await openChapter(tester);
      file.deleteSync();
      await tester.runAsync(() => rootWatch.scan());
      await settle(tester);

      expect(find.text('This chapter\'s file is gone'), findsOneWidget);
      await tester.tap(find.text('Keep mine'));
      await settle(tester);

      expect(file.existsSync(), isTrue);
      expect(find.text('target 5'), findsOneWidget);
    });

    testWidgets('a deleted file can be left closed', (tester) async {
      await openChapter(tester);
      file.deleteSync();
      await scan(tester);

      await tester.tap(find.text('Close chapter'));
      await settle(tester);

      expect(find.text('open'), findsOneWidget);
      expect(file.existsSync(), isFalse);
    });

    testWidgets('the banner appears below the rows, without moving them', (
      tester,
    ) async {
      await openChapter(tester);
      final top = tester.getTopLeft(find.text('target 3')).dy;

      File('${dir.path}/01.sync-conflict-20261031-120000-ABC.txt')
          .writeAsStringSync('x');
      await scan(tester);

      expect(find.byType(MaterialBanner), findsOneWidget);
      expect(tester.getTopLeft(find.text('target 3')).dy, top);

      await tester.tap(find.text('Show'));
      await settle(tester);
      expect(
        find.textContaining('01.sync-conflict-20261031-120000-ABC.txt'),
        findsOneWidget,
      );
      expect(find.byType(RowTile), findsWidgets);
    });

    group('the tree', () {
      Future<void> openTree(WidgetTester tester) async {
        await settle(
          tester,
          MaterialApp(
            home: FolderTreeScreen(
              rootPath: dir.path,
              settings: settings,
              onChangeRoot: () {},
              createWatch: (path) => rootWatch = RootWatch(
                path,
                interval: const Duration(days: 1),
                useSystemEvents: false,
              ),
            ),
          ),
        );
      }

      testWidgets('follows changes and shows the banner', (tester) async {
        file.writeAsStringSync('@ a\n< First\n>\n');
        await openTree(tester);
        expect(find.text('First'), findsOneWidget);
        expect(find.byType(MaterialBanner), findsNothing);

        File('${dir.path}/02.txt').writeAsStringSync('@ a\n< Second\n>\n');
        File('${dir.path}/01.sync-conflict-20261031-120000-ABC.txt')
            .writeAsStringSync('x');
        await scan(tester);

        expect(find.text('Second'), findsOneWidget);
        expect(
          find.text('There is 1 conflict copy in this root folder.'),
          findsOneWidget,
        );
      });

      testWidgets('an open chapter gets the change too', (tester) async {
        file.writeAsStringSync('@ a\n< Title\n>\n\n@ b\n< Body\n>\n');
        await openTree(tester);
        await tester.tap(find.text('Title'));
        await settle(tester);
        expect(find.text('Body'), findsOneWidget);

        file.writeAsStringSync('@ a\n< Title\n>\n\n@ b\n< From elsewhere\n>\n');
        await scan(tester);

        expect(find.text('From elsewhere'), findsOneWidget);
      });
    });
  });
}
