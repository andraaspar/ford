// Command-line import of an Obsidian book folder.
//
// Usage:
//   dart run tool/import_obsidian.dart <source-folder> [<target-folder>]
//
// Without a target folder only a dry-run report is printed.
import 'dart:io';

import 'package:ford/src/import/book_importer.dart';

Future<void> main(List<String> args) async {
  if (args.isEmpty || args.length > 2) {
    stderr.writeln(
      'Usage: dart run tool/import_obsidian.dart <source-folder> [<target-folder>]',
    );
    exit(64);
  }
  final imports = await BookImporter.dryRun(Directory(args[0]));
  var rows = 0, blank = 0, untranslated = 0, warnings = 0;
  for (final i in imports) {
    final segs = i.result.chapter.segments;
    final b = segs.where((s) => s.source.isEmpty && s.target.isEmpty).length;
    final u = segs.where((s) => s.source.isNotEmpty && s.target.isEmpty).length;
    rows += segs.length;
    blank += b;
    untranslated += u;
    warnings += i.result.warnings.length;
    stdout.writeln(
      '${i.sourceName.padRight(8)} -> ${i.targetName.padRight(8)} '
      '${segs.length.toString().padLeft(4)} rows, '
      '${b.toString().padLeft(3)} blank, '
      '${u.toString().padLeft(3)} untranslated  '
      '"${i.result.chapter.title ?? ''}"',
    );
    for (final w in i.result.warnings) {
      stdout.writeln('    ! $w');
    }
  }
  stdout.writeln(
    '\n${imports.length} chapters, $rows rows, $blank blank, '
    '$untranslated untranslated, $warnings warnings.',
  );
  if (args.length == 2) {
    await BookImporter.write(imports, Directory(args[1]));
    stdout.writeln('Written to ${args[1]}');
  } else {
    stdout.writeln('Dry run: nothing written.');
  }
}

