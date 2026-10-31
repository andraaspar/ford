import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

import '../editing/chapter_editor.dart';
import '../model/chapter.dart';
import '../model/segment.dart';
import '../settings/app_settings.dart';
import 'row_menu.dart';

/// The side-by-side list of rows, editable in place.
///
/// The list lays rows out from a center row: rows after it grow downwards,
/// rows before it grow upwards, and changing which rows come before it moves
/// everything. So whenever the rows change, this keeps the center out of the way
/// or jumps back to the row that was at the top, to the same pixel.
class ChapterView extends StatefulWidget {
  const ChapterView({
    super.key,
    required this.editor,
    this.initialPosition,
    this.onPositionChanged,
  });

  final ChapterEditor editor;
  final ReadingPosition? initialPosition;
  final ValueChanged<ReadingPosition>? onPositionChanged;

  @override
  State<ChapterView> createState() => _ChapterViewState();
}

class _ChapterViewState extends State<ChapterView> {
  /// Where a restored row lands when it was out of sight.
  static const _revealAlignment = 0.25;

  final _scroll = ItemScrollController();
  final _positions = ItemPositionsListener.create();
  final _collapsedRemarks = <String>{};

  late final int _initialIndex;
  late final double _initialAlignment;

  /// The list's center row.
  late int _center;
  late Chapter _shown;
  String? _activeRowId;

  ChapterEditor get _editor => widget.editor;

  @override
  void initState() {
    super.initState();
    _shown = _editor.chapter;
    final saved = widget.initialPosition;
    // The row may be gone if the file changed; then start from the top.
    final index = saved == null ? -1 : _shown.indexOfId(saved.rowId);
    _initialIndex = index < 0 ? 0 : index;
    _initialAlignment = index < 0 ? 0 : saved!.alignment;
    _center = _initialIndex;
    _positions.itemPositions.addListener(_reportPosition);
    _editor.addListener(_onEditorChanged);
  }

  @override
  void dispose() {
    _positions.itemPositions.removeListener(_reportPosition);
    _editor.removeListener(_onEditorChanged);
    super.dispose();
  }

  /// The first row that is at least partly visible.
  ItemPosition? _topVisible() {
    ItemPosition? top;
    for (final position in _positions.itemPositions.value) {
      final isVisible = position.itemTrailingEdge > 0;
      if (isVisible && (top == null || position.index < top.index)) {
        top = position;
      }
    }
    return top;
  }

  void _reportPosition() {
    final onChanged = widget.onPositionChanged;
    if (onChanged == null) return;
    final top = _topVisible();
    if (top == null || top.index >= _shown.length) return;
    onChanged(
      ReadingPosition(_shown.segments[top.index].id, top.itemLeadingEdge),
    );
  }

  // Runs before the new rows are laid out, so the positions still describe the
  // rows in [_shown].
  void _onEditorChanged() {
    final before = _shown;
    final after = _editor.chapter;
    _shown = after;
    var jumped = false;
    if (!identical(before, after) && _scroll.isAttached && after.length > 0) {
      jumped = _keepPosition(before, after);
    }
    final reveal = _editor.takeReveal();
    if (reveal != null && _scroll.isAttached) {
      jumped = _reveal(before, reveal) || jumped;
    }

    final activeRowId = _editor.active?.rowId;
    if (activeRowId != null && activeRowId != _activeRowId && !jumped) {
      _centerOnTopRow();
    }
    _activeRowId = activeRowId;
    setState(() {});
  }

  /// Keeps the rows on screen where they are after [before] became [after].
  /// Returns whether that took a jump.
  bool _keepPosition(Chapter before, Chapter after) {
    final top = _topVisible();
    if (top == null || top.index >= before.length) return false;
    final topId = before.segments[top.index].id;
    final topIndex = after.indexOfId(topId);
    // If the top row itself is gone, the row now in its place takes over.
    final index = topIndex < 0
        ? top.index.clamp(0, after.length - 1)
        : topIndex;

    final centerIsStill =
        _center < before.length &&
        _center < after.length &&
        before.segments[_center].id == after.segments[_center].id;
    if (topIndex == top.index && centerIsStill && top.index >= _center) {
      return false;
    }
    _jump(index, top.itemLeadingEdge, rowCountBefore: before.length);
    return true;
  }

