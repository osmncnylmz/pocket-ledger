import 'package:drift/drift.dart';

import '../domain/enums.dart';

/// Archiving hides an account and keeps its history readable. Hard deletion
/// exists too, but it goes through `AccountsDao` so the far leg of every
/// transfer is cleaned up in the same SQL transaction.
@DataClassName('AccountRow')
@TableIndex(name: 'idx_accounts_sort', columns: {#archived, #sortOrder})
class Accounts extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text().withLength(min: 1, max: 60)();
  TextColumn get kind => textEnum<AccountKind>()();

  /// Balance before the first recorded entry, in minor units.
  IntColumn get openingBalanceMinor =>
      integer().withDefault(const Constant(0))();

  TextColumn get currencyCode => text().withLength(min: 3, max: 3)();

  /// 32 bit ARGB.
  IntColumn get colorValue => integer()();

  BoolColumn get archived => boolean().withDefault(const Constant(false))();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  List<Set<Column<Object>>> get uniqueKeys => [
    {name},
  ];
}

/// Spending and income buckets, optionally nested one level deep.
@DataClassName('CategoryRow')
@TableIndex(name: 'idx_categories_parent', columns: {#parentId})
@TableIndex(name: 'idx_categories_kind', columns: {#kind, #name})
class Categories extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text().withLength(min: 1, max: 60)();

  /// Key into the app's `const` icon table, not a raw code point: storing code
  /// points would force `--no-tree-shake-icons` on every release build.
  TextColumn get iconKey => text().withLength(min: 1, max: 40)();

  IntColumn get colorValue => integer()();
  TextColumn get kind => textEnum<CategoryKind>()();

  IntColumn get parentId => integer().nullable().references(
    Categories,
    #id,
    onDelete: KeyAction.setNull,
  )();

  /// Added in schema v2: hides a category from pickers without rewriting the
  /// history that already references it.
  BoolColumn get archived => boolean().withDefault(const Constant(false))();

  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

/// `amountMinor` is signed: negative leaves the account, positive enters it.
/// The `CHECK` constraints below put that in the database, where the app
/// cannot forget it.
@DataClassName('TransactionRow')
@TableIndex(
  name: 'idx_transactions_date',
  columns: {IndexedColumn(#date, orderBy: OrderingMode.desc)},
)
@TableIndex(name: 'idx_transactions_account_date', columns: {#accountId, #date})
@TableIndex(
  name: 'idx_transactions_category_date',
  columns: {#categoryId, #date},
)
@TableIndex(name: 'idx_transactions_counterpart', columns: {#counterpartId})
// Added in schema v2, for the "amount between x and y" filter.
@TableIndex.sql(
  'CREATE INDEX idx_transactions_abs_amount '
  'ON transactions (ABS(amount_minor));',
)
class Transactions extends Table {
  IntColumn get id => integer().autoIncrement()();

  IntColumn get accountId =>
      integer().references(Accounts, #id, onDelete: KeyAction.cascade)();

  /// Null for transfers, which move money without spending it.
  IntColumn get categoryId => integer().nullable().references(
    Categories,
    #id,
    onDelete: KeyAction.setNull,
  )();

  IntColumn get amountMinor => integer()();

  DateTimeColumn get date => dateTime()();
  TextColumn get note =>
      text().withDefault(const Constant('')).withLength(max: 200)();
  TextColumn get type => textEnum<TransactionType>()();

  /// The other leg of a transfer. Both legs point at each other.
  IntColumn get counterpartId => integer().nullable().references(
    Transactions,
    #id,
    onDelete: KeyAction.setNull,
  )();

  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  // Written as literals because that is the only form drift's generator can
  // read: pull one out into a named constant and it silently drops out of the
  // schema, taking it out of `drift_dev schema dump` with it.
  @override
  List<String> get customConstraints => [
    // The sign of an entry follows from its type, so no amount of application
    // code can post an expense that adds to a balance.
    '''
CHECK (
      (type = 'income' AND amount_minor > 0)
   OR (type = 'expense' AND amount_minor < 0)
   OR (type = 'transfer' AND amount_minor <> 0))''',
    // Moving money between your own accounts is not spending, so a transfer
    // cannot carry a category and skew the breakdowns.
    "CHECK (type <> 'transfer' OR category_id IS NULL)",
    // An entry cannot be its own transfer counterpart.
    'CHECK (counterpart_id IS NULL OR counterpart_id <> id)',
  ];
}

@DataClassName('BudgetRow')
class Budgets extends Table {
  IntColumn get id => integer().autoIncrement()();

  IntColumn get categoryId =>
      integer().references(Categories, #id, onDelete: KeyAction.cascade)();

  /// Added in schema v2. Before that every budget was implicitly monthly, so
  /// the migration backfills `'monthly'`.
  TextColumn get period =>
      textEnum<BudgetPeriod>().withDefault(const Constant('monthly'))();

  IntColumn get limitMinor => integer()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  List<Set<Column<Object>>> get uniqueKeys => [
    {categoryId, period},
  ];
}
