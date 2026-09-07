import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

import '../domain/enums.dart';

import 'daos/accounts_dao.dart';
import 'daos/budgets_dao.dart';
import 'daos/categories_dao.dart';
import 'daos/transactions_dao.dart';
import 'tables.dart';

export 'tables.dart';

part 'database.g.dart';

/// The application database.
///
/// Everything the app knows lives here. There is no server, no sync engine and
/// no cache to invalidate: SQLite *is* the source of truth, and drift's query
/// streams are what keep the UI in step with it.
@DriftDatabase(
  tables: [Accounts, Categories, Transactions, Budgets],
  daos: [AccountsDao, CategoriesDao, TransactionsDao, BudgetsDao],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.executor);

  /// Opens the on-device database file (`pocket_ledger.sqlite` in the
  /// application documents directory).
  AppDatabase.open() : super(driftDatabase(name: 'pocket_ledger'));

  @override
  int get schemaVersion => 2;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) async {
      await m.createAll();
    },
    onUpgrade: (m, from, to) async {
      // Table rewrites (`alterTable`) are implemented as create/copy/drop, so
      // foreign keys have to be off while they run. See
      // https://sqlite.org/lang_altertable.html#otheralter
      await customStatement('PRAGMA foreign_keys = OFF');

      await transaction(() async {
        if (from < 2) {
          // v2 introduced archivable categories ...
          await m.addColumn(categories, categories.archived);
          // ... budget periods. Existing budgets were implicitly monthly, and
          // the column default backfills them. Rewriting the table also picks
          // up the new UNIQUE(category_id, period) constraint, which a plain
          // ADD COLUMN cannot express.
          await m.alterTable(
            TableMigration(budgets, newColumns: [budgets.period]),
          );
          // ... and an index for the "amount between" filter.
          await m.createIndex(idxTransactionsAbsAmount);
        }
      });

      final brokenReferences = await customSelect('PRAGMA foreign_key_check')
          .get();
      if (brokenReferences.isNotEmpty) {
        throw StateError(
          'Migration $from -> $to left ${brokenReferences.length} dangling '
          'foreign key reference(s).',
        );
      }

      await customStatement('PRAGMA foreign_keys = ON');
    },
    beforeOpen: (details) async {
      // SQLite does not enforce foreign keys unless asked, per connection.
      await customStatement('PRAGMA foreign_keys = ON');
    },
  );
}
