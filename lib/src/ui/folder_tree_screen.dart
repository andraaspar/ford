import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../folders/folder_ops.dart';
import '../folders/folder_tree.dart';
import '../settings/app_settings.dart';
import 'chapter_screen.dart';
import 'folder_dialogs.dart';
import 'reorder_screen.dart';
import 'target_picker_screen.dart';
import 'tree_row.dart';

/// The tree of folders and chapters, where they are opened and organized.
///
/// A chapter's screen covers this one and only closes once its edits are saved,
/// so everything done here starts from what's on disk.
class FolderTreeScreen extends StatefulWidget {
  const FolderTreeScreen({
    super.key,
    required this.rootPath,
    required this.settings,
    required this.onChangeRoot,
  });

  final String rootPath;
  final AppSettings settings;
  final VoidCallback onChangeRoot;

  @override
  State<FolderTreeScreen> createState() => _FolderTreeScreenState();
}

class _FolderTreeScreenState extends State<FolderTreeScreen> {
  late Future<FolderEntry> _tree = FolderTree.load(widget.rootPath);
  final _expanded = <String>{};

  @override
  void initState() {
    super.initState();
    _resumeLastChapter();
  }

  /// Goes straight back to the chapter being read. If it's gone or can't be
  /// read, the user simply stays on the tree.
  Future<void> _resumeLastChapter() async {
    final last = widget.settings.lastChapter(widget.rootPath);
    final FolderEntry root;
    try {
      root = await _tree;
    } on FileSystemException {
      return; // The screen shows this error.
    }
    if (last == null || !mounted) return;
    final entry = root.find(p.join(widget.rootPath, last));
    if (entry is! ChapterEntry) return;
    setState(() => expandAround(entry, _expanded));
    if (entry.error == null) await _open(entry);
  }

  Future<void> _reload() async {
    final next = FolderTree.load(widget.rootPath);
    setState(() {
      _tree = next;
    });
    await next;
  }

  Future<void> _reloadQuietly() async {
    try {
      await _reload();
    } on FileSystemException {
      return; // The screen shows this error.
    }
  }