  /// Brings [change] into sight if it's off screen. Returns whether it had to.
  bool _reveal(Chapter before, ChapterChange change) {
    final visible = _positions.itemPositions.value
        .where((p) => p.itemTrailingEdge > 0 && p.itemLeadingEdge < 1)
        .map((p) => p.index)
        .toList();
    if (visible.isEmpty) return false;
    final first = visible.reduce((a, b) => a < b ? a : b);
    final topId = first < before.length ? before.segments[first].id : null;
    final firstNow = topId == null ? first : _shown.indexOfId(topId);
    if (firstNow >= 0 &&
        change.index >= firstNow &&
        change.index < firstNow + visible.length) {
      return false;
    }
    _jump(change.index, _revealAlignment, rowCountBefore: before.length);
    return true;
  }

  /// Puts the center at the top row without moving anything on screen, so that a
  /// row growing while it's typed in pushes only the rows below it.
  void _centerOnTopRow() {
    final top = _topVisible();
    if (top == null || top.index == _center || !_scroll.isAttached) return;
    _jump(top.index, top.itemLeadingEdge, rowCountBefore: _shown.length);
  }

  void _jump(int index, double alignment, {required int rowCountBefore}) {
    _center = index;
    _scroll.jumpTo(index: index, alignment: alignment);
    // The list clamps a jump to the row count of its last build.
    if (index >= rowCountBefore) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _scroll.jumpTo(index: index, alignment: alignment);
      });
    }
  }

  void _toggleRemark(String id) {
    setState(() {
      if (!_collapsedRemarks.remove(id)) _collapsedRemarks.add(id);
    });
  }

  void _addFirstRow() {
    _editor.insertBlank(0);
    _editor.activate(_editor.chapter.segments.first.id, Field.source);
  }

  @override
  Widget build(BuildContext context) {
    final chapter = _editor.chapter;
    if (chapter.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('This chapter is empty.'),
            const SizedBox(height: 16),
            OutlinedButton(
              onPressed: _addFirstRow,
              child: const Text('Add a row'),
            ),
          ],
        ),
      );
    }
    return ScrollablePositionedList.builder(
      itemCount: chapter.length,
      initialScrollIndex: _initialIndex,
      initialAlignment: _initialAlignment,
      itemScrollController: _scroll,
      itemPositionsListener: _positions,
      // Lets the last row scroll clear of the system navigation bar and, while
      // a cell is open, of the keyboard. The keyboard's actual height doesn't
      // matter here, which keeps its animation from changing the layout.
      padding: EdgeInsets.only(
        bottom:
            MediaQuery.paddingOf(context).bottom +
            32 +
            (_editor.active == null
                ? 0
                : MediaQuery.sizeOf(context).height * 0.75),
      ),
      itemBuilder: (context, index) {
        final segment = chapter.segments[index];
        return RowTile(
          editor: _editor,
          segment: segment,
          isTitle: index == 0,
          remarkCollapsed: _collapsedRemarks.contains(segment.id),
          onToggleRemark: () => _toggleRemark(segment.id),
        );
      },
    );
  }
}

/// One row: source and target in equal columns, the remark below them.
class RowTile extends StatelessWidget {
  const RowTile({
    super.key,
    required this.editor,
    required this.segment,
    required this.isTitle,
    required this.remarkCollapsed,
    required this.onToggleRemark,
  });

  final ChapterEditor editor;
  final Segment segment;
  final bool isTitle;
  final bool remarkCollapsed;
  final VoidCallback onToggleRemark;

  void _activate(Field field, int offset) =>
      editor.activate(segment.id, field, offset: offset);

  @override
  Widget build(BuildContext context) {
    final active = editor.active?.rowId == segment.id ? editor.active : null;
    return GestureDetector(
      onLongPress: () => showRowMenu(context, editor, segment.id),
      onSecondaryTap: () => showRowMenu(context, editor, segment.id),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _sides(context, active),
          if (active?.field == Field.remark)
            _RemarkEditor(
              key: ValueKey('${segment.id}/remark'),
              editor: editor,
              rowId: segment.id,
              text: segment.remark,
            )
          else if (segment.hasRemark)
            _Remark(
              text: segment.remark,
              // A remark being read while its row is edited stays open.
              collapsed: remarkCollapsed && active == null,
              onTap: onToggleRemark,
            ),
          Divider(
            height: 1,
            thickness: 1,
            color: Theme.of(context).colorScheme.outlineVariant,
          ),
        ],
      ),
    );
  }

  Widget _sides(BuildContext context, ActiveCell? active) {
    final theme = Theme.of(context);
    final style = isTitle
        ? theme.textTheme.titleMedium
        : theme.textTheme.bodyMedium;

    Widget cell(Field field, Color? background) {
      if (active?.field == field) {
        return _CellEditor(
          key: ValueKey('${segment.id}/${field.name}'),
          editor: editor,
          rowId: segment.id,
          field: field,
          text: segment.field(field),
          style: style,
        );
      }
      return _Cell(
        text: segment.field(field),
        style: style,
        background: background,
        onTapAt: (offset) => _activate(field, offset),
      );
    }

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: cell(Field.source, null)),
          VerticalDivider(width: 1, color: theme.colorScheme.outlineVariant),
          Expanded(
            child: cell(
              Field.target,
              // A source with no translation yet.
              segment.target.isEmpty && segment.source.isNotEmpty
                  ? theme.colorScheme.errorContainer.withValues(alpha: 0.45)
                  : null,
            ),
          ),
        ],
      ),
    );
  }
}

