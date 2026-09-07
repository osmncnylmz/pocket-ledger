import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/entities.dart';
import '../../domain/enums.dart';
import '../../domain/money.dart';
import '../category_icons.dart';
import '../providers.dart';
import '../theme.dart';
import '../widgets/amount_field.dart';

/// Opens the account editor. Pass [existing] to edit.
Future<void> showAccountEditor(BuildContext context, {Account? existing}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (context) => AccountEditorSheet(existing: existing),
  );
}

/// Creates and edits accounts.
class AccountEditorSheet extends ConsumerStatefulWidget {
  const AccountEditorSheet({super.key, this.existing});

  final Account? existing;

  @override
  ConsumerState<AccountEditorSheet> createState() => _AccountEditorSheetState();
}

class _AccountEditorSheetState extends ConsumerState<AccountEditorSheet> {
  late final TextEditingController _nameController;
  late final TextEditingController _openingController;
  late AccountKind _kind;
  late int _color;
  String? _error;

  bool get _isEditing => widget.existing != null;

  static const _palette = <int>[
    0xFF3F51B5,
    0xFF00897B,
    0xFFD81B60,
    0xFF6A1B9A,
    0xFF2E7D32,
    0xFFEF6C00,
    0xFF00838F,
    0xFF5D4037,
  ];

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _nameController = TextEditingController(text: existing?.name ?? '');
    _kind = existing?.kind ?? AccountKind.checking;
    _color = existing?.colorValue ?? _palette.first;
    _openingController = TextEditingController(
      text: existing == null
          ? ''
          : ref.read(moneyFormatterProvider).editable(existing.openingBalance),
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _openingController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Give the account a name.');
      return;
    }

    final activeCurrency = ref.read(activeCurrencyProvider);
    final currency = widget.existing?.currency ?? activeCurrency;
    final separator = ref.read(moneyFormatterProvider).decimalSeparator;
    final typed = AmountField.read(_openingController, currency, separator);
    final signed = _kind.isLiability && typed != null && typed.isPositive
        ? -typed
        : typed;
    final opening = signed ?? Money.zero(currency);

    final dao = ref.read(databaseProvider).accountsDao;
    final navigator = Navigator.of(context);
    try {
      if (_isEditing) {
        await dao.updateAccount(
          id: widget.existing!.id,
          name: name,
          kind: _kind,
          openingBalance: opening,
          colorValue: _color,
        );
      } else {
        await dao.createAccount(
          name: name,
          kind: _kind,
          openingBalance: opening,
          colorValue: _color,
        );
      }
      navigator.pop();
    } on Object catch (error) {
      setState(
        () => _error = error.toString().contains('UNIQUE')
            ? 'An account called "$name" already exists.'
            : '$error',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final activeCurrency = ref.watch(activeCurrencyProvider);
    final currency = widget.existing?.currency ?? activeCurrency;
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
              _isEditing ? 'Edit account' : 'New account',
              style: context.texts.titleLarge,
            ),
            const SizedBox(height: Insets.lg),
            TextField(
              controller: _nameController,
              autofocus: !_isEditing,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(labelText: 'Name', errorText: _error),
            ),
            const SizedBox(height: Insets.md),
            AmountField(
              controller: _openingController,
              currency: currency,
              decimalSeparator: formatter.decimalSeparator,
              label: _kind.isLiability ? 'Amount owed' : 'Opening balance',
            ),
            const SizedBox(height: Insets.lg),
            Text(
              'Kind',
              style: context.texts.labelMedium?.copyWith(
                color: context.colors.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: Insets.sm),
            Wrap(
              spacing: Insets.sm,
              runSpacing: Insets.sm,
              children: [
                for (final kind in AccountKind.values)
                  ChoiceChip(
                    selected: _kind == kind,
                    onSelected: (_) => setState(() => _kind = kind),
                    avatar: Icon(
                      accountIcons[kind.name] ?? Icons.account_balance_outlined,
                      size: 16,
                    ),
                    label: Text(_kindLabel(kind)),
                  ),
              ],
            ),
            const SizedBox(height: Insets.lg),
            Text(
              'Colour',
              style: context.texts.labelMedium?.copyWith(
                color: context.colors.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: Insets.sm),
            Wrap(
              spacing: Insets.md,
              children: [
                for (final value in _palette)
                  InkResponse(
                    onTap: () => setState(() => _color = value),
                    radius: 22,
                    child: AnimatedContainer(
                      duration: Motion.of(context, Motion.quick),
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: Color(value),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: _color == value
                              ? context.colors.onSurface
                              : Colors.transparent,
                          width: 2.5,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: Insets.xl),
            FilledButton(
              onPressed: _save,
              child: Text(_isEditing ? 'Save' : 'Add account'),
            ),
          ],
        ),
      ),
    );
  }

  static String _kindLabel(AccountKind kind) => switch (kind) {
    AccountKind.cash => 'Cash',
    AccountKind.checking => 'Current',
    AccountKind.savings => 'Savings',
    AccountKind.credit => 'Credit',
    AccountKind.investment => 'Investment',
  };
}
