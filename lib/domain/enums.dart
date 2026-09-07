/// Enumerations shared by every layer.
///
/// These are persisted by name (`textEnum` columns in the drift schema), so the
/// identifiers below are part of the on-disk format: renaming one is a schema
/// change and needs a migration.
library;

enum AccountKind {
  cash,
  checking,
  savings,
  credit,
  investment;

  /// Credit accounts normally carry a negative balance; that is not an error
  /// state and the UI must not flag it as one.
  bool get isLiability => this == AccountKind.credit;
}

enum CategoryKind { income, expense }

/// The sign of `amountMinor` follows from this, and a `CHECK` constraint in
/// the schema enforces it: income strictly positive, expense strictly
/// negative, transfer non-zero and always paired with an opposite-signed leg.
enum TransactionType {
  income,
  expense,
  transfer;

  bool get isTransfer => this == TransactionType.transfer;
}

enum BudgetPeriod {
  weekly,
  monthly,
  yearly;

  String get label => switch (this) {
    BudgetPeriod.weekly => 'Weekly',
    BudgetPeriod.monthly => 'Monthly',
    BudgetPeriod.yearly => 'Yearly',
  };
}

enum AppThemeMode { system, light, dark }