const _cellPadding = EdgeInsets.symmetric(horizontal: 8, vertical: 4);

class _Cell extends StatelessWidget {
  const _Cell({
    required this.text,
    required this.onTapAt,
    this.style,
    this.background,
  });

  final String text;
  final TextStyle? style;
  final Color? background;

  /// Called with the text offset that was tapped.
  final ValueChanged<int> onTapAt;

  int _offsetAt(BuildContext context, Offset position) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: DefaultTextStyle.of(context).style.merge(style),
      ),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
    )..layout(maxWidth: context.size!.width - _cellPadding.horizontal);
    final offset = painter.getPositionForOffset(
      position - _cellPadding.topLeft,
    );
    painter.dispose();
    return offset.offset;
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapUp: (details) => onTapAt(_offsetAt(context, details.localPosition)),
      child: ColoredBox(
        color: background ?? Colors.transparent,
        child: Padding(
          padding: _cellPadding,
          child: Text(text, style: style),
        ),
      ),
    );
  }
}

/// A text field bound to one field of one row.
///
/// Keeps itself alive so that scrolling away from it doesn't close the keyboard.
/// The caret lives in the editor, so a new instance picks up where this one was
/// when its row moves to another place in the list.
class _BoundField extends StatefulWidget {
  const _BoundField({
    required this.editor,
    required this.rowId,
    required this.field,
    required this.text,
    required this.style,
  });

  final ChapterEditor editor;
  final String rowId;
  final Field field;
  final String text;
  final TextStyle? style;

  @override
  State<_BoundField> createState() => _BoundFieldState();
}

/// Keeps [_startGuard] at the start of the text and reports its deletion.
class _StartGuardFormatter extends TextInputFormatter {
  _StartGuardFormatter(this.onDeleted);

  final VoidCallback onDeleted;

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (oldValue.text.startsWith(_startGuard) &&
        newValue.text == oldValue.text.substring(1)) {
      onDeleted();
      return oldValue;
    }
    if (newValue.text.startsWith(_startGuard)) return newValue;
    int shift(int offset) => offset < 0 ? offset : offset + 1;
    final composing = newValue.composing;
    return TextEditingValue(
      text: '$_startGuard${newValue.text}',
      selection: newValue.selection.copyWith(
        baseOffset: shift(newValue.selection.baseOffset),
        extentOffset: shift(newValue.selection.extentOffset),
      ),
      composing: TextRange(
        start: shift(composing.start),
        end: shift(composing.end),
      ),
    );
  }
}

/// An invisible character kept before the text of source and target cells.
///
/// Android keyboards usually send nothing for Backspace when there's nothing
/// before the caret. With this there always is, and its deletion tells us about
/// the key press. It never leaves the text field.
const _startGuard = '\u200B';

