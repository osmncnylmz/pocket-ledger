import 'package:drift/drift.dart';

import '../../domain/entities.dart';
import '../../domain/enums.dart';
import '../../domain/money.dart';
import '../database.dart';
import '../mappers.dart';

part 'accounts_dao.g.dart';

@DriftAccessor(tables: [Accounts, Transactions])
class AccountsDao extends DatabaseAccessor<AppDatabase>
    with _$AccountsDaoMixin {
  AccountsDao(super.db);

  /// `opening_balance_minor + COALESCE(SUM(amount_minor), 0)`, evaluated by
  /// SQLite in one grouped left join. Reading every row and adding it up in
  /// Dart works fine for a demo and falls over for a ledger.
  Stream<List<AccountBalance>> watchBalances({bool includeArchived = false}) {
    final posted = transactions.amountMinor.sum();
    final balance =
        accounts.openingBalanceMinor + coalesce([posted, const Constant(0)]);

    final query =
        select(accounts).join([
            leftOuterJoin(
              transactions,
              transactions.accountId.equalsExp(accounts.id),
            ),
          ])
          ..addColumns([balance])
          ..groupBy([accounts.id])
          ..orderBy([
            OrderingTerm.asc(accounts.sortOrder),
            OrderingTerm.asc(accounts.name),
          ]);

    if (!includeArchived) {
      query.where(accounts.archived.equals(false));
    }

    return query.watch().map(
      (rows) => rows.map((row) {
        final account = row.readTable(accounts).toEntity();
        return AccountBalance(
          account: account,
          balance: Money(row.read(balance) ?? 0, account.currency),
        );
      }).toList(),
    );
  }

  /// A ledger holding EUR and USD accounts gets two honest numbers rather
  /// than one meaningless one.
  ///
  /// Hand-written SQL because the fold happens in two stages: per account
  /// first — otherwise the left join repeats each opening balance once per
  /// entry and inflates the total — then per currency.
  Stream<Map<Currency, Money>> watchTotalsByCurrency() {
    return customSelect(
      '''
SELECT currency_code, SUM(balance) AS total_minor
FROM (
  SELECT a.currency_code                                       AS currency_code,
         a.opening_balance_minor + COALESCE(SUM(t.amount_minor), 0) AS balance
  FROM accounts a
  LEFT JOIN transactions t ON t.account_id = a.id
  WHERE a.archived = 0
  GROUP BY a.id
)
GROUP BY currency_code
ORDER BY currency_code
''',
      readsFrom: {accounts, transactions},
    ).watch().map((rows) {
      return {
        for (final row in rows)
          Currency.byCode(row.read<String>('currency_code')): Money(
            row.read<int>('total_minor'),
            Currency.byCode(row.read<String>('currency_code')),
          ),
      };
    });
  }

  Stream<List<Account>> watchAccounts({bool includeArchived = false}) {
    final query = select(accounts)
      ..orderBy([
        (a) => OrderingTerm.asc(a.sortOrder),
        (a) => OrderingTerm.asc(a.name),
      ]);
    if (!includeArchived) {
      query.where((a) => a.archived.equals(false));
    }
    return query.watch().map((rows) => rows.map((r) => r.toEntity()).toList());
  }

  Future<List<Account>> allAccounts({bool includeArchived = false}) {
    final query = select(accounts)
      ..orderBy([
        (a) => OrderingTerm.asc(a.sortOrder),
        (a) => OrderingTerm.asc(a.name),
      ]);
    if (!includeArchived) {
      query.where((a) => a.archived.equals(false));
    }
    return query.get().then((rows) => rows.map((r) => r.toEntity()).toList());
  }

  Future<Account?> findById(int id) async {
    final row = await (select(
      accounts,
    )..where((a) => a.id.equals(id))).getSingleOrNull();
    return row?.toEntity();
  }

  Future<int> createAccount({
    required String name,
    required AccountKind kind,
    required Money openingBalance,
    required int colorValue,
  }) async {
    final nextOrder =
        await (selectOnly(accounts)..addColumns([accounts.sortOrder.max()]))
            .map((row) => row.read(accounts.sortOrder.max()))
            .getSingleOrNull() ??
        0;

    return into(accounts).insert(
      AccountsCompanion.insert(
        name: name,
        kind: kind,
        currencyCode: openingBalance.currency.code,
        colorValue: colorValue,
        openingBalanceMinor: Value(openingBalance.minorUnits),
        sortOrder: Value(nextOrder + 1),
      ),
    );
  }

  Future<void> updateAccount({
    required int id,
    required String name,
    required AccountKind kind,
    required Money openingBalance,
    required int colorValue,
  }) {
    return (update(accounts)..where((a) => a.id.equals(id))).write(
      AccountsCompanion(
        name: Value(name),
        kind: Value(kind),
        openingBalanceMinor: Value(openingBalance.minorUnits),
        currencyCode: Value(openingBalance.currency.code),
        colorValue: Value(colorValue),
      ),
    );
  }

  Future<void> setArchived(int id, {required bool archived}) {
    return (update(accounts)..where((a) => a.id.equals(id))).write(
      AccountsCompanion(archived: Value(archived)),
    );
  }

  /// Entries in this account go by `ON DELETE CASCADE`. That alone would
  /// strand the *far* leg of every transfer in another account, still claiming
  /// to be a transfer, so those are removed first in the same transaction.
  Future<void> deleteAccount(int id) {
    return transaction(() async {
      await customStatement(
        'DELETE FROM transactions '
        'WHERE counterpart_id IN '
        '(SELECT id FROM transactions WHERE account_id = ?)',
        [id],
      );
      await (delete(accounts)..where((a) => a.id.equals(id))).go();
    });
  }

  Future<void> reorder(List<int> idsInOrder) {
    return transaction(() async {
      for (var index = 0; index < idsInOrder.length; index++) {
        await (update(accounts)..where((a) => a.id.equals(idsInOrder[index])))
            .write(AccountsCompanion(sortOrder: Value(index)));
      }
    });
  }
}
