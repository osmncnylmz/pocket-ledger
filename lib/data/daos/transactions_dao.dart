import 'package:drift/drift.dart';

import '../../domain/date_range.dart';
import '../../domain/entities.dart';
import '../../domain/enums.dart';
import '../../domain/money.dart';
import '../../domain/services/transfer.dart';
import '../../domain/transaction_filter.dart';
import '../database.dart';
import '../mappers.dart';

part 'transactions_dao.g.dart';

/// A page of ledger entries plus the total number of matches, so the list can
/// show "42 results" without a second round trip from the UI layer.
final class LedgerPage {
  const LedgerPage({required this.entries, required this.totalCount});

  final List<LedgerEntryDetail> entries;
  final int totalCount;

  bool get isEmpty => entries.isEmpty;
}

/// Everything that reads or writes ledger entries.
@DriftAccessor(tables: [Accounts, Categories, Transactions])
class TransactionsDao extends DatabaseAccessor<AppDatabase>
    with _$TransactionsDaoMixin {
  TransactionsDao(super.db);

  // The counterpart of a transfer is the same table joined to itself, so it
  // needs an alias; likewise the account that counterpart sits in.
  late final $TransactionsTable _counterpart = alias(
    transactions,
    'counterpart',
  );
  late final $AccountsTable _counterpartAccount = alias(
    accounts,
    'counterpart_account',
  );

  List<Join<HasResultSet, dynamic>> get _detailJoins => [
    innerJoin(accounts, accounts.id.equalsExp(transactions.accountId)),
    leftOuterJoin(categories, categories.id.equalsExp(transactions.categoryId)),
    leftOuterJoin(
      _counterpart,
      _counterpart.id.equalsExp(transactions.counterpartId),
    ),
    leftOuterJoin(
      _counterpartAccount,
      _counterpartAccount.id.equalsExp(_counterpart.accountId),
    ),
  ];

  LedgerEntryDetail _readDetail(TypedResult row) {
    final account = row.readTable(accounts).toEntity();
    final counterpartAccount = row
        .readTableOrNull(_counterpartAccount)
        ?.toEntity();
    return LedgerEntryDetail(
      entry: row.readTable(transactions).toEntity(account.currency),
      account: account,
      category: row.readTableOrNull(categories)?.toEntity(),
      counterpartAccount: counterpartAccount,
    );
  }

  /// Translates a [TransactionFilter] into one `WHERE` clause.
  ///
  /// Every predicate below runs inside SQLite. Nothing is post-filtered in
  /// Dart, which is what lets the list stay on an index instead of reading the
  /// table.
  Expression<bool> _predicate(TransactionFilter filter) {
    final clauses = <Expression<bool>>[];

    final text = filter.text.trim();
    if (text.isNotEmpty) {
      // `instr` rather than `LIKE` so that a user typing `50%` searches for the
      // literal characters instead of accidentally writing a wildcard.
      clauses.add(
        _containsIgnoringCase(transactions.note, text) |
            _containsIgnoringCase(categories.name, text) |
            _containsIgnoringCase(accounts.name, text),
      );
    }

    final range = filter.range;
    if (range != null) {
      clauses
        ..add(transactions.date.isBiggerOrEqualValue(range.start))
        ..add(transactions.date.isSmallerThanValue(range.end));
    }

    if (filter.accountIds.isNotEmpty) {
      clauses.add(transactions.accountId.isIn(filter.accountIds));
    }
    if (filter.categoryIds.isNotEmpty) {
      clauses.add(transactions.categoryId.isIn(filter.categoryIds));
    }
    if (filter.types.isNotEmpty) {
      clauses.add(
        transactions.type.isIn(filter.types.map((t) => t.name).toList()),
      );
    }

    final magnitude = transactions.amountMinor.abs();
    final min = filter.minAmountMinor;
    if (min != null) {
      clauses.add(magnitude.isBiggerOrEqualValue(min));
    }
    final max = filter.maxAmountMinor;
    if (max != null) {
      clauses.add(magnitude.isSmallerOrEqualValue(max));
    }

    if (clauses.isEmpty) return const Constant(true);
    return clauses.reduce((a, b) => a & b);
  }

  static Expression<bool> _containsIgnoringCase(
    Expression<String> column,
    String needle,
  ) {
    // SQLite's `lower()` folds ASCII only, so both sides go through the same
    // function and agree with each other.
    return FunctionCallExpression<int>('instr', [
      column.lower(),
      Variable<String>(needle).lower(),
    ]).isBiggerThanValue(0);
  }

  /// One page of the ledger, newest first, with its accounts and categories
  /// already joined in.
  Stream<LedgerPage> watchPage({
    TransactionFilter filter = TransactionFilter.empty,
    int limit = 50,
    int offset = 0,
  }) {
    final predicate = _predicate(filter);

    final rows = select(transactions).join(_detailJoins)
      ..where(predicate)
      // `id` breaks ties so that paging is stable when several entries
      // share a date, which they always do.
      ..orderBy([
        OrderingTerm.desc(transactions.date),
        OrderingTerm.desc(transactions.id),
      ])
      ..limit(limit, offset: offset);

    final counter = transactions.id.count();
    final countQuery = selectOnly(transactions)
      ..addColumns([counter])
      ..join([
        innerJoin(accounts, accounts.id.equalsExp(transactions.accountId)),
        leftOuterJoin(
          categories,
          categories.id.equalsExp(transactions.categoryId),
        ),
      ])
      ..where(predicate);

    return rows.watch().asyncMap((results) async {
      final total = await countQuery
          .map((row) => row.read(counter) ?? 0)
          .getSingle();
      return LedgerPage(
        entries: results.map(_readDetail).toList(),
        totalCount: total,
      );
    });
  }

  Future<LedgerEntryDetail?> findById(int id) async {
    final query = select(transactions).join(_detailJoins)
      ..where(transactions.id.equals(id));
    final row = await query.getSingleOrNull();
    return row == null ? null : _readDetail(row);
  }

  /// Spending per category over [range], biggest first.
  ///
  /// Transfers are excluded on purpose: moving money between your own accounts
  /// is not spending, and counting it would double every savings deposit.
  Stream<List<CategorySpend>> watchCategorySpend(
    DateRange range, {
    required Currency currency,
    int? limit,
  }) {
    final total = transactions.amountMinor.sum();
    final entries = transactions.id.count();

    final query =
        select(transactions).join([
            innerJoin(
              categories,
              categories.id.equalsExp(transactions.categoryId),
            ),
            innerJoin(accounts, accounts.id.equalsExp(transactions.accountId)),
          ])
          ..addColumns([total, entries])
          ..where(
            transactions.type.equalsValue(TransactionType.expense) &
                transactions.date.isBiggerOrEqualValue(range.start) &
                transactions.date.isSmallerThanValue(range.end) &
                accounts.currencyCode.equals(currency.code),
          )
          ..groupBy([categories.id])
          // Expenses are negative, so ascending is "most spent first".
          ..orderBy([OrderingTerm.asc(total)]);

    if (limit != null) query.limit(limit);

    return query.watch().map(
      (rows) => rows
          .map(
            (row) => CategorySpend(
              category: row.readTable(categories).toEntity(),
              total: Money(-(row.read(total) ?? 0), currency),
              entryCount: row.read(entries) ?? 0,
            ),
          )
          .toList(),
    );
  }

  /// Income and expense per calendar month for the [months] months ending with
  /// the month containing [endingIn], oldest first. Months with no activity are
  /// filled in with zeros so the trend line has no gaps.
  Stream<List<MonthlyTotals>> watchMonthlyTotals({
    required DateTime endingIn,
    required int months,
    required Currency currency,
  }) {
    final windows = DateRange.lastMonths(endingIn, months);
    final from = windows.first.start;
    final to = windows.last.end;

    return customSelect(
      '''
SELECT
  strftime('%Y-%m', t.date, 'unixepoch', 'localtime')                  AS month,
  COALESCE(SUM(CASE WHEN t.type = 'income'  THEN  t.amount_minor END), 0) AS income_minor,
  COALESCE(SUM(CASE WHEN t.type = 'expense' THEN -t.amount_minor END), 0) AS expense_minor
FROM transactions t
JOIN accounts a ON a.id = t.account_id
WHERE t.date >= ? AND t.date < ? AND a.currency_code = ?
GROUP BY month
ORDER BY month
''',
      variables: [
        Variable<DateTime>(from),
        Variable<DateTime>(to),
        Variable<String>(currency.code),
      ],
      readsFrom: {transactions, accounts},
    ).watch().map((rows) {
      final byMonth = {
        for (final row in rows)
          row.read<String>('month'): (
            income: row.read<int>('income_minor'),
            expense: row.read<int>('expense_minor'),
          ),
      };

      return [
        for (final window in windows)
          () {
            final key = _monthKey(window.start);
            final totals = byMonth[key];
            return MonthlyTotals(
              month: window.start,
              income: Money(totals?.income ?? 0, currency),
              expense: Money(totals?.expense ?? 0, currency),
            );
          }(),
      ];
    });
  }

  static String _monthKey(DateTime month) =>
      '${month.year.toString().padLeft(4, '0')}-'
      '${month.month.toString().padLeft(2, '0')}';

  /// Records an income or expense.
  ///
  /// [amount] is a magnitude; the sign is applied here from [type] so that the
  /// caller can never post an expense that increases a balance. The `CHECK`
  /// constraint in the schema is the second line of defence.
  Future<int> createEntry({
    required int accountId,
    required int? categoryId,
    required Money amount,
    required DateTime date,
    required TransactionType type,
    String note = '',
  }) {
    assert(!type.isTransfer, 'Use createTransfer for transfers');
    return into(transactions).insert(
      TransactionsCompanion.insert(
        accountId: accountId,
        categoryId: Value(categoryId),
        amountMinor: _signed(amount, type),
        date: date,
        type: type,
        note: Value(note),
      ),
    );
  }

  Future<void> updateEntry({
    required int id,
    required int accountId,
    required int? categoryId,
    required Money amount,
    required DateTime date,
    required TransactionType type,
    String note = '',
  }) {
    assert(!type.isTransfer, 'Use updateTransfer for transfers');
    return (update(transactions)..where((t) => t.id.equals(id))).write(
      TransactionsCompanion(
        accountId: Value(accountId),
        categoryId: Value(categoryId),
        amountMinor: Value(_signed(amount, type)),
        date: Value(date),
        type: Value(type),
        note: Value(note),
      ),
    );
  }

  static int _signed(Money amount, TransactionType type) {
    final magnitude = amount.minorUnits.abs();
    return type == TransactionType.expense ? -magnitude : magnitude;
  }

  /// Posts a transfer as two mirrored entries that point at each other.
  ///
  /// Returns the id of the outgoing leg. The whole thing runs in one SQL
  /// transaction, so there is no window in which a half-transfer exists.
  Future<int> createTransfer(TransferDraft draft) {
    final problems = draft.validate();
    if (problems.isNotEmpty) {
      throw ArgumentError(problems.map(describeTransferProblem).join(' '));
    }

    return transaction(() async {
      final outgoing = await into(transactions).insert(
        TransactionsCompanion.insert(
          accountId: draft.from.id,
          amountMinor: -draft.amount.minorUnits,
          date: draft.date,
          type: TransactionType.transfer,
          note: Value(draft.note),
        ),
      );
      final incoming = await into(transactions).insert(
        TransactionsCompanion.insert(
          accountId: draft.to.id,
          amountMinor: draft.amount.minorUnits,
          date: draft.date,
          type: TransactionType.transfer,
          note: Value(draft.note),
          counterpartId: Value(outgoing),
        ),
      );
      await (update(transactions)..where((t) => t.id.equals(outgoing))).write(
        TransactionsCompanion(counterpartId: Value(incoming)),
      );
      return outgoing;
    });
  }

  /// Rewrites both legs of an existing transfer from [draft].
  ///
  /// [legId] may be either leg; the sibling is found through `counterpart_id`.
  Future<void> updateTransfer(int legId, TransferDraft draft) {
    final problems = draft.validate();
    if (problems.isNotEmpty) {
      throw ArgumentError(problems.map(describeTransferProblem).join(' '));
    }

    return transaction(() async {
      final leg = await (select(
        transactions,
      )..where((t) => t.id.equals(legId))).getSingleOrNull();
      if (leg == null || !leg.type.isTransfer || leg.counterpartId == null) {
        throw StateError('Entry $legId is not one leg of a transfer.');
      }

      // Whichever leg was passed in, the outgoing one gets the negative amount
      // and the source account.
      final outgoingId = leg.amountMinor < 0 ? leg.id : leg.counterpartId!;
      final incomingId = leg.amountMinor < 0 ? leg.counterpartId! : leg.id;

      await (update(transactions)..where((t) => t.id.equals(outgoingId))).write(
        TransactionsCompanion(
          accountId: Value(draft.from.id),
          amountMinor: Value(-draft.amount.minorUnits),
          date: Value(draft.date),
          note: Value(draft.note),
        ),
      );
      await (update(transactions)..where((t) => t.id.equals(incomingId))).write(
        TransactionsCompanion(
          accountId: Value(draft.to.id),
          amountMinor: Value(draft.amount.minorUnits),
          date: Value(draft.date),
          note: Value(draft.note),
        ),
      );
    });
  }

  /// Deletes an entry, taking the far leg of a transfer with it.
  ///
  /// Returns the rows that were removed so the caller can offer undo without
  /// having to re-derive them.
  Future<List<TransactionRow>> deleteEntry(int id) {
    return transaction(() async {
      final row = await (select(
        transactions,
      )..where((t) => t.id.equals(id))).getSingleOrNull();
      if (row == null) return const <TransactionRow>[];

      final ids = <int>{row.id, ?row.counterpartId};
      final doomed = await (select(
        transactions,
      )..where((t) => t.id.isIn(ids))).get();

      // Break the mutual link first: deleting one leg would otherwise null out
      // the other's `counterpart_id` before we had a chance to record it.
      await (update(transactions)..where((t) => t.id.isIn(ids))).write(
        const TransactionsCompanion(counterpartId: Value(null)),
      );
      await (delete(transactions)..where((t) => t.id.isIn(ids))).go();
      return doomed;
    });
  }

  /// Puts previously deleted rows back, ids and transfer links included.
  Future<void> restoreEntries(List<TransactionRow> rows) {
    if (rows.isEmpty) return Future.value();
    return transaction(() async {
      for (final row in rows) {
        await into(transactions)
            .insert(row.copyWith(counterpartId: const Value(null)));
      }
      for (final row in rows) {
        if (row.counterpartId == null) continue;
        await (update(transactions)..where((t) => t.id.equals(row.id))).write(
          TransactionsCompanion(counterpartId: Value(row.counterpartId)),
        );
      }
    });
  }

  /// Total number of entries, used by the empty states and the settings screen.
  Future<int> countAll() {
    final counter = transactions.id.count();
    return (selectOnly(
      transactions,
    )..addColumns([counter])).map((row) => row.read(counter) ?? 0).getSingle();
  }
}
