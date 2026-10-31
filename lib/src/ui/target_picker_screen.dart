import 'package:flutter/material.dart';

import '../folders/folder_ops.dart';
import '../folders/folder_tree.dart';
import '../folders/target_selection.dart';
import 'folder_dialogs.dart';
import 'tree_row.dart';

/// Picks any selection of folders and chapters, for actions such as search or
/// export. Pops with the paths of the chosen chapters.
class TargetPickerScreen extends StatefulWidget {
  const TargetPickerScreen({
    super.key,
    required this.rootPath,
    this.title = 'Choose folders and chapters',
    this.initial = const {},
  });

  final String rootPath;
  final String title;

  /// Chapter paths ticked to begin with.
  final Set<String> initial;

  @override
  State<TargetPickerScreen> createState() => _TargetPickerScreenState();
}

class _TargetPickerScreenState extends State<TargetPickerScreen> {
  late final Future<FolderEntry> _tree = FolderTree.load(widget.rootPath);
  late final _selection = TargetSelection(widget.initial);
  final _expanded = <String>{};

  void _toggleExpanded(FolderEntry folder) => setState(() {
    if (!_expanded.remove(folder.path)) _expanded.add(folder.path);
  });

  @override
  Widget build(BuildContext context) {
    final count = _selection.chapterPaths.length;
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: _TreeLoader(
        tree: _tree,
        builder: (root) {
          final rows = visibleRows(root, _expanded);
          return ListView.builder(
            itemCount: rows.length,
            itemBuilder: (context, index) {
              final (:entry, :depth) = rows[index];
              final tickable = switch (entry) {
                ChapterEntry() => true,
                FolderEntry() => entry.allChapters.isNotEmpty,
              };
              void toggle() => setState(() => _selection.toggle(entry));
              return TreeRow(
                entry: entry,
                depth: depth,
                isExpanded: _expanded.contains(entry.path),
                onToggleExpanded: () {
                  if (entry is FolderEntry) _toggleExpanded(entry);
                },
                trailing: Checkbox(
                  tristate: true,
                  value: _selection.stateOf(entry),
                  onChanged: tickable ? (_) => toggle() : null,
                ),
                onTap: tickable ? toggle : null,
              );
            },
          );
        },
      ),
      bottomNavigationBar: _BottomBar(
        children: [
          Expanded(child: Text(count == 1 ? '1 chapter' : '$count chapters')),
          FilledButton(
            onPressed: count == 0
                ? null
                : () => Navigator.of(context).pop(_selection.chapterPaths),
            child: const Text('Use these'),
          ),
        ],
      ),
    );
  }
}

/// Picks one folder, optionally creating it first. Pops with its path.
class DestinationPickerScreen extends StatefulWidget {
  const DestinationPickerScreen({
    super.key,
    required this.rootPath,
    required this.title,
    required this.action,
    this.isAllowed,
  });

  final String rootPath;
  final String title;

  /// What the confirming button says.
  final String action;

  /// Which folders can be chosen; all of them if null.
  final bool Function(FolderEntry folder)? isAllowed;

  @override
  State<DestinationPickerScreen> createState() =>
      _DestinationPickerScreenState();
}

class _DestinationPickerScreenState extends State<DestinationPickerScreen> {
  late Future<FolderEntry> _tree = FolderTree.load(widget.rootPath);
  final _expanded = <String>{};
  String? _selected;

  bool _allowed(FolderEntry folder) => widget.isAllowed?.call(folder) ?? true;

  Future<void> _createFolder(FolderEntry root) async {
    final found = _selected == null ? null : root.find(_selected!);
    final parent = found is FolderEntry ? found : root;
    final name = await showNameDialog(
      context,
      title: parent.isRoot ? 'New folder' : 'New folder in "${parent.label}"',
      action: 'Create',
    );
    if (name == null) return;
    try {
      final path = await FolderOps.createFolder(
        parent,
        name.source,
        name.target,
      );
      final tree = FolderTree.load(widget.rootPath);
      await tree;
      if (!mounted) return;
      setState(() {
        _tree = tree;
        _selected = path;
        expandAround(parent, _expanded);
        _expanded.add(parent.path);
      });
    } on Object catch (e) {
      if (mounted) await showFolderError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    return _TreeLoader(
      tree: _tree,
      scaffoldTitle: widget.title,
      builder: (root) {
        final rows = visibleRows(root, _expanded, foldersOnly: true);
        final selected = _selected;
        return Scaffold(
          appBar: AppBar(title: Text(widget.title)),
          body: ListView(
            children: [
              ListTile(
                contentPadding: const EdgeInsetsDirectional.only(
                  start: 8,
                  end: 8,
                ),
                leading: const SizedBox(
                  width: 40,
                  child: Icon(Icons.home_outlined),
                ),
                title: const Text('Root folder'),
                subtitle: Text(root.diskName),
                enabled: _allowed(root),
                selected: selected == root.path,
                onTap: () => setState(() => _selected = root.path),
              ),
              for (final (:entry, :depth) in rows)
                TreeRow(
                  entry: entry,
                  depth: depth + 1,
                  isExpanded: _expanded.contains(entry.path),
                  showFolderContents: false,
                  onToggleExpanded: () => setState(() {
                    if (!_expanded.remove(entry.path)) {
                      _expanded.add(entry.path);
                    }
                  }),
                  enabled: _allowed(entry as FolderEntry),
                  selected: selected == entry.path,
                  onTap: () => setState(() => _selected = entry.path),
                ),
            ],
          ),
          bottomNavigationBar: _BottomBar(
            children: [
              OutlinedButton(
                onPressed: () => _createFolder(root),
                child: const Text('New folder'),
              ),
              const Spacer(),
              FilledButton(
                onPressed: selected == null
                    ? null
                    : () => Navigator.of(context).pop(selected),
                child: Text(widget.action),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Shows the tree once it has loaded. With [scaffoldTitle] it also provides the
/// screen around the loading and error states.
class _TreeLoader extends StatelessWidget {
  const _TreeLoader({
    required this.tree,
    required this.builder,
    this.scaffoldTitle,
  });

  final Future<FolderEntry> tree;
  final Widget Function(FolderEntry root) builder;
  final String? scaffoldTitle;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder(
      future: tree,
      builder: (context, snapshot) {
        final root = snapshot.data;
        if (root != null) return builder(root);
        final Widget state = snapshot.hasError
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Text('Can\'t read this folder: ${snapshot.error}'),
                ),
              )
            : const Center(child: CircularProgressIndicator());
        final title = scaffoldTitle;
        return title == null
            ? state
            : Scaffold(
                appBar: AppBar(title: Text(title)),
                body: state,
              );
      },
    );
  }
}

class _BottomBar extends StatelessWidget {
  const _BottomBar({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(
            top: BorderSide(color: Theme.of(context).dividerColor),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(children: children),
        ),
      ),
    );
  }
}
