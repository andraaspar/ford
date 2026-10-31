import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../folders/folder_tree.dart';
import '../model/natural_sort.dart';

/// Browses folders with plain file access. Pops with the chosen folder's path.
class FolderPickerScreen extends StatefulWidget {
  const FolderPickerScreen({super.key, this.initialPath});

  final String? initialPath;

  @override
  State<FolderPickerScreen> createState() => _FolderPickerScreenState();
}

class _FolderPickerScreenState extends State<FolderPickerScreen> {
  /// The folder being shown; null until the first listing finishes.
  String? _path;
  List<String> _folders = const [];
  int _chapterCount = 0;
  String? _error;

  static String get _startPath {
    if (Platform.isAndroid) return '/storage/emulated/0';
    return Platform.environment['HOME'] ??
        Platform.environment['USERPROFILE'] ??
        Directory.current.path;
  }

  @override
  void initState() {
    super.initState();
    final initial = widget.initialPath;
    _open(
      initial != null && Directory(initial).existsSync() ? initial : _startPath,
    );
  }

  Future<void> _open(String path) async {
    final folders = <String>[];
    var chapterCount = 0;
    String? error;
    try {
      await for (final entry in Directory(path).list(followLinks: false)) {
        final name = p.basename(entry.path);
        if (entry is Directory && FolderTree.isFolderName(name)) {
          folders.add(entry.path);
        } else if (entry is File && FolderTree.isChapterFileName(name)) {
          chapterCount++;
        }
      }
      folders.sort((a, b) => naturalCompare(p.basename(a), p.basename(b)));
    } on FileSystemException catch (e) {
      error = e.osError?.message ?? e.message;
    }
    if (!mounted) return;
    setState(() {
      _path = path;
      _folders = folders;
      _chapterCount = chapterCount;
      _error = error;
    });
  }

  @override
  Widget build(BuildContext context) {
    final path = _path;
    if (path == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final parent = p.dirname(path);
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Choose root folder')),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Text(path, style: theme.textTheme.bodySmall),
          ),
          const Divider(height: 1),
          Expanded(
            child: ListView(
              children: [
                if (parent != path)
                  ListTile(
                    leading: const Icon(Icons.arrow_upward),
                    title: const Text('Up'),
                    onTap: () => _open(parent),
                  ),
                if (_error case final error?)
                  ListTile(
                    leading: const Icon(Icons.error_outline),
                    title: Text('Can\'t open this folder: $error'),
                  ),
                for (final folder in _folders)
                  ListTile(
                    leading: const Icon(Icons.folder_outlined),
                    title: Text(p.basename(folder)),
                    onTap: () => _open(folder),
                  ),
              ],
            ),
          ),
          const Divider(height: 1),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      _chapterCount == 1
                          ? '1 chapter file here'
                          : '$_chapterCount chapter files here',
                    ),
                  ),
                  const SizedBox(width: 16),
                  FilledButton(
                    onPressed: _error != null
                        ? null
                        : () => Navigator.of(context).pop(path),
                    child: const Text('Use this folder'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
