import 'dart:io';

import 'package:path/path.dart' as p;

import '../model/chapter_format.dart';
import '../model/natural_sort.dart';

/// One chapter file in a book folder.
class ChapterEntry {
  ChapterEntry({required this.file, required this.title, this.error});

  final File file;

  /// The chapter's title row, or null when it has none or can't be read.
  final String? title;

  /// Why the file could not be read, if it couldn't.
  final String? error;

  String get fileName => p.basename(file.path);
}

/// A book is a folder; each `.txt` file in it is a chapter, ordered by name.
class BookFolder {
  BookFolder(this.path);

  static const chapterExtension = '.txt';

  final String path;

  String get name => p.basename(path);

  static bool isChapterFileName(String name) =>
      name.toLowerCase().endsWith(chapterExtension) &&
      !name.startsWith('.') &&
      !name.contains('.sync-conflict-');

  /// Chapter files in natural order, without reading them.
  Future<List<File>> chapterFiles() async {
    final files = await Directory(path)
        .list(followLinks: false)
        .where((e) => e is File && isChapterFileName(p.basename(e.path)))
        .cast<File>()
        .toList();
    files.sort(
      (a, b) => naturalCompare(p.basename(a.path), p.basename(b.path)),
    );
    return files;
  }

  /// All chapters with their titles. A file that can't be read is still
  /// listed, with [ChapterEntry.error] set, so it never silently disappears.
  Future<List<ChapterEntry>> listChapters() async {
    final entries = <ChapterEntry>[];
    for (final file in await chapterFiles()) {
      try {
        final parsed = ChapterFormat.parse(await file.readAsString());
        entries.add(ChapterEntry(file: file, title: parsed.chapter.title));
      } on Object catch (e) {
        entries.add(ChapterEntry(file: file, title: null, error: '$e'));
      }
    }
    return entries;
  }
}
