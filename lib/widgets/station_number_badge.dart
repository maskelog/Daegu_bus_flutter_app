import 'package:flutter/material.dart';

class StationNumberBadge extends StatelessWidget {
  final String stationNumber;

  const StationNumberBadge({
    super.key,
    required this.stationNumber,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final backgroundColor = isDark
        ? colorScheme.surfaceContainerHighest
        : colorScheme.primaryContainer;
    final foregroundColor = isDark
        ? colorScheme.onSurface
        : colorScheme.onPrimaryContainer;
    final borderColor = isDark
        ? colorScheme.outlineVariant
        : colorScheme.primary.withAlpha(64);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: borderColor),
      ),
      child: Text(
        stationNumber,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w700,
          color: foregroundColor,
        ),
      ),
    );
  }
}
