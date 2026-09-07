# Pocket Ledger

An offline-first expense tracker built with Flutter and drift. No account, no
server: the SQLite file on the device is the only copy of your data, and the
Android manifest asks for no `INTERNET` permission.

The part worth reading is where the rules live. Money is an integer, all the
way down. The ledger's invariants are `CHECK` constraints rather than
conventions the app has to remember, so no amount of application code can post
an expense that adds to a balance. Filtering, paging and every aggregate are
SQL. The v1 to v2 migration is tested by running it against a database built
from the real v1 schema dump.

## What it does

Four screens behind a bottom nav bar. The dashboard is the busy one: balances
per account and per currency, this month's income and spending, a donut of
spending by category, a six-month trend, and the budgets closest to their
limit. The month can be stepped backwards and forwards, and every figure on the
screen follows it.

The transactions list is a filtered, paged view of the ledger with day headers,
free-text search and swipe-to-delete with undo. A budget is a weekly, monthly
or yearly limit on one category, drawn with a marker for where an evenly paced
spender would be today. Settings holds the theme and display currency, account
and category management, and backup and restore.

Transfers between your own accounts post as two mirrored rows that point at each
other. They move money without being spending, so they are excluded from the
category breakdown, the monthly totals and every budget.

Backups are a JSON dump of the whole database, written to a timestamped file in
the app's documents directory and restored either from the list of past exports
or from pasted text. With no server to fall back on, that export is the only way
data leaves the device, so it is pretty-printed and readable by hand.

## How it is put together

```
lib/domain/        Money, DateRange, filters, budget rules. No Flutter imports.
lib/data/          drift schema, DAOs, backup service, seed data.
lib/presentation/  Riverpod providers, screens, sheets, widgets.
```

The domain layer depends on nothing but `meta` and `intl`, which is what makes
its rules cheap to test. The data layer owns SQL. The presentation layer reads
drift's query streams through Riverpod providers and never touches a table.

### Money is an integer

`Money` is a signed count of minor units plus a `Currency`. No amount is ever a
`double`, from the column type through the arithmetic to the formatter, which
groups digits by string slicing so an amount past 2^53 minor units still renders
exactly. Arithmetic between two currencies throws; there is no exchange rate
to guess at.

### Schema and constraints

The sign of a row follows from its type, and the schema says so:

```sql
CHECK (
      (type = 'income' AND amount_minor > 0)
   OR (type = 'expense' AND amount_minor < 0)
   OR (type = 'transfer' AND amount_minor <> 0))
```

Two more constraints keep transfers uncategorised and stop a row being its own
counterpart, and `UNIQUE(category_id, period)` makes "one limit per category per
period" something the app cannot race. Foreign keys are on, which SQLite does
not do by default.

### Queries stay in SQL

Balances are a grouped left join. Spending by category is one `GROUP BY`.
Budget progress computes its three possible windows in Dart, so month lengths
and daylight saving stay `DateTime`'s problem, and then picks the right one per
row with a `CASE` — the whole list in one query. The transaction filter compiles
to a single `WHERE` clause; nothing is post-filtered in Dart. Three tests read
`EXPLAIN QUERY PLAN` to check that the list, the account filter and the amount
filter each land on an index instead of scanning.

### Migrations

`drift_schemas/` holds JSON dumps of schema v1 and v2. The migration test builds
a real v1 database from the v1 dump, populates it with v1-era SQL, runs the
actual upgrade and then checks both that the result matches v2 exactly and that
the rows survived with the new columns backfilled.

## Running it

```
flutter pub get
flutter run
```

A fresh install seeds a default set of categories and one checking account.
Settings can also load six months of generated transactions, which is the
fastest way to see the dashboard with something in it.

Android, iOS, macOS, Linux and Windows targets are checked in.

## Tests

```
flutter test
```

113 tests: domain rules against plain Dart, DAOs and migrations against real
in-memory SQLite (`NativeDatabase.memory()`, never a fake), and the dashboard
as a widget test driven through the same drift streams the app uses.

Generated code is committed — the drift `*.g.dart` files, the schema dumps and
the versioned schema classes under `test/generated/` — so a clone runs
`flutter pub get && flutter test` with no code generation step. After changing
`lib/data/tables.dart`:

```
dart run build_runner build --delete-conflicting-outputs
dart run drift_dev schema dump lib/data/database.dart drift_schemas/
dart run drift_dev schema generate drift_schemas/ test/generated/schema/
```

## License

MIT. See [LICENSE](LICENSE).
