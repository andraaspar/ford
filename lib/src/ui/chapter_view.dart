import 'package:flutter/material.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

import '../model/chapter.dart';
import '../model/segment.dart';
import '../settings/app_settings.dart';

/// The side-by-side list of rows.
class ChapterView extends StatefulWidget {
  const ChapterView({
    super.key,
    required this.chapter,
    this.initialPosition,
    this.onPositionChanged,
  });

  final Chapter chapter;
  final ReadingPosition? initialPosition;
  final ValueChanged<ReadingPosition>? onPositionChanged;

  @override
  State<ChapterView> createState() => _ChapterViewState();
}

class _ChapterViewState extends State<ChapterView> {
  final _positions = ItemPositionsListener.create();
  final _collapsedRemarks = <String>{};

  late final int _initialIndex;
  late final double _initialAlignment;

  @override
  void initState() {
    super.initState();
    final saved = widget.initialPosition;
    // The row may be gone if the file changed; then start from the top.
    final index = saved == null ? -1 : widget.chapter.indexOfId(saved.rowId);
    _initialIndex = index < 0 ? 0 : index;
    _initialAlignment = index < 0 ? 0 : saved!.alignment;
    _positions.itemPositions.addListener(_reportPosition);
  }

  @override
  void dispose() {
    _positions.itemPositions.removeListener(_reportPosition);
    super.dispose();
  }

  void _reportPosition() {
    final onChanged = widget.onPositionChanged;
    if (onChanged == null) return;
    ItemPosition? top;
    for (final position in _positions.itemPositions.value) {
      final isVisible = position.itemTrailingEdge > 0;
      if (isVisible && (top == null || position.index < top.index)) {
        top = position;
      }
    }
    if (top == null || top.index >= widget.chapter.length) return;
    onChanged(
      ReadingPosition(
        widget.chapter.segments[top.index].id,
        top.itemLeadingEdge,
      ),
    );
  }

  void _toggleRemark(String id) {
    setState(() {
      if (!_collapsedRemarks.remove(id)) _collapsedRemarks.add(id);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (widget.chapter.isEmpty) {
      return const Center(child: Text('This chapter is empty.'));
    }
    return ScrollablePositionedList.builder(
      itemCount: widget.chapter.length,
      initialScrollIndex: _initialIndex,
      initialAlignment: _initialAlignment,
      itemPositionsListener: _positions,
      // Lets the last row scroll clear of the system navigation bar.
      padding: EdgeInsets.only(
        bottom: MediaQuery.paddingOf(context).bottom + 32,
      ),
      itemBuilder: (context, index) {
        final segment = widget.chapter.segments[index];
        return RowTile(
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
    required this.segment,
    required this.isTitle,
    required this.remarkCollapsed,
    required this.onToggleRemark,
  });

  /// Height of a blank row. Blank rows add up, so three of them are visibly a
  /// bigger break than one.
  static const breakHeight = 14.0;

  final Segment segment;
  final bool isTitle;
  final bool remarkCollapsed;
  final VoidCallback onToggleRemark;

  @override
  Widget build(BuildContext context) {
    final isBlank = segment.source.isEmpty && segment.target.isEmpty;
    final remark = segment.hasRemark
        ? _Remark(
            text: segment.remark,
            collapsed: remarkCollapsed,
            onTap: onToggleRemark,
          )
        : null;
    if (isBlank) return remark ?? const SizedBox(height: breakHeight);

    final theme = Theme.of(context);
    final style = isTitle
        ? theme.textTheme.titleMedium
        : theme.textTheme.bodyMedium;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: _Cell(text: segment.source, style: style),
              ),
              VerticalDivider(
                width: 1,
                color: theme.colorScheme.outlineVariant,
              ),
              Expanded(
                child: _Cell(
                  text: segment.target,
                  style: style,
                  // A source with no translation yet.
                  background: segment.target.isEmpty
                      ? theme.colorScheme.errorContainer.withValues(alpha: 0.45)
                      : null,
                ),
              ),
            ],
          ),
        ),
        ?remark,
      ],
    );
  }
}

class _Cell extends StatelessWidget {
  const _Cell({required this.text, this.style, this.background});

  final String text;
  final TextStyle? style;
  final Color? background;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: background ?? Colors.transparent,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Text(text, style: style),
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
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 2, 8, 6),
        child: Text(
          '💬 $text',
          maxLines: collapsed ? 1 : null,
          overflow: collapsed ? TextOverflow.ellipsis : null,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            fontStyle: FontStyle.italic,
          ),
        ),
      ),
    );
  }
}
