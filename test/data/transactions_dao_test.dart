import 'package:drift/drift.dart' show Variable;
import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_ledger/data/database.dart';
import 'package:pocket_ledger/domain/date_range.dart';
import 'package:pocket_ledger/domain/entities.dart';
import 'package:pocket_ledger/domain/enums.dart';
import 'package:pocket_ledger/domain/money.dart';
import 'package:pocket_ledger/domain/services/transfer.dart';
import 'package:pocket_ledger/domain/transaction_filter.dart';

import 'fixtures.dart';
import 'test_database.dart';

void main() {
  late AppDatabase db;
  late Account everyday;
  late Account savings;
  late Category groceries;
  late Category dining;
  late Category salary;

  setUp(() async {
    db = newTestDatabase();
    everyday = await db.makeAccount(
      'Everyday',
      openingBalance: Money.major(2000, Currency.usd),
    );
    savings = await db.makeAccount(
      'Savings',
      kind: AccountKind.savings,
      openingBalance: Money.major(5000, Currency.usd),
    );
    groceries = await db.makeCategory('Groceries');
    dining = await db.makeCategory('Dining', iconKey: 'dining');
    salary = await db.makeCategory('Salary', kind: CategoryKind.income);
  });

  tearDown(() => db.close());

  group('signs', () {
    test('an expense is stored negative and income positive', () async {
      await db.spend(everyday, groceries, 4599, DateTime(2026, 3, 2));
      await db.earn(everyday, salary, 250000, DateTime(2026, 3, 25));

      final rows = await db.select(db.transactions).get();
      final expense = rows.firstWhere((r) => r.type == TransactionType.expense);
      final income = rows.firstWhere((r) => r.type == TransactionType.income);

      expect(expense.amountMinor, -4599);
      expect(income.amountMinor, 250000);
    });

    test('a magnitude passed to an expense is never stored positive', () async {
      // The DAO applies the sign, so callers cannot post an expense that
      // increases a balance by mistake.
      await db.transactionsDao.createEntry(
        accountId: everyday.id,
        categoryId: groceries.id,
        amount: const Money(1234, Currency.usd),
        date: DateTime(2026, 3, 2),
        type: TransactionType.expense,
      );
      final row = await db.select(db.transactions).getSingle();
      expect(row.amountMinor, -1234);
    });

    test('the schema rejects an expense with a positive amount', () async {
      await expectLater(
        db.customStatement(
          'INSERT INTO transactions (account_id, amount_minor, date, note, '
          "type, created_at) VALUES (${everyday.id}, 500, 1700000000, '', "
          "'expense', 1700000000)",
        ),
        throwsA(
          predicate<Object>(
            (error) => error.toString().contains('CHECK'),
            'a CHECK constraint violation',
          ),
        ),
      );
    });

    test('the schema rejects a categorised transfer', () async {
      await expectLater(
        db.customStatement(
          'INSERT INTO transactions (account_id, category_id, amount_minor, '
          'date, note, type, created_at) VALUES (${everyday.id}, '
          "${groceries.id}, -500, 1700000000, '', 'transfer', 1700000000)",
        ),
        throwsA(
          predicate<Object>(
            (error) => error.toString().contains('CHECK'),
            'a CHECK constraint violation',
          ),
        ),
      );
    });
  });

  group('transfers', () {
    test('post as two mirrored legs that point at each other', () async {
      final outgoingId = await db.transactionsDao.createTransfer(
        TransferDraft(
          from: everyday,
          to: savings,
          amount: Money.major(300, Currency.usd),
          date: DateTime(2026, 3, 26),
          note: 'Standing order',
        ),
      );

      final rows = await db.select(db.transactions).get();
      expect(rows, hasLength(2));

      final outgoing = rows.firstWhere((r) => r.id == outgoingId);
      final incoming = rows.firstWhere((r) => r.id != outgoingId);

      expect(outgoing.accountId, everyday.id);
      expect(incoming.accountId, savings.id);
      expect(outgoing.amountMinor, -30000);
      expect(incoming.amountMinor, 30000);
      expect(outgoing.amountMinor + incoming.amountMinor, 0);
      expect(outgoing.counterpartId, incoming.id);
      expect(incoming.counterpartId, outgoing.id);
      expect(outgoing.categoryId, isNull);
      expect(incoming.categoryId, isNull);
      expect(outgoing.date, incoming.date);
    });

    test('move money between balances without changing net worth', () async {
      final before = await db.accountsDao.watchTotalsByCurrency().first;

      await db.transactionsDao.createTransfer(
        TransferDraft(
          from: everyday,
          to: savings,
          amount: Money.major(300, Currency.usd),
          date: DateTime(2026, 3, 26),
        ),
      );

      final balances = await db.accountsDao.watchBalances().first;
      final byName = {for (final b in balances) b.account.name: b.balance};
      expect(byName['Everyday'], Money.major(1700, Currency.usd));
      expect(byName['Savings'], Money.major(5300, Currency.usd));

      final after = await db.accountsDao.watchTotalsByCurrency().first;
      expect(after[Currency.usd], before[Currency.usd]);
    });

    test('are refused when the two sides are the same account', () async {
      expect(
        () => db.transactionsDao.createTransfer(
          TransferDraft(
            from: everyday,
            to: everyday,
            amount: Money.major(10, Currency.usd),
            date: DateTime(2026, 3, 26),
          ),
        ),
        throwsArgumentError,
      );
    });

    test('are refused across currencies', () async {
      final berlin = await db.makeAccount(
        'Berlin',
        currency: Currency.eur,
        openingBalance: const Money.zero(Currency.eur),
      );
      expect(
        () => db.transactionsDao.createTransfer(
          TransferDraft(
            from: everyday,
            to: berlin,
            amount: Money.major(10, Currency.usd),
            date: DateTime(2026, 3, 26),
          ),
        ),
        throwsArgumentError,
      );
    });

    test('editing one leg rewrites both', () async {
      final outgoingId = await db.transactionsDao.createTransfer(
        TransferDraft(
          from: everyday,
          to: savings,
          amount: Money.major(300, Currency.usd),
          date: DateTime(2026, 3, 26),
        ),
      );
      final incomingId = (await db.transactionsDao.findById(outgoingId))!
          .entry
          .counterpartId!;

      // Edit through the *incoming* leg, and swap the direction as well.
      await db.transactionsDao.updateTransfer(
        incomingId,
        TransferDraft(
          from: savings,
          to: everyday,
          amount: Money.major(125, Currency.usd),
          date: DateTime(2026, 4),
          note: 'Moved back',
        ),
      );

      final rows = await db.select(db.transactions).get();
      expect(rows, hasLength(2));
      final fromSavings = rows.firstWhere((r) => r.accountId == savings.id);
      final toEveryday = rows.firstWhere((r) => r.accountId == everyday.id);

      expect(fromSavings.amountMinor, -12500);
      expect(toEveryday.amountMinor, 12500);
      expect(fromSavings.date, DateTime(2026, 4));
      expect(toEveryday.date, DateTime(2026, 4));
      expect(fromSavings.note, 'Moved back');
      expect(fromSavings.counterpartId, toEveryday.id);
      expect(toEveryday.counterpartId, fromSavings.id);
    });

    test('deleting one leg deletes both, and undo restores both', () async {
      final outgoingId = await db.transactionsDao.createTransfer(
        TransferDraft(
          from: everyday,
          to: savings,
          amount: Money.major(300, Currency.usd),
          date: DateTime(2026, 3, 26),
        ),
      );

      final removed = await db.transactionsDao.deleteEntry(outgoingId);
      expect(removed, hasLength(2));
      expect(await db.transactionsDao.countAll(), 0);

      await db.transactionsDao.restoreEntries(removed);

      final rows = await db.select(db.transactions).get();
      expect(rows, hasLength(2));
      final restoredOutgoing = rows.firstWhere((r) => r.id == outgoingId);
      expect(restoredOutgoing.amountMinor, -30000);
      expect(restoredOutgoing.counterpartId, isNotNull);
      // The mutual link survives the round trip.
      final sibling = rows.firstWhere(
        (r) => r.id == restoredOutgoing.counterpartId,
      );
      expect(sibling.counterpartId, restoredOutgoing.id);
    });

    test('are excluded from category spend and monthly totals', () async {
      await db.spend(everyday, groceries, 5000, DateTime(2026, 3, 5));
      await db.transactionsDao.createTransfer(
        TransferDraft(
          from: everyday,
          to: savings,
          amount: Money.major(300, Currency.usd),
          date: DateTime(2026, 3, 26),
        ),
      );

      final spend = await db.transactionsDao
          .watchCategorySpend(
            DateRange.month(DateTime(2026, 3, 15)),
            currency: Currency.usd,
          )
          .first;
      expect(spend, hasLength(1));
      expect(spend.single.total, const Money(5000, Currency.usd));

      final totals = await db.transactionsDao
          .watchMonthlyTotals(
            endingIn: DateTime(2026, 3, 15),
            months: 1,
            currency: Currency.usd,
          )
          .first;
      expect(totals.single.expense, const Money(5000, Currency.usd));
      expect(totals.single.income, const Money.zero(Currency.usd));
    });
  });

  group('aggregates', () {
    test('category spend groups, sums and orders by size', () async {
      await db.spend(everyday, groceries, 4000, DateTime(2026, 3, 2));
      await db.spend(everyday, groceries, 2500, DateTime(2026, 3, 9));
      await db.spend(everyday, dining, 9000, DateTime(2026, 3, 11));
      // Outside the window.
      await db.spend(everyday, dining, 99999, DateTime(2026, 2, 27));

      final spend = await db.transactionsDao
          .watchCategorySpend(
            DateRange.month(DateTime(2026, 3, 15)),
            currency: Currency.usd,
          )
          .first;

      expect(spend.map((s) => s.category.name), ['Dining', 'Groceries']);
      expect(spend.first.total, const Money(9000, Currency.usd));
      expect(spend.first.entryCount, 1);
      expect(spend.last.total, const Money(6500, Currency.usd));
      expect(spend.last.entryCount, 2);
    });

    test('category spend ignores accounts in other currencies', () async {
      final berlin = await db.makeAccount('Berlin', currency: Currency.eur);
      await db.spend(everyday, groceries, 4000, DateTime(2026, 3, 2));
      await db.spend(berlin, groceries, 7000, DateTime(2026, 3, 3));

      final usd = await db.transactionsDao
          .watchCategorySpend(
            DateRange.month(DateTime(2026, 3, 15)),
            currency: Currency.usd,
          )
          .first;
      final eur = await db.transactionsDao
          .watchCategorySpend(
            DateRange.month(DateTime(2026, 3, 15)),
            currency: Currency.eur,
          )
          .first;

      expect(usd.single.total, const Money(4000, Currency.usd));
      expect(eur.single.total, const Money(7000, Currency.eur));
    });

    test('monthly totals fill in months with no activity', () async {
      await db.spend(everyday, groceries, 1000, DateTime(2026, 1, 15));
      await db.earn(everyday, salary, 300000, DateTime(2026, 3, 25));

      final totals = await db.transactionsDao
          .watchMonthlyTotals(
            endingIn: DateTime(2026, 3, 20),
            months: 3,
            currency: Currency.usd,
          )
          .first;

      expect(totals.map((t) => t.month), [
        DateTime(2026),
        DateTime(2026, 2),
        DateTime(2026, 3),
      ]);
      expect(totals[0].expense, const Money(1000, Currency.usd));
      expect(totals[1].expense, const Money.zero(Currency.usd));
      expect(totals[1].income, const Money.zero(Currency.usd));
      expect(totals[2].income, const Money(300000, Currency.usd));
      expect(totals[2].net, const Money(300000, Currency.usd));
    });

    test('monthly totals put an entry in the month it belongs to', () async {
      // Boundary check: the last second of March and the first of April.
      await db.spend(
        everyday,
        groceries,
        111,
        DateTime(2026, 3, 31, 23, 59, 59),
      );
      await db.spend(everyday, groceries, 222, DateTime(2026, 4));

      final totals = await db.transactionsDao
          .watchMonthlyTotals(
            endingIn: DateTime(2026, 4, 10),
            months: 2,
            currency: Currency.usd,
          )
          .first;

      expect(totals[0].expense, const Money(111, Currency.usd));
      expect(totals[1].expense, const Money(222, Currency.usd));
    });
  });

  group('search and filter', () {
    setUp(() async {
      await db.spend(
        everyday,
        groceries,
        4599,
        DateTime(2026, 3, 2),
        note: 'Weekly market',
      );
      await db.spend(
        everyday,
        dining,
        12000,
        DateTime(2026, 3, 9),
        note: 'Birthday dinner',
      );
      await db.spend(
        savings,
        groceries,
        800,
        DateTime(2026, 2, 20),
        note: 'Corner shop',
      );
      await db.earn(
        everyday,
        salary,
        300000,
        DateTime(2026, 3, 25),
        note: 'March pay',
      );
    });

    Future<List<String>> notesMatching(TransactionFilter filter) async {
      final page = await db.transactionsDao.watchPage(filter: filter).first;
      return page.entries.map((e) => e.entry.note).toList();
    }

    test('free text searches notes, categories and accounts', () async {
      expect(await notesMatching(const TransactionFilter(text: 'birthday')), [
        'Birthday dinner',
      ]);
      // Matches the category name, not the note.
      expect(await notesMatching(const TransactionFilter(text: 'grocer')), [
        'Weekly market',
        'Corner shop',
      ]);
      // Matches the account name.
      expect(await notesMatching(const TransactionFilter(text: 'savings')), [
        'Corner shop',
      ]);
    });

    test('free text treats SQL wildcards as literal characters', () async {
      await db.spend(
        everyday,
        dining,
        100,
        DateTime(2026, 3, 12),
        note: '50% off',
      );

      expect(await notesMatching(const TransactionFilter(text: '50%')), [
        '50% off',
      ]);
      // A bare '%' would match everything if it were a LIKE wildcard.
      expect(await notesMatching(const TransactionFilter(text: '%')), [
        '50% off',
      ]);
    });

    test('date range is half open', () async {
      final march = DateRange.month(DateTime(2026, 3, 15));
      expect(await notesMatching(TransactionFilter(range: march)), [
        'March pay',
        'Birthday dinner',
        'Weekly market',
      ]);
    });

    test('account, category and type narrow the result', () async {
      expect(await notesMatching(TransactionFilter(accountIds: {savings.id})), [
        'Corner shop',
      ]);
      expect(await notesMatching(TransactionFilter(categoryIds: {dining.id})), [
        'Birthday dinner',
      ]);
      expect(
        await notesMatching(
          const TransactionFilter(types: {TransactionType.income}),
        ),
        ['March pay'],
      );
    });

    test('amount bounds compare magnitudes, not signs', () async {
      expect(
        await notesMatching(
          const TransactionFilter(minAmountMinor: 1000, maxAmountMinor: 20000),
        ),
        ['Birthday dinner', 'Weekly market'],
      );
    });

    test('filters combine with AND', () async {
      expect(
        await notesMatching(
          TransactionFilter(
            range: DateRange.month(DateTime(2026, 3, 15)),
            categoryIds: {groceries.id},
            maxAmountMinor: 5000,
          ),
        ),
        ['Weekly market'],
      );
    });

    test('the page reports the total match count, not the page size', () async {
      final page = await db.transactionsDao.watchPage(limit: 2).first;
      expect(page.entries, hasLength(2));
      expect(page.totalCount, 4);
    });

    test('paging is stable when entries share a date', () async {
      final sameDay = DateTime(2026, 5, 4);
      for (var i = 0; i < 6; i++) {
        await db.spend(everyday, groceries, 100 + i, sameDay);
      }

      final first = await db.transactionsDao
          .watchPage(
            filter: TransactionFilter(range: DateRange.month(sameDay)),
            limit: 3,
          )
          .first;
      final second = await db.transactionsDao
          .watchPage(
            filter: TransactionFilter(range: DateRange.month(sameDay)),
            limit: 3,
            offset: 3,
          )
          .first;

      final ids = [
        ...first.entries.map((e) => e.id),
        ...second.entries.map((e) => e.id),
      ];
      expect(ids.toSet(), hasLength(6));
      // Newest id first, because the tie-break is `id DESC`.
      expect(ids, List.of(ids)..sort((a, b) => b.compareTo(a)));
    });
  });

  group('joined detail rows', () {
    test('carry the account, category and transfer counterpart', () async {
      await db.spend(
        everyday,
        groceries,
        4599,
        DateTime(2026, 3, 2),
        note: 'Market',
      );
      final transferId = await db.transactionsDao.createTransfer(
        TransferDraft(
          from: everyday,
          to: savings,
          amount: Money.major(300, Currency.usd),
          date: DateTime(2026, 3, 26),
        ),
      );

      final expense = (await db.transactionsDao.findById(1))!;
      expect(expense.account.name, 'Everyday');
      expect(expense.category!.name, 'Groceries');
      expect(expense.counterpartAccount, isNull);
      expect(expense.title, 'Groceries');

      final outgoing = (await db.transactionsDao.findById(transferId))!;
      expect(outgoing.counterpartAccount!.name, 'Savings');
      expect(outgoing.title, 'Transfer to Savings');

      final incoming = (await db.transactionsDao.findById(
        outgoing.entry.counterpartId!,
      ))!;
      expect(incoming.title, 'Transfer from Everyday');
    });

    test('survive their category being deleted', () async {
      await db.spend(
        everyday,
        groceries,
        4599,
        DateTime(2026, 3, 2),
        note: 'Market',
      );
      await db.categoriesDao.deleteCategory(groceries.id);

      final detail = (await db.transactionsDao.findById(1))!;
      expect(detail.category, isNull);
      expect(detail.entry.amount, const Money(-4599, Currency.usd));
      expect(detail.title, 'Market');
    });
  });

  group('query plans', () {
    // These assert the *reason* the indices exist. If someone drops one, the
    // query silently degrades to a table scan and only these tests notice.
    Future<String> planFor(String sql, [List<Object?> args = const []]) async {
      final rows = await db
          .customSelect(
            'EXPLAIN QUERY PLAN $sql',
            variables: [for (final arg in args) Variable(arg)],
          )
          .get();
      return rows.map((row) => row.read<String>('detail')).join(' | ');
    }

    test('the ledger list is served from the date index', () async {
      final plan = await planFor(
        'SELECT * FROM transactions ORDER BY date DESC, id DESC LIMIT 50',
      );
      expect(plan, contains('idx_transactions_date'));
    });

    test('filtering by account and date uses the composite index', () async {
      final plan = await planFor(
        'SELECT * FROM transactions WHERE account_id = ? AND date >= ?',
        [1, 0],
      );
      expect(plan, contains('idx_transactions_account_date'));
    });

    test('filtering by amount uses the expression index', () async {
      final plan = await planFor(
        'SELECT * FROM transactions WHERE ABS(amount_minor) BETWEEN ? AND ?',
        [0, 100],
      );
      expect(plan, contains('idx_transactions_abs_amount'));
    });
  });
}
