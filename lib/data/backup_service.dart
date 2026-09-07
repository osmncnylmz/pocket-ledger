import 'dart:convert';

import 'package:drift/drift.dart';

import '../domain/enums.dart';
import 'database.dart';

final class ImportSummary {
  const ImportSummary({
    required this.accounts,
    required this.categories,
    required this.transactions,
    required this.budgets,
  });

  final int accounts;
  final int categories;
  final int transactions;
  final int budgets;

  int get total => accounts + categories + transactions + budgets;
}

final class BackupFormatException implements Exception {
  const BackupFormatException(this.message);

  final String message;

  @override
  String toString() => 'BackupFormatException: $message';
}

/// With no server behind it, this is the backup story: the user has to be
/// able to take their data out in a format they can read and put back. The
/// file is a straight dump of the four tables plus a header, so a future
/// version can always migrate an old export by reading [schemaVersionKey].
final class BackupService {
  const BackupService(this._db);

  final AppDatabase _db;

  static const formatMarker = 'pocket-ledger.backup';
  static const formatVersion = 1;
  static const schemaVersionKey = 'schemaVersion';

  /// Pretty-printed on purpose. A backup you cannot read in a text editor is
  /// a backup you cannot trust.
  Future<String> exportToJson({DateTime? now}) async {
    final accounts = await _db.select(_db.accounts).get();
    final categories = await _db.select(_db.categories).get();
    final transactions = await _db.select(_db.transactions).get();
    final budgets = await _db.select(_db.budgets).get();

    final document = <String, Object?>{
      'format': formatMarker,
      'formatVersion': formatVersion,
      schemaVersionKey: _db.schemaVersion,
      'exportedAt': (now ?? DateTime.now()).toUtc().toIso8601String(),
      'accounts': [
        for (final row in accounts)
          {
            'id': row.id,
            'name': row.name,
            'kind': row.kind.name,
            'openingBalanceMinor': row.openingBalanceMinor,
            'currencyCode': row.currencyCode,
            'colorValue': row.colorValue,
            'archived': row.archived,
            'sortOrder': row.sortOrder,
            'createdAt': row.createdAt.toUtc().toIso8601String(),
          },
      ],
      'categories': [
        for (final row in categories)
          {
            'id': row.id,
            'name': row.name,
            'iconKey': row.iconKey,
            'colorValue': row.colorValue,
            'kind': row.kind.name,
            'parentId': row.parentId,
            'archived': row.archived,
            'createdAt': row.createdAt.toUtc().toIso8601String(),
          },
      ],
      'transactions': [
        for (final row in transactions)
          {
            'id': row.id,
            'accountId': row.accountId,
            'categoryId': row.categoryId,
            'amountMinor': row.amountMinor,
            'date': row.date.toUtc().toIso8601String(),
            'note': row.note,
            'type': row.type.name,
            'counterpartId': row.counterpartId,
            'createdAt': row.createdAt.toUtc().toIso8601String(),
          },
      ],
      'budgets': [
        for (final row in budgets)
          {
            'id': row.id,
            'categoryId': row.categoryId,
            'period': row.period.name,
            'limitMinor': row.limitMinor,
            'createdAt': row.createdAt.toUtc().toIso8601String(),
          },
      ],
    };

    return const JsonEncoder.withIndent('  ').convert(document);
  }

