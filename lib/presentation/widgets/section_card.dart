import 'package:flutter/material.dart';

import '../theme.dart';

/// Card with an optional title row. Every block on the dashboard is one.
class SectionCard extends StatelessWidget {
  const SectionCard({
    required this.child,
    super.key,
    this.title,
    this.subtitle,
    this.trailing,
    this.padding = const EdgeInsets.all(Insets.lg),
  });

  final String? title;
  final String? subtitle;
  final Widget? trailing;
  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: padding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (title != null)
              Padding(
                padding: const EdgeInsets.only(bottom: Insets.md),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(title!, style: context.texts.titleMedium),
                          if (subtitle != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: Text(
                                subtitle!,
                                style: context.texts.bodySmall?.copyWith(
                                  color: context.colors.onSurfaceVariant,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    ?trailing,
                  ],
                ),
              ),
            child,
          ],
        ),
      ),
    );
  }
}

/// Error line shown in place of the section body.
class SectionError extends StatelessWidget {
  const SectionError({required this.message, super.key});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(Icons.error_outline, size: 18, color: context.colors.error),
        const SizedBox(width: Insets.sm),
        Expanded(
          child: Text(
            message,
            style: context.texts.bodySmall?.copyWith(
              color: context.colors.error,
            ),
          ),
        ),
      ],
    );
  }
}

/// Sized to the content it stands in for, so the layout does not jump when
/// the query comes back.
class SectionLoading extends StatelessWidget {
  const SectionLoading({required this.height, super.key});

  final double height;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: Center(
        child: SizedBox(
          width: 22,
          height: 22,
          child: CircularProgressIndicator(
            strokeWidth: 2.4,
            color: context.colors.outlineVariant,
          ),
        ),
      ),
    );
  }
}
