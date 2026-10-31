import 'dart:io';
import 'dart:math';

import 'package:path/path.dart' as p;

import '../model/chapter.dart';
import '../model/chapter_format.dart';
import '../model/ids.dart';
import '../model/natural_sort.dart';
import '../model/segment.dart';
import 'atomic_write.dart';
import 'folder_tree.dart';

/// A folder's display name that an action would change.
class NameChange {
  NameChange(this.folder, this.from, this.to);

  final FolderEntry folder;
  final String from;
  final String to;
}

/// What deleting a folder takes with it.
class DeletionSummary {
  DeletionSummary(this.chapters, this.folders, this.otherFiles);

  final int chapters;
  final int folders;

  /// Files that aren't chapters, such as notes or Syncthing conflict copies.
  final int otherFiles;
}

/// Name of the dedicated first file that gives a folder its display name.
const nameFileName = '00${FolderTree.chapterExtension}';

/// Changes to the folders and chapters on disk.
///
/// Order comes from names on disk, so these actions rename entries when they
/// have to. Those that do return the moves they made, old path to new path.
class FolderOps {
  /// Creates a folder at the end of [parent], with a first file holding its
  /// display name. Returns the new folder's path.
  static Future<String> createFolder(
    FolderEntry parent,
    String source,
    String target,
  ) async {
    final folder = Directory(p.join(parent.path, _addedName(parent, '')));
    await folder.create();
    await _writeNewChapter(
      File(p.join(folder.path, nameFileName)),
      source,
      target,
    );
    return folder.path;
  }

  /// Creates a chapter in [parent] and returns its file.
  static Future<File> createChapter(
    FolderEntry parent,
    String source,
    String target,
  ) async {
    final file = File(
      p.join(parent.path, _addedName(parent, FolderTree.chapterExtension)),
    );
    await _writeNewChapter(file, source, target);
    return file;
  }

  /// The title row of [chapter] as it is on disk.
  static Future<({String source, String target})> readTitleRow(
    ChapterEntry chapter,
  ) async {
    final parsed = ChapterFormat.parse(await chapter.file.readAsString());
    final first = parsed.chapter.segments.firstOrNull;
    return (source: first?.source ?? '', target: first?.target ?? '');
  }

  /// Sets [folder]'s display name in the title row of its first file. A folder
  /// without files gets a first file.
  static Future<void> editName(
    FolderEntry folder,
    String source,
    String target,
  ) async {
    final first = folder.firstChapter;
    if (first == null) {
      await _writeNewChapter(
        File(p.join(folder.path, nameFileName)),
        source,
        target,
      );
      return;
    }
    final chapter = ChapterFormat.parse(await first.file.readAsString())
        .chapter;
    final Chapter updated;
    if (chapter.isEmpty) {
      updated = _titleOnly(source, target);
    } else {
      updated = chapter.updateSegment(
        0,
        chapter.segments.first.copyWith(source: source, target: target),
      );
    }
    await writeAtomically(first.file, ChapterFormat.serialize(updated));
  }

  /// Adds a dedicated first file in front of everything in [folder], so that
  /// the file that was first keeps its title.
  static Future<Map<String, String>> addName(
    FolderEntry folder,
    String source,
    String target,
  ) async {
    final names = folder.children.map((c) => c.diskName).toList();
    final fits = names.isEmpty || naturalCompare(nameFileName, names.first) < 0;
    final moves = fits
        ? <String, String>{}
        : _movesTo(folder, folder.children, renumbered(names, start: 1));
    await applyMoves(moves);
    await _writeNewChapter(
      File(p.join(folder.path, nameFileName)),
      source,
      target,
    );
    return moves;
  }

  /// Puts [folder]'s children in the order of [desired].
  static Future<Map<String, String>> reorder(
    FolderEntry folder,
    List<TreeEntry> desired,
  ) async {
    final names = namesForOrder(desired.map((c) => c.diskName).toList());
    final moves = _movesTo(folder, desired, names);
    await applyMoves(moves);
    return moves;
  }

  /// Moves [entry] into [destination].
  static Future<Map<String, String>> move(
    TreeEntry entry,
    FolderEntry destination,
  ) async {
    final moves = {
      entry.path: p.join(destination.path, nameAfterMove(entry, destination)),
    };
    await applyMoves(moves);
    return moves;
  }

