import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../domain/entities.dart';
import '../../domain/enums.dart';
import '../../domain/services/transfer.dart';
import '../category_icons.dart';
import '../providers.dart';
import '../theme.dart';
import '../widgets/amount_field.dart';
import '../widgets/empty_state.dart';

Future<void> showTransactionEditor(
  BuildContext context, {
  LedgerEntryDetail? existing,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (context) => TransactionEditorSheet(existing: existing),
  );
}

/// Bottom sheet for creating or editing one transaction, transfers included.
class TransactionEditorSheet extends ConsumerStatefulWidget {
  const TransactionEditorSheet({super.key, this.existing});

  final LedgerEntryDetail? existing;

  @override
  ConsumerState<TransactionEditorSheet> createState() =>
      _TransactionEditorSheetState();
}

class _TransactionEditorSheetState
    extends ConsumerState<TransactionEditorSheet> {
  late final TextEditingController _amountController;
  late final TextEditingController _noteController;

  late TransactionType _type;
  late DateTime _date;
  int? _accountId;
  int? _destinationAccountId;
  int? _categoryId;
  String? _error;
  bool _saving = false;

  bool get _isEditing => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    final formatter = ref.read(moneyFormatterProvider);

    _type = existing?.entry.type ?? TransactionType.expense;
    _date = existing?.date ?? ref.read(nowProvider);
    _accountId = existing?.account.id;
    _categoryId = existing?.category?.id;
    _noteController = TextEditingController(text: existing?.entry.note ?? '');

    if (existing != null && existing.entry.type.isTransfer) {
      // Show a transfer as "from → to" whichever leg was tapped, or editing
      // the incoming side would silently reverse it.
      if (existing.entry.isOutflow) {
        _accountId = existing.account.id;
        _destinationAccountId = existing.counterpartAccount?.id;
      } else {
        _accountId = existing.counterpartAccount?.id;
        _destinationAccountId = existing.account.id;
      }
    }

    _amountController = TextEditingController(
      text: existing == null ? '' : formatter.editable(existing.amount.abs),
    );
  }

  @override
  void dispose() {
    _amountController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  CategoryKind get _categoryKind => _type == TransactionType.income
      ? CategoryKind.income
      : CategoryKind.expense;

  Future<void> _save(List<Account> accounts) async {
    final currency = ref.read(activeCurrencyProvider);
    final formatter = ref.read(moneyFormatterProvider);
    final amount = AmountField.read(
      _amountController,
      currency,
      formatter.decimalSeparator,
    );

    if (amount == null || !amount.isPositive) {
      setState(() => _error = 'Enter an amount greater than zero.');
      return;
    }
    final accountId = _accountId;
    if (accountId == null) {
      setState(() => _error = 'Pick an account.');
      return;
    }

    final dao = ref.read(databaseProvider).transactionsDao;
    setState(() {
      _error = null;
      _saving = true;
    });

    try {
      if (_type.isTransfer) {
        final destinationId = _destinationAccountId;
        if (destinationId == null) {
          setState(() {
            _error = 'Pick an account to transfer into.';
            _saving = false;
          });
          return;
        }
        final draft = TransferDraft(
          from: accounts.firstWhere((a) => a.id == accountId),
          to: accounts.firstWhere((a) => a.id == destinationId),
          amount: amount,
          date: _date,
          note: _noteController.text.trim(),
        );
        final problems = draft.validate();
        if (problems.isNotEmpty) {
          setState(() {
            _error = problems.map(describeTransferProblem).join(' ');
            _saving = false;
          });
          return;
        }

        final existing = widget.existing;
        if (existing != null && existing.entry.type.isTransfer) {
          await dao.updateTransfer(existing.id, draft);
        } else {
          if (existing != null) await dao.deleteEntry(existing.id);
          await dao.createTransfer(draft);
        }
      } else {
        final existing = widget.existing;
        if (existing != null && !existing.entry.type.isTransfer) {
          await dao.updateEntry(
            id: existing.id,
            accountId: accountId,
            categoryId: _categoryId,
            amount: amount,
            date: _date,
            type: _type,
            note: _noteController.text.trim(),
          );
        } else {
          if (existing != null) await dao.deleteEntry(existing.id);
          await dao.createEntry(
            accountId: accountId,
            categoryId: _categoryId,
            amount: amount,
            date: _date,
            type: _type,
            note: _noteController.text.trim(),
          );
        }
      }

      if (mounted) Navigator.of(context).pop();
    } on Object catch (error) {
      setState(() {
        _error = '$error';
        _saving = false;
      });
    }
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2000),
      lastDate: DateTime(ref.read(nowProvider).year + 5),
    );
    if (picked != null) {
      setState(
        () => _date = DateTime(
          picked.year,
          picked.month,
          picked.day,
          _date.hour,
          _date.minute,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final accounts = ref.watch(allAccountsProvider).value ?? const <Account>[];
    final active = accounts.where((a) => !a.archived).toList();
    final categories =
        ref.watch(categoriesProvider(_categoryKind)).value ??
        const <Category>[];
    final currency = ref.watch(activeCurrencyProvider);
    final formatter = ref.watch(moneyFormatterProvider);

    _accountId ??= active.firstOrNull?.id;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(Insets.lg, 0, Insets.lg, Insets.xl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _isEditing ? 'Edit transaction' : 'New transaction',
              style: context.texts.titleLarge,
            ),
            const SizedBox(height: Insets.lg),
            if (active.isEmpty)
              const EmptyState(
                icon: Icons.account_balance_wallet_outlined,
                title: 'No accounts yet',
                message: 'Add an account in Settings before recording money.',
                compact: true,
              )
            else ...[
              SegmentedButton<TransactionType>(
                segments: const [
                  ButtonSegment(
                    value: TransactionType.expense,
                    label: Text('Expense'),
                    icon: Icon(Icons.south_west),
                  ),
                  ButtonSegment(
                    value: TransactionType.income,
                    label: Text('Income'),
                    icon: Icon(Icons.north_east),
                  ),
                  ButtonSegment(
                    value: TransactionType.transfer,
                    label: Text('Transfer'),
                    icon: Icon(Icons.swap_horiz),
                  ),
                ],
                selected: {_type},
                onSelectionChanged: (selection) => setState(() {
                  _type = selection.first;
                  if (_type.isTransfer) {
                    _categoryId = null;
                    _destinationAccountId ??= active
                        .where((a) => a.id != _accountId)
                        .firstOrNull
                        ?.id;
                  }
                }),
              ),
              const SizedBox(height: Insets.lg),
              AmountField(
                controller: _amountController,
                currency: currency,
                decimalSeparator: formatter.decimalSeparator,
                autofocus: !_isEditing,
                errorText: _error,
              ),
              const SizedBox(height: Insets.md),
              _AccountPicker(
                label: _type.isTransfer ? 'From' : 'Account',
                accounts: active,
                value: _accountId,
                onChanged: (id) => setState(() => _accountId = id),
              ),
              if (_type.isTransfer) ...[
                const SizedBox(height: Insets.md),
                _AccountPicker(
                  label: 'To',
                  accounts: active,
                  value: _destinationAccountId,
                  onChanged: (id) => setState(() => _destinationAccountId = id),
                ),
              ] else ...[
                const SizedBox(height: Insets.lg),
                _CategoryPicker(
                  categories: categories,
                  value: _categoryId,
                  onChanged: (id) => setState(() => _categoryId = id),
                ),
              ],
              const SizedBox(height: Insets.md),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _pickDate,
                      icon: const Icon(Icons.event_outlined),
                      label: Text(DateFormat.yMMMd().format(_date)),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: Insets.md),
              TextField(
                controller: _noteController,
                maxLength: 200,
                decoration: const InputDecoration(
                  labelText: 'Note',
                  counterText: '',
                ),
              ),
              const SizedBox(height: Insets.lg),
              Row(
                children: [
                  if (_isEditing)
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _saving ? null : _deleteExisting,
                        icon: const Icon(Icons.delete_outline),
                        label: const Text('Delete'),
                      ),
                    ),
                  if (_isEditing) const SizedBox(width: Insets.md),
                  Expanded(
                    flex: 2,
                    child: FilledButton(
                      onPressed: _saving ? null : () => _save(active),
                      child: Text(_isEditing ? 'Save changes' : 'Add'),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _deleteExisting() async {
    final existing = widget.existing;
    if (existing == null) return;
    final navigator = Navigator.of(context);
    await ref.read(databaseProvider).transactionsDao.deleteEntry(existing.id);
    navigator.pop();
  }
}

class _AccountPicker extends StatelessWidget {
  const _AccountPicker({
    required this.label,
    required this.accounts,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final List<Account> accounts;
  final int? value;
  final ValueChanged<int?> onChanged;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<int>(
      initialValue: accounts.any((a) => a.id == value) ? value : null,
      decoration: InputDecoration(labelText: label),
      items: [
        for (final account in accounts)
          DropdownMenuItem(
            value: account.id,
            child: Row(
              children: [
                Icon(
                  accountIcons[account.kind.name] ??
                      Icons.account_balance_outlined,
                  size: 18,
                  color: Color(account.colorValue),
                ),
                const SizedBox(width: Insets.sm),
                Text(account.name),
              ],
            ),
          ),
      ],
      onChanged: onChanged,
    );
  }
}

class _CategoryPicker extends StatelessWidget {
  const _CategoryPicker({
    required this.categories,
    required this.value,
    required this.onChanged,
  });

  final List<Category> categories;
  final int? value;
  final ValueChanged<int?> onChanged;

  @override
  Widget build(BuildContext context) {
    if (categories.isEmpty) {
      return Text(
        'No categories yet. Add one in Settings.',
        style: context.texts.bodySmall?.copyWith(
          color: context.colors.onSurfaceVariant,
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
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
                selected: value == category.id,
                onSelected: (selected) =>
                    onChanged(selected ? category.id : null),
                avatar: Icon(
                  categoryIconFor(category.iconKey),
                  size: 16,
                  color: Color(category.colorValue),
                ),
                label: Text(category.name),
              ),
          ],
        ),
      ],
    );
  }
}
