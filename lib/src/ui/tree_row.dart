import 'dart:math';

import 'package:flutter/material.dart';

import '../folders/folder_tree.dart';

/// One visible row of a tree, at its nesting depth.
typedef VisibleRow = ({TreeEntry entry, int depth});

/// The rows of [folder]'s contents that show given which folders are [expanded].
List<VisibleRow> visibleRows(
  FolderEntry folder,
  Set<String> expanded, {
  bool foldersOnly = false,
  int depth = 0,
}) => [
  for (final child in folder.children)
    if (!foldersOnly || child is FolderEntry) ...[
      (entry: child, depth: depth),
      if (child is FolderEntry && expanded.contains(child.path))
        ...visibleRows(
          child,
          expanded,
          foldersOnly: foldersOnly,
          depth: depth + 1,
        ),
    ],
];

/// Adds the folders around [entry] to [expanded], so that it shows.
void expandAround(TreeEntry entry, Set<String> expanded) {
  for (var folder = entry.parent; folder != null; folder = folder.parent) {
    expanded.add(folder.path);
  }
}

/// What a folder's row says below its name.
String folderSubtitle(FolderEntry folder) {
  if (folder.error != null) {
    return '${folder.diskName}: can\'t read this folder';
  }
  return folder.isUnnamed ? 'Unnamed folder' : folder.diskName;
}

/// What a chapter's row says below its title.
String chapterSubtitle(ChapterEntry chapter) => chapter.error == null
    ? chapter.fileName
    : '${chapter.fileName}: can\'t read this file';

/// A row of a tree of folders and chapters, for the chapter tree and the target
/// pickers alike.
class TreeRow extends StatelessWidget {
  const TreeRow({
    super.key,
    required this.entry,
    required this.depth,
    required this.isExpanded,
    required this.onToggleExpanded,
    this.showFolderContents = true,
    this.enabled = true,
    this.selected = false,
    this.trailing,
    this.onTap,
    this.onLongPress,
    this.onSecondaryTap,
  });

  final TreeEntry entry;
  final int depth;
  final bool isExpanded;
  final VoidCallback onToggleExpanded;

  /// Whether a folder's chapters count as something to expand it for.
  final bool showFolderContents;
  final bool enabled;
  final bool selected;
  final Widget? trailing;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final VoidCallback? onSecondaryTap;

  /// Beyond this, deeper rows line up, so that text keeps room on a phone.
  static const _maxIndentDepth = 5;

  @override
  Widget build(BuildContext context) {
    final entry = this.entry;
    final Widget leading;
    final String subtitle;
    switch (entry) {
      case ChapterEntry():
        leading = const SizedBox(
          width: 40,
          child: Icon(Icons.description_outlined),
        );
        subtitle = chapterSubtitle(entry);
      case FolderEntry():
        final canExpand = showFolderContents
            ? entry.children.isNotEmpty
            : entry.folders.isNotEmpty;
        leading = canExpand
            ? IconButton(
                tooltip: isExpanded ? 'Collapse' : 'Expand',
                icon: Icon(
                  isExpanded ? Icons.expand_more : Icons.chevron_right,
                ),
                onPressed: onToggleExpanded,
              )
            : const SizedBox(width: 40, child: Icon(Icons.folder_outlined));
        subtitle = folderSubtitle(entry);
    }
    return GestureDetector(
      onSecondaryTap: onSecondaryTap,
      child: ListTile(
        contentPadding: EdgeInsetsDirectional.only(
          start: 8.0 + 16 * min(depth, _maxIndentDepth),
          end: 8,
        ),
        leading: leading,
        title: Text(entry.label, overflow: TextOverflow.ellipsis),
        subtitle: Text(subtitle, overflow: TextOverflow.ellipsis),
        trailing: trailing,
        enabled: enabled,
        selected: selected,
        onTap: onTap,
        onLongPress: onLongPress,
      ),
    );
  }
}
