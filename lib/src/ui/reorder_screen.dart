import 'package:flutter/material.dart';

import '../folders/folder_tree.dart';
import 'tree_row.dart';

/// Lets the user drag a folder's contents into a new order. Pops with that order
/// if it changed; Back leaves everything as it was.
class ReorderScreen extends StatefulWidget {
  const ReorderScreen({super.key, required this.folder});

  final FolderEntry folder;

  @override
  State<ReorderScreen> createState() => _ReorderScreenState();
}

class _ReorderScreenState extends State<ReorderScreen> {
  late final _order = [...widget.folder.children];

  bool get _changed {
    final children = widget.folder.children;
    for (var i = 0; i < children.length; i++) {
      if (children[i] != _order[i]) return true;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.folder.label, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            tooltip: 'Save this order',
            icon: const Icon(Icons.check),
            onPressed: _changed
                ? () => Navigator.of(context).pop(_order)
                : null,
          ),
        ],
      ),
      body: ReorderableListView.builder(
        buildDefaultDragHandles: false,
        itemCount: _order.length,
        onReorderItem: (oldIndex, newIndex) => setState(() {
          _order.insert(newIndex, _order.removeAt(oldIndex));
        }),
        itemBuilder: (context, index) {
          final entry = _order[index];
          return ListTile(
            key: ValueKey(entry.path),
            leading: Icon(switch (entry) {
              ChapterEntry() => Icons.description_outlined,
              FolderEntry() => Icons.folder_outlined,
            }),
            title: Text(entry.label, overflow: TextOverflow.ellipsis),
            subtitle: Text(switch (entry) {
              ChapterEntry() => chapterSubtitle(entry),
              FolderEntry() => folderSubtitle(entry),
            }, overflow: TextOverflow.ellipsis),
            trailing: ReorderableDragStartListener(
              index: index,
              child: const Padding(
                padding: EdgeInsets.all(8),
                child: Icon(Icons.drag_handle),
              ),
            ),
          );
        },
      ),
    );
  }
}
