import 'folder_tree.dart';

/// Which chapters an action such as search or export applies to. Ticking a folder
/// ticks everything inside it, and anything inside can then be unticked.
class TargetSelection {
  TargetSelection([Iterable<String> chapterPaths = const []])
    : _chapterPaths = {...chapterPaths};

  final Set<String> _chapterPaths;

  Set<String> get chapterPaths => Set.unmodifiable(_chapterPaths);

  /// True if [entry] is wholly ticked, false if nothing in it is, and null if
  /// only part of it is. A folder holding no chapters can't be ticked.
  bool? stateOf(TreeEntry entry) {
    final chapters = _chaptersIn(entry).toList();
    final ticked = chapters.where((c) => _chapterPaths.contains(c.path)).length;
    if (ticked == 0) return false;
    return ticked == chapters.length ? true : null;
  }

  /// Unticks [entry] if it's wholly ticked; otherwise ticks all of it.
  void toggle(TreeEntry entry) {
    final paths = _chaptersIn(entry).map((c) => c.path);
    if (stateOf(entry) == true) {
      _chapterPaths.removeAll(paths);
    } else {
      _chapterPaths.addAll(paths);
    }
  }

  static Iterable<ChapterEntry> _chaptersIn(TreeEntry entry) => switch (entry) {
    ChapterEntry() => [entry],
    FolderEntry() => entry.allChapters,
  };
}
