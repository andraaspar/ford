import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../folders/folder_tree.dart';
import '../folders/root_watch.dart';
import '../editing/chapter_autosaver.dart';
import '../editing/chapter_editor.dart';
import '../model/chapter_format.dart';
import '../search/text_search.dart';
import '../settings/app_settings.dart';
import 'chapter_view.dart';
import 'conflict_banner.dart';
import 'folder_dialogs.dart';
import 'move_rows.dart';
import 'row_menu.dart';
import 'search_screen.dart';

enum _ConflictChoice { keepMine, takeTheirs, saveCopy }

/// Loads one chapter file for editing, saving the text and the reading position
/// as they change.
///
/// Pops with a [SearchHit] when a search result in another chapter was tapped,
/// for that chapter to open next. There's never more than one of these screens,
/// because two editors on one file would overwrite each other.
class ChapterScreen extends StatefulWidget {
  const ChapterScreen({
    super.key,
    required this.entry,
    required this.rootPath,
    required this.settings,
    required this.search,
    this.match,
    this.watch,
  });

  final ChapterEntry entry;
  final String rootPath;
  final AppSettings settings;
  final SearchSession search;

  /// A search result to go to, instead of the place the user left off.
  final SearchHit? match;

  /// Tells when files under the root folder change.
  final RootWatch? watch;

  @override
  State<ChapterScreen> createState() => _ChapterScreenState();
}