  static Future<void> delete(TreeEntry entry) async {
    switch (entry) {
      case ChapterEntry():
        await entry.file.delete();
      case FolderEntry():
        if (entry.isRoot) {
          throw ArgumentError('The root folder can\'t be deleted.');
        }
        await Directory(entry.path).delete(recursive: true);
    }
  }

  /// Counts what's in [folder] on disk right now, including files the tree
  /// doesn't show.
  static Future<DeletionSummary> summarizeDeletion(FolderEntry folder) async {
    var chapters = 0, folders = 0, otherFiles = 0;
    await for (final entity in Directory(
      folder.path,
    ).list(recursive: true, followLinks: false)) {
      if (entity is Directory) {
        folders++;
      } else if (FolderTree.isChapterFileName(p.basename(entity.path))) {
        chapters++;
      } else {
        otherFiles++;
      }
    }
    return DeletionSummary(chapters, folders, otherFiles);
  }

  static List<NameChange> nameChangesForReorder(
    FolderEntry folder,
    List<TreeEntry> desired,
  ) => [
    ?_nameChange(folder, desired.whereType<ChapterEntry>().firstOrNull?.title),
  ];

  static List<NameChange> nameChangesForMove(
    TreeEntry entry,
    FolderEntry destination,
  ) {
    if (entry is! ChapterEntry) return const [];
    return [
      ...nameChangesForDelete(entry),
      ..._nameChangesForAdded(
        destination,
        nameAfterMove(entry, destination),
        entry.title,
      ),
    ];
  }

  /// [title] is the title row the new chapter will have.
  static List<NameChange> nameChangesForNewChapter(
    FolderEntry parent,
    String title,
  ) => _nameChangesForAdded(
    parent,
    _addedName(parent, FolderTree.chapterExtension),
    title,
  );

  static List<NameChange> nameChangesForDelete(ChapterEntry entry) {
    final parent = entry.parent;
    if (parent == null || parent.firstChapter != entry) return const [];
    return [?_nameChange(parent, parent.chapters.skip(1).firstOrNull?.title)];
  }

  static List<NameChange> _nameChangesForAdded(
    FolderEntry folder,
    String name,
    String? title,
  ) {
    final first = folder.firstChapter;
    if (first != null && naturalCompare(first.diskName, name) < 0) {
      return const [];
    }
    return [?_nameChange(folder, title)];
  }

  static NameChange? _nameChange(FolderEntry folder, String? newName) {
    if (folder.isRoot || newName == folder.displayName) return null;
    return NameChange(folder, folder.label, newName ?? folder.diskName);
  }

  static Chapter _titleOnly(String source, String target) =>
      Chapter([Segment(id: newId(const {}), source: source, target: target)]);

  static Future<void> _writeNewChapter(
    File file,
    String source,
    String target,
  ) async {
    if (await file.exists()) {
      throw FileSystemException('Already exists', file.path);
    }
    await writeAtomically(
      file,
      ChapterFormat.serialize(_titleOnly(source, target)),
    );
  }

  static Map<String, String> _movesTo(
    FolderEntry folder,
    List<TreeEntry> entries,
    List<String> names,
  ) => {
    for (var i = 0; i < entries.length; i++)
      if (entries[i].diskName != names[i])
        entries[i].path: p.join(folder.path, names[i]),
  };

  /// The name a new entry gets in [folder]: the next free number.
  static String _addedName(FolderEntry folder, String suffix) {
    final numbers = folder.children
        .map((c) => _NumberedName.parse(c.diskName).number)
        .nonNulls;
    final values = numbers.map(int.tryParse).nonNulls;
    var next = values.isEmpty ? 1 : values.reduce(max) + 1;
    final width = numbers.map((n) => n.length).fold(2, max);
    while (true) {
      final name = '${'$next'.padLeft(width, '0')}$suffix';
      if (!_exists(p.join(folder.path, name))) return name;
      next++;
    }
  }

