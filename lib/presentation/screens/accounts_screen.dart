import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/entities.dart';
import '../category_icons.dart';
import '../providers.dart';
import '../sheets/account_editor_sheet.dart';
import '../theme.dart';
import '../widgets/empty_state.dart';
import '../widgets/money_text.dart';

/// Manage accounts: add, edit, archive, delete.
class AccountsScreen extends ConsumerWidget {
  const AccountsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final balances = ref.watch(accountBalancesProvider);
    final all = ref.watch(allAccountsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Accounts')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => showAccountEditor(context),
        icon: const Icon(Icons.add),
        label: const Text('Account'),
      ),
      body: switch (all) {
        AsyncError(:final error) => Center(child: Text('$error')),
        AsyncData(value: final accounts) when accounts.isEmpty =>
          const EmptyState(
            icon: Icons.account_balance_wallet_outlined,
            title: 'No accounts',
            message:
                'An account is where money sits: a wallet, a current account, a '
                'credit card. Add one to start recording against it.',
          ),
        AsyncData(value: final accounts) => ListView(
          padding: const EdgeInsets.only(bottom: 96),
          children: [
            for (final account in accounts.where((a) => !a.archived))
              _AccountTile(
                account: account,
                balance: balances.value
                    ?.where((b) => b.account.id == account.id)
                    .firstOrNull,
              ),
            if (accounts.any((a) => a.archived)) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  Insets.lg,
                  Insets.xl,
                  Insets.lg,
                  Insets.sm,
                ),
                child: Text(
                  'Archived',
                  style: context.texts.labelLarge?.copyWith(
                    color: context.colors.onSurfaceVariant,
                  ),
                ),
              ),
              for (final account in accounts.where((a) => a.archived))
                _AccountTile(account: account, balance: null),
            ],
          ],
        ),
        _ => const Center(child: CircularProgressIndicator()),
      },
    );
  }
}

class _AccountTile extends ConsumerWidget {
  const _AccountTile({required this.account, required this.balance});

  final Account account;
  final AccountBalance? balance;

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete ${account.name}?'),
        content: const Text(
          'Every transaction in this account is deleted too, and any transfer '
          'to or from it is removed from the other side as well. This cannot '
          'be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed ?? false) {
      await ref.read(databaseProvider).accountsDao.deleteAccount(account.id);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final color = Color(account.colorValue);

    return ListTile(
      onTap: () => showAccountEditor(context, existing: account),
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: color.withValues(alpha: account.archived ? 0.08 : 0.16),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(
          accountIcons[account.kind.name] ?? Icons.account_balance_outlined,
          size: 20,
          color: account.archived ? context.colors.outline : color,
        ),
      ),
      title: Text(account.name),
      subtitle: Text(
        '${account.kind.name[0].toUpperCase()}${account.kind.name.substring(1)}'
        ' · ${account.currency.code}',
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (balance != null)
            MoneyText(
              balance!.balance,
              style: context.texts.bodyLarge?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          PopupMenuButton<String>(
            onSelected: (value) async {
              switch (value) {
                case 'archive':
                  await ref
                      .read(databaseProvider)
                      .accountsDao
                      .setArchived(account.id, archived: !account.archived);
                case 'delete':
                  if (context.mounted) await _confirmDelete(context, ref);
              }
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'archive',
                child: Text(account.archived ? 'Unarchive' : 'Archive'),
              ),
              const PopupMenuItem(value: 'delete', child: Text('Delete')),
            ],
          ),
        ],
      ),
    );
  }
}
