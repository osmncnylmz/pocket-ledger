import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../domain/date_range.dart';
import '../../domain/entities.dart';
import '../../domain/enums.dart';
import '../../domain/money.dart';
import '../../domain/transaction_filter.dart';
import '../providers.dart';
import '../theme.dart';
import '../widgets/amount_field.dart';

Future<void> showFilterSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (context) => const FilterSheet(),
  );
}

/// Every control here maps onto a `WHERE` clause. Nothing is filtered after
/// the query comes back.
class FilterSheet extends ConsumerStatefulWidget {
  const FilterSheet({super.key});

  @override
  ConsumerState<FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends ConsumerState<FilterSheet> {
  late TransactionFilter _draft;
  late final TextEditingController _minController;
  late final TextEditingController _maxController;

  @override
  void initState() {
    super.initState();
    _draft = ref.read(transactionFilterProvider);
    final currency = ref.read(activeCurrencyProvider);
    final formatter = ref.read(moneyFormatterProvider);

    _minController = TextEditingController(
      text: _draft.minAmountMinor == null
          ? ''
          : formatter.editable(Money(_draft.minAmountMinor!, currency)),
    );
    _maxController = TextEditingController(
      text: _draft.maxAmountMinor == null
          ? ''
          : formatter.editable(Money(_draft.maxAmountMinor!, currency)),
    );
  }

  @override
  void dispose() {
    _minController.dispose();
    _maxController.dispose();
    super.dispose();
  }

  void _apply() {
    final currency = ref.read(activeCurrencyProvider);
    final separator = ref.read(moneyFormatterProvider).decimalSeparator;

    final min = AmountField.read(_minController, currency, separator);
    final max = AmountField.read(_maxController, currency, separator);

    ref
        .read(transactionFilterProvider.notifier)
        .apply(
          _draft.copyWith(
            clearAmounts: true,
            minAmountMinor: min?.minorUnits,
            maxAmountMinor: max?.minorUnits,
          ),
        );
    Navigator.of(context).pop();
  }

  Future<void> _pickRange() async {
    final now = ref.read(nowProvider);
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: DateTime(now.year + 5),
      initialDateRange: _draft.range == null
          ? null
          : DateTimeRange(
              start: _draft.range!.start,
              end: _draft.range!.end.subtract(const Duration(days: 1)),
            ),
    );
    if (picked != null) {
      setState(
        () => _draft = _draft.copyWith(
          range: DateRange(
            startOfDay(picked.start),
            startOfDay(picked.end).add(const Duration(days: 1)),
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final accounts = ref.watch(allAccountsProvider).value ?? const <Account>[];
    final expenseCategories =
        ref.watch(categoriesProvider(CategoryKind.expense)).value ??
        const <Category>[];
    final incomeCategories =
        ref.watch(categoriesProvider(CategoryKind.income)).value ??
        const <Category>[];
    final currency = ref.watch(activeCurrencyProvider);
    final formatter = ref.watch(moneyFormatterProvider);

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(Insets.lg, 0, Insets.lg, Insets.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Text('Filter', style: context.texts.titleLarge),
              const Spacer(),
              TextButton(
                onPressed: () {
                  _minController.clear();
                  _maxController.clear();
                  setState(() => _draft = TransactionFilter.empty);
                },
                child: const Text('Reset'),
              ),
            ],
          ),
          const SizedBox(height: Insets.md),
          const _Label('Date range'),
          const SizedBox(height: Insets.sm),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _pickRange,
                  icon: const Icon(Icons.date_range_outlined),
                  label: Text(
                    _draft.range == null
                        ? 'Any date'
                        : '${DateFormat.yMMMd().format(_draft.range!.start)}'
                              ' – '
                              '${DateFormat.yMMMd().format(_draft.range!.end.subtract(const Duration(days: 1)))}',
                  ),
                ),
              ),
              if (_draft.range != null)
                IconButton(
                  tooltip: 'Clear date range',
                  onPressed: () => setState(
                    () => _draft = _draft.copyWith(clearRange: true),
                  ),
                  icon: const Icon(Icons.close),
                ),
            ],
          ),
          const SizedBox(height: Insets.sm),
          Wrap(
            spacing: Insets.sm,
            children: [
              for (final preset in _presets(ref.read(nowProvider)))
                ActionChip(
                  label: Text(preset.$1),
                  onPressed: () => setState(
                    () => _draft = _draft.copyWith(range: preset.$2),
                  ),
                ),
            ],
          ),
          const SizedBox(height: Insets.lg),
          const _Label('Type'),
          const SizedBox(height: Insets.sm),
          Wrap(
            spacing: Insets.sm,
            children: [
              for (final type in TransactionType.values)
                FilterChip(
                  label: Text(_typeLabel(type)),
                  selected: _draft.types.contains(type),
                  onSelected: (selected) => setState(() {
                    final types = {..._draft.types};
                    if (selected) {
                      types.add(type);
                    } else {
                      types.remove(type);
                    }
                    _draft = _draft.copyWith(types: types);
                  }),
                ),
            ],
          ),
          if (accounts.isNotEmpty) ...[
            const SizedBox(height: Insets.lg),
            const _Label('Accounts'),
            const SizedBox(height: Insets.sm),
            Wrap(
              spacing: Insets.sm,
              runSpacing: Insets.sm,
              children: [
                for (final account in accounts)
                  FilterChip(
                    label: Text(account.name),
                    selected: _draft.accountIds.contains(account.id),
                    onSelected: (selected) => setState(() {
                      final ids = {..._draft.accountIds};
                      if (selected) {
                        ids.add(account.id);
                      } else {
                        ids.remove(account.id);
                      }
                      _draft = _draft.copyWith(accountIds: ids);
                    }),
                  ),
              ],
            ),
          ],
          if (expenseCategories.isNotEmpty || incomeCategories.isNotEmpty) ...[
            const SizedBox(height: Insets.lg),
            const _Label('Categories'),
            const SizedBox(height: Insets.sm),
            Wrap(
              spacing: Insets.sm,
              runSpacing: Insets.sm,
              children: [
                for (final category in [
                  ...expenseCategories,
                  ...incomeCategories,
                ])
                  FilterChip(
                    label: Text(category.name),
                    selected: _draft.categoryIds.contains(category.id),
                    onSelected: (selected) => setState(() {
                      final ids = {..._draft.categoryIds};
                      if (selected) {
                        ids.add(category.id);
                      } else {
                        ids.remove(category.id);
                      }
                      _draft = _draft.copyWith(categoryIds: ids);
                    }),
                  ),
              ],
            ),
          ],
          const SizedBox(height: Insets.lg),
          const _Label('Amount between'),
          const SizedBox(height: Insets.sm),
          Row(
            children: [
              Expanded(
                child: AmountField(
                  controller: _minController,
                  currency: currency,
                  decimalSeparator: formatter.decimalSeparator,
                  label: 'Least',
                ),
              ),
              const SizedBox(width: Insets.md),
              Expanded(
                child: AmountField(
                  controller: _maxController,
                  currency: currency,
                  decimalSeparator: formatter.decimalSeparator,
                  label: 'Most',
                ),
              ),
            ],
          ),
          const SizedBox(height: Insets.xl),
          FilledButton(onPressed: _apply, child: const Text('Show results')),
        ],
      ),
    );
  }

  static String _typeLabel(TransactionType type) => switch (type) {
    TransactionType.expense => 'Expenses',
    TransactionType.income => 'Income',
    TransactionType.transfer => 'Transfers',
  };

  static List<(String, DateRange)> _presets(DateTime now) => [
    ('This month', DateRange.month(now)),
    ('Last month', DateRange.month(DateTime(now.year, now.month - 1))),
    ('This week', DateRange.week(now)),
    ('This year', DateRange.year(now)),
  ];
}

class _Label extends StatelessWidget {
  const _Label(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: context.texts.labelLarge?.copyWith(
        color: context.colors.onSurfaceVariant,
      ),
    );
  }
}
