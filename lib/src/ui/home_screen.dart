import 'dart:io';

import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../book/book_folder.dart';
import '../settings/app_settings.dart';
import 'chapter_list_screen.dart';
import 'folder_picker_screen.dart';

/// Gets the app to a usable state: storage access first (Android), then a book
/// folder, then the book's chapter list.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.settings});

  final AppSettings settings;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  bool? _hasStorageAccess;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkStorageAccess();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // The permission is granted on a system settings screen, so check again when
  // the user comes back from it.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _checkStorageAccess();
  }

  Future<void> _checkStorageAccess() async {
    final granted =
        !Platform.isAndroid || await Permission.manageExternalStorage.isGranted;
    if (mounted && granted != _hasStorageAccess) {
      setState(() => _hasStorageAccess = granted);
    }
  }

  Future<void> _pickBook() async {
    final path = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) =>
            FolderPickerScreen(initialPath: widget.settings.bookPath),
      ),
    );
    if (path != null) {
      await widget.settings.setBookPath(path);
      if (mounted) setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasAccess = _hasStorageAccess;
    if (hasAccess == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (!hasAccess) {
      return _Prompt(
        icon: Icons.folder_off_outlined,
        message:
            'Ford reads and saves your book as plain files in your Syncthing '
            'folder, so it needs the "All files access" permission.',
        action: 'Allow access',
        onPressed: Permission.manageExternalStorage.request,
      );
    }
    final bookPath = widget.settings.bookPath;
    if (bookPath == null) {
      return _Prompt(
        icon: Icons.menu_book_outlined,
        message: 'Choose the folder that holds your book\'s chapter files.',
        action: 'Choose book folder',
        onPressed: _pickBook,
      );
    }
    return ChapterListScreen(
      // A different book starts from a fresh list.
      key: ValueKey(bookPath),
      book: BookFolder(bookPath),
      settings: widget.settings,
      onChangeBook: _pickBook,
    );
  }
}

class _Prompt extends StatelessWidget {
  const _Prompt({
    required this.icon,
    required this.message,
    required this.action,
    required this.onPressed,
  });

  final IconData icon;
  final String message;
  final String action;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Ford')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 48),
              const SizedBox(height: 16),
              Text(message, textAlign: TextAlign.center),
              const SizedBox(height: 24),
              FilledButton(onPressed: onPressed, child: Text(action)),
            ],
          ),
        ),
      ),
    );
  }
}
