import 'package:meta/meta.dart';

/// A half-open interval `[start, end)` of local time.
///
/// Half-open is deliberate: it makes "the whole of March" expressible without
/// worrying about the last microsecond of the 31st, and it turns every date
/// filter into `date >= start AND date < end`, which SQLite can serve straight
/// from an index.
@immutable
final class DateRange {
  const DateRange(this.start, this.end);

  factory DateRange.month(DateTime moment) {
    final start = DateTime(moment.year, moment.month);
    return DateRange(start, DateTime(moment.year, moment.month + 1));
  }

  /// ISO weeks: Monday to Sunday.
  factory DateRange.week(DateTime moment) {
    final day = DateTime(moment.year, moment.month, moment.day);
    final start = day.subtract(Duration(days: day.weekday - DateTime.monday));
    return DateRange(start, DateTime(start.year, start.month, start.day + 7));
  }

  factory DateRange.year(DateTime moment) =>
      DateRange(DateTime(moment.year), DateTime(moment.year + 1));

  final DateTime start;
  final DateTime end;

  /// Oldest first, and the month of [moment] is the last one, not the one
  /// before it.
  static List<DateRange> lastMonths(DateTime moment, int count) {
    assert(count > 0, 'count must be positive');
    return [
      for (var offset = count - 1; offset >= 0; offset--)
        DateRange.month(DateTime(moment.year, moment.month - offset)),
    ];
  }

  bool contains(DateTime moment) =>
      !moment.isBefore(start) && moment.isBefore(end);

  /// Number of whole days spanned. Uses UTC arithmetic so that a daylight
  /// saving transition inside the range does not shorten or lengthen it.
  int get days {
    final utcStart = DateTime.utc(start.year, start.month, start.day);
    final utcEnd = DateTime.utc(end.year, end.month, end.day);
    return utcEnd.difference(utcStart).inDays;
  }

  /// Days elapsed at [moment], clamped to `1..days`. Drives the "ahead of
  /// pace" check on budgets.
  int elapsedDays(DateTime moment) {
    if (!moment.isAfter(start)) return 1;
    final utcStart = DateTime.utc(start.year, start.month, start.day);
    final utcNow = DateTime.utc(moment.year, moment.month, moment.day);
    final elapsed = utcNow.difference(utcStart).inDays + 1;
    return elapsed.clamp(1, days);
  }

  @override
  bool operator ==(Object other) =>
      other is DateRange && other.start == start && other.end == end;

  @override
  int get hashCode => Object.hash(start, end);

  @override
  String toString() =>
      'DateRange(${start.toIso8601String()} .. '
      '${end.toIso8601String()})';
}

DateTime startOfDay(DateTime moment) =>
    DateTime(moment.year, moment.month, moment.day);
