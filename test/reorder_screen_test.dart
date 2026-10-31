import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ford/src/folders/folder_tree.dart';
import 'package:ford/src/ui/reorder_screen.dart';

void main() {
  testWidgets('the last entry can scroll clear of the navigation bar', (
    tester,
  ) async {
    const navigationBar = 48.0;
    final folder = FolderEntry(
      path: 'root',
      children: [
        for (var i = 0; i < 30; i++)
          ChapterEntry(file: File('root/$i.txt'), title: 'Chapter $i'),
      ],
    );
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(padding: const EdgeInsets.only(bottom: navigationBar)),
          child: child!,
        ),
        home: ReorderScreen(folder: folder),
      ),
    );

    await tester.drag(find.byType(ListTile).first, const Offset(0, -5000));
    await tester.pumpAndSettle();

    final last = tester.getRect(
      find.ancestor(
        of: find.text('Chapter 29'),
        matching: find.byType(ListTile),
      ),
    );
    expect(
      last.bottom,
      lessThanOrEqualTo(
        tester.view.physicalSize.height / tester.view.devicePixelRatio -
            navigationBar,
      ),
    );
  });
}
