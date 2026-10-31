import 'package:flutter/material.dart';

import '../editing/chapter_editor.dart';

/// Shows the operations for one row.
Future<void> showRowMenu(
  BuildContext context,
  ChapterEditor editor,
  String rowId,
) async {
  final action = await showModalBottomSheet<VoidCallback>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (context) => _RowMenu(editor: editor, rowId: rowId),
  );
  action?.call();
}

class _RowMenu extends StatelessWidget {
  const _RowMenu({required this.editor, required this.rowId});

  final ChapterEditor editor;
  final String rowId;

  @override
  Widget build(BuildContext context) {
    final index = editor.chapter.indexOfId(rowId);
    final segment = editor.chapter.segments[index];
    final active = editor.active;
    final canSplit = active?.rowId == rowId && active?.field.side != null;

    Widget item(IconData icon, String label, VoidCallback? action) => ListTile(
      leading: Icon(icon),
      title: Text(label),
      enabled: action != null,
      onTap: () => Navigator.of(context).pop(action),
    );

    return SafeArea(
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            item(
              Icons.vertical_split_outlined,
              'Split at cursor',
              canSplit ? editor.splitAtCaret : null,
            ),
            item(
              Icons.vertical_align_top,
              'Insert blank row above',
              // Nothing goes above the title row.
              index > 0 ? () => editor.insertBlank(index) : null,
            ),
            item(
              Icons.vertical_align_bottom,
              'Insert blank row below',
              () => editor.insertBlank(index + 1),
            ),
            item(
              Icons.comment_outlined,
              segment.hasRemark ? 'Edit remark' : 'Add remark',
              () => editor.activate(rowId, .remark),
            ),
            item(
              Icons.delete_outline,
              'Delete row',
              () => editor.delete(rowId),
            ),
            item(
              Icons.checklist,
              'Select rows',
              () => editor.startSelecting(rowId),
            ),
          ],
        ),
      ),
    );
  }
}

/// Merges the active row into the one above it. Asks first if that also moves
/// text on the other side.
Future<void> mergeWithPrevious(
  BuildContext context,
  ChapterEditor editor,
) async {
  if (!editor.canMergeActiveWithPrevious) return;
  if (editor.activeMergeMovesOtherSide) {
    final confirmed = await showDialog<bool>(
      context: context,
      // The dialog takes the focus, which closes the keyboard. It shouldn't move
      // while that happens.
      builder: (context) => MediaQuery.removeViewInsets(
        context: context,
        removeBottom: true,
        child: AlertDialog(
          title: const Text('Merge with the previous row?'),
          content: const Text(
            'Both sides and the remarks of the two rows are merged into one.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Merge'),
            ),
          ],
        ),
      ),
    );
    if (!(confirmed ?? false)) return;
  }
  editor.mergeActiveWithPrevious();
}
