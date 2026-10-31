import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../folders/folder_tree.dart';
import '../editing/chapter_autosaver.dart';
import '../editing/chapter_editor.dart';
import '../model/chapter_format.dart';
import '../settings/app_settings.dart';
import 'chapter_view.dart';
import 'move_rows.dart';
import 'row_menu.dart';

/// Loads one chapter file for editing, saving the text and the reading position
/// as they change.
class ChapterScreen extends StatefulWidget {
  const ChapterScreen({
    super.key,
    required this.entry,
    required this.rootPath,
    required this.settings,
  });

  final ChapterEntry entry;
  final String rootPath;
  final AppSettings settings;

  @override
  State<ChapterScreen> createState() => _ChapterScreenState();
}

class _ChapterScreenState extends State<ChapterScreen>
    with WidgetsBindingObserver {
  static const _saveDelay = Duration(milliseconds: 500);

  late final Future<ParseResult> _loaded = widget.entry.file
      .readAsString()
      .then(ChapterFormat.parse)
      .then((parsed) {
        final editor = ChapterEditor(parsed.chapter);
        _editor = editor;
        _saver = ChapterAutosaver(editor, widget.entry.file);
        return parsed;
      });

  ChapterEditor? _editor;
  ChapterAutosaver? _saver;
  Timer? _saveTimer;
  ReadingPosition? _unsaved;

  String get _path => widget.entry.file.path;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _savePosition();
    final editor = _editor;
    final saver = _saver;
    if (editor != null && saver != null) {
      unawaited(
        saver.flush().whenComplete(() {
          saver.dispose();
          editor.dispose();
        }),
      );
    }
    super.dispose();
  }

  // The app can be killed at any time once it's in the background.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      _savePosition();
      unawaited(_saver?.flush());
    }
  }

  void _onPositionChanged(ReadingPosition position) {
    _unsaved = position;
    _saveTimer?.cancel();
    _saveTimer = Timer(_saveDelay, _savePosition);
  }

  void _savePosition() {
    _saveTimer?.cancel();
    final position = _unsaved;
    if (position == null) return;
    _unsaved = null;
    unawaited(widget.settings.setPosition(_path, position));
  }

  void _showWarnings(List<String> warnings) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Repaired while reading'),
        content: SingleChildScrollView(child: Text(warnings.join('\n'))),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  void _showSaveError(ChapterAutosaver saver) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Can\'t save this chapter'),
        content: SingleChildScrollView(
          child: Text(
            'Your edits are kept here while the app stays open.\n\n'
            '${saver.error}',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.of(context).pop();
              unawaited(saver.flush());
            },
            child: const Text('Try again'),
          ),
        ],
      ),
    );
  }

  /// Handles Back while leaving isn't simply safe: it first ends selecting or
  /// closes the active cell, then saves, and only leaves unsaved edits behind if
  /// the user says so.
  Future<void> _onBackBlocked(
    ChapterEditor editor,
    ChapterAutosaver saver,
  ) async {
    if (editor.isSelecting) {
      editor.clearSelection();
      return;
    }
    if (editor.active != null) {
      editor.deactivate();
      return;
    }
    await saver.flush();
    if (!mounted) return;
    final navigator = Navigator.of(context);
    if (saver.isUpToDate) {
      navigator.pop();
      return;
    }
    final leave = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Leave without saving?'),
        content: SingleChildScrollView(
          child: Text(
            'This chapter can\'t be saved, so your latest edits would be '
            'lost.\n\n${saver.error}',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Discard edits'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Stay'),
          ),
        ],
      ),
    );
    if (leave ?? false) navigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder(
      future: _loaded,
      builder: (context, snapshot) {
        final parsed = snapshot.data;
        final editor = _editor;
        final saver = _saver;
        if (parsed != null && editor != null && saver != null) {
          return ListenableBuilder(
            listenable: Listenable.merge([editor, saver]),
            builder: (context, _) =>
                _editorScreen(editor, saver, parsed.warnings),
          );
        }
        return Scaffold(
          appBar: AppBar(title: Text(widget.entry.fileName)),
          body: snapshot.hasError
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Text(
                      'Can\'t read ${widget.entry.fileName}: ${snapshot.error}',
                    ),
                  ),
                )
              : const Center(child: CircularProgressIndicator()),
        );
      },
    );
  }

  Widget _editorScreen(
    ChapterEditor editor,
    ChapterAutosaver saver,
    List<String> warnings,
  ) {
    final active = editor.active;
    return PopScope(
      canPop: active == null && !editor.isSelecting && saver.isUpToDate,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) unawaited(_onBackBlocked(editor, saver));
      },
      child: CallbackShortcuts(
        // Closer to the text field than Flutter's own undo shortcuts, which
        // would only undo typing in the current cell.
        bindings: {
          const SingleActivator(LogicalKeyboardKey.keyZ, control: true):
              editor.undo,
          const SingleActivator(LogicalKeyboardKey.keyY, control: true):
              editor.redo,
          const SingleActivator(
            LogicalKeyboardKey.keyZ,
            control: true,
            shift: true,
          ): editor.redo,
          const SingleActivator(LogicalKeyboardKey.escape): () {
            editor.clearSelection();
            editor.deactivate();
          },
        },
        child: Focus(
          autofocus: true,
          child: Scaffold(
            // The keyboard slides over the list. Resizing the list for each step
            // of its animation would lay out many rows per frame, which is slow
            // on a phone.
            resizeToAvoidBottomInset: false,
            appBar: editor.isSelecting
                ? _selectionBar(editor, saver)
                : AppBar(
                    title: Text(
                      editor.chapter.title ?? widget.entry.fileName,
                      overflow: TextOverflow.ellipsis,
                    ),
                    actions: [
                      if (saver.error != null)
                        IconButton(
                          tooltip: 'Can\'t save this chapter',
                          icon: Icon(
                            Icons.sync_problem,
                            color: Theme.of(context).colorScheme.error,
                          ),
                          onPressed: () => _showSaveError(saver),
                        ),
                      if (warnings.isNotEmpty)
                        IconButton(
                          tooltip: 'Repairs made while reading this file',
                          icon: const Icon(Icons.warning_amber),
                          onPressed: () => _showWarnings(warnings),
                        ),
                      IconButton(
                        tooltip: 'Undo',
                        icon: const Icon(Icons.undo),
                        onPressed: editor.canUndo ? editor.undo : null,
                      ),
                      IconButton(
                        tooltip: 'Redo',
                        icon: const Icon(Icons.redo),
                        onPressed: editor.canRedo ? editor.redo : null,
                      ),
                      if (active != null) ...[
                        IconButton(
                          tooltip: 'Row actions',
                          icon: const Icon(Icons.more_vert),
                          onPressed: () =>
                              showRowMenu(context, editor, active.rowId),
                        ),
                        IconButton(
                          tooltip: 'Finish editing',
                          icon: const Icon(Icons.check),
                          onPressed: editor.deactivate,
                        ),
                      ],
                    ],
                  ),
            body: ChapterView(
              editor: editor,
              initialPosition: widget.settings.position(_path),
              onPositionChanged: _onPositionChanged,
            ),
          ),
        ),
      ),
    );
  }

  PreferredSizeWidget _selectionBar(
    ChapterEditor editor,
    ChapterAutosaver saver,
  ) {
    return AppBar(
      leading: IconButton(
        tooltip: 'Cancel selection',
        icon: const Icon(Icons.close),
        onPressed: editor.clearSelection,
      ),
      title: Text('${editor.selectedCount} selected'),
      actions: [
        IconButton(
          tooltip: 'Move up',
          icon: const Icon(Icons.arrow_upward),
          onPressed: editor.canMoveSelectedUp ? editor.moveSelectedUp : null,
        ),
        IconButton(
          tooltip: 'Move down',
          icon: const Icon(Icons.arrow_downward),
          onPressed: editor.canMoveSelectedDown
              ? editor.moveSelectedDown
              : null,
        ),
        IconButton(
          tooltip: 'Move within this chapter',
          icon: const Icon(Icons.swap_vert),
          onPressed: editor.selectedCount < editor.chapter.length
              ? () => unawaited(moveSelectedRowsWithin(context, editor))
              : null,
        ),
        IconButton(
          tooltip: 'Move to another chapter',
          icon: const Icon(Icons.drive_file_move_outline),
          onPressed: () => unawaited(
            moveSelectedRows(
              context,
              editor: editor,
              saver: saver,
              rootPath: widget.rootPath,
              currentPath: _path,
            ),
          ),
        ),
      ],
    );
  }
}
