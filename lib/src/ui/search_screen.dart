import 'dart:async';

import 'package:flutter/material.dart';

import '../folders/folder_tree.dart';
import '../model/chapter.dart';
import '../model/segment.dart';
import '../search/text_search.dart';
import 'highlighted_text.dart';
import 'target_picker_screen.dart';

/// Which chapters a search goes through.
enum SearchTarget { chapter, folder, chosen }

/// A search as the user left it, so that going to a result and coming back to
/// the list takes up where it was.
class SearchSession {
  String text = '';
  bool matchCase = false;
  SearchScope scope = SearchScope.all;
  SearchTarget target = SearchTarget.chapter;
  Set<String> chosen = {};
  SearchResults? results;
  double scrollOffset = 0;

  /// Makes the chosen chapters follow files and folders that moved.
  void relocate(Map<String, String> moves) {
    chosen = {for (final path in chosen) movedPath(path, moves) ?? path};
  }
}

/// Searches chapters and lists the matches. Pops with the [SearchHit] tapped.
class SearchScreen extends StatefulWidget {
  const SearchScreen({
    super.key,
    required this.rootPath,
    required this.session,
    this.chapterPath,
    this.openChapter,
    this.folderPath,
  });

  final String rootPath;
  final SearchSession session;

  /// The current chapter; without one, the current folder is the first choice.
  final String? chapterPath;

  /// The current chapter's rows, which may be ahead of its file.
  final Chapter? openChapter;

  /// The current folder. By default that's the one around the current chapter,
  /// or else the root folder.
  final String? folderPath;

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  /// Long enough not to search for each letter of a word being typed.
  static const _typingDelay = Duration(milliseconds: 250);

  late final Future<FolderEntry> _tree = FolderTree.load(widget.rootPath);
  late final _text = TextEditingController(text: _session.text);
  late final _scroll = ScrollController(
    initialScrollOffset: _session.scrollOffset,
  );
  Timer? _typing;
  int _latestRun = 0;

  SearchSession get _session => widget.session;

  SearchTarget get _target =>
      _session.target == SearchTarget.chapter && widget.chapterPath == null
      ? SearchTarget.folder
      : _session.target;

  @override
  void initState() {
    super.initState();
    _text.selection = TextSelection(
      baseOffset: 0,
      extentOffset: _text.text.length,
    );
    _scroll.addListener(() => _session.scrollOffset = _scroll.offset);
    // What's on disk may have changed since this search last ran.
    if (_session.text.isNotEmpty) unawaited(_run(fromTheTop: false));
  }