  /// Replaces the whole database with the contents of [json].
  ///
  /// One SQL transaction: either the entire ledger is replaced or nothing is,
  /// so a file that turns out to be malformed halfway through cannot leave the
  /// user holding half their history. Throws [BackupFormatException] for
  /// anything that is not a well-formed backup.
  Future<ImportSummary> importFromJson(String json) async {
    final Object? decoded;
    try {
      decoded = jsonDecode(json);
    } on FormatException catch (error) {
      throw BackupFormatException(
        'The file is not valid JSON: ${error.message}',
      );
    }

    if (decoded is! Map<String, Object?>) {
      throw const BackupFormatException('Expected a JSON object at the root.');
    }
    if (decoded['format'] != formatMarker) {
      throw const BackupFormatException(
        'Missing the "pocket-ledger.backup" marker; this is not a Pocket '
        'Ledger export.',
      );
    }
    final version = decoded['formatVersion'];
    if (version is! int || version > formatVersion) {
      throw BackupFormatException(
        'Backup format $version was written by a newer version of the app.',
      );
    }

    final accounts = _rows(decoded, 'accounts');
    final categories = _rows(decoded, 'categories');
    final transactions = _rows(decoded, 'transactions');
    final budgets = _rows(decoded, 'budgets');

    await _db.transaction(() async {
      // Foreign keys are deferred rather than disabled: they are still checked,
      // just at COMMIT, which lets rows arrive in any order (a category can
      // reference a parent that has not been inserted yet).
      await _db.customStatement('PRAGMA defer_foreign_keys = ON');

      await _db.delete(_db.transactions).go();
      await _db.delete(_db.budgets).go();
      await _db.delete(_db.categories).go();
      await _db.delete(_db.accounts).go();

      await _db.batch((batch) {
        batch
          ..insertAll(_db.accounts, [
            for (final row in accounts)
              AccountsCompanion.insert(
                id: Value(_int(row, 'id')),
                name: _string(row, 'name'),
                kind: _enumValue(AccountKind.values, row, 'kind'),
                currencyCode: _string(row, 'currencyCode'),
                colorValue: _int(row, 'colorValue'),
                openingBalanceMinor: Value(_int(row, 'openingBalanceMinor')),
                archived: Value(_bool(row, 'archived')),
                sortOrder: Value(_int(row, 'sortOrder')),
                createdAt: Value(_dateTime(row, 'createdAt')),
              ),
          ])
          ..insertAll(_db.categories, [
            for (final row in categories)
              CategoriesCompanion.insert(
                id: Value(_int(row, 'id')),
                name: _string(row, 'name'),
                iconKey: _string(row, 'iconKey'),
                colorValue: _int(row, 'colorValue'),
                kind: _enumValue(CategoryKind.values, row, 'kind'),
                parentId: Value(_intOrNull(row, 'parentId')),
                archived: Value(_bool(row, 'archived')),
                createdAt: Value(_dateTime(row, 'createdAt')),
              ),
          ])
          ..insertAll(_db.transactions, [
            for (final row in transactions)
              TransactionsCompanion.insert(
                id: Value(_int(row, 'id')),
                accountId: _int(row, 'accountId'),
                categoryId: Value(_intOrNull(row, 'categoryId')),
                amountMinor: _int(row, 'amountMinor'),
                date: _dateTime(row, 'date'),
                type: _enumValue(TransactionType.values, row, 'type'),
                note: Value(_string(row, 'note')),
                counterpartId: Value(_intOrNull(row, 'counterpartId')),
                createdAt: Value(_dateTime(row, 'createdAt')),
              ),
          ])
          ..insertAll(_db.budgets, [
            for (final row in budgets)
              BudgetsCompanion.insert(
                id: Value(_int(row, 'id')),
                categoryId: _int(row, 'categoryId'),
                limitMinor: _int(row, 'limitMinor'),
                period: Value(_enumValue(BudgetPeriod.values, row, 'period')),
                createdAt: Value(_dateTime(row, 'createdAt')),
              ),
          ]);
      });
    });

    return ImportSummary(
      accounts: accounts.length,
      categories: categories.length,
      transactions: transactions.length,
      budgets: budgets.length,
    );
  }

  static List<Map<String, Object?>> _rows(
    Map<String, Object?> document,
    String key,
  ) {
    final value = document[key];
    if (value == null) return const [];
    if (value is! List) {
      throw BackupFormatException('"$key" should be a list.');
    }
    return [
      for (final entry in value)
        if (entry is Map<String, Object?>)
          entry
        else
          throw BackupFormatException('"$key" contains a non-object entry.'),
    ];
  }

  static Never _bad(String key, Object? value) =>
      throw BackupFormatException('Unexpected value for "$key": $value');

  static int _int(Map<String, Object?> row, String key) {
    final value = row[key];
    return value is int ? value : _bad(key, value);
  }

  static int? _intOrNull(Map<String, Object?> row, String key) {
    final value = row[key];
    if (value == null) return null;
    return value is int ? value : _bad(key, value);
  }

  static String _string(Map<String, Object?> row, String key) {
    final value = row[key];
    return value is String ? value : _bad(key, value);
  }

  static bool _bool(Map<String, Object?> row, String key) {
    final value = row[key];
    return value is bool ? value : _bad(key, value);
  }

  static DateTime _dateTime(Map<String, Object?> row, String key) {
    final value = row[key];
    if (value is! String) _bad(key, value);
    final parsed = DateTime.tryParse(value);
    if (parsed == null) _bad(key, value);
    return parsed.toLocal();
  }

  static T _enumValue<T extends Enum>(
    List<T> values,
    Map<String, Object?> row,
    String key,
  ) {
    final name = _string(row, key);
    for (final value in values) {
      if (value.name == name) return value;
    }
    return _bad(key, name);
  }
}
