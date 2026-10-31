import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ford/src/settings/app_settings.dart';
import 'package:ford/src/ui/folder_tree_screen.dart';
import 'package:ford/src/ui/target_picker_screen.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  // These screens really read and write files, and listing a folder never
  // finishes under the default binding's fake clock. Everything here therefore
  // runs in real time.
  LiveTestWidgetsFlutterBinding.ensureInitialized().framePolicy =
      LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  late Directory dir;
  late AppSettings settings;

  setUp(() async {
    dir = Directory.systemTemp.createTempSync('ford_ui_');
    SharedPreferences.setMockInitialValues({});
    settings = await AppSettings.load();
  });
  tearDown(() => dir.deleteSync(recursive: true));

  String path(String relative) => p.join(dir.path, relative);

  void chapter(String relative, String title) {
    File(path(relative))
      ..createSync(recursive: true)
      ..writeAsStringSync(
        '@ title\n< $title\n>\n\n@ row01\n< Body $title\n>\n',
      );
  }

  Future<void> settle(WidgetTester tester, [Widget? widget]) async {
    if (widget != null) await tester.pumpWidget(widget);
    for (var i = 0; i < 6; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
      await tester.pump();
    }
  }

  Widget treeScreen() => MaterialApp(
    home: FolderTreeScreen(
      rootPath: dir.path,
      settings: settings,
      onChangeRoot: () {},
    ),
  );

  Future<void> tapAndSettle(WidgetTester tester, Finder finder) async {
    await tester.tap(finder);
    await settle(tester);
  }

  Future<void> openMenu(WidgetTester tester, String label) async {
    final row = find.ancestor(
      of: find.text(label),
      matching: find.byType(ListTile),
    );
    await tapAndSettle(
      tester,
      find.descendant(of: row.first, matching: find.byTooltip('Actions')),
    );
  }

  group('FolderTreeScreen', () {
    testWidgets('shows display names and expands folders on tap', (
      tester,
    ) async {
      chapter('01/00.txt', 'The Part');
      chapter('01/01.txt', 'Chapter One');
      Directory(path('02')).createSync();

      await settle(tester, treeScreen());

      expect(find.text('The Part'), findsOneWidget);
      expect(find.text('Chapter One'), findsNothing);
      expect(find.text('02'), findsOneWidget);
      expect(find.text('Unnamed folder'), findsOneWidget);

      await tapAndSettle(tester, find.text('The Part'));

      expect(find.text('Chapter One'), findsOneWidget);
    });

    testWidgets('a long press opens the actions', (tester) async {
      chapter('01/00.txt', 'The Part');

      await settle(tester, treeScreen());
      await tester.longPress(find.text('The Part'));
      await settle(tester);

      expect(find.text('Edit name'), findsOneWidget);
    });

    testWidgets('reopens a chapter inside nested folders, then shows it', (
      tester,
    ) async {
      chapter('01/02/03.txt', 'Deep');
      chapter('01/00.txt', 'Outer');
      await settings.setLastChapter(dir.path, p.join('01', '02', '03.txt'));

      await settle(tester, treeScreen());
      expect(find.text('Body Deep'), findsOneWidget);

      await tester.pageBack();
      await settle(tester);

      // Both the chapter and the folder it names.
      expect(find.text('Deep'), findsNWidgets(2));
      expect(find.byIcon(Icons.bookmark), findsOneWidget);
    });

    testWidgets('creates a folder from the root menu', (tester) async {
      await settle(tester, treeScreen());
      expect(find.textContaining('Nothing here yet'), findsOneWidget);

      await tapAndSettle(tester, find.byTooltip('Root folder actions'));
      await tapAndSettle(tester, find.text('New folder'));
      await tester.enterText(find.byType(TextField).first, 'Made Here');
      await tester.pump();
      await tapAndSettle(tester, find.text('Create'));

      expect(find.text('Made Here'), findsOneWidget);
      expect(File(path('01/00.txt')).existsSync(), isTrue);
    });

    testWidgets(
      'edits a display name, pointing out a chapter title it shares',
      (tester) async {
        chapter('01/01.txt', 'Shared');

        await settle(tester, treeScreen());
        await openMenu(tester, 'Shared');
        await tapAndSettle(tester, find.text('Edit name'));

        expect(find.textContaining('also changes the title'), findsOneWidget);
        expect(find.widgetWithText(TextField, 'Source'), findsOneWidget);
        await tester.enterText(find.byType(TextField).first, 'Renamed');
        await tester.pump();
        await tapAndSettle(tester, find.text('Save'));

        expect(find.text('Renamed'), findsOneWidget);
        expect(Directory(path('01')).existsSync(), isTrue);
      },
    );

    testWidgets('names what a delete takes along, and cancelling keeps it', (
      tester,
    ) async {
      chapter('01/00.txt', 'Doomed');
      chapter('01/02/00.txt', 'Nested');

      await settle(tester, treeScreen());
      await openMenu(tester, 'Doomed');
      await tapAndSettle(tester, find.text('Delete…'));

      expect(find.text('Delete folder "Doomed"?'), findsOneWidget);
      expect(
        find.textContaining('2 chapters and 1 nested folder'),
        findsOneWidget,
      );

      await tapAndSettle(tester, find.text('Cancel'));
      expect(File(path('01/00.txt')).existsSync(), isTrue);

      await openMenu(tester, 'Doomed');
      await tapAndSettle(tester, find.text('Delete…'));
      await tapAndSettle(tester, find.widgetWithText(FilledButton, 'Delete'));

      expect(Directory(path('01')).existsSync(), isFalse);
      expect(find.text('Doomed'), findsNothing);
    });

    testWidgets('reorders by dragging, warning about the display name', (
      tester,
    ) async {
      chapter('01/00.txt', 'Name');
      chapter('01/01.txt', 'Chapter');

      await settle(tester, treeScreen());
      await openMenu(tester, 'Name');
      await tapAndSettle(tester, find.text('Reorder contents'));

      final handles = find.byIcon(Icons.drag_handle);
      await tester.timedDrag(
        handles.first,
        const Offset(0, 160),
        const Duration(seconds: 1),
      );
      await settle(tester);
      await tapAndSettle(tester, find.byTooltip('Save this order'));

      expect(find.text('This renames a folder'), findsOneWidget);
      expect(find.textContaining('"Name" would show as "Chapter"'), findsOne);

      await tapAndSettle(tester, find.text('Continue'));

      expect(find.text('Chapter'), findsOneWidget);
      expect(File(path('01/00.txt')).readAsStringSync(), contains('< Chapter'));
    });

    testWidgets('moves a chapter and its saved position to another folder', (
      tester,
    ) async {
      chapter('01/00.txt', 'From');
      chapter('01/01.txt', 'Traveller');
      chapter('02/00.txt', 'To');
      await settings.setPosition(
        path('01/01.txt'),
        const ReadingPosition('row01', 0),
      );

      await settle(tester, treeScreen());
      await tapAndSettle(tester, find.text('From'));
      await openMenu(tester, 'Traveller');
      await tapAndSettle(tester, find.text('Move to…'));

      // Its own folder isn't a place to move it to.
      await tapAndSettle(tester, find.text('From').last);
      final moveHere = find.widgetWithText(FilledButton, 'Move here');
      expect(tester.widget<FilledButton>(moveHere).onPressed, isNull);

      await tapAndSettle(tester, find.text('To').last);
      await tapAndSettle(tester, moveHere);

      expect(File(path('01/01.txt')).existsSync(), isFalse);
      expect(File(path('02/01.txt')).existsSync(), isTrue);
      expect(settings.position(path('02/01.txt'))?.rowId, 'row01');
    });
  });

  group('TargetPickerScreen', () {
    testWidgets('a ticked folder can have parts unticked', (tester) async {
      chapter('01/00.txt', 'Part');
      chapter('01/01.txt', 'One');
      chapter('02/00.txt', 'Skipped');
      Set<String>? picked;

      await settle(
        tester,
        MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                picked = await Navigator.of(context).push<Set<String>>(
                  MaterialPageRoute(
                    builder: (_) => TargetPickerScreen(rootPath: dir.path),
                  ),
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tapAndSettle(tester, find.text('open'));

      await tester.tap(find.text('Part'));
      await tester.pump();
      expect(find.text('2 chapters'), findsOneWidget);

      await tester.tap(find.byTooltip('Expand').first);
      await tester.pump();
      await tester.tap(find.text('One'));
      await tester.pump();

      expect(find.text('1 chapter'), findsOneWidget);
      final partBox = tester.widget<Checkbox>(find.byType(Checkbox).first);
      expect(partBox.value, isNull);

      await tapAndSettle(tester, find.text('Use these'));

      expect(picked, {path('01/00.txt')});
    });
  });

  group('DestinationPickerScreen', () {
    testWidgets('can create the folder it picks', (tester) async {
      chapter('01/00.txt', 'Existing');

      await settle(
        tester,
        MaterialApp(
          home: DestinationPickerScreen(
            rootPath: dir.path,
            title: 'Import to',
            action: 'Import here',
          ),
        ),
      );
      await tapAndSettle(tester, find.text('New folder'));
      await tester.enterText(find.byType(TextField).first, 'Fresh');
      await tester.pump();
      await tapAndSettle(tester, find.text('Create'));

      expect(find.text('Fresh'), findsOneWidget);
      expect(File(path('02/00.txt')).existsSync(), isTrue);
      final importHere = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Import here'),
      );
      expect(importHere.onPressed, isNotNull);
    });
  });
}
