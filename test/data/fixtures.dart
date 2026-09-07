import 'package:pocket_ledger/data/database.dart';
import 'package:pocket_ledger/domain/entities.dart';
import 'package:pocket_ledger/domain/enums.dart';
import 'package:pocket_ledger/domain/money.dart';

/// Small helpers so the tests read as scenarios.
extension Fixtures on AppDatabase {
  Future<Account> makeAccount(
    String name, {
    AccountKind kind = AccountKind.checking,
    Money? openingBalance,
    Currency currency = Currency.usd,
    int colorValue = 0xFF3F51B5,
  }) async {
    final id = await accountsDao.createAccount(
      name: name,
      kind: kind,
      openingBalance: openingBalance ?? Money.zero(currency),
      colorValue: colorValue,
    );
    return (await accountsDao.findById(id))!;
  }

  Future<Category> makeCategory(
    String name, {
    CategoryKind kind = CategoryKind.expense,
    String iconKey = 'groceries',
    int colorValue = 0xFF2E7D32,
    int? parentId,
  }) async {
    final id = await categoriesDao.createCategory(
      name: name,
      iconKey: iconKey,
      colorValue: colorValue,
      kind: kind,
      parentId: parentId,
    );
    return (await categoriesDao.findById(id))!;
  }

  Future<int> spend(
    Account account,
    Category category,
    int minorUnits,
    DateTime date, {
    String note = '',
  }) {
    return transactionsDao.createEntry(
      accountId: account.id,
      categoryId: category.id,
      amount: Money(minorUnits, account.currency),
      date: date,
      type: TransactionType.expense,
      note: note,
    );
  }

  Future<int> earn(
    Account account,
    Category category,
    int minorUnits,
    DateTime date, {
    String note = '',
  }) {
    return transactionsDao.createEntry(
      accountId: account.id,
      categoryId: category.id,
      amount: Money(minorUnits, account.currency),
      date: date,
      type: TransactionType.income,
      note: note,
    );
  }
}
