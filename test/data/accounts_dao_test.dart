import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_ledger/data/database.dart';
import 'package:pocket_ledger/domain/enums.dart';
import 'package:pocket_ledger/domain/money.dart';
import 'package:pocket_ledger/domain/services/transfer.dart';

import 'fixtures.dart';
import 'test_database.dart';

void main() {
  late AppDatabase db;

  setUp(() => db = newTestDatabase());
  tearDown(() => db.close());

  test('a balance is the opening balance plus every posted entry', () async {
    final account = await db.makeAccount(
      'Everyday',
      openingBalance: Money.major(1000, Currency.usd),
    );
    final groceries = await db.makeCategory('Groceries');
    final salary = await db.makeCategory('Salary', kind: CategoryKind.income);

    await db.spend(account, groceries, 4599, DateTime(2026, 3, 2));
    await db.spend(account, groceries, 1250, DateTime(2026, 3, 3));
    await db.earn(account, salary, 250000, DateTime(2026, 3, 25));

    final balances = await db.accountsDao.watchBalances().first;

    // 100000 - 4599 - 1250 + 250000
    expect(balances.single.balance, const Money(344151, Currency.usd));
  });

  test(
    'an account with no entries still reports its opening balance',
    () async {
      await db.makeAccount(
        'Savings',
        openingBalance: Money.major(250, Currency.usd),
      );

      final balances = await db.accountsDao.watchBalances().first;
      expect(balances.single.balance, Money.major(250, Currency.usd));
    },
  );

  test('archived accounts are hidden unless asked for', () async {
    final account = await db.makeAccount('Old card');
    await db.makeAccount('Everyday');

    await db.accountsDao.setArchived(account.id, archived: true);

    expect(await db.accountsDao.allAccounts(), hasLength(1));
    expect(
      await db.accountsDao.allAccounts(includeArchived: true),
      hasLength(2),
    );
  });

  test('per-currency totals do not multiply opening balances by entry count', () async {
    // The regression this guards: a naive `SUM(opening_balance) + SUM(amount)`
    // over a left join counts the opening balance once per transaction.
    final usd = await db.makeAccount(
      'Everyday',
      openingBalance: Money.major(1000, Currency.usd),
    );
    final euro = await db.makeAccount(
      'Berlin',
      openingBalance: Money.major(500, Currency.eur),
      currency: Currency.eur,
    );
    final groceries = await db.makeCategory('Groceries');

    for (var day = 1; day <= 5; day++) {
      await db.spend(usd, groceries, 1000, DateTime(2026, 3, day));
    }
    await db.spend(euro, groceries, 2000, DateTime(2026, 3));

    final totals = await db.accountsDao.watchTotalsByCurrency().first;

    expect(totals[Currency.usd], const Money(95000, Currency.usd));
    expect(totals[Currency.eur], const Money(48000, Currency.eur));
  });

  test(
    'deleting an account also removes the far leg of its transfers',
    () async {
      final everyday = await db.makeAccount(
        'Everyday',
        openingBalance: Money.major(1000, Currency.usd),
      );
      final savings = await db.makeAccount('Savings');

      await db.transactionsDao.createTransfer(
        TransferDraft(
          from: everyday,
          to: savings,
          amount: Money.major(200, Currency.usd),
          date: DateTime(2026, 3, 10),
        ),
      );
      expect(await db.transactionsDao.countAll(), 2);

      await db.accountsDao.deleteAccount(everyday.id);

      // Both legs are gone: the savings account must not be left holding an
      // incoming transfer from an account that no longer exists.
      expect(await db.transactionsDao.countAll(), 0);
      final balances = await db.accountsDao.watchBalances().first;
      expect(balances.single.account.name, 'Savings');
      expect(balances.single.balance, const Money.zero(Currency.usd));
    },
  );

  test('account names are unique', () async {
    await db.makeAccount('Everyday');
    await expectLater(
      db.makeAccount('Everyday'),
      throwsA(
        predicate<Object>(
          (error) => error.toString().contains('UNIQUE'),
          'a UNIQUE constraint violation',
        ),
      ),
    );
  });
}