class _ChapterScreenState extends State<ChapterScreen>
    with WidgetsBindingObserver {
  static const _saveDelay = Duration(milliseconds: 500);

  late final Future<void> _loaded = widget.entry.file.readAsString().then((
    text,
  ) {
    final parsed = ChapterFormat.parse(text);
    final editor = ChapterEditor(parsed.chapter);
    final saver = ChapterAutosaver(
      editor,
      widget.entry.file,
      diskText: text,
      warnings: parsed.warnings,
    );
    saver.addListener(_promptIfConflict);
    _editor = editor;
    _saver = saver;
    final match = widget.match;
    if (match != null) _showMatch(editor, match);
    if (_checkPending) _checkDisk();
  });

  ChapterEditor? _editor;
  ChapterAutosaver? _saver;
  Timer? _saveTimer;
  ReadingPosition? _unsaved;
  StreamSubscription<void>? _diskChanges;
  bool _checkPending = false;
  bool _prompting = false;

  String get _path => widget.entry.file.path;

  /// Whether nothing is open on top of this screen. A dialog or another screen
  /// may be working from the rows as they are now.
  bool get _isCurrent => ModalRoute.isCurrentOf(context) ?? true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _diskChanges = widget.watch?.changes.listen((_) => _checkDisk());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Also runs whenever something on top of this screen closes.
    if (_isCurrent) {
      scheduleMicrotask(() {
        if (!mounted) return;
        if (_checkPending) _checkDisk();
        _promptIfConflict();
      });
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_diskChanges?.cancel());
    _savePosition();
    final editor = _editor;
    final saver = _saver;
    if (editor != null && saver != null) {
      saver.removeListener(_promptIfConflict);
      unawaited(
        saver.flush().whenComplete(() {
          saver.dispose();
          editor.dispose();
        }),
      );
    }
    super.dispose();
  }

  // The app can be killed at any time once it's in the background, and the file
  // may have changed by the time it comes back.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkDisk();
    } else {
      _savePosition();
      unawaited(_saver?.flush());
    }
  }

  /// Follows changes to the file, once nothing is open on top of this screen.
  void _checkDisk() {
    final saver = _saver;
    if (saver == null || !mounted || !_isCurrent) {
      _checkPending = true;
      return;
    }
    _checkPending = false;
    unawaited(saver.checkDisk());
  }

  void _promptIfConflict() {
    final saver = _saver;
    final conflict = saver?.conflict;
    if (saver == null || conflict == null) return;
    if (_prompting || !mounted || !_isCurrent) return;
    _prompting = true;
    final prompt = conflict.isDeleted
        ? _promptDeleted(saver)
        : _promptChanged(saver);
    unawaited(prompt.whenComplete(() => _prompting = false));
  }

  Future<void> _promptChanged(ChapterAutosaver saver) async {
    final choice = await showDialog<_ConflictChoice>(
      context: context,
      barrierDismissible: false,
      builder: (context) => PopScope(
        canPop: false,
        child: AlertDialog(
          title: const Text('This chapter changed elsewhere'),
          content: const SingleChildScrollView(
            child: Text(
              'Another device or program changed this file while you had edits '
              'that weren\'t saved yet.\n\n'
              'Keep mine: your version replaces the other one.\n\n'
              'Take theirs: your latest edits are dropped, and undo history for '
              'this chapter ends here.\n\n'
              'Save mine as a copy: your version goes to a new file beside this '
              'one, and this chapter shows the other version.',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () =>
                  Navigator.of(context).pop(_ConflictChoice.saveCopy),
              child: const Text('Save mine as a copy'),
            ),
            TextButton(
              onPressed: () =>
                  Navigator.of(context).pop(_ConflictChoice.takeTheirs),
              child: const Text('Take theirs'),
            ),
            FilledButton(
              onPressed: () =>
                  Navigator.of(context).pop(_ConflictChoice.keepMine),
              child: const Text('Keep mine'),
            ),
          ],
        ),
      ),
    );
    switch (choice) {
      case _ConflictChoice.keepMine:
        unawaited(saver.keepMine());
      case _ConflictChoice.takeTheirs:
        saver.takeTheirs();
      case _ConflictChoice.saveCopy:
        await _saveCopy(saver);
      case null:
        break;
    }
  }

  Future<void> _saveCopy(ChapterAutosaver saver) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final name = await saver.saveMineAsCopy();
      messenger.showSnackBar(
        SnackBar(content: Text('Your version was saved as $name')),
      );
    } on Object catch (e) {
      if (!mounted) return;
      await showFolderError(context, e);
      // The question is still open. This runs once the current prompt has ended.
      scheduleMicrotask(_promptIfConflict);
    }
  }

  Future<void> _promptDeleted(ChapterAutosaver saver) async {
    final navigator = Navigator.of(context);
    final keep = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => PopScope(
        canPop: false,
        child: AlertDialog(
          title: const Text('This chapter\'s file is gone'),
          content: const SingleChildScrollView(
            child: Text(
              'Another device or program deleted or moved this file.\n\n'
              'Keep mine: the file is written again from what\'s open here.\n\n'
              'Close chapter: what\'s open here is dropped.',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Close chapter'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Keep mine'),
            ),
          ],
        ),
      ),
    );
    if (keep ?? false) {
      unawaited(saver.keepMine());
    } else {
      navigator.pop();
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
    final navigator = Navigator.of(context);
    if (await _mayLeave(saver)) navigator.pop();
  }

  /// Saves, and only allows leaving unsaved edits behind if the user says so.
  Future<bool> _mayLeave(ChapterAutosaver saver) async {
    await saver.flush();
    // The user has that question to answer first.
    if (saver.conflict != null) return false;
    if (saver.isUpToDate) return true;
    if (!mounted) return false;
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
    return leave ?? false;
  }

  Future<void> _search(ChapterEditor editor, ChapterAutosaver saver) async {
    final navigator = Navigator.of(context);
    final hit = await navigator.push<SearchHit>(
      MaterialPageRoute(
        builder: (_) => SearchScreen(
          rootPath: widget.rootPath,
          session: widget.search,
          chapterPath: _path,
          openChapter: editor.chapter,
        ),
      ),
    );
    if (hit == null || !mounted) return;
    if (hit.chapter.path == _path) {
      _showMatch(editor, hit);
    } else if (await _mayLeave(saver)) {
      navigator.pop(hit);
    }
  }

  void _showMatch(ChapterEditor editor, SearchHit hit) {
    final rows = editor.chapter.segments;
    final known = editor.chapter.indexOfId(hit.rowId) >= 0;
    if (!known && hit.rowIndex >= rows.length) return;
    final rowId = known ? hit.rowId : rows[hit.rowIndex].id;
    editor.showMark(TextMark(rowId, hit.field, hit.start, hit.end));
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder(
      future: _loaded,
      builder: (context, snapshot) {
        final editor = _editor;
        final saver = _saver;
        if (editor != null && saver != null) {
          return ListenableBuilder(
            listenable: Listenable.merge([editor, saver]),
            builder: (context, _) => _editorScreen(editor, saver),
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

  Widget _editorScreen(ChapterEditor editor, ChapterAutosaver saver) {
    final active = editor.active;
    final warnings = saver.warnings;
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
                      if (active == null)
                        IconButton(
                          tooltip: 'Search',
                          icon: const Icon(Icons.search),
                          onPressed: () => unawaited(_search(editor, saver)),
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
            body: Column(
              children: [
                Expanded(
                  child: ChapterView(
                    editor: editor,
                    initialPosition: widget.settings.position(_path),
                    onPositionChanged: _onPositionChanged,
                  ),
                ),
                // Below the list, so that the rows don't move when it appears.
                SafeArea(
                  top: false,
                  child: ConflictBanner(watch: widget.watch),
                ),
              ],
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
