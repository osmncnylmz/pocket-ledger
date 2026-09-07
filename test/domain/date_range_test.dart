import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_ledger/domain/date_range.dart';

void main() {
  test('a month range is half open', () {
    final march = DateRange.month(DateTime(2026, 3, 17, 14, 30));

    expect(march.start, DateTime(2026, 3));
    expect(march.end, DateTime(2026, 4));
    expect(march.contains(DateTime(2026, 3)), isTrue);
    expect(march.contains(DateTime(2026, 3, 31, 23, 59, 59)), isTrue);
    expect(march.contains(DateTime(2026, 4)), isFalse);
    expect(march.days, 31);
  });

  test('a December month rolls over into the next year', () {
    final december = DateRange.month(DateTime(2026, 12, 5));
    expect(december.end, DateTime(2027));
  });

  test('February knows about leap years', () {
    expect(DateRange.month(DateTime(2024, 2, 10)).days, 29);
    expect(DateRange.month(DateTime(2026, 2, 10)).days, 28);
  });

  test('a week starts on Monday', () {
    // 18 March 2026 is a Wednesday.
    final week = DateRange.week(DateTime(2026, 3, 18, 9));
    expect(week.start, DateTime(2026, 3, 16));
    expect(week.end, DateTime(2026, 3, 23));
    expect(week.days, 7);

    // A Sunday belongs to the week that started six days earlier.
    final sunday = DateRange.week(DateTime(2026, 3, 22));
    expect(sunday.start, DateTime(2026, 3, 16));
  });

  test('lastMonths walks backwards across a year boundary', () {
    final months = DateRange.lastMonths(DateTime(2026, 2, 14), 4);

    expect(months.map((m) => m.start), [
      DateTime(2025, 11),
      DateTime(2025, 12),
      DateTime(2026),
      DateTime(2026, 2),
    ]);
    expect(months.last.end, DateTime(2026, 3));
  });

  test('elapsedDays counts the current day and clamps to the window', () {
    final march = DateRange.month(DateTime(2026, 3));

    expect(march.elapsedDays(DateTime(2026, 3, 1, 0, 1)), 1);
    expect(march.elapsedDays(DateTime(2026, 3, 10)), 10);
    expect(march.elapsedDays(DateTime(2026, 3, 31, 23)), 31);
    // Outside the window in both directions.
    expect(march.elapsedDays(DateTime(2026, 2, 20)), 1);
    expect(march.elapsedDays(DateTime(2026, 5, 20)), 31);
  });

  test('startOfDay drops the time', () {
    expect(startOfDay(DateTime(2026, 3, 18, 23, 59)), DateTime(2026, 3, 18));
  });
}
