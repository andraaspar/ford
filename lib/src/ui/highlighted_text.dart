import 'package:flutter/material.dart';

/// [text] with the range from [start] to [end] marked. The range is clamped to
/// the text. The marked part only changes colours, so it takes up the same room
/// as plain text.
TextSpan highlightedSpan(
  BuildContext context,
  String text,
  int start,
  int end,
) {
  final colors = Theme.of(context).colorScheme;
  final from = start.clamp(0, text.length);
  final to = end.clamp(from, text.length);
  return TextSpan(
    children: [
      TextSpan(text: text.substring(0, from)),
      TextSpan(
        text: text.substring(from, to),
        style: TextStyle(
          color: colors.onTertiaryContainer,
          backgroundColor: colors.tertiaryContainer,
        ),
      ),
      TextSpan(text: text.substring(to)),
    ],
  );
}