  /// The name [entry] gets in [destination]. A number gives way to the next free
  /// one there, and any other part of the name stays.
  static String nameAfterMove(TreeEntry entry, FolderEntry destination) {
    final name = _NumberedName.parse(entry.diskName);
    if (name.number == null) {
      if (!_exists(p.join(destination.path, entry.diskName))) {
        return entry.diskName;
      }
      return _addedName(destination, ' ${entry.diskName}');
    }
    return _addedName(destination, name.rest);
  }

  static bool _exists(String path) =>
      FileSystemEntity.typeSync(path, followLinks: false) !=
      FileSystemEntityType.notFound;
}

/// The names that put [desired] in that order, changing as few as possible.
///
/// The numbers at the start of the names are handed out again in the new order,
/// and the rest of each name stays with its entry. If that can't express the
/// order, for example because some names don't start with a number, all the
/// entries are numbered afresh.
List<String> namesForOrder(List<String> desired) {
  final parsed = desired.map(_NumberedName.parse).toList();
  if (parsed.every((n) => n.number != null)) {
    final numbers = parsed.map((n) => n.number!).toList()..sort(naturalCompare);
    final names = [
      for (var i = 0; i < parsed.length; i++) '${numbers[i]}${parsed[i].rest}',
    ];
    if (_isAscending(names)) return names;
  }
  final numbers = parsed
      .map((n) => n.number)
      .nonNulls
      .map(int.tryParse)
      .nonNulls;
  return renumbered(desired, start: numbers.isEmpty ? 1 : numbers.reduce(min));
}

/// Numbers [names] in order, from [start]. A name that doesn't start with a
/// number keeps its text after the new number, so a folder that goes by its name
/// on disk can still be recognized.
List<String> renumbered(List<String> names, {required int start}) {
  final width = max(2, '${start + names.length - 1}'.length);
  return [
    for (var i = 0; i < names.length; i++)
      '${'${start + i}'.padLeft(width, '0')}'
          '${_NumberedName.parse(names[i]).separatedRest}',
  ];
}

bool _isAscending(List<String> names) {
  for (var i = 1; i < names.length; i++) {
    if (naturalCompare(names[i - 1], names[i]) >= 0) return false;
  }
  return true;
}

class _NumberedName {
  _NumberedName(this.number, this.rest);

  factory _NumberedName.parse(String name) {
    final match = RegExp(r'^\d+').firstMatch(name);
    return match == null
        ? _NumberedName(null, name)
        : _NumberedName(match[0], name.substring(match.end));
  }

  /// The digits at the start of the name, if any.
  final String? number;
  final String rest;

  /// What goes after a new number.
  String get separatedRest => number == null ? ' $rest' : rest;
}

/// Makes [moves] (old path to new path). If one fails, those already made are
/// undone and the error is rethrown.
///
/// A rotation of names needs one entry parked out of the way. It keeps a visible
/// name, so that a crash at that moment can't make it disappear from the app.
Future<void> applyMoves(Map<String, String> moves) async {
  final pending = Map.of(moves)..removeWhere((from, to) => from == to);
  for (final target in pending.values) {
    if (!pending.containsKey(target) && await _existsOnDisk(target)) {
      throw FileSystemException('Already exists', target);
    }
  }
  final done = <(String, String)>[];
  Future<void> rename(String from, String to) async {
    await _rename(from, to);
    done.add((from, to));
  }

  try {
    while (pending.isNotEmpty) {
      final free = pending.entries
          .where((e) => !pending.containsKey(e.value))
          .firstOrNull;
      if (free != null) {
        await rename(free.key, free.value);
        pending.remove(free.key);
        continue;
      }
      final MapEntry(key: from, value: to) = pending.entries.first;
      final parked = p.join(p.dirname(from), '~moving-${p.basename(to)}');
      if (await _existsOnDisk(parked)) {
        throw FileSystemException('Already exists', parked);
      }
      await rename(from, parked);
      pending
        ..remove(from)
        ..[parked] = to;
    }
  } on Object {
    for (final (from, to) in done.reversed) {
      await _rename(to, from);
    }
    rethrow;
  }
}

Future<bool> _existsOnDisk(String path) async =>
    await FileSystemEntity.type(path, followLinks: false) !=
    FileSystemEntityType.notFound;

Future<void> _rename(String from, String to) async {
  if (await FileSystemEntity.isDirectory(from)) {
    await Directory(from).rename(to);
  } else {
    await File(from).rename(to);
  }
}
