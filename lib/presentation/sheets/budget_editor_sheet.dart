import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/entities.dart';
import '../../domain/enums.dart';
import '../../domain/services/budget_evaluator.dart';
import '../category_icons.dart';
import '../providers.dart';
import '../theme.dart';
import '../widgets/amount_field.dart';

Future<void> showBudgetEditor(
  BuildContext context, {
  BudgetProgress? existing,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (context) => BudgetEditorSheet(existing: existing),
  );
}

class BudgetEditorSheet extends ConsumerStatefulWidget {
  const BudgetEditorSheet({super.key, this.existing});

  final BudgetProgress? existing;

  @override
  ConsumerState<BudgetEditorSheet> createState() => _BudgetEditorSheetState();
}

class _BudgetEditorSheetState extends ConsumerState<BudgetEditorSheet> {
  late final TextEditingController _amountController;
  late BudgetPeriod _period;
  int? _categoryId;
  String? _error;

  bool get _isEditing => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _period = existing?.budget.period ?? BudgetPeriod.monthly;
    _categoryId = existing?.category.id;
    _amountController = TextEditingController(
      text: existing == null
          ? ''
          : ref.read(moneyFormatterProvider).editable(existing.limit),
    );
  }

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final currency = ref.read(activeCurrencyProvider);
    final separator = ref.read(moneyFormatterProvider).decimalSeparator;
    final limit = AmountField.read(_amountController, currency, separator);
    final categoryId = _categoryId;

    if (categoryId == null) {
      setState(() => _error = 'Pick a category.');
      return;
    }
    if (limit == null || !limit.isPositive) {
      setState(() => _error = 'Enter a limit greater than zero.');
      return;
    }

    final navigator = Navigator.of(context);
    await ref
        .read(databaseProvider)
        .budgetsDao
        .setLimit(categoryId: categoryId, period: _period, limit: limit);
    navigator.pop();
  }

  Future<void> _delete() async {
    final existing = widget.existing;
    if (existing == null) return;
    final navigator = Navigator.of(context);
    await ref
        .read(databaseProvider)
        .budgetsDao
        .deleteBudget(existing.budget.id);
    navigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    final categories =
        ref.watch(categoriesProvider(CategoryKind.expense)).value ??
        const <Category>[];
    final currency = ref.watch(activeCurrencyProvider);
    final formatter = ref.watch(moneyFormatterProvider);

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(Insets.lg, 0, Insets.lg, Insets.xl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _isEditing ? 'Edit budget' : 'New budget',
              style: context.texts.titleLarge,
            ),
            const SizedBox(height: Insets.lg),
            SegmentedButton<BudgetPeriod>(
              segments: [
                for (final period in BudgetPeriod.values)
                  ButtonSegment(value: period, label: Text(period.label)),
              ],
              selected: {_period},
              onSelectionChanged: (selection) =>
                  setState(() => _period = selection.first),
            ),
            const SizedBox(height: Insets.lg),
            AmountField(
              controller: _amountController,
              currency: currency,
              decimalSeparator: formatter.decimalSeparator,
              label: 'Limit',
              autofocus: !_isEditing,
              errorText: _error,
            ),
            const SizedBox(height: Insets.lg),
            Text(
              'Category',
              style: context.texts.labelMedium?.copyWith(
                color: context.colors.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: Insets.sm),
            Wrap(
              spacing: Insets.sm,
              runSpacing: Insets.sm,
              children: [
                for (final category in categories)
                  ChoiceChip(
                    selected: _categoryId == category.id,
                    onSelected: (selected) => setState(
                      () => _categoryId = selected ? category.id : null,
                    ),
                    avatar: Icon(
                      categoryIconFor(category.iconKey),
                      size: 16,
                      color: Color(category.colorValue),
                    ),
                    label: Text(category.name),
                  ),
              ],
            ),
            const SizedBox(height: Insets.xl),
            Row(
              children: [
                if (_isEditing)
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _delete,
                      icon: const Icon(Icons.delete_outline),
                      label: const Text('Remove'),
                    ),
                  ),
                if (_isEditing) const SizedBox(width: Insets.md),
                Expanded(
                  flex: 2,
                  child: FilledButton(
                    onPressed: _save,
                    child: Text(_isEditing ? 'Save' : 'Set budget'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