  @override
  void dispose() {
    _typing?.cancel();
    _latestRun++;
    _text.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _onTyped(String text) {
    _session.text = text;
    _typing?.cancel();
    _typing = Timer(_typingDelay, () => unawaited(_run()));
  }

  void _clear() {
    _text.clear();
    _session.text = '';
    unawaited(_run());
  }

  /// Applies a change to the search, then runs it again.
  void _change(VoidCallback change) {
    setState(change);
    unawaited(_run());
  }

  Future<void> _run({bool fromTheTop = true}) async {
    _typing?.cancel();
    final run = ++_latestRun;
    if (_session.text.isEmpty) {
      setState(() => _session.results = null);
      return;
    }
    final FolderEntry root;
    try {
      root = await _tree;
    } on Object {
      return; // The screen shows this error.
    }
    final open = widget.chapterPath;
    final openChapter = widget.openChapter;
    final results = await searchChapters(
      _targetChapters(root),
      SearchQuery(
        _session.text,
        matchCase: _session.matchCase,
        scope: _session.scope,
      ),
      open: {if (open != null && openChapter != null) open: openChapter},
      isCancelled: () => run != _latestRun,
    );
    if (run != _latestRun || !mounted) return;
    setState(() => _session.results = results);
    if (fromTheTop && _scroll.hasClients) _scroll.jumpTo(0);
  }

  FolderEntry _currentFolder(FolderEntry root) {
    final path = widget.folderPath;
    final chapterPath = widget.chapterPath;
    final entry = path != null
        ? root.find(path)
        : chapterPath == null
        ? root
        : root.find(chapterPath)?.parent;
    return entry is FolderEntry ? entry : root;
  }

  /// In tree order, whichever way they were chosen.
  Iterable<ChapterEntry> _targetChapters(FolderEntry root) {
    switch (_target) {
      case SearchTarget.chapter:
        final entry = root.find(widget.chapterPath!);
        return entry is ChapterEntry ? [entry] : const [];
      case SearchTarget.folder:
        return _currentFolder(root).allChapters;
      case SearchTarget.chosen:
        return root.allChapters.where(
          (chapter) => _session.chosen.contains(chapter.path),
        );
    }
  }

  Future<void> _choose() async {
    final chosen = await Navigator.of(context).push<Set<String>>(
      MaterialPageRoute(
        builder: (_) => TargetPickerScreen(
          rootPath: widget.rootPath,
          title: 'Search in',
          initial: _session.chosen,
        ),
      ),
    );
    if (chosen == null || !mounted) return;
    _change(() {
      _session.chosen = chosen;
      _session.target = SearchTarget.chosen;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _text,
          // Coming back to a list of results shouldn't cover it with a keyboard.
          autofocus: _session.text.isEmpty,
          decoration: const InputDecoration(
            hintText: 'Search',
            border: InputBorder.none,
          ),
          textInputAction: TextInputAction.search,
          onChanged: _onTyped,
          onSubmitted: (_) => unawaited(_run()),
        ),
        actions: [
          ListenableBuilder(
            listenable: _text,
            builder: (context, _) => _text.text.isEmpty
                ? const SizedBox.shrink()
                : IconButton(
                    tooltip: 'Clear',
                    icon: const Icon(Icons.close),
                    onPressed: _clear,
                  ),
          ),
        ],
      ),
      body: FutureBuilder(
        future: _tree,
        builder: (context, snapshot) {
          final root = snapshot.data;
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Text('Can\'t read this folder: ${snapshot.error}'),
              ),
            );
          }
          if (root == null) {
            return const Center(child: CircularProgressIndicator());
          }
          return _body(root);
        },
      ),
    );
  }

  Widget _body(FolderEntry root) {
    final results = _session.results;
    final hits = results?.hits ?? const <SearchHit>[];
    // The filters scroll away with the results, so that they can't crowd out the
    // list when the keyboard is up on a small screen.
    return CustomScrollView(
      controller: _scroll,
      slivers: [
        SliverToBoxAdapter(child: _filters(root)),
        if (results != null) SliverToBoxAdapter(child: _Summary(results)),
        SliverPadding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.paddingOf(context).bottom,
          ),
          sliver: SliverList.separated(
            itemCount: hits.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, index) => _ResultTile(
              hit: hits[index],
              onTap: () => Navigator.of(context).pop(hits[index]),
            ),
          ),
        ),
      ],
    );
  }

  Widget _filters(FolderEntry root) {
    final chosen = _session.chosen.length;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 8,
            children: [
              for (final scope in SearchScope.values)
                ChoiceChip(
                  label: Text(switch (scope) {
                    SearchScope.all => 'All',
                    SearchScope.source => 'Source',
                    SearchScope.target => 'Target',
                    SearchScope.remarks => 'Remarks',
                  }),
                  selected: _session.scope == scope,
                  onSelected: (_) => _change(() => _session.scope = scope),
                ),
              FilterChip(
                label: const Text('Match case'),
                selected: _session.matchCase,
                onSelected: (value) =>
                    _change(() => _session.matchCase = value),
              ),
            ],
          ),
          Wrap(
            spacing: 8,
            children: [
              if (widget.chapterPath != null)
                ChoiceChip(
                  label: const Text('This chapter'),
                  selected: _target == SearchTarget.chapter,
                  onSelected: (_) =>
                      _change(() => _session.target = SearchTarget.chapter),
                ),
              ChoiceChip(
                label: Text(
                  _currentFolder(root).isRoot ? 'Root folder' : 'This folder',
                ),
                selected: _target == SearchTarget.folder,
                onSelected: (_) =>
                    _change(() => _session.target = SearchTarget.folder),
              ),
              ChoiceChip(
                label: Text(chosen == 0 ? 'Choose…' : 'Chosen: $chosen'),
                selected: _target == SearchTarget.chosen,
                onSelected: (_) => unawaited(_choose()),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

String _count(int n, String one) => n == 1 ? '1 $one' : '$n ${one}s';

class _Summary extends StatelessWidget {
  const _Summary(this.results);

  final SearchResults results;

  String get _text {
    final searched = results.searched;
    if (searched == 0) return 'No chapters to search';
    if (results.hits.isEmpty) {
      return 'No matches in ${_count(searched, 'chapter')}';
    }
    final matches = results.hits.length;
    return '$matches ${matches == 1 ? 'match' : 'matches'} in '
        '${results.chaptersWithHits} of ${_count(searched, 'chapter')}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final unreadable = results.unreadable;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(_text, style: theme.textTheme.labelLarge),
          if (unreadable.isNotEmpty)
            Text(
              'Can\'t read ${_count(unreadable.length, 'file')}: '
              '${unreadable.map((c) => c.fileName).join(', ')}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
        ],
      ),
    );
  }
}

class _ResultTile extends StatelessWidget {
  const _ResultTile({required this.hit, required this.onTap});

  final SearchHit hit;
  final VoidCallback onTap;

  /// The folder's display name, the chapter, and which part of the row it is.
  String get _location {
    final folder = hit.chapter.parent;
    return [
      if (folder != null && !folder.isRoot) folder.label,
      hit.chapter.label,
      switch (hit.field) {
        Field.source => 'Source',
        Field.target => 'Target',
        Field.remark => 'Remark',
      },
    ].join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final snippet = snippetOf(hit);
    return ListTile(
      dense: true,
      title: Text.rich(
        highlightedSpan(context, snippet.text, snippet.start, snippet.end),
        maxLines: 3,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(_location, overflow: TextOverflow.ellipsis),
      onTap: onTap,
    );
  }
}
