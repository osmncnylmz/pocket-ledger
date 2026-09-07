import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_ledger/data/database.dart';
import 'package:pocket_ledger/domain/enums.dart';
import 'package:pocket_ledger/domain/money.dart';
import 'package:pocket_ledger/domain/services/transfer.dart';
import 'package:pocket_ledger/presentation/screens/dashboard_screen.dart';
import 'package:pocket_ledger/presentation/widgets/donut_chart.dart';
import 'package:pocket_ledger/presentation/widgets/section_card.dart';
import 'package:pocket_ledger/presentation/widgets/trend_chart.dart';

import '../data/fixtures.dart';
import '../data/test_database.dart';
import 'harness.dart';

void main() {
  final now = DateTime(2026, 3, 18, 10);

  Future<AppDatabase> seededLedger() async {
    final db = newTestDatabase();
    final everyday = await db.makeAccount(
      'Everyday',
      openingBalance: Money.major(1500, Currency.usd),
    );
    final savings = await db.makeAccount(
      'Savings',
      kind: AccountKind.savings,
      openingBalance: Money.major(4000, Currency.usd),
    );
    final groceries = await db.makeCategory('Groceries');
    final dining = await db.makeCategory('Dining', iconKey: 'dining');
    final salary = await db.makeCategory('Salary', kind: CategoryKind.income);

    await db.earn(everyday, salary, 320000, DateTime(2026, 3, 2));
    await db.spend(everyday, groceries, 12500, DateTime(2026, 3, 4));
    await db.spend(everyday, groceries, 8900, DateTime(2026, 3, 11));
    await db.spend(everyday, dining, 4200, DateTime(2026, 3, 12));
    await db.spend(everyday, groceries, 6000, DateTime(2026, 2, 8));
    await db.transactionsDao.createTransfer(
      TransferDraft(
        from: everyday,
        to: savings,
        amount: Money.major(300, Currency.usd),
        date: DateTime(2026, 3, 14),
      ),
    );
    await db.budgetsDao.setLimit(
      categoryId: groceries.id,
      period: BudgetPeriod.monthly,
      limit: Money.major(300, Currency.usd),
    );
    return db;
  }

  testWidgets('shows the total balance and every account', (tester) async {
    final db = await seededLedger();
    addTearDown(db.close);
    await pumpScreen(tester, const DashboardScreen(), database: db, now: now);

    // 1500 + 4000 opening and 3200 of salary, less the 316 spent across
    // February and March. The transfer moves money between two accounts, so it
    // leaves the total alone.
    expect(find.text(r'$8,384.00'), findsOneWidget);
    expect(find.text('Everyday'), findsOneWidget);
    expect(find.text('Savings'), findsOneWidget);
    expect(find.text(r'$4,300.00'), findsOneWidget);
  });

  testWidgets('summarises the selected month', (tester) async {
    final db = await seededLedger();
    addTearDown(db.close);
    await pumpScreen(tester, const DashboardScreen(), database: db, now: now);

    // Scoped to the summary card: the donut in the card below reports the same
    // total, which is the point, but it is not what this test is about.
    final summary = find.ancestor(
      of: find.text('March 2026'),
      matching: find.byType(SectionCard),
    );
    expect(summary, findsOneWidget);
    expect(
      find.descendant(of: summary, matching: find.text('Spent')),
      findsOneWidget,
    );
    // 125.00 + 89.00 + 42.00, with the transfer excluded.
    expect(
      find.descendant(of: summary, matching: find.text(r'$256.00')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: summary, matching: find.text(r'$3,200.00')),
      findsOneWidget,
    );
  });

  testWidgets('breaks spending down by category with a donut', (tester) async {
    final db = await seededLedger();
    addTearDown(db.close);
    await pumpScreen(tester, const DashboardScreen(), database: db, now: now);

    await tester.scrollUntilVisible(find.byType(DonutChart), 200);
    expect(find.byType(DonutChart), findsOneWidget);
    // The legend lists the categories, biggest first.
    expect(find.text('Groceries'), findsWidgets);
    expect(find.text('Dining'), findsWidgets);
  });

  testWidgets('tapping a legend entry focuses that slice', (tester) async {
    final db = await seededLedger();
    addTearDown(db.close);
    await pumpScreen(tester, const DashboardScreen(), database: db, now: now);

    await tester.scrollUntilVisible(find.byType(DonutChart), 200);
    expect(find.text('Total'), findsOneWidget);

    await tester.tap(find.text('Dining').first);
    await tester.pumpAndSettle();

    // The centre of the donut now reads the selected category and its total.
    expect(find.text('Total'), findsNothing);
    expect(find.text(r'$42.00'), findsWidgets);
  });

  testWidgets('draws a six month trend', (tester) async {
    final db = await seededLedger();
    addTearDown(db.close);
    await pumpScreen(tester, const DashboardScreen(), database: db, now: now);

    await tester.scrollUntilVisible(find.byType(TrendChart), 200);
    final chart = tester.widget<TrendChart>(find.byType(TrendChart));
    expect(chart.points, hasLength(6));
    expect(chart.points.last.label, 'Mar');
    expect(chart.points.last.expense, 25600);
    expect(chart.points.last.income, 320000);
    // February held one 60.00 expense and no income.
    expect(chart.points[4].expense, 6000);
    expect(chart.points[4].income, 0);
  });

  testWidgets('shows budget progress against the monthly limit', (
    tester,
  ) async {
    final db = await seededLedger();
    addTearDown(db.close);
    await pumpScreen(tester, const DashboardScreen(), database: db, now: now);

    await tester.scrollUntilVisible(find.text('Budgets'), 200);
    // 214.00 spent of a 300.00 limit is 71%.
    expect(find.text('71%'), findsOneWidget);
    expect(find.text('Ahead of pace'), findsOneWidget);
  });

  testWidgets('stepping back a month changes every figure', (tester) async {
    final db = await seededLedger();
    addTearDown(db.close);
    await pumpScreen(tester, const DashboardScreen(), database: db, now: now);

    await tester.tap(find.byTooltip('Previous month'));
    await tester.pumpAndSettle();

    expect(find.text('February 2026'), findsOneWidget);
    expect(find.text(r'$60.00'), findsWidgets);
    expect(find.text(r'$256.00'), findsNothing);
  });

  testWidgets('an empty ledger shows empty states', (tester) async {
    await pumpScreen(tester, const DashboardScreen(), now: now);

    expect(find.text('No accounts yet'), findsOneWidget);
    expect(find.text('Nothing spent this month'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('No budgets set'), 200);
    expect(find.text('No budgets set'), findsOneWidget);
  });

  testWidgets('renders in the dark theme', (tester) async {
    final db = await seededLedger();
    addTearDown(db.close);
    await pumpScreen(
      tester,
      const DashboardScreen(),
      database: db,
      now: now,
      brightness: Brightness.dark,
    );

    expect(find.text(r'$8,384.00'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('honours the reduced motion setting', (tester) async {
    final db = await seededLedger();
    addTearDown(db.close);

    await tester.binding.setSurfaceSize(testSurface);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await pumpScreen(
      tester,
      const MediaQuery(
        data: MediaQueryData(disableAnimations: true),
        child: DashboardScreen(),
      ),
      database: db,
      now: now,
    );

    // Motion.of collapses every duration to zero under reduced motion, so the
    // chart is already at its final state on the first frame.
    await tester.scrollUntilVisible(find.byType(DonutChart), 200);
    expect(find.byType(DonutChart), findsOneWidget);
  });
}
