import 'package:meta/meta.dart';

import 'enums.dart';
import 'money.dart';

/// A place money sits: a wallet, a current account, a credit card.
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

  /// Opaque 32 bit ARGB value. The domain does not depend on Flutter, so the
  /// colour stays an integer until the presentation layer wraps it.
  final int colorValue;

  final bool archived;
  final int sortOrder;

  Currency get currency => openingBalance.currency;
}

/// An account plus its derived balance.
@immutable
final class AccountBalance {
  const AccountBalance({required this.account, required this.balance});

  final Account account;

  /// Opening balance plus every posted entry, computed by SQL.
  final Money balance;
}

/// A spending or income bucket. Categories may nest one level via [parentId].
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

  /// Stable key into the app's icon table. Storing a key rather than a raw
  /// `IconData` code point keeps Flutter's icon tree-shaking working: every
  /// icon the app can show is referenced as a `const` in Dart source.
  final String iconKey;

  final int colorValue;
  final CategoryKind kind;
  final int? parentId;
  final bool archived;

  bool get isSubcategory => parentId != null;
}

/// One posted line of the ledger.
///
/// [amount] is signed: negative means money left [accountId]. Transfers are
/// stored as two entries pointing at each other through [counterpartId].
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

  /// The other leg of a transfer, if this entry is one.
  final int? counterpartId;

  bool get isOutflow => amount.isNegative;
}

/// A ledger entry joined with the account and category it points at, which is
/// what every list in the app actually needs.
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

  /// For a transfer, the account on the other side.
  final Account? counterpartAccount;

  int get id => entry.id;
  Money get amount => entry.amount;
  DateTime get date => entry.date;

  /// What to show as the entry's headline.
  String get title {
    if (entry.type.isTransfer) {
      final other = counterpartAccount?.name ?? 'another account';
      return entry.isOutflow ? 'Transfer to $other' : 'Transfer from $other';
    }
    if (category != null) return category!.name;
    return entry.note.isEmpty ? 'Uncategorised' : entry.note;
  }
}

/// A per-category limit for a recurring window.
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

/// Total spending in one category over some window, produced by a `GROUP BY`.
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

/// Income and expense totals for one calendar month.
@immutable
final class MonthlyTotals {
  const MonthlyTotals({
    required this.month,
    required this.income,
    required this.expense,
  });

  /// First instant of the month these totals describe.
  final DateTime month;

  /// Positive magnitude of money received.
  final Money income;

  /// Positive magnitude of money spent.
  final Money expense;

  Money get net => income - expense;
}
