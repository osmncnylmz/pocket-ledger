import 'package:flutter/material.dart';

import '../theme.dart';

class EmptyState extends StatelessWidget {
  const EmptyState({
    required this.icon,
    required this.title,
    required this.message,
    super.key,
    this.action,
    this.compact = false,
  });

  final IconData icon;
  final String title;
  final String message;
  final Widget? action;

  /// Tighter layout, for use inside a card.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: Insets.xl,
          vertical: compact ? Insets.lg : Insets.xxl,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: compact ? 48 : 64,
              height: compact ? 48 : 64,
              decoration: BoxDecoration(
                color: context.colors.surfaceContainerHighest,
                shape: BoxShape.circle,
              ),
              child: Icon(
                icon,
                size: compact ? 24 : 30,
                color: context.colors.onSurfaceVariant,
              ),
            ),
            SizedBox(height: compact ? Insets.md : Insets.lg),
            Text(
              title,
              textAlign: TextAlign.center,
              style:
                  (compact
                          ? context.texts.titleSmall
                          : context.texts.titleMedium)
                      ?.copyWith(color: context.colors.onSurface),
            ),
            const SizedBox(height: Insets.xs),
            Text(
              message,
              textAlign: TextAlign.center,
              style: context.texts.bodySmall?.copyWith(
                color: context.colors.onSurfaceVariant,
                height: 1.4,
              ),
            ),
            if (action != null) ...[const SizedBox(height: Insets.lg), action!],
          ],
        ),
      ),
    );
  }
}
