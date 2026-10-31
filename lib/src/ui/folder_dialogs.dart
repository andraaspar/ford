import 'package:flutter/material.dart';

import '../folders/folder_ops.dart';

/// Asks for a title pair, such as a folder's display name. Returns the trimmed
/// sides, at least one of them non-empty, or null if cancelled.
Future<({String source, String target})?> showNameDialog(
  BuildContext context, {
  required String title,
  required String action,
  String source = '',
  String target = '',
  String? note,
}) => showDialog(
  context: context,
  builder: (_) => _NameDialog(
    title: title,
    action: action,
    source: source,
    target: target,
    note: note,
  ),
);

class _NameDialog extends StatefulWidget {
  const _NameDialog({
    required this.title,
    required this.action,
    required this.source,
    required this.target,
    this.note,
  });

  final String title;
  final String action;
  final String source;
  final String target;
  final String? note;

  @override
  State<_NameDialog> createState() => _NameDialogState();
}

class _NameDialogState extends State<_NameDialog> {
  late final _source = TextEditingController(text: widget.source);
  late final _target = TextEditingController(text: widget.target);

  bool get _canSubmit =>
      _source.text.trim().isNotEmpty || _target.text.trim().isNotEmpty;

  @override
  void dispose() {
    _source.dispose();
    _target.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_canSubmit) return;
    Navigator.of(context)
        .pop((source: _source.text.trim(), target: _target.text.trim()));
  }

  @override
  Widget build(BuildContext context) {
    final note = widget.note;
    return AlertDialog(
      title: Text(widget.title),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (note != null) ...[Text(note), const SizedBox(height: 16)],
            TextField(
              controller: _source,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Source'),
              textInputAction: TextInputAction.next,
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _target,
              decoration: const InputDecoration(labelText: 'Target'),
              onChanged: (_) => setState(() {}),
              onSubmitted: (_) => _submit(),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _canSubmit ? _submit : null,
          child: Text(widget.action),
        ),
      ],
    );
  }
}

/// Says which folder names an action would change, and asks whether to go on.
/// Doesn't ask if there are none.
Future<bool> confirmNameChanges(
  BuildContext context,
  List<NameChange> changes,
) async {
  if (changes.isEmpty) return true;
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('This renames a folder'),
      content: SingleChildScrollView(
        child: Text(
          [
            'A folder is named by the first row of its first file, and that '
                'file would change:',
            for (final change in changes)
              '"${change.from}" would show as "${change.to}".',
          ].join('\n\n'),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Continue'),
        ),
      ],
    ),
  );
  return confirmed ?? false;
}

/// Asks before deleting something. [details] are shown as separate paragraphs.
Future<bool> confirmDeletion(
  BuildContext context, {
  required String title,
  required List<String> details,
}) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) {
      final colors = Theme.of(context).colorScheme;
      return AlertDialog(
        title: Text(title),
        content: SingleChildScrollView(child: Text(details.join('\n\n'))),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: colors.error,
              foregroundColor: colors.onError,
            ),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      );
    },
  );
  return confirmed ?? false;
}

/// Reports an action that failed.
Future<void> showFolderError(BuildContext context, Object error) =>
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('That didn\'t work'),
        content: SingleChildScrollView(child: Text('$error')),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
