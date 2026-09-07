import 'package:meta/meta.dart';

import '../entities.dart';
import '../money.dart';

/// Why a proposed transfer cannot be posted.
enum TransferProblem {
  sameAccount,
  nonPositiveAmount,
  currencyMismatch,
  archivedAccount,
}

/// A transfer the user has described but that has not been written yet.
///
/// Validation lives here rather than in the DAO so that the editor sheet can
/// disable its save button using exactly the rule the database will enforce.
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

  /// Empty when the transfer is postable.
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

/// Human-readable explanation of a [TransferProblem].
String describeTransferProblem(TransferProblem problem) => switch (problem) {
  TransferProblem.sameAccount => 'Pick two different accounts.',
  TransferProblem.nonPositiveAmount => 'Enter an amount greater than zero.',
  TransferProblem.currencyMismatch =>
    'Both accounts must use the same currency.',
  TransferProblem.archivedAccount => 'Archived accounts cannot be used.',
};
