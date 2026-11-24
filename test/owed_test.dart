import 'package:alcohol_neon/features/dashboard/owed.dart';
import 'package:alcohol_neon/generated/zinc/models/owed_res.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, Object?> _item(String name, String state, String? reason) => {
  'habitId': 'h-$name',
  'habitName': name,
  'localDate': '2026-11-02',
  'amount': '5.00',
  'currency': 'USD',
  'charityName': 'Red Cross',
  'state': state,
  'reason': reason,
};

void main() {
  test('maps zinc owed items, oldest first, with state and reason', () {
    final owed = owedFromRes(
      OwedRes.fromJson({
        'total': '17.50',
        'currency': 'USD',
        'items': [
          _item('Run', 'couldNotCharge', 'chargeFailed'),
          _item('Read', 'charging', null),
        ],
      }),
    );
    expect(owed.total, 17.5);
    expect([for (final i in owed.items) i.habitName], ['Run', 'Read']);
    expect(owed.items.first.date, DateTime(2026, 11, 2));
    expect(owed.items.first.state, OwedState.couldntCharge);
    expect(owed.items.last.state, OwedState.charging);
    expect(owed.couldntCharge, hasLength(1));
    // Only a declined card: Fix card, not Add a card.
    expect(owed.needsCard, isFalse);
  });

  test('a penalty with no card asks to add one', () {
    final owed = owedFromRes(
      OwedRes.fromJson({
        'total': '10.00',
        'currency': 'USD',
        'items': [
          _item('Run', 'couldNotCharge', 'chargeFailed'),
          _item('Gym', 'couldNotCharge', 'noCard'),
        ],
      }),
    );
    expect(owed.needsCard, isTrue);
  });

  test('nothing owed: null currency, no items', () {
    final owed = owedFromRes(
      OwedRes.fromJson({'total': '0.00', 'currency': null, 'items': []}),
    );
    expect(owed.total, 0);
    expect(owed.items, isEmpty);
    expect(formatMoney(owed.total, owed.currency, cents: true), r'$0.00');
  });
}
