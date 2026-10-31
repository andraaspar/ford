import 'dart:async';

import 'package:flutter/material.dart';

import '../book/book_folder.dart';
import '../model/chapter_format.dart';
import '../settings/app_settings.dart';
import 'chapter_view.dart';

/// Loads one chapter file and shows it, remembering the reading position.
class ChapterScreen extends StatefulWidget {
  const ChapterScreen({super.key, required this.entry, required this.settings});

  final ChapterEntry entry;
  final AppSettings settings;

  @override
  State<ChapterScreen> createState() => _ChapterScreenState();
}

class _ChapterScreenState extends State<ChapterScreen>
    with WidgetsBindingObserver {
  static const _saveDelay = Duration(milliseconds: 500);

  late final Future<ParseResult> _loaded = widget.entry.file
      .readAsString()
      .then(ChapterFormat.parse);

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
    super.dispose();
  }

  // The app can be killed at any time once it's in the background.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) _savePosition();
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

  @override
  Widget build(BuildContext context) {
    return FutureBuilder(
      future: _loaded,
      builder: (context, snapshot) {
        final warnings = snapshot.data?.warnings ?? const <String>[];
        return Scaffold(
          appBar: AppBar(
            title: Text(
              snapshot.data?.chapter.title ?? widget.entry.fileName,
              overflow: TextOverflow.ellipsis,
            ),
            actions: [
              if (warnings.isNotEmpty)
                IconButton(
                  tooltip: 'Repairs made while reading this file',
                  icon: const Icon(Icons.warning_amber),
                  onPressed: () => _showWarnings(warnings),
                ),
            ],
          ),
          body: switch (snapshot) {
            AsyncSnapshot(hasError: true) => Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Text(
                  'Can\'t read ${widget.entry.fileName}: ${snapshot.error}',
                ),
              ),
            ),
            AsyncSnapshot(:final data?) => ChapterView(
              chapter: data.chapter,
              initialPosition: widget.settings.position(_path),
              onPositionChanged: _onPositionChanged,
            ),
            _ => const Center(child: CircularProgressIndicator()),
          },
        );
      },
    );
  }
}
