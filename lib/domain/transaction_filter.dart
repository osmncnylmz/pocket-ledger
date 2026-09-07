import 'package:meta/meta.dart';

import 'date_range.dart';
import 'enums.dart';

/// Everything the transactions screen can narrow the ledger by.
///
/// Every field here is translated into SQL by `TransactionsDao`; nothing is
/// filtered in Dart. That matters once the ledger has tens of thousands of
/// rows: the database reads an index range instead of the app reading the
/// whole table.
@immutable
final class TransactionFilter {
  const TransactionFilter({
    this.text = '',
    this.range,
    this.accountIds = const {},
    this.categoryIds = const {},
    this.types = const {},
    this.minAmountMinor,
    this.maxAmountMinor,
  });

  /// Free text, matched against the note, the category name and the account
  /// name.
  final String text;

  /// Half-open date interval.
  final DateRange? range;

  final Set<int> accountIds;
  final Set<int> categoryIds;
  final Set<TransactionType> types;

  /// Inclusive bounds on the *absolute* amount in minor units.
  final int? minAmountMinor;
  final int? maxAmountMinor;

  static const empty = TransactionFilter();

  bool get isEmpty =>
      text.trim().isEmpty &&
      range == null &&
      accountIds.isEmpty &&
      categoryIds.isEmpty &&
      types.isEmpty &&
      minAmountMinor == null &&
      maxAmountMinor == null;

  bool get isNotEmpty => !isEmpty;

  /// Number of distinct constraints in play, for the "3 filters" chip.
  int get activeCount => [
    text.trim().isNotEmpty,
    range != null,
    accountIds.isNotEmpty,
    categoryIds.isNotEmpty,
    types.isNotEmpty,
    minAmountMinor != null || maxAmountMinor != null,
  ].where((active) => active).length;

  TransactionFilter copyWith({
    String? text,
    DateRange? range,
    bool clearRange = false,
    Set<int>? accountIds,
    Set<int>? categoryIds,
    Set<TransactionType>? types,
    int? minAmountMinor,
    int? maxAmountMinor,
    bool clearAmounts = false,
  }) {
    return TransactionFilter(
      text: text ?? this.text,
      range: clearRange ? null : (range ?? this.range),
      accountIds: accountIds ?? this.accountIds,
      categoryIds: categoryIds ?? this.categoryIds,
      types: types ?? this.types,
      minAmountMinor: clearAmounts
          ? null
          : (minAmountMinor ?? this.minAmountMinor),
      maxAmountMinor: clearAmounts
          ? null
          : (maxAmountMinor ?? this.maxAmountMinor),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is TransactionFilter &&
      other.text == text &&
      other.range == range &&
      _setEquals(other.accountIds, accountIds) &&
      _setEquals(other.categoryIds, categoryIds) &&
      _setEquals(other.types, types) &&
      other.minAmountMinor == minAmountMinor &&
      other.maxAmountMinor == maxAmountMinor;

  @override
  int get hashCode => Object.hash(
    text,
    range,
    Object.hashAllUnordered(accountIds),
    Object.hashAllUnordered(categoryIds),
    Object.hashAllUnordered(types),
    minAmountMinor,
    maxAmountMinor,
  );

  static bool _setEquals<T>(Set<T> a, Set<T> b) =>
      a.length == b.length && a.containsAll(b);
}
