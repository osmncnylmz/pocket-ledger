/// Enumerations shared by every layer.
///
/// These are persisted by name (`textEnum` columns in the drift schema), so the
/// identifiers below are part of the on-disk format: renaming one is a schema
/// change and needs a migration.
library;

/// The kind of a real-world account a ledger account stands for.
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

/// Whether a category groups money coming in or money going out.
enum CategoryKind { income, expense }

/// The semantic type of a ledger entry.
///
/// The sign of `amountMinor` is derived from this and is enforced by a `CHECK`
/// constraint in the schema:
///
/// * [income] rows are strictly positive,
/// * [expense] rows are strictly negative,
/// * [transfer] rows are non-zero and always come in pairs with opposite signs.
enum TransactionType {
  income,
  expense,
  transfer;

  bool get isTransfer => this == TransactionType.transfer;
}

/// The recurrence window a budget limit applies to.
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

/// How the user wants the app themed.
enum AppThemeMode { system, light, dark }
