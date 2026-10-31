import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:path/path.dart' as p;
import 'package:watcher/watcher.dart';

import 'folder_tree.dart';

/// Keeps an eye on everything under the root folder: tells when chapters or
/// folders change, and which conflict copies exist.
///
/// On the desktop the system reports changes. On Android, or if that stops
/// working, the folder is scanned at [interval] while the app is in the
/// foreground. Either way it's scanned when the app resumes, and only a scan that
/// finds a difference is passed on, so the app's own temp files stay quiet.
class RootWatch extends ChangeNotifier with WidgetsBindingObserver {
  RootWatch(
    this.rootPath, {
    this.interval = const Duration(seconds: 5),
    bool? useSystemEvents,
  }) {
    WidgetsBinding.instance.addObserver(this);
    unawaited(scan());
    if (useSystemEvents ?? !Platform.isAndroid) {
      _listenToSystem();
    } else {
      _startPolling();
    }
  }

  static const _settleTime = Duration(milliseconds: 300);

  final String rootPath;
  final Duration interval;
  final _changes = StreamController<void>.broadcast();

  StreamSubscription<WatchEvent>? _events;
  Timer? _settle;
  Timer? _poll;
  bool _polling = false;
  Future<void>? _scanning;
  bool _scanAgain = false;
  bool _disposed = false;
  String? _signature;
  List<String> _conflictFiles = const [];

  /// Fires when chapters or folders have changed since the last scan.
  Stream<void> get changes => _changes.stream;

  /// The conflict copies under the root, as paths relative to it.
  List<String> get conflictFiles => _conflictFiles;

  static bool isConflictFileName(String name) =>
      name.contains('.sync-conflict-');

  void _listenToSystem() {
    _events = DirectoryWatcher(rootPath).events.listen(
      (_) {
        _settle?.cancel();
        _settle = Timer(_settleTime, () => unawaited(scan()));
      },
      // For example if the system's limit on watched folders was reached.
      onError: (Object _) => _startPolling(),
    );
  }

  void _startPolling() {
    _polling = true;
    _poll?.cancel();
    _poll = Timer.periodic(interval, (_) => unawaited(scan()));
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(scan());
      if (_polling) _startPolling();
    } else if (state == AppLifecycleState.paused) {
      _poll?.cancel();
    }
  }

  /// Looks through the folder now. A root that can't be read is left for the
  /// next scan.
  Future<void> scan() {
    if (_scanning case final running?) {
      _scanAgain = true;
      return running;
    }
    return _scanning = _scanUntilCurrent().whenComplete(
      () => _scanning = null,
    );
  }

  Future<void> _scanUntilCurrent() async {
    do {
      _scanAgain = false;
      final signature = StringBuffer();
      final conflicts = <String>[];
      try {
        await _scanFolder(rootPath, signature, conflicts);
      } on FileSystemException {
        continue;
      }
      if (_disposed) return;
      _report(signature.toString(), conflicts);
    } while (_scanAgain);
  }

  Future<void> _scanFolder(
    String path,
    StringBuffer signature,
    List<String> conflicts,
  ) async {
    final found = await Directory(path).list(followLinks: false).toList();
    found.sort((a, b) => a.path.compareTo(b.path));
    for (final entity in found) {
      final name = p.basename(entity.path);
      if (entity is Directory && FolderTree.isFolderName(name)) {
        signature.writeln(entity.path);
        await _scanFolder(entity.path, signature, conflicts);
      } else if (entity is File && isConflictFileName(name)) {
        conflicts.add(p.relative(entity.path, from: rootPath));
      } else if (entity is File && FolderTree.isChapterFileName(name)) {
        final stat = await entity.stat();
        signature.writeln('${entity.path}|${stat.size}|${stat.modified}');
      }
    }
  }

  void _report(String signature, List<String> conflicts) {
    final known = _signature;
    _signature = signature;
    if (known != null && known != signature) _changes.add(null);
    if (!listEquals(conflicts, _conflictFiles)) {
      _conflictFiles = conflicts;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_events?.cancel());
    _settle?.cancel();
    _poll?.cancel();
    unawaited(_changes.close());
    super.dispose();
  }
}
