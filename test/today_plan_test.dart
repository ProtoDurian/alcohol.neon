import 'package:alcohol_neon/features/dashboard/today_plan.dart';
import 'package:alcohol_neon/generated/zinc/models/habit_execution_res.dart';
import 'package:alcohol_neon/generated/zinc/models/habit_overview_habit_res.dart';
import 'package:flutter_test/flutter_test.dart';

// 09-11-2026 is a Monday: index 1 in zinc's Sunday-first days[].
HabitOverviewHabitRes habit(
  String id, {
  String? status = 'not_applicable',
  int minutesLeft = 120,
  bool enabled = true,
  bool scheduledToday = true,
  String? deadlineUtc,
  int? sortOrder,
  String? name,
  String? habitTime,
  String? reminder,
  String? proof,
}) => HabitOverviewHabitRes.fromJson({
  'id': id,
  'name': name ?? id,
  'habitTime': habitTime,
  'notificationTime': reminder,
  'proof': proof,
  'sortOrder': ?sortOrder,
  'enabled': enabled,
  'days': List.generate(7, (i) => i == 1 ? scheduledToday : !scheduledToday),
  'stake': {'amount': 1, 'currency': 'USD'},
  'charity': {'name': 'Red Cross'},
  'version': {'id': 'v-$id', 'version': 1, 'isActive': true},
  'timeLeftToEodMinutes': minutesLeft,
  'todayDeadlineUtc': deadlineUtc,
  'status': {
    'currentStreak': 0,
    'maxStreak': 0,
    'isCompleteToday': false,
    'today': '09-11-2026',
    'todayStatus': status,
    'week': <String, Object?>{},
  },
});

