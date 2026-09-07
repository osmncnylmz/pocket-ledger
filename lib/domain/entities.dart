import 'package:meta/meta.dart';

import 'enums.dart';
import 'money.dart';

/// Where money sits. The currency comes from the opening balance.
@immutable
final class Account {
  const Account({
    required this.id,
    required this.name,
    required this.kind,
    required this.openingBalance,
    required this.colorValue,
    required this.archived,
    required this.sortOrder,
  });

  final int id;
  final String name;
  final AccountKind kind;

  /// Balance the account already had when it was added to the ledger.
  final Money openingBalance;

  /// 32 bit ARGB. The domain does not import Flutter, so the colour stays an
  /// integer until the presentation layer wraps it.
  final int colorValue;

  final bool archived;
  final int sortOrder;

  Currency get currency => openingBalance.currency;
}

@immutable
final class AccountBalance {
  const AccountBalance({required this.account, required this.balance});

  final Account account;

  /// Opening balance plus every posted entry, computed by SQL.
  final Money balance;
}

/// A spending or income bucket. Nests one level deep, no further.
@immutable
final class Category {
  const Category({
    required this.id,
    required this.name,
    required this.iconKey,
    required this.colorValue,
    required this.kind,
    required this.parentId,
    required this.archived,
  });

  final int id;
  final String name;

  /// Stable key into the app's icon table. See `category_icons.dart` for why
  /// it is a key and not a code point.
  final String iconKey;

  final int colorValue;
  final CategoryKind kind;
  final int? parentId;
  final bool archived;

  bool get isSubcategory => parentId != null;
}

/// One posted line of the ledger.
///
/// [amount] is signed: negative means money left [accountId]. A transfer is
/// two of these, pointing at each other through [counterpartId].
@immutable
final class LedgerEntry {
  const LedgerEntry({
    required this.id,
    required this.accountId,
    required this.categoryId,
    required this.amount,
    required this.date,
    required this.note,
    required this.type,
    required this.counterpartId,
  });

  final int id;
  final int accountId;
  final int? categoryId;
  final Money amount;
  final DateTime date;
  final String note;
  final TransactionType type;

  final int? counterpartId;

  bool get isOutflow => amount.isNegative;
}

/// An entry with the account, category and counterpart rows it points at.
@immutable
final class LedgerEntryDetail {
  const LedgerEntryDetail({
    required this.entry,
    required this.account,
    required this.category,
    required this.counterpartAccount,
  });

  final LedgerEntry entry;
  final Account account;
  final Category? category;

  final Account? counterpartAccount;

  int get id => entry.id;
  Money get amount => entry.amount;
  DateTime get date => entry.date;

  String get title {
    if (entry.type.isTransfer) {
      final other = counterpartAccount?.name ?? 'another account';
      return entry.isOutflow ? 'Transfer to $other' : 'Transfer from $other';
    }
    if (category != null) return category!.name;
    return entry.note.isEmpty ? 'Uncategorised' : entry.note;
  }
}

@immutable
final class Budget {
  const Budget({
    required this.id,
    required this.categoryId,
    required this.period,
    required this.limit,
  });

  final int id;
  final int categoryId;
  final BudgetPeriod period;
  final Money limit;
}

@immutable
final class CategorySpend {
  const CategorySpend({
    required this.category,
    required this.total,
    required this.entryCount,
  });

  final Category category;

  /// Positive magnitude of money spent.
  final Money total;
  final int entryCount;
}

@immutable
final class MonthlyTotals {
  const MonthlyTotals({
    required this.month,
    required this.income,
    required this.expense,
  });

  /// First instant of the month, not an arbitrary date inside it.
  final DateTime month;

  /// Both are positive magnitudes, unlike the signed rows they came from.
  final Money income;
  final Money expense;

  Money get net => income - expense;
}
