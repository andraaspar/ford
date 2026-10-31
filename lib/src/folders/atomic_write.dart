import 'dart:io';

import 'package:path/path.dart' as p;

/// Syncthing or a crash must never see a half-written chapter, so the text goes
/// to a hidden temp file that then replaces the real one.
Future<void> writeAtomically(File file, String content) async {
  final temp = File(
    p.join(p.dirname(file.path), '.${p.basename(file.path)}.tmp'),
  );
  await temp.writeAsString(content, flush: true);
  await temp.rename(file.path);
}
