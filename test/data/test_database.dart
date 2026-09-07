import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:pocket_ledger/data/database.dart';

/// An empty database backed by SQLite in memory.
///
/// `NativeDatabase.memory()` is the real SQLite engine, so every constraint,
/// index and `CHECK` in the schema is exercised by the tests exactly as it will
/// be on a device. Nothing here is a fake.
AppDatabase newTestDatabase({bool logStatements = false}) {
  // Each test database has its own private in-memory executor, so drift's
  // "you opened the database twice" warning does not apply here.
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  return AppDatabase(
    DatabaseConnection(
      NativeDatabase.memory(logStatements: logStatements),
      // In production drift keeps a cancelled query stream cached for one event
      // loop turn, so a rebuilding StreamBuilder does not re-run the statement.
      // That turn is scheduled with a Timer, and widget tests run on a fake
      // clock that only advances while the tester pumps - so a `close()` after
      // the tree is torn down would wait for a timer that can never fire.
      closeStreamsSynchronously: true,
    ),
  );
}

/// Runs [body] against a fresh database and closes it afterwards.
Future<T> withTestDatabase<T>(Future<T> Function(AppDatabase db) body) async {
  final db = newTestDatabase();
  try {
    return await body(db);
  } finally {
    await db.close();
  }
}

/// The logical shape of a database: every table's columns (with type,
/// nullability and default) plus every index, as an order-insensitive set.
///
/// This is what two databases have to agree on for the same queries to work.
/// The raw `sqlite_master` text is deliberately not compared: `ALTER TABLE ...
/// ADD COLUMN` appends to the end of the declaration, so a migrated table and a
/// freshly created one differ in wording while being identical to SQL.
Future<Set<String>> schemaShape(GeneratedDatabase db) async {
  final objects = await db
      .customSelect(
        'SELECT type, name FROM sqlite_master '
        "WHERE sql IS NOT NULL AND name NOT LIKE 'sqlite_%' ORDER BY name",
      )
      .get();

  final shape = <String>{};
  for (final object in objects) {
    final type = object.read<String>('type');
    final name = object.read<String>('name');

    if (type == 'index') {
      final info = await db.customSelect('PRAGMA index_info($name)').get();
      final columns = info
          .map((row) => row.read<String?>('name') ?? '<expression>')
          .join(',');
      shape.add('index $name($columns)');
      continue;
    }

    final columns = await db.customSelect('PRAGMA table_info($name)').get();
    for (final column in columns) {
      shape.add(
        'column $name.${column.read<String>('name')} '
        '${column.read<String>('type')} '
        'notnull=${column.read<int>('notnull')} '
        'default=${column.read<String?>('dflt_value')}',
      );
    }

    final keys = await db.customSelect('PRAGMA foreign_key_list($name)').get();
    for (final key in keys) {
      shape.add(
        'fk $name.${key.read<String?>('from')} -> '
        '${key.read<String>('table')}.${key.read<String?>('to')} '
        'on_delete=${key.read<String>('on_delete')}',
      );
    }
  }
  return shape;
}