  Future<void> _open(ChapterEntry entry) async {
    await widget.settings.setLastChapter(
      widget.rootPath,
      p.relative(entry.path, from: widget.rootPath),
    );
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ChapterScreen(
          entry: entry,
          rootPath: widget.rootPath,
          settings: widget.settings,
        ),
      ),
    );
    if (!mounted) return;
    // The last-read marker may have moved, and the title may have been edited.
    await _reloadQuietly();
  }

  /// Runs an action, then shows the tree as it now is, whether or not it worked.
  Future<void> _run(Future<void> Function() action) async {
    try {
      await action();
    } on Object catch (e) {
      if (mounted) await showFolderError(context, e);
    }
    if (mounted) await _reloadQuietly();
  }

  Future<void> _applyMoves(Map<String, String> moves) async {
    await widget.settings.relocate(moves);
    final expanded = [
      for (final path in _expanded) movedPath(path, moves) ?? path,
    ];
    _expanded
      ..clear()
      ..addAll(expanded);
  }

  Future<void> _createFolder(FolderEntry parent) async {
    final name = await showNameDialog(
      context,
      title: parent.isRoot ? 'New folder' : 'New folder in "${parent.label}"',
      action: 'Create',
    );
    if (name == null) return;
    _expanded.add(parent.path);
    await _run(() => FolderOps.createFolder(parent, name.source, name.target));
  }

  Future<void> _createChapter(FolderEntry parent) async {
    final name = await showNameDialog(
      context,
      title: parent.isRoot ? 'New chapter' : 'New chapter in "${parent.label}"',
      action: 'Create',
    );
    if (name == null || !mounted) return;
    final title = name.source.isNotEmpty ? name.source : name.target;
    final changes = FolderOps.nameChangesForNewChapter(parent, title);
    if (!await confirmNameChanges(context, changes)) return;
    _expanded.add(parent.path);
    await _run(() => FolderOps.createChapter(parent, name.source, name.target));
  }

  Future<void> _editName(FolderEntry folder) async {
    final first = folder.firstChapter;
    final ({String source, String target})? current;
    try {
      current = first == null ? null : await FolderOps.readTitleRow(first);
    } on Object catch (e) {
      if (mounted) await showFolderError(context, e);
      return;
    }
    if (!mounted) return;
    final name = await showNameDialog(
      context,
      title: 'Folder name',
      action: 'Save',
      source: current?.source ?? '',
      target: current?.target ?? '',
      note: first != null && first.rowCount > 1
          ? 'This also changes the title of chapter ${first.fileName}. '
                'To keep that title, use Add name instead.'
          : null,
    );
    if (name == null) return;
    await _run(() => FolderOps.editName(folder, name.source, name.target));
  }

  Future<void> _addName(FolderEntry folder) async {
    final name = await showNameDialog(
      context,
      title: 'Add a folder name',
      action: 'Add',
      note:
          'This adds a new first file with this name, so the title of '
          'chapter ${folder.firstChapter?.fileName} stays as it is.',
    );
    if (name == null) return;
    await _run(() async {
      await _applyMoves(
        await FolderOps.addName(folder, name.source, name.target),
      );
    });
  }

  Future<void> _reorder(FolderEntry folder) async {
    final order = await Navigator.of(context).push<List<TreeEntry>>(
      MaterialPageRoute(builder: (_) => ReorderScreen(folder: folder)),
    );
    if (order == null || !mounted) return;
    final changes = FolderOps.nameChangesForReorder(folder, order);
    if (!await confirmNameChanges(context, changes)) return;
    await _run(() async {
      await _applyMoves(await FolderOps.reorder(folder, order));
    });
  }

  Future<void> _move(TreeEntry entry) async {
    final path = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => DestinationPickerScreen(
          rootPath: widget.rootPath,
          title: 'Move "${entry.label}"',
          action: 'Move here',
          isAllowed: (folder) =>
              folder.path != entry.parent?.path &&
              folder.path != entry.path &&
              !p.isWithin(entry.path, folder.path),
        ),
      ),
    );
    if (path == null || !mounted) return;
    // The picker may have just created this folder, so look at the disk.
    await _run(() async {
      final root = await FolderTree.load(widget.rootPath);
      final fresh = root.find(entry.path);
      final destination = root.find(path);
      if (fresh == null || destination is! FolderEntry) {
        throw FileSystemException(
          'Not found',
          fresh == null ? entry.path : path,
        );
      }
      if (!mounted) return;
      final changes = FolderOps.nameChangesForMove(fresh, destination);
      if (!await confirmNameChanges(context, changes)) return;
      await _applyMoves(await FolderOps.move(fresh, destination));
      _expanded.add(destination.path);
      expandAround(destination, _expanded);
    });
  }

  Future<void> _delete(TreeEntry entry) async {
    await _run(() async {
      switch (entry) {
        case ChapterEntry():
          final changes = FolderOps.nameChangesForDelete(entry);
          final confirmed = await confirmDeletion(
            context,
            title: 'Delete chapter "${entry.label}"?',
            details: [
              'This deletes ${entry.fileName}.',
              for (final change in changes)
                'The folder "${change.from}" would show as "${change.to}".',
              _syncthingNote,
            ],
          );
          if (!confirmed) return;
        case FolderEntry():
          final summary = await FolderOps.summarizeDeletion(entry);
          if (!mounted) return;
          final confirmed = await confirmDeletion(
            context,
            title: 'Delete folder "${entry.label}"?',
            details: [_describe(summary), _syncthingNote],
          );
          if (!confirmed) return;
      }
      await FolderOps.delete(entry);
      await widget.settings.forget(entry.path);
    });
  }

  static const _syncthingNote =
      'Syncthing passes the deletion on to your other devices.';

  static String _describe(DeletionSummary summary) {
    String count(int n, String one, String many) => '$n ${n == 1 ? one : many}';
    final parts = [
      count(summary.chapters, 'chapter', 'chapters'),
      count(summary.folders, 'nested folder', 'nested folders'),
      if (summary.otherFiles > 0)
        count(summary.otherFiles, 'other file', 'other files'),
    ];
    final last = parts.removeLast();
    return 'This deletes ${parts.join(', ')} and $last.';
  }

  Future<void> _showMenu(TreeEntry entry) async {
    final action = await showModalBottomSheet<VoidCallback>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) {
        Widget item(IconData icon, String label, VoidCallback action) =>
            ListTile(
              leading: Icon(icon),
              title: Text(label),
              onTap: () => Navigator.of(context).pop(action),
            );
        final parent = entry.parent;
        return SafeArea(
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (entry case final FolderEntry folder) ...[
                  item(
                    Icons.note_add_outlined,
                    'New chapter',
                    () => _createChapter(folder),
                  ),
                  item(
                    Icons.create_new_folder_outlined,
                    'New folder',
                    () => _createFolder(folder),
                  ),
                  if (!folder.isRoot) ...[
                    item(
                      Icons.edit_outlined,
                      'Edit name',
                      () => _editName(folder),
                    ),
                    if ((folder.firstChapter?.rowCount ?? 0) > 1)
                      item(
                        Icons.label_outline,
                        'Add name',
                        () => _addName(folder),
                      ),
                  ],
                  if (folder.children.length > 1)
                    item(
                      Icons.low_priority,
                      'Reorder contents',
                      () => _reorder(folder),
                    ),
                ],
                if (parent != null) ...[
                  if (parent.children.length > 1)
                    item(
                      Icons.swap_vert,
                      'Reorder with neighbours',
                      () => _reorder(parent),
                    ),
                  item(
                    Icons.drive_file_move_outline,
                    'Move to…',
                    () => _move(entry),
                  ),
                  item(Icons.delete_outline, 'Delete…', () => _delete(entry)),
                ],
              ],
            ),
          ),
        );
      },
    );
    action?.call();
  }

  void _toggleExpanded(FolderEntry folder) => setState(() {
    if (!_expanded.remove(folder.path)) _expanded.add(folder.path);
  });

  @override
  Widget build(BuildContext context) {
    final last = widget.settings.lastChapter(widget.rootPath);
    final lastPath = last == null ? null : p.join(widget.rootPath, last);
    return FutureBuilder(
      future: _tree,
      builder: (context, snapshot) {
        final root = snapshot.data;
        return Scaffold(
          appBar: AppBar(
            title: Text(p.basename(widget.rootPath)),
            actions: [
              IconButton(
                tooltip: 'Choose another root folder',
                icon: const Icon(Icons.folder_open_outlined),
                onPressed: widget.onChangeRoot,
              ),
              if (root != null)
                IconButton(
                  tooltip: 'Root folder actions',
                  icon: const Icon(Icons.more_vert),
                  onPressed: () => _showMenu(root),
                ),
            ],
          ),
          body: _body(snapshot, lastPath),
        );
      },
    );
  }

  Widget _body(AsyncSnapshot<FolderEntry> snapshot, String? lastPath) {
    if (snapshot.hasError) {
      return _Message(
        'Can\'t read this folder: ${snapshot.error}',
        onRetry: _reloadQuietly,
      );
    }
    final root = snapshot.data;
    if (root == null) return const Center(child: CircularProgressIndicator());
    if (root.children.isEmpty) {
      return _Message(
        'Nothing here yet. Use ⋮ above to add a folder or chapter.',
        onRetry: _reloadQuietly,
      );
    }
    final rows = visibleRows(root, _expanded);
    return RefreshIndicator(
      onRefresh: _reload,
      child: ListView.builder(
        itemCount: rows.length,
        itemBuilder: (context, index) {
          final (:entry, :depth) = rows[index];
          return TreeRow(
            key: ValueKey(entry.path),
            entry: entry,
            depth: depth,
            isExpanded: _expanded.contains(entry.path),
            onToggleExpanded: () {
              if (entry is FolderEntry) _toggleExpanded(entry);
            },
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (entry.path == lastPath)
                  const Icon(Icons.bookmark, semanticLabel: 'Last read'),
                IconButton(
                  tooltip: 'Actions',
                  icon: const Icon(Icons.more_vert),
                  onPressed: () => _showMenu(entry),
                ),
              ],
            ),
            onTap: () {
              switch (entry) {
                case ChapterEntry():
                  _open(entry);
                case FolderEntry():
                  _toggleExpanded(entry);
              }
            },
            onLongPress: () => _showMenu(entry),
            onSecondaryTap: () => _showMenu(entry),
          );
        },
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message(this.text, {required this.onRetry});

  final String text;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(text, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            OutlinedButton(onPressed: onRetry, child: const Text('Try again')),
          ],
        ),
      ),
    );
  }
}