class _BoundFieldState extends State<_BoundField>
    with AutomaticKeepAliveClientMixin {
  /// Source and target are one line each: Enter splits the row, and line breaks
  /// in pasted text become spaces.
  static final _noLineBreaks = FilteringTextInputFormatter.deny(
    RegExp(r'[\r\n]+'),
    replacementString: ' ',
  );

  late final TextEditingController _controller;
  final _focusNode = FocusNode();

  @override
  bool get wantKeepAlive => true;

  bool get _isSplittable => widget.field.side != null;

  String get _prefix => _isSplittable ? _startGuard : '';

  TextEditingValue _valueAtCaret() {
    final length = widget.text.length;
    final offset = (widget.editor.active?.offset ?? length).clamp(0, length);
    return TextEditingValue(
      text: '$_prefix${widget.text}',
      selection: TextSelection.collapsed(offset: offset + _prefix.length),
    );
  }

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController.fromValue(_valueAtCaret());
    _controller.addListener(_onControllerChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _focusNode.requestFocus();
      // The field this one replaces has just closed its connection to the
      // keyboard, which hides the keyboard in the next microtask unless a new
      // connection exists by then. Waiting for the scheduled focus update would
      // be too late and make the keyboard flicker.
      FocusManager.instance.applyFocusChangesIfNeeded();
    });
  }

  @override
  void didUpdateWidget(_BoundField oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Undo and redo change the text from outside.
    if ('$_prefix${widget.text}' != _controller.text) {
      _controller.value = _valueAtCaret();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _onControllerChanged() {
    final selection = _controller.selection;
    if (!selection.isValid) return;
    // Keeps the guard out of reach of the caret, and out of anything copied.
    final first = _prefix.length;
    if (selection.baseOffset < first || selection.extentOffset < first) {
      _controller.selection = selection.copyWith(
        baseOffset: selection.baseOffset < first ? first : null,
        extentOffset: selection.extentOffset < first ? first : null,
      );
      return;
    }
    if (_isActive) widget.editor.moveCaret(selection.start - first);
  }

  void _onBackspaceAtStart() {
    // This is called while the text field is working out its new value.
    scheduleMicrotask(() {
      if (mounted) unawaited(mergeWithPrevious(context, widget.editor));
    });
  }

  bool get _isActive {
    final active = widget.editor.active;
    return active?.rowId == widget.rowId && active?.field == widget.field;
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final splitsOnEnter = _isSplittable;
    return TextField(
      controller: _controller,
      focusNode: _focusNode,
      style: widget.style,
      maxLines: null,
      keyboardType: splitsOnEnter
          ? TextInputType.text
          : TextInputType.multiline,
      textInputAction: splitsOnEnter
          ? TextInputAction.done
          : TextInputAction.newline,
      inputFormatters: splitsOnEnter
          ? [_noLineBreaks, _StartGuardFormatter(_onBackspaceAtStart)]
          : null,
      // The list doesn't shrink for the keyboard, so the caret has to be kept
      // clear of it here.
      scrollPadding: EdgeInsets.fromLTRB(
        20,
        20,
        20,
        20 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      // No decoration, so that opening a cell doesn't change the row's height.
      decoration: null,
      onChanged: (text) => widget.editor.setText(
        widget.rowId,
        widget.field,
        text.substring(_prefix.length),
      ),
      onSubmitted: splitsOnEnter ? (_) => widget.editor.splitAtCaret() : null,
      // These two keep the cell open: it closes only when another one is tapped
      // or editing is finished, not when a toolbar button is clicked.
      onEditingComplete: () {},
      onTapOutside: (_) {},
    );
  }
}

class _CellEditor extends StatelessWidget {
  const _CellEditor({
    super.key,
    required this.editor,
    required this.rowId,
    required this.field,
    required this.text,
    required this.style,
  });

  final ChapterEditor editor;
  final String rowId;
  final Field field;
  final String text;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Theme.of(context).colorScheme.primaryContainer
          .withValues(alpha: 0.35),
      child: Padding(
        padding: _cellPadding,
        child: _BoundField(
          editor: editor,
          rowId: rowId,
          field: field,
          text: text,
          style: style,
        ),
      ),
    );
  }
}

const _remarkPadding = EdgeInsets.fromLTRB(8, 2, 8, 6);

TextStyle? _remarkStyle(ThemeData theme) => theme.textTheme.bodySmall?.copyWith(
  color: theme.colorScheme.onSurfaceVariant,
  fontStyle: FontStyle.italic,
);

class _RemarkEditor extends StatelessWidget {
  const _RemarkEditor({
    super.key,
    required this.editor,
    required this.rowId,
    required this.text,
  });

  final ChapterEditor editor;
  final String rowId;
  final String text;

  @override
  Widget build(BuildContext context) {
    final style = _remarkStyle(Theme.of(context));
    return Padding(
      padding: _remarkPadding,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('💬 ', style: style),
          Expanded(
            child: _BoundField(
              editor: editor,
              rowId: rowId,
              field: Field.remark,
              text: text,
              style: style,
            ),
          ),
        ],
      ),
    );
  }
}

class _Remark extends StatelessWidget {
  const _Remark({
    required this.text,
    required this.collapsed,
    required this.onTap,
  });

  final String text;
  final bool collapsed;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: _remarkPadding,
        child: Text(
          '💬 $text',
          maxLines: collapsed ? 1 : null,
          overflow: collapsed ? TextOverflow.ellipsis : null,
          style: _remarkStyle(Theme.of(context)),
        ),
      ),
    );
  }
}
