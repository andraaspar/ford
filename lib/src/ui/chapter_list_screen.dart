import 'package:flutter/material.dart';

import '../book/book_folder.dart';
import '../settings/app_settings.dart';
import 'chapter_screen.dart';

class ChapterListScreen extends StatefulWidget {
  const ChapterListScreen({
    super.key,
    required this.book,
    required this.settings,
    required this.onChangeBook,
  });

  final BookFolder book;
  final AppSettings settings;
  final VoidCallback onChangeBook;

  @override
  State<ChapterListScreen> createState() => _ChapterListScreenState();
}

class _ChapterListScreenState extends State<ChapterListScreen> {
  late Future<List<ChapterEntry>> _chapters = widget.book.listChapters();

  @override
  void initState() {
    super.initState();
    _resumeLastChapter();
  }

  /// Goes straight back to the chapter being read. If it's gone or can't be
  /// read, the user simply stays on the list.
  Future<void> _resumeLastChapter() async {
    final last = widget.settings.lastChapter(widget.book.path);
    if (last == null) return;
    final List<ChapterEntry> chapters;
    try {
      chapters = await _chapters;
    } on Object {
      return; // The list shows this error.
    }
    final entry = chapters
        .where((c) => c.fileName == last && c.error == null)
        .firstOrNull;
    if (entry != null && mounted) await _open(entry);
  }

  Future<void> _reload() async {
    final next = widget.book.listChapters();
    setState(() => _chapters = next);
    await next;
  }

  Future<void> _open(ChapterEntry entry) async {
    await widget.settings.setLastChapter(widget.book.path, entry.fileName);
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ChapterScreen(entry: entry, settings: widget.settings),
      ),
    );
    if (mounted) setState(() {}); // The last-read marker may have moved.
  }

  @override
  Widget build(BuildContext context) {
    final lastChapter = widget.settings.lastChapter(widget.book.path);
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.book.name),
        actions: [
          IconButton(
            tooltip: 'Choose another book folder',
            icon: const Icon(Icons.folder_open_outlined),
            onPressed: widget.onChangeBook,
          ),
        ],
      ),
      body: FutureBuilder(
        future: _chapters,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return _Message(
              'Can\'t read this folder: ${snapshot.error}',
              onRetry: _reload,
            );
          }
          final chapters = snapshot.data;
          if (chapters == null) {
            return const Center(child: CircularProgressIndicator());
          }
          if (chapters.isEmpty) {
            return _Message('No chapter files here.', onRetry: _reload);
          }
          return RefreshIndicator(
            onRefresh: _reload,
            child: ListView.builder(
              itemCount: chapters.length,
              itemBuilder: (context, index) {
                final entry = chapters[index];
                final error = entry.error;
                return ListTile(
                  title: Text(entry.title ?? entry.fileName),
                  subtitle: Text(
                    error == null
                        ? entry.fileName
                        : '${entry.fileName}: can\'t read this file',
                  ),
                  trailing: entry.fileName == lastChapter
                      ? const Icon(Icons.bookmark, semanticLabel: 'Last read')
                      : null,
                  onTap: () => _open(entry),
                );
              },
            ),
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
