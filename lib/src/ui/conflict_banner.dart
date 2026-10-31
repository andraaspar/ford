import 'package:flutter/material.dart';

import '../folders/root_watch.dart';

/// Says that conflict copies exist under the root folder, for as long as they
/// do. Takes no space otherwise.
class ConflictBanner extends StatelessWidget {
  const ConflictBanner({super.key, required this.watch});

  final RootWatch? watch;

  void _showFiles(BuildContext context, List<String> files) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Conflict copies'),
        content: SingleChildScrollView(
          child: Text(
            'These were made because a file changed on two devices at once. '
            'They aren\'t shown as chapters. Copy what you need from them into '
            'the chapter, then delete them.\n\n${files.join('\n')}',
          ),
        ),
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
    final watch = this.watch;
    if (watch == null) return const SizedBox.shrink();
    return ListenableBuilder(
      listenable: watch,
      builder: (context, _) {
        final files = watch.conflictFiles;
        if (files.isEmpty) return const SizedBox.shrink();
        return MaterialBanner(
          leading: const Icon(Icons.call_split),
          content: Text(
            files.length == 1
                ? 'There is 1 conflict copy in this root folder.'
                : 'There are ${files.length} conflict copies in this root '
                      'folder.',
          ),
          actions: [
            TextButton(
              onPressed: () => _showFiles(context, files),
              child: const Text('Show'),
            ),
          ],
        );
      },
    );
  }
}
