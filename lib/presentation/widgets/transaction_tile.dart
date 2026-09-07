import 'package:flutter/material.dart';

import '../../domain/entities.dart';
import '../category_icons.dart';
import '../theme.dart';
import 'money_text.dart';

class TransactionTile extends StatelessWidget {
  const TransactionTile({required this.detail, super.key, this.onTap});

  final LedgerEntryDetail detail;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final entry = detail.entry;
    final isTransfer = entry.type.isTransfer;
    final accent = isTransfer
        ? context.colors.onSurfaceVariant
        : Color(
            detail.category?.colorValue ?? context.colors.primary.toARGB32(),
          );

    final subtitle = [
      detail.account.name,
      if (entry.note.isNotEmpty && entry.note != detail.title) entry.note,
    ].join(' · ');

    return ListTile(
      onTap: onTap,
      leading: Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          color: accent.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(13),
        ),
        child: Icon(
          isTransfer
              ? (entry.isOutflow
                    ? Icons.arrow_outward_rounded
                    : Icons.south_west_rounded)
              : categoryIconFor(detail.category?.iconKey ?? 'other'),
          size: 21,
          color: accent,
        ),
      ),
      title: Text(
        detail.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: context.texts.bodyLarge?.copyWith(fontWeight: FontWeight.w500),
      ),
      subtitle: Text(
        subtitle,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: context.texts.bodySmall?.copyWith(
          color: context.colors.onSurfaceVariant,
        ),
      ),
      trailing: MoneyText(
        entry.amount,
        colorBySign: !isTransfer,
        forceSign: !isTransfer,
        style: context.texts.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
      ),
    );
  }
}

class DayHeader extends StatelessWidget {
  const DayHeader({required this.label, required this.total, super.key});

  final String label;
  final Widget total;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: context.colors.surface,
      padding: const EdgeInsets.fromLTRB(
        Insets.lg,
        Insets.md,
        Insets.lg,
        Insets.sm,
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: context.texts.labelLarge?.copyWith(
                color: context.colors.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          DefaultTextStyle.merge(
            style: context.texts.labelLarge!.copyWith(
              color: context.colors.onSurfaceVariant,
            ),
            child: total,
          ),
        ],
      ),
    );
  }
}