void main() {
  final loadedAt = DateTime(2026, 11, 9, 18);
  String? serverStatus(HabitOverviewHabitRes h) => h.status.todayStatus;
  TodayPlan plan(List<HabitOverviewHabitRes> habits) =>
      buildTodayPlan(habits, todayStatus: serverStatus, loadedAt: loadedAt);
  List<String?> ids(List<TodayItem> items) => [
    for (final i in items) i.habit.id,
  ];

  group('tabs', () {
    test('each side of 12:00 and 18:00, and no time at all', () {
      expect(tabOf(habit('a', habitTime: '00:00')), TodayTab.morning);
      expect(tabOf(habit('a', habitTime: '11:59')), TodayTab.morning);
      expect(tabOf(habit('a', habitTime: '12:00')), TodayTab.afternoon);
      expect(tabOf(habit('a', habitTime: '17:59')), TodayTab.afternoon);
      expect(tabOf(habit('a', habitTime: '18:00')), TodayTab.evening);
      expect(tabOf(habit('a', habitTime: '23:59')), TodayTab.evening);
      expect(tabOf(habit('a')), TodayTab.anytime);
    });

    test('reads HH:mm:ss, and falls back to the reminder time', () {
      expect(tabOf(habit('a', habitTime: '11:59:59')), TodayTab.morning);
      expect(tabOf(habit('a', reminder: '17:59:00')), TodayTab.afternoon);
      expect(tabOf(habit('a', reminder: '18:00')), TodayTab.evening);
      // The habit time wins over the reminder.
      expect(
        tabOf(habit('a', habitTime: '19:00', reminder: '08:00:00')),
        TodayTab.evening,
      );
      // An unreadable time counts as none.
      expect(tabOf(habit('a', habitTime: '25:00')), TodayTab.anytime);
    });

    test('a tab lists its habits in time order, All lists every one', () {
      final p = plan([
        habit('eve', habitTime: '18:00'),
        habit('none'),
        habit('noon', habitTime: '12:00'),
        habit('late-am', habitTime: '11:59'),
        habit('pm', reminder: '17:59:00'),
      ]);
      expect(ids(p.inTab(TodayTab.morning)), ['late-am']);
      expect(ids(p.inTab(TodayTab.afternoon)), ['noon', 'pm']);
      expect(ids(p.inTab(TodayTab.evening)), ['eve']);
      expect(ids(p.inTab(TodayTab.anytime)), ['none']);
      expect(ids(p.inTab(TodayTab.all)), [
        'late-am',
        'noon',
        'pm',
        'eve',
        'none',
      ]);
    });
  });

  group('sort', () {
    test('sort time first, no time last, ties by sortOrder then id', () {
      final p = plan([
        habit('none-b', sortOrder: 0),
        habit('nine-z', habitTime: '09:00', sortOrder: 5),
        habit('nine-y', habitTime: '09:00:00', sortOrder: 5),
        habit('nine-a', reminder: '09:00:00', sortOrder: 6),
        habit('seven', habitTime: '07:00', sortOrder: 9),
        habit('none-a', sortOrder: 1),
      ]);
      expect(ids(p.items), [
        'seven',
        'nine-y',
        'nine-z',
        'nine-a',
        'none-b',
        'none-a',
      ]);
    });

    test('done habits keep their time slot; not-today ones are hidden', () {
      final p = plan([
        habit('eve', habitTime: '20:00'),
        habit('done', habitTime: '08:00', status: 'succeeded'),
        habit('rest', habitTime: '07:00', scheduledToday: false),
        habit('missed', habitTime: '10:00', status: 'failed'),
        habit('paused-today', habitTime: '09:00', enabled: false),
        habit('paused-rest', enabled: false, scheduledToday: false),
      ]);
      expect(ids(p.items), ['done', 'paused-today', 'missed', 'eve']);
      expect(ids(p.todo), ['eve']);
      expect(ids(p.done), ['done', 'missed']);
      expect(p.scheduled, 3);
    });

    test('Next up is the first open habit by time, not by deadline', () {
      final p = buildTodayPlan(
        [
          habit('late-check', habitTime: '21:00', minutesLeft: 30),
          habit('early', habitTime: '07:00', minutesLeft: 600),
          habit('done', habitTime: '06:00', status: 'succeeded'),
        ],
        todayStatus: serverStatus,
        loadedAt: DateTime(2026, 11, 9, 6),
      );
      expect(p.next!.habit.id, 'early');
      expect(p.next!.deadline, DateTime(2026, 11, 9, 16));
    });

    test('without sortOrder (older zinc) ties keep the server order', () {
      final p = plan([habit('m'), habit('z'), habit('a')]);
      expect(ids(p.items), ['m', 'z', 'a']);
    });

    test('an unsaved reorder breaks ties before sortOrder', () {
      final p = buildTodayPlan(
        [
          habit('a', sortOrder: 0),
          habit('b', sortOrder: 1),
          habit('t', habitTime: '08:00', sortOrder: 2),
        ],
        todayStatus: serverStatus,
        loadedAt: loadedAt,
        order: ['t', 'b', 'a'],
      );
      expect(ids(p.items), ['t', 'b', 'a']);
    });
  });

  test('the server deadline wins over minutes left when present', () {
    final p = buildTodayPlan(
      [habit('a', minutesLeft: 600, deadlineUtc: '2026-11-09T10:15:00Z')],
      todayStatus: serverStatus,
      loadedAt: DateTime.utc(2026, 11, 9, 10),
    );
    expect(p.next!.deadline!.toUtc(), DateTime.utc(2026, 11, 9, 10, 15));
  });

  test('an acknowledged action overrides the stale server status', () {
    final p = buildTodayPlan(
      [habit('a'), habit('b')],
      todayStatus: (h) => h.id == 'a' ? 'skip' : h.status.todayStatus,
      loadedAt: loadedAt,
    );
    expect(p.next!.habit.id, 'b');
    expect(p.done.single.state, TodayState.skipped);
  });

  test("a past day: its weekday's habits with their results", () {
    HabitExecutionRes ran(String id, String status) => HabitExecutionRes(
      id: 'e-$id',
      habitVersionId: 'v-$id',
      date: '10-11-2026',
      status: status,
      paymentProcessed: false,
    );
    // Tuesday 10 Nov 2026; the helper's habits run on Mondays only unless
    // scheduledToday is false (then every day but Monday).
    final items = pastItems(
      [
        habit('mon-only', habitTime: '09:00'),
        habit('done', habitTime: '20:00', scheduledToday: false),
        habit('missed', habitTime: '07:00', scheduledToday: false),
        habit('none', scheduledToday: false),
      ],
      DateTime(2026, 11, 10),
      [ran('done', 'succeeded'), ran('missed', 'failed')],
    );
    expect(
      {for (final i in items) i.habit.id: i.state},
      {
        'missed': TodayState.settled,
        'done': TodayState.done,
        'none': TodayState.unknown,
      },
    );
    expect(ids(items), ['missed', 'done', 'none']);
  });

  test('row labels: proof, time and a short stake', () {
    expect(proofLabel(habit('a', proof: 'strava')), 'Auto from Strava');
    expect(proofLabel(habit('a', proof: 'nfc')), 'NFC tag');
    expect(proofLabel(habit('a', proof: 'manual')), isNull);
    expect(sortTimeLabel(habit('a', reminder: '07:05:00')), '07:05');
    expect(sortTimeLabel(habit('a')), isNull);
    expect(stakeShort(habit('a')), r'$1 at stake');
  });
}
