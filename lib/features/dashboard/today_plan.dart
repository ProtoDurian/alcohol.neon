import '../../core/date_format.dart';
import '../../generated/zinc/models/habit_execution_res.dart';
import '../../generated/zinc/models/habit_overview_habit_res.dart';

/// Where a habit stands today, from the server's habit-local date and status.
enum TodayState {
  todo,
  done,
  skipped,
  frozen,
  vacation,
  settled,
  rest,
  paused,
  unknown,
}

class TodayItem {
  final HabitOverviewHabitRes habit;
  final TodayState state;

  /// When today's check ends; null when the habit isn't open today.
  final DateTime? deadline;

  const TodayItem(this.habit, this.state, this.deadline);

  bool get open => state == TodayState.todo;
}

/// Today's tabs. A habit sits in the part of the day its sort time falls in
/// (the habit's own wall-clock time, so the user's timezone); [anytime] is
/// for habits with no habit time and no reminder time.
enum TodayTab {
  all('All'),
  morning('Morning'),
  afternoon('Afternoon'),
  evening('Evening'),
  anytime('Anytime');

  final String label;
  const TodayTab(this.label);

  bool includes(HabitOverviewHabitRes habit) =>
      this == all || this == tabOf(habit);
}

/// "HH:mm" or "HH:mm:ss" as minutes after midnight; null when unreadable.
int? parseClockMinutes(String? value) {
  final parts = value?.split(':') ?? const <String>[];
  if (parts.length < 2) return null;
  final h = int.tryParse(parts[0]), m = int.tryParse(parts[1]);
  if (h == null || m == null || h < 0 || h > 23 || m < 0 || m > 59) {
    return null;
  }
  return h * 60 + m;
}

/// When the habit is planned: its habit time, else its reminder time, as
/// minutes after midnight. Null when it has neither.
int? sortTimeOf(HabitOverviewHabitRes h) =>
    parseClockMinutes(h.habitTime) ?? parseClockMinutes(h.notificationTime);

/// Morning before 12:00, afternoon 12:00 to 17:59, evening from 18:00.
TodayTab tabOf(HabitOverviewHabitRes h) => switch (sortTimeOf(h)) {
  null => TodayTab.anytime,
  final m when m < 12 * 60 => TodayTab.morning,
  final m when m < 18 * 60 => TodayTab.afternoon,
  _ => TodayTab.evening,
};

/// Today's habits in one list, sort time first: done ones stay in their
/// place, and habits not scheduled today are left out.
class TodayPlan {
  final List<TodayItem> items;

  const TodayPlan(this.items);

  /// The open habits, in list order. Next up, the widgets and the Live
  /// Activity follow this.
  List<TodayItem> get todo => [
    for (final i in items)
      if (i.open) i,
  ];

  /// The habits settled today: done, skipped, frozen, on vacation or missed.
  List<TodayItem> get done => [
    for (final i in items)
      if (_settled.contains(i.state)) i,
  ];

  /// The habit to do now: the first open one by time.
  TodayItem? get next {
    for (final i in items) {
      if (i.open) return i;
    }
    return null;
  }

  /// Habits that count toward today's ring: open plus settled today.
  int get scheduled => todo.length + done.length;

  List<TodayItem> inTab(TodayTab tab) => [
    for (final i in items)
      if (tab.includes(i.habit)) i,
  ];

  static const _settled = {
    TodayState.done,
    TodayState.skipped,
    TodayState.frozen,
    TodayState.vacation,
    TodayState.settled,
  };
}

/// Mirrors the old dashboard's precedence: paused, then a missing status, then
/// the settled statuses, then rest days; anything left is open today.
TodayState todayStateOf(HabitOverviewHabitRes habit, String? todayStatus) {
  if (!habit.enabled) return TodayState.paused;
  final today = tryParseStandardDate(habit.status.today);
  if (today == null || todayStatus == null) return TodayState.unknown;
  switch (todayStatus) {
    case 'succeeded':
      return TodayState.done;
    case 'skip':
      return TodayState.skipped;
    case 'frozen':
      return TodayState.frozen;
    case 'vacation':
      return TodayState.vacation;
    case 'failed':
      return TodayState.settled;
  }
  return _onTodaysSchedule(habit) ? TodayState.todo : TodayState.rest;
}

/// Whether the habit runs on the server's habit-local today (Sunday = 0).
/// True when the server's today can't be read, so nothing vanishes.
bool _onTodaysSchedule(HabitOverviewHabitRes h) {
  final today = tryParseStandardDate(h.status.today);
  if (today == null) return true;
  final index = today.weekday % 7;
  final days = h.days ?? const <bool>[];
  return index < days.length && days[index];
}

