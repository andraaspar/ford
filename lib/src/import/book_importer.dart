import 'dart:io';

import '../model/chapter_format.dart';
import '../model/natural_sort.dart';
import 'markdown_table_importer.dart';

/// Result of converting one Markdown chapter file.
class ChapterImport {
  ChapterImport(this.sourceName, this.targetName, this.result);
  final String sourceName;
  final String targetName;
  final ImportResult result;
}

/// Converts a folder of Obsidian chapter files (`1.md`, `2.md`, ...) into a
/// book folder of chapter files (`01.txt`, `02.txt`, ...).
class BookImporter {
  static const chapterExtension = '.txt';

  /// Reads and converts every `.md` file in [sourceDir], in natural order.
  /// Nothing is written.
  static Future<List<ChapterImport>> dryRun(Directory sourceDir) async {
    final files = await sourceDir
        .list()
        .where((e) => e is File && e.path.toLowerCase().endsWith('.md'))
        .cast<File>()
        .toList();
    String name(File f) => f.uri.pathSegments.last;
    files.sort((a, b) => naturalCompare(name(a), name(b)));

    final width = files.length.toString().length.clamp(2, 9);
    final out = <ChapterImport>[];
    for (final f in files) {
      final base = name(f).substring(0, name(f).length - 3);
      final padded = int.tryParse(base) != null
          ? base.padLeft(width, '0')
          : base;
      final result = MarkdownTableImporter.import(await f.readAsString());
      out.add(ChapterImport(name(f), '$padded$chapterExtension', result));
    }
    return out;
  }

  /// Writes [imports] into [targetDir]. Refuses to overwrite existing files.
  static Future<void> write(
    List<ChapterImport> imports,
    Directory targetDir,
  ) async {
    await targetDir.create(recursive: true);
    for (final i in imports) {
      final f = File('${targetDir.path}/${i.targetName}');
      if (await f.exists()) {
        throw FileSystemException('Refusing to overwrite', f.path);
      }
    }
    for (final i in imports) {
      final f = File('${targetDir.path}/${i.targetName}');
      await f.writeAsString(ChapterFormat.serialize(i.result.chapter));
    }
  }
}

