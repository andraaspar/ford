import 'dart:io';

import 'package:path/path.dart' as p;

import '../model/chapter_format.dart';
import '../model/natural_sort.dart';

/// A chapter or folder in the tree under the root folder.
sealed class TreeEntry {
  TreeEntry(this.path);

  final String path;

  /// The folder this entry is directly inside; null only for the root.
  FolderEntry? parent;

  String get diskName => p.basename(path);

  /// What the app calls this entry.
  String get label;
}

/// One chapter file.
class ChapterEntry extends TreeEntry {
  ChapterEntry({
    required this.file,
    required this.title,
    this.rowCount = 0,
    this.error,
  }) : super(file.path);

  final File file;

  /// The chapter's title row, or null when it has none or can't be read.
  final String? title;

  final int rowCount;

  /// Why the file could not be read, if it couldn't.
  final String? error;

  String get fileName => diskName;

  @override
  String get label => title ?? fileName;
}

/// A folder and everything inside it, sorted by name.
class FolderEntry extends TreeEntry {
  FolderEntry({required String path, required this.children, this.error})
    : super(path) {
    for (final child in children) {
      child.parent = this;
    }
  }

  final List<TreeEntry> children;

  /// Why the folder could not be listed, if it couldn't.
  final String? error;

  bool get isRoot => parent == null;

  Iterable<ChapterEntry> get chapters => children.whereType<ChapterEntry>();

  Iterable<FolderEntry> get folders => children.whereType<FolderEntry>();

  /// The first file directly inside this folder, which decides its name.
  ChapterEntry? get firstChapter => chapters.firstOrNull;

  /// The first row of the first file. The root folder has no display name.
  String? get displayName => isRoot ? null : firstChapter?.title;

  /// A folder without a display name goes by its name on disk.
  bool get isUnnamed => displayName == null;

  @override
  String get label => displayName ?? diskName;

  /// Every chapter below this folder, at any depth.
  Iterable<ChapterEntry> get allChapters sync* {
    for (final child in children) {
      switch (child) {
        case ChapterEntry():
          yield child;
        case FolderEntry():
          yield* child.allChapters;
      }
    }
  }

  /// Every folder below this folder, at any depth.
  Iterable<FolderEntry> get allFolders sync* {
    for (final folder in folders) {
      yield folder;
      yield* folder.allFolders;
    }
  }

  /// The entry at [path], here or at any depth below.
  TreeEntry? find(String path) {
    if (path == this.path) return this;
    for (final child in children) {
      if (child.path == path) return child;
      if (child is FolderEntry && p.isWithin(child.path, path)) {
        return child.find(path);
      }
    }
    return null;
  }
}

/// Reads the tree of folders and chapter files under a root folder.
class FolderTree {
  static const chapterExtension = '.txt';

  static bool isChapterFileName(String name) =>
      name.toLowerCase().endsWith(chapterExtension) &&
      !name.startsWith('.') &&
      !name.contains('.sync-conflict-');

  /// Hidden folders, such as Syncthing's `.stversions`, aren't part of the tree.
  static bool isFolderName(String name) => !name.startsWith('.');

  /// Reads everything under [rootPath]. Throws if the root can't be listed. A
  /// file or nested folder that can't be read is still listed, with its `error`
  /// set, so it never silently disappears.
  static Future<FolderEntry> load(String rootPath) async =>
      FolderEntry(path: rootPath, children: await _readChildren(rootPath));

  static Future<List<TreeEntry>> _readChildren(String path) async {
    final found = await Directory(path).list(followLinks: false).toList();
    found.sort(
      (a, b) => naturalCompare(p.basename(a.path), p.basename(b.path)),
    );
    final children = <TreeEntry>[];
    for (final entity in found) {
      final name = p.basename(entity.path);
      if (entity is File && isChapterFileName(name)) {
        children.add(await _readChapter(entity));
      } else if (entity is Directory && isFolderName(name)) {
        children.add(await _readFolder(entity.path));
      }
    }
    return children;
  }

  static Future<FolderEntry> _readFolder(String path) async {
    try {
      return FolderEntry(path: path, children: await _readChildren(path));
    } on FileSystemException catch (e) {
      return FolderEntry(path: path, children: [], error: '$e');
    }
  }

  static Future<ChapterEntry> _readChapter(File file) async {
    try {
      final chapter = ChapterFormat.parse(await file.readAsString()).chapter;
      return ChapterEntry(
        file: file,
        title: chapter.title,
        rowCount: chapter.length,
      );
    } on Object catch (e) {
      return ChapterEntry(file: file, title: null, error: '$e');
    }
  }
}

/// Where [path] ends up after [moves] (old path to new path), or null if neither
/// it nor any folder around it moved.
String? movedPath(String path, Map<String, String> moves) {
  for (final MapEntry(key: from, value: to) in moves.entries) {
    if (path == from) return to;
    if (p.isWithin(from, path)) return p.join(to, p.relative(path, from: from));
  }
  return null;
}
