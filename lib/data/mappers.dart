import '../domain/entities.dart';
import '../domain/money.dart';
import 'database.dart';

/// Translations from drift row classes into domain entities.
///
/// The dependency arrow points inward: `data` knows about `domain`, never the
/// other way round. Nothing above this file ever sees a `*Row` type, which is
/// what keeps the schema free to change without touching the UI.
extension AccountRowMapper on AccountRow {
  Account toEntity() => Account(
    id: id,
    name: name,
    kind: kind,
    openingBalance: Money(openingBalanceMinor, Currency.byCode(currencyCode)),
    colorValue: colorValue,
    archived: archived,
    sortOrder: sortOrder,
  );
}

extension CategoryRowMapper on CategoryRow {
  Category toEntity() => Category(
    id: id,
    name: name,
    iconKey: iconKey,
    colorValue: colorValue,
    kind: kind,
    parentId: parentId,
    archived: archived,
  );
}

extension TransactionRowMapper on TransactionRow {
  LedgerEntry toEntity(Currency currency) => LedgerEntry(
    id: id,
    accountId: accountId,
    categoryId: categoryId,
    amount: Money(amountMinor, currency),
    date: date,
    note: note,
    type: type,
    counterpartId: counterpartId,
  );
}

extension BudgetRowMapper on BudgetRow {
  Budget toEntity(Currency currency) => Budget(
    id: id,
    categoryId: categoryId,
    period: period,
    limit: Money(limitMinor, currency),
  );
}
