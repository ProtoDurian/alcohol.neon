import 'package:alcohol_neon/features/dashboard/dashboard_view.dart';
import 'package:alcohol_neon/features/subscription/upgrade_sheet.dart';
import 'package:alcohol_neon/features/vacation/vacation_controller.dart';
import 'package:alcohol_neon/features/vacation/vacation_create_view.dart';
import 'package:alcohol_neon/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:alcohol_neon/generated/zinc/models/plan_res.dart';
import 'package:alcohol_neon/generated/zinc/models/vacation_res.dart';
import 'package:flutter_test/flutter_test.dart';

/// Plan limits: the skip confirmation, the yearly vacation count and what
/// the upgrade prompt says the next plan gives.
void main() {
  PlanRes plan(String key, int skips, int vacations, int? maxDays) => PlanRes(
    key: key,
    priceCents: 0,
    habitsUnlimited: false,
    skipsMonthly: skips,
    vacationWindowsYearly: vacations,
    freezeBase: 0,
    vacationMaxDays: maxDays,
  );
  final free = plan('free', 3, 0, 0);
  final pro = plan('pro', 5, 2, 14);
  final ultimate = plan('ultimate', 10, 5, 30);

  group('skip confirmation', () {
    test('says how many are left after this skip', () {
      expect(
        skipConfirmMessage(3, 5),
        'This uses 1 skip. You’ll have 2 of 5 left this month.',
      );
    });
    test('the last skip says so instead of "0 left"', () {
      expect(skipConfirmMessage(1, 5), 'This uses your last skip this month.');
    });
  });

  group('vacations counted by start year', () {
    VacationRes v(String start, String end) =>
        VacationRes(id: start, startDate: start, endDate: end, timezone: 'UTC');
    final list = [
      v('30-12-2025', '04-01-2026'), // over New Year: counts for 2025 only
      v('10-03-2026', '12-03-2026'),
      v('28-12-2026', '05-01-2027'), // counts for 2026
    ];
    test('a New Year vacation counts once, in its start year', () {
      expect(vacationsStartingIn(list, 2025), 1);
      expect(vacationsStartingIn(list, 2026), 2);
      expect(vacationsStartingIn(list, 2027), 0);
    });
  });

  testWidgets('the calendar stops the last day at the plan length', (
    tester,
  ) async {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month + 1, 1);
    final tapped = <int>[];
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: SingleChildScrollView(
            child: RangeCalendar(
              start: start,
              end: null,
              maxDays: 14,
              onTap: (d) => tapped.add(d.day),
            ),
          ),
        ),
      ),
    );
    // Day 14 makes 14 days, both ends counted; day 15 would be 15.
    await tester.tap(find.text('15'));
    await tester.tap(find.text('14'));
    expect(tapped, [14]);
  });

  group('upgrade line', () {
    test('names what the next plan gives for the limit hit', () {
      expect(
        upgradeLine(PlanLimit.skips, free, pro),
        'Pro gives 5 skips a month.',
      );
      expect(
        upgradeLine(PlanLimit.vacations, free, pro),
        'Pro gives 2 vacations a year, up to 14 days each.',
      );
      expect(
        upgradeLine(PlanLimit.vacationLength, pro, ultimate),
        'Ultimate allows up to 30 days per vacation.',
      );
    });
    test('says nothing when the next plan gives no more', () {
      final same = plan('ultimate', 5, 2, 14);
      expect(upgradeLine(PlanLimit.skips, pro, same), isNull);
      expect(upgradeLine(PlanLimit.vacations, pro, same), isNull);
      expect(upgradeLine(PlanLimit.vacationLength, pro, same), isNull);
    });
    test('an older zinc without a length sends no length line', () {
      final old = plan('pro', 5, 2, null);
      expect(
        upgradeLine(PlanLimit.vacations, free, old),
        'Pro gives 2 vacations a year.',
      );
      expect(upgradeLine(PlanLimit.vacationLength, free, old), isNull);
    });
  });
}
