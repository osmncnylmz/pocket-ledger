import 'package:meta/meta.dart';

import '../entities.dart';
import '../money.dart';

enum TransferProblem {
  sameAccount,
  nonPositiveAmount,
  currencyMismatch,
  archivedAccount,
}

/// A transfer the user has described but that has not been written yet.
///
/// The editor sheet needs the same rule the database enforces, so the rule
/// lives in the domain and both sides call it.
@immutable
final class TransferDraft {
  const TransferDraft({
    required this.from,
    required this.to,
    required this.amount,
    required this.date,
    this.note = '',
  });

  final Account from;
  final Account to;

  /// Always a positive magnitude; the two legs get their signs from the DAO.
  final Money amount;

  final DateTime date;
  final String note;

  /// Empty when the transfer is postable. Callers show every problem at once;
  /// fixing them one at a time is miserable.
  List<TransferProblem> validate() {
    return [
      if (from.id == to.id) TransferProblem.sameAccount,
      if (!amount.isPositive) TransferProblem.nonPositiveAmount,
      if (from.currency != to.currency || amount.currency != from.currency)
        TransferProblem.currencyMismatch,
      if (from.archived || to.archived) TransferProblem.archivedAccount,
    ];
  }

  bool get isValid => validate().isEmpty;
}

String describeTransferProblem(TransferProblem problem) => switch (problem) {
  TransferProblem.sameAccount => 'Pick two different accounts.',
  TransferProblem.nonPositiveAmount => 'Enter an amount greater than zero.',
  TransferProblem.currencyMismatch =>
    'Both accounts must use the same currency.',
  TransferProblem.archivedAccount => 'Archived accounts cannot be used.',
};
