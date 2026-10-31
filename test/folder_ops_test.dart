import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ford/src/folders/folder_ops.dart';
import 'package:ford/src/folders/folder_tree.dart';
import 'package:ford/src/folders/target_selection.dart';
import 'package:ford/src/model/chapter_format.dart';
import 'package:ford/src/settings/app_settings.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late Directory dir;

  setUp(() => dir = Directory.systemTemp.createTempSync('ford_folders_'));
  tearDown(() => dir.deleteSync(recursive: true));

  String path(String relative) => p.join(dir.path, relative);

  void chapter(
    String relative,
    String title, {
    String target = '',
    int rows = 1,
  }) {
    File(path(relative))
      ..createSync(recursive: true)
      ..writeAsStringSync(
        [
          '@ title\n< $title\n> $target\n',
          for (var i = 1; i < rows; i++) '@ row$i\n< Row $i\n>\n',
        ].join('\n'),
      );
  }

  Future<FolderEntry> tree() => FolderTree.load(dir.path);

  Future<FolderEntry> folder(String relative) async =>
      (await tree()).find(path(relative))! as FolderEntry;

  /// Direct contents on disk, in order.
  Future<List<String>> names([String relative = '']) async => [
    for (final c
        in ((await tree()).find(p.join(dir.path, relative))! as FolderEntry)
            .children)
      c.diskName,
  ];

  String titleOf(String relative) =>
      ChapterFormat.parse(File(path(relative)).readAsStringSync())
          .chapter
          .segments
          .first
          .source;

  group('FolderTree', () {
    test('sorts files and folders together, nesting to any depth', () async {
      chapter('01/00.txt', 'Part');
      chapter('01/01.txt', 'One');
      chapter('01/02/00.txt', 'Inner');
      chapter('01/02/03/00.txt', 'Deep');
      chapter('01/03.txt', 'Three');

      expect(await names('01'), ['00.txt', '01.txt', '02', '03.txt']);
      final root = await tree();
      expect(root.allChapters.length, 5);
      expect(root.allFolders.length, 3);
      expect(root.find(path('01/02/03/00.txt')), isA<ChapterEntry>());
    });

    test('a folder is named by the first row of its first file', () async {
      chapter('a/02.txt', 'Second');
      chapter('a/03.txt', 'Third');
      Directory(path('a/01')).createSync();

      final a = await folder('a');
      expect(a.displayName, 'Second');
      expect(a.isUnnamed, isFalse);
    });

    test('falls back to the name on disk, marked as unnamed', () async {
      Directory(path('empty')).createSync();
      chapter('blank/00.txt', '');
      File(path('broken/01.txt'))
        ..createSync(recursive: true)
        ..writeAsBytesSync([0xFF, 0xFE, 0xFF]);

      for (final name in ['empty', 'blank', 'broken']) {
        final f = await folder(name);
        expect(f.isUnnamed, isTrue, reason: name);
        expect(f.label, name);
      }
    });

    test(
      'the root has no display name, and chapters in it still work',
      () async {
        chapter('01.txt', 'Loose');

        final root = await tree();
        expect(root.isUnnamed, isTrue);
        expect(root.chapters.single.title, 'Loose');
      },
    );

    test('leaves out hidden folders and conflict copies', () async {
      chapter('.stversions/01.txt', 'Old');
      chapter('01.sync-conflict-20261031-120000-ABC.txt', 'Conflict');
      chapter('01.txt', 'Real');

      expect(await names(), ['01.txt']);
    });
  });

  group('namesForOrder', () {
    test('changes nothing for the current order', () {
      expect(namesForOrder(['01.txt', '02', '03.txt']), [
        '01.txt',
        '02',
        '03.txt',
      ]);
    });

    test('renames only the entries between the old and new place', () {
      expect(
        namesForOrder(['01.txt', '04.txt', '02.txt', '03.txt', '05.txt']),
        ['01.txt', '02.txt', '03.txt', '04.txt', '05.txt'],
      );
    });

    test('files and folders swap numbers but keep their kind', () {
      expect(namesForOrder(['03.txt', '01', '02 Notes']), [
        '01.txt',
        '02',
        '03 Notes',
      ]);
    });

    test('keeps gaps and wide numbers that were already there', () {
      expect(namesForOrder(['010.txt', '002.txt']), ['002.txt', '010.txt']);
    });

    test('names that are not numbered keep their text after a new number', () {
      expect(namesForOrder(['Beta', 'Alpha', '07.txt']), [
        '07 Beta',
        '08 Alpha',
        '09.txt',
      ]);
      expect(namesForOrder(['Beta', 'Alpha']), ['01 Beta', '02 Alpha']);
    });

    test('renumbers when two entries share a number', () {
      expect(namesForOrder(['02.txt', '02']), ['02.txt', '03']);
    });

    test('the same value written differently still has an order', () {
      expect(namesForOrder(['2.txt', '02.txt']), ['02.txt', '2.txt']);
    });
  });

  group('applyMoves', () {
    test('rotates names without losing anything', () async {
      chapter('01.txt', 'A');
      chapter('02.txt', 'B');
      chapter('03.txt', 'C');

      await applyMoves({
        path('01.txt'): path('02.txt'),
        path('02.txt'): path('03.txt'),
        path('03.txt'): path('01.txt'),
      });

      expect(titleOf('01.txt'), 'C');
      expect(titleOf('02.txt'), 'A');
      expect(titleOf('03.txt'), 'B');
      expect(dir.listSync().length, 3);
    });

    test('refuses a target that belongs to something else', () async {
      chapter('01.txt', 'A');
      chapter('02.txt', 'B');

      await expectLater(
        applyMoves({path('01.txt'): path('02.txt')}),
        throwsA(isA<FileSystemException>()),
      );

      expect(titleOf('01.txt'), 'A');
      expect(titleOf('02.txt'), 'B');
    });

    test('undoes what it did when a move fails partway', () async {
      chapter('01.txt', 'A');
      chapter('02.txt', 'B');

      await expectLater(
        applyMoves({
          path('01.txt'): path('03.txt'),
          path('gone.txt'): path('04.txt'),
          path('02.txt'): path('05.txt'),
        }),
        throwsA(isA<FileSystemException>()),
      );

      expect(await names(), ['01.txt', '02.txt']);
      expect(titleOf('01.txt'), 'A');
    });
  });

  group('FolderOps', () {
    test(
      'creating a folder writes its name file; the disk name is generated',
      () async {
        chapter('01/00.txt', 'First');
        chapter('03.txt', 'Three');

        final created = await FolderOps.createFolder(
          await tree(),
          'The House',
          'A Ház',
        );

        expect(p.basename(created), '04');
        final made = (await tree()).find(created)! as FolderEntry;
        expect(made.displayName, 'The House');
        expect(made.children.single.diskName, '00.txt');
        final row = ChapterFormat.parse(
          File(p.join(created, '00.txt')).readAsStringSync(),
        ).chapter.segments.single;
        expect(row.source, 'The House');
        expect(row.target, 'A Ház');
      },
    );

    test('editing a name changes the title row and not the folder', () async {
      chapter('01/00.txt', 'Old', target: 'Régi', rows: 3);

      await FolderOps.editName(await folder('01'), 'New', 'Új');

      expect(Directory(path('01')).existsSync(), isTrue);
      final segments = ChapterFormat.parse(
        File(path('01/00.txt')).readAsStringSync(),
      ).chapter.segments;
      expect(segments.first.id, 'title');
      expect(segments.first.source, 'New');
      expect(segments.first.target, 'Új');
      expect(segments.length, 3);
    });

    test(
      'editing the name of a folder without files adds a first file',
      () async {
        Directory(path('01')).createSync();

        await FolderOps.editName(await folder('01'), 'Named', '');

        expect((await folder('01')).displayName, 'Named');
        expect(await names('01'), ['00.txt']);
      },
    );

    test('adding a name keeps the first chapter\'s title', () async {
      chapter('01/01.txt', 'Chapter one', rows: 2);

      final moves = await FolderOps.addName(await folder('01'), 'Part', 'Rész');

      expect(moves, isEmpty);
      expect(await names('01'), ['00.txt', '01.txt']);
      expect((await folder('01')).displayName, 'Part');
      expect(titleOf('01/01.txt'), 'Chapter one');
    });

    test('adding a name makes room when 00.txt is taken', () async {
      chapter('01/00.txt', 'Prologue', rows: 2);
      chapter('01/01.txt', 'Chapter one');

      final moves = await FolderOps.addName(await folder('01'), 'Part', '');

      expect(await names('01'), ['00.txt', '01.txt', '02.txt']);
      expect(titleOf('01/00.txt'), 'Part');
      expect(titleOf('01/01.txt'), 'Prologue');
      expect(titleOf('01/02.txt'), 'Chapter one');
      expect(moves[path('01/00.txt')], path('01/01.txt'));
    });

    test('reordering renames only what it needs to, across kinds', () async {
      chapter('01.txt', 'One');
      chapter('02/00.txt', 'Folder');
      chapter('03.txt', 'Three');
      chapter('04.txt', 'Four');
      final root = await tree();
      final [a, b, c, d] = root.children;

      final moves = await FolderOps.reorder(root, [a, d, b, c]);

      expect(moves.length, 3);
      expect(await names(), ['01.txt', '02.txt', '03', '04.txt']);
      expect(titleOf('02.txt'), 'Four');
      expect(titleOf('03/00.txt'), 'Folder');
      expect(titleOf('04.txt'), 'Three');
    });

    test('moving takes the next number there and keeps the rest', () async {
      chapter('01/05.txt', 'Chapter');
      chapter('02/00.txt', 'Dest');
      chapter('02/01.txt', 'Dest one');
      final root = await tree();

      final moves = await FolderOps.move(
        root.find(path('01/05.txt'))!,
        root.find(path('02'))! as FolderEntry,
      );

      expect(moves, {path('01/05.txt'): path('02/02.txt')});
      expect(await names('01'), isEmpty);
      expect(titleOf('02/02.txt'), 'Chapter');
    });

    test('moving a folder takes everything inside with it', () async {
      chapter('01/00.txt', 'Moved');
      chapter('01/01.txt', 'Inside');
      chapter('02/00.txt', 'Dest');
      final root = await tree();

      await FolderOps.move(
        root.find(path('01'))!,
        root.find(path('02'))! as FolderEntry,
      );

      expect(titleOf('02/01/01.txt'), 'Inside');
    });

    test(
      'a name that isn\'t numbered survives a move unless it\'s taken',
      () async {
        chapter('Beta/00.txt', 'Mine');
        chapter('Dest/Beta/00.txt', 'Theirs');
        chapter('Other/00.txt', 'Other');
        final root = await tree();
        final beta = root.find(path('Beta'))!;

        expect(
          FolderOps.nameAfterMove(
            beta,
            root.find(path('Other'))! as FolderEntry,
          ),
          'Beta',
        );
        expect(
          FolderOps.nameAfterMove(
            beta,
            root.find(path('Dest'))! as FolderEntry,
          ),
          '01 Beta',
        );
      },
    );

    test('deleting removes the folder and all it holds', () async {
      chapter('01/00.txt', 'Gone');
      chapter('01/02/00.txt', 'Nested');
      File(path('01/notes.md')).writeAsStringSync('notes');
      chapter('02/00.txt', 'Stays');
      final gone = await folder('01');

      final summary = await FolderOps.summarizeDeletion(gone);
      await FolderOps.delete(gone);

      expect(summary.chapters, 2);
      expect(summary.folders, 1);
      expect(summary.otherFiles, 1);
      expect(await names(), ['02']);
    });

    test('the root can\'t be deleted', () async {
      expect(
        () => FolderOps.delete(FolderEntry(path: dir.path, children: [])),
        throwsArgumentError,
      );
      expect(dir.existsSync(), isTrue);
    });
  });

  group('name warnings', () {
    test('reordering warns when a different file becomes first', () async {
      chapter('a/00.txt', 'Name');
      chapter('a/01.txt', 'Chapter');
      final a = await folder('a');
      final [name, ch] = a.children;

      final changes = FolderOps.nameChangesForReorder(a, [ch, name]);
      expect(changes.single.from, 'Name');
      expect(changes.single.to, 'Chapter');
      expect(FolderOps.nameChangesForReorder(a, [name, ch]), isEmpty);
    });

    test('a folder moving past the first file changes nothing', () async {
      chapter('a/01/00.txt', 'Inner');
      chapter('a/02.txt', 'Name');
      final a = await folder('a');

      expect(
        FolderOps.nameChangesForReorder(a, a.children.reversed.toList()),
        isEmpty,
      );
    });

    test('the root never warns', () async {
      chapter('01.txt', 'A');
      chapter('02.txt', 'B');
      final root = await tree();

      expect(
        FolderOps.nameChangesForReorder(root, root.children.reversed.toList()),
        isEmpty,
      );
    });

    test('moving the first file out warns about the source folder', () async {
      chapter('a/00.txt', 'Name');
      chapter('a/01.txt', 'Next');
      chapter('b/00.txt', 'Dest');
      final root = await tree();

      final changes = FolderOps.nameChangesForMove(
        root.find(path('a/00.txt'))!,
        root.find(path('b'))! as FolderEntry,
      );

      expect(changes.single.folder.diskName, 'a');
      expect(changes.single.to, 'Next');
    });

    test(
      'moving a file into a folder without files names that folder',
      () async {
        chapter('a/00.txt', 'Name');
        chapter('a/01.txt', 'Chapter');
        Directory(path('b')).createSync();
        final root = await tree();

        final changes = FolderOps.nameChangesForMove(
          root.find(path('a/01.txt'))!,
          root.find(path('b'))! as FolderEntry,
        );

        expect(changes.single.folder.diskName, 'b');
        expect(changes.single.from, 'b');
        expect(changes.single.to, 'Chapter');
      },
    );

    test('losing the only file falls back to the name on disk', () async {
      chapter('a/00.txt', 'Name');
      final root = await tree();

      final changes = FolderOps.nameChangesForDelete(
        root.find(path('a/00.txt'))! as ChapterEntry,
      );

      expect(changes.single.to, 'a');
    });

    test('a new chapter warns only if it comes first', () async {
      chapter('a/00.txt', 'Name');
      chapter('b/intro.txt', 'Intro');
      Directory(path('c')).createSync();

      expect(
        FolderOps.nameChangesForNewChapter(await folder('a'), 'New'),
        isEmpty,
      );
      expect(
        FolderOps.nameChangesForNewChapter(await folder('b'), 'New').single.to,
        'New',
      );
      expect(
        FolderOps.nameChangesForNewChapter(await folder('c'), 'New').single.to,
        'New',
      );
    });
  });

  group('TargetSelection', () {
    test(
      'ticking a folder takes everything inside; parts can be unticked',
      () async {
        chapter('a/00.txt', 'Name');
        chapter('a/b/00.txt', 'Inner');
        chapter('c/00.txt', 'Other');
        final root = await tree();
        final a = root.find(path('a'))!;
        final inner = root.find(path('a/b/00.txt'))!;
        final other = root.find(path('c'))!;
        final selection = TargetSelection();

        selection.toggle(a);
        expect(selection.stateOf(a), isTrue);
        expect(selection.stateOf(inner), isTrue);
        expect(selection.stateOf(other), isFalse);
        expect(selection.chapterPaths, {path('a/00.txt'), path('a/b/00.txt')});

        selection.toggle(inner);
        expect(selection.stateOf(a), isNull);
        expect(selection.chapterPaths, {path('a/00.txt')});

        selection.toggle(a);
        expect(selection.stateOf(a), isTrue);

        selection.toggle(a);
        expect(selection.chapterPaths, isEmpty);
      },
    );

    test('a folder holding no chapters stays unticked', () async {
      Directory(path('empty')).createSync();
      final empty = await folder('empty');
      final selection = TargetSelection();

      selection.toggle(empty);

      expect(selection.stateOf(empty), isFalse);
    });
  });

  group('AppSettings', () {
    Future<AppSettings> settings() async {
      SharedPreferences.setMockInitialValues({});
      return AppSettings.load();
    }

    test('positions follow a file or anything inside a moved folder', () async {
      final s = await settings();
      await s.setPosition('/r/01.txt', const ReadingPosition('a', 0));
      await s.setPosition('/r/02/05.txt', const ReadingPosition('b', 0));
      await s.setPosition('/r/020/05.txt', const ReadingPosition('c', 0));

      await s.relocate({'/r/01.txt': '/r/03.txt', '/r/02': '/r/04'});

      expect(s.position('/r/01.txt'), isNull);
      expect(s.position('/r/03.txt')?.rowId, 'a');
      expect(s.position('/r/02/05.txt'), isNull);
      expect(s.position('/r/04/05.txt')?.rowId, 'b');
      expect(s.position('/r/020/05.txt')?.rowId, 'c');
    });

    test('positions swap when two files swap names', () async {
      final s = await settings();
      await s.setPosition('/r/01.txt', const ReadingPosition('a', 0));
      await s.setPosition('/r/02.txt', const ReadingPosition('b', 0));

      await s.relocate({'/r/01.txt': '/r/02.txt', '/r/02.txt': '/r/01.txt'});

      expect(s.position('/r/01.txt')?.rowId, 'b');
      expect(s.position('/r/02.txt')?.rowId, 'a');
    });

    test('the last chapter follows its folder', () async {
      final s = await settings();
      await s.setLastChapter('/r', p.join('02', '05.txt'));

      await s.relocate({'/r/02': '/r/07'});

      expect(s.lastChapter('/r'), p.join('07', '05.txt'));
    });

    test('forgets what was inside a deleted folder', () async {
      final s = await settings();
      await s.setPosition('/r/02/05.txt', const ReadingPosition('a', 0));
      await s.setPosition('/r/03.txt', const ReadingPosition('b', 0));
      await s.setLastChapter('/r', p.join('02', '05.txt'));

      await s.forget('/r/02');

      expect(s.position('/r/02/05.txt'), isNull);
      expect(s.position('/r/03.txt')?.rowId, 'b');
      expect(s.lastChapter('/r'), isNull);
    });

    test('keeps a root folder chosen before the rename', () async {
      SharedPreferences.setMockInitialValues({'bookPath': '/old/choice'});

      expect((await AppSettings.load()).rootPath, '/old/choice');
    });
  });
}