/// Compares habits in the user's order: an unsaved reorder ([order], habit
/// ids) first, then zinc's `sortOrder`, or the overview's own order from a
/// zinc that doesn't send one. Ties go to the habit id.
Comparator<HabitOverviewHabitRes> userOrder(
  List<HabitOverviewHabitRes> habits, {
  List<String>? order,
}) {
  final moved = {for (final (i, id) in (order ?? const []).indexed) id: i};
  final rank = {
    for (final (i, h) in habits.indexed)
      h: moved[h.id] ?? moved.length + (h.sortOrder ?? i),
  };
  return (a, b) {
    final byRank = rank[a]!.compareTo(rank[b]!);
    return byRank != 0 ? byRank : (a.id ?? '').compareTo(b.id ?? '');
  };
}

/// Compares habits by sort time, habits without one last; ties go to the
/// user's order (see [userOrder]).
Comparator<HabitOverviewHabitRes> timeOrder(
  List<HabitOverviewHabitRes> habits, {
  List<String>? order,
}) {
  final byUser = userOrder(habits, order: order);
  return (a, b) {
    final ta = sortTimeOf(a), tb = sortTimeOf(b);
    if (ta != tb) {
      if (ta == null) return 1;
      if (tb == null) return -1;
      return ta.compareTo(tb);
    }
    return byUser(a, b);
  };
}

TodayPlan buildTodayPlan(
  List<HabitOverviewHabitRes> habits, {
  required String? Function(HabitOverviewHabitRes) todayStatus,
  required DateTime loadedAt,
  List<String>? order,
}) {
  final items = <TodayItem>[];
  for (final h in [...habits]..sort(timeOrder(habits, order: order))) {
    final state = todayStateOf(h, todayStatus(h));
    switch (state) {
      case TodayState.todo:
        // The stored check's end (zinc ≥ 1.37); older servers only send the
        // minutes left, counted from when the overview was loaded.
        final deadline =
            h.todayDeadlineUtc?.toLocal() ??
            loadedAt.add(Duration(minutes: h.timeLeftToEodMinutes));
        items.add(TodayItem(h, state, deadline));
      case TodayState.rest:
        break; // not scheduled today: hidden
      case TodayState.paused:
        // Still listed on its days, so it can be opened and turned back on.
        if (_onTodaysSchedule(h)) items.add(TodayItem(h, state, null));
      default:
        items.add(TodayItem(h, state, null));
    }
  }
  return TodayPlan(items);
}

/// A past day's list, read only, in time order: the habits on that weekday's
/// schedule plus any with a result that day, each with its result from
/// zinc's executions (matched by habit version). No result shows as
/// [TodayState.unknown].
List<TodayItem> pastItems(
  List<HabitOverviewHabitRes> habits,
  DateTime day,
  List<HabitExecutionRes> executions,
) {
  final results = {for (final e in executions) e.habitVersionId: e.status};
  final index = day.weekday % 7;
  bool onSchedule(HabitOverviewHabitRes h) {
    final days = h.days ?? const <bool>[];
    return index < days.length && days[index];
  }

  return [
    for (final h in [...habits]..sort(timeOrder(habits)))
      if (results.containsKey(h.version.id) || onSchedule(h))
        TodayItem(h, switch (results[h.version.id]) {
          'succeeded' => TodayState.done,
          'failed' => TodayState.settled,
          'skip' => TodayState.skipped,
          'frozen' => TodayState.frozen,
          'vacation' => TodayState.vacation,
          _ => TodayState.unknown,
        }, null),
  ];
}

/// How the habit is proven, for its row: Strava and NFC habits say so, a
/// plain check-in (or an unknown proof) says nothing.
String? proofLabel(HabitOverviewHabitRes h) => switch (h.proof) {
  'strava' => 'Auto from Strava',
  'nfc' => 'NFC tag',
  _ => null,
};

/// The planned time as "07:00", or null with no habit or reminder time.
String? sortTimeLabel(HabitOverviewHabitRes h) {
  final m = sortTimeOf(h);
  if (m == null) return null;
  String two(int v) => v.toString().padLeft(2, '0');
  return '${two(m ~/ 60)}:${two(m % 60)}';
}

/// The stake, short, for a row: "$5 at stake"; null when nothing is.
String? stakeShort(HabitOverviewHabitRes h) {
  final a = h.stake.amount;
  if (a <= 0) return null;
  final amount = a == a.roundToDouble()
      ? a.toStringAsFixed(0)
      : a.toStringAsFixed(2);
  final currency = h.stake.currency;
  return currency == null || currency == 'USD'
      ? '\$$amount at stake'
      : '$currency $amount at stake';
}

/// What's at stake on a miss, as one quiet line; null when nothing is.
String? stakeLine(HabitOverviewHabitRes h) {
  if (h.stake.amount <= 0) return null;
  final amount =
      '${h.stake.currency ?? ''} ${h.stake.amount.toStringAsFixed(2)}'.trim();
  return '$amount to ${h.charity?.name ?? 'charity'} if you miss';
}
