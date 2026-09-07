import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_ledger/domain/entities.dart';
import 'package:pocket_ledger/domain/enums.dart';
import 'package:pocket_ledger/domain/money.dart';
import 'package:pocket_ledger/domain/services/transfer.dart';

void main() {
  Account account(
    int id,
    String name, {
    Currency currency = Currency.usd,
    bool archived = false,
  }) {
    return Account(
      id: id,
      name: name,
      kind: AccountKind.checking,
      openingBalance: Money.zero(currency),
      colorValue: 0,
      archived: archived,
      sortOrder: 0,
    );
  }

  final everyday = account(1, 'Everyday');
  final savings = account(2, 'Savings');

  TransferDraft draft({Account? from, Account? to, Money? amount}) {
    return TransferDraft(
      from: from ?? everyday,
      to: to ?? savings,
      amount: amount ?? Money.major(100, Currency.usd),
      date: DateTime(2026, 3, 26),
    );
  }

  test('a well-formed transfer has no problems', () {
    expect(draft().validate(), isEmpty);
    expect(draft().isValid, isTrue);
  });

  test('the two sides must differ', () {
    expect(
      draft(to: everyday).validate(),
      contains(TransferProblem.sameAccount),
    );
  });

  test('the amount must be positive', () {
    expect(
      draft(amount: const Money.zero(Currency.usd)).validate(),
      contains(TransferProblem.nonPositiveAmount),
    );
    expect(
      draft(amount: const Money(-100, Currency.usd)).validate(),
      contains(TransferProblem.nonPositiveAmount),
    );
  });

  test('both sides must share a currency', () {
    final berlin = account(3, 'Berlin', currency: Currency.eur);
    expect(
      draft(to: berlin).validate(),
      contains(TransferProblem.currencyMismatch),
    );
  });

  test('archived accounts are not valid endpoints', () {
    final old = account(4, 'Old card', archived: true);
    expect(
      draft(to: old).validate(),
      contains(TransferProblem.archivedAccount),
    );
  });

  test('each problem has a message', () {
    for (final problem in TransferProblem.values) {
      expect(describeTransferProblem(problem), isNotEmpty);
    }
  });
}
