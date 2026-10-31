import 'dart:async';

import 'package:flutter/material.dart';

import '../editing/chapter_autosaver.dart';
import '../editing/chapter_editor.dart';
import '../folders/folder_ops.dart';
import '../folders/folder_tree.dart';
import '../model/chapter.dart';
import '../model/segment.dart';
import 'folder_dialogs.dart';
import 'target_picker_screen.dart';

String rowCountLabel(int count) => count == 1 ? '1 row' : '$count rows';

/// Moves the selected rows to a place in another chapter that the user picks.
///
/// The other file is written first. If the app stops right after that, the rows
/// are in both chapters, rather than in neither.
Future<void> moveSelectedRows(
  BuildContext context, {
  required ChapterEditor editor,
  required ChapterAutosaver saver,
  required String rootPath,
  required String currentPath,
}) async {
  final count = rowCountLabel(editor.selectedCount);
  final navigator = Navigator.of(context);
  final messenger = ScaffoldMessenger.of(context);

  ChapterEntry destination;
  RowPlacement placement;
  while (true) {
    final chapter = await navigator.push<ChapterEntry>(
      MaterialPageRoute(
        builder: (_) => ChapterPickerScreen(
          rootPath: rootPath,
          currentPath: currentPath,
          title: 'Move $count to',
        ),
      ),
    );
    if (chapter == null) return;
    final place = await navigator.push<RowPlacement>(
      MaterialPageRoute(
        builder: (_) => RowPlacementScreen.intoFile(
          file: chapter.file,
          title: 'Place in "${chapter.label}"',
        ),
      ),
    );
    // Back from here goes back to choosing the chapter.
    if (place == null) continue;
    destination = chapter;
    placement = place;
    break;
  }
  if (!context.mounted) return;

  final rows = editor.selectedRows;
  final left = editor.chapterWithoutSelected;
  final movesTitle = rows.first.id == editor.chapter.segments.first.id;
  final destinationHasRows = destination.rowCount > 0;
  // At the start of a chapter, the first moved row takes over as its title.
  final givesTitle =
      placement.afterRowId == null && (destinationHasRows || movesTitle);
  final changes = _folderNameChanges(
    destination,
    currentPath,
    currentLeft: movesTitle ? left : null,
    destinationFirstRow: givesTitle ? rows.first : null,
  );
  if (!await confirmNameChanges(context, changes)) return;
  if (!context.mounted) return;

  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text('Move $count?'),
      content: Text(
        'To "${destination.label}", ${placement.description}.\n\n'
        '${movesTitle ? '${_titleNote(left)}\n\n' : ''}'
        '${givesTitle && destinationHasRows ? '${_destinationTitleNote(rows.first)}\n\n' : ''}'
        'Undo can\'t reverse this, and undo history for this chapter ends here. '
        'You can move the rows back the same way.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Move'),
        ),
      ],
    ),
  );
  if (!(confirmed ?? false)) return;

  try {
    await FolderOps.insertRows(
      destination.file,
      rows,
      afterRowId: placement.afterRowId,
      firstIsTitle: movesTitle,
    );
  } on Object catch (e) {
    if (context.mounted) await showFolderError(context, e);
    return;
  }
  editor.removeSelectedAfterMove();
  unawaited(saver.flush());
  messenger.showSnackBar(
    SnackBar(content: Text('Moved $count to "${destination.label}"')),
  );
}

/// Moves the selected rows to a place in this chapter that the user picks. Undo
/// reverses this like any other row operation.
Future<void> moveSelectedRowsWithin(
  BuildContext context,
  ChapterEditor editor,
) async {
  final placement = await Navigator.of(context).push<RowPlacement>(
    MaterialPageRoute(
      builder: (_) => RowPlacementScreen.within(
        chapter: editor.chapter,
        moving: editor.selectedRows.map((s) => s.id).toSet(),
        title:
            'Move ${rowCountLabel(editor.selectedCount)} within this chapter',
      ),
    ),
  );
  if (placement != null) editor.moveSelectedAfter(placement.afterRowId);
}

/// What moving the title row does to the current chapter's title.
String _titleNote(Chapter left) {
  if (left.isEmpty) return 'This chapter will have no rows left.';
  final title = left.title;
  return title == null
      ? 'This chapter\'s title row moves, and the first row left is blank, so '
            'the chapter will have no title.'
      : 'This chapter\'s title row moves, so "$title" becomes its title.';
}

/// What placing [row] before another chapter's title does to that chapter.
String _destinationTitleNote(Segment row) {
  final title = Chapter([row]).title;
  return title == null
      ? 'The first moved row is blank, so that chapter will have no title.'
      : '"$title" becomes that chapter\'s title.';
}

/// The folders whose names change with the moved rows. [currentLeft] is what's
/// left of the current chapter if its title row moves, and [destinationFirstRow]
/// is the row that becomes the destination's title, if one does.
List<NameChange> _folderNameChanges(
  ChapterEntry destination,
  String currentPath, {
  Chapter? currentLeft,
  Segment? destinationFirstRow,
}) {
  var root = destination.parent;
  while (root?.parent != null) {
    root = root?.parent;
  }
  final current = root?.find(currentPath);
  return [
    if (currentLeft != null && current is ChapterEntry)
      ...FolderOps.nameChangesForTitle(current, currentLeft.title),
    if (destinationFirstRow != null)
      ...FolderOps.nameChangesForTitle(
        destination,
        Chapter([destinationFirstRow]).title,
      ),
  ];
}
