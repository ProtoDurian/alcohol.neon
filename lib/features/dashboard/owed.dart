import '../../generated/zinc/models/owed_res.dart';

/// Where a penalty stands. zinc charges penalties on its own every 15
/// minutes; one it couldn't charge waits until the card is added or fixed.
enum OwedState { charging, couldntCharge }

/// Why zinc couldn't charge: no card on file, or the card was declined.
enum OwedReason { noCard, chargeFailed }

/// One missed day the user owes for.
class OwedItem {
  final String habitName;
  final DateTime? date;
  final double amount;
  final String? currency;
  final String? charityName;
  final OwedState state;
  final OwedReason? reason;

  const OwedItem({
    required this.habitName,
    required this.amount,
    required this.state,
    this.date,
    this.currency,
    this.charityName,
    this.reason,
  });
}

/// What the Owed screen lists.
class Owed {
  final double total;
  final String? currency;
  final List<OwedItem> items;

  const Owed(this.total, this.currency, this.items);

  List<OwedItem> get couldntCharge => [
    for (final i in items)
      if (i.state == OwedState.couldntCharge) i,
  ];

  /// Some penalty is waiting for a card: Add a card wins over Fix card.
  bool get needsCard => couldntCharge.any((i) => i.reason == OwedReason.noCard);
}

/// zinc's money strings ("12.50") as a number; 0 when unreadable.
double parseMoney(String? value) => double.tryParse(value ?? '') ?? 0;

/// zinc's owed list (`GET /Penalty/{userId}/owed`), oldest first.
Owed owedFromRes(OwedRes res) => Owed(parseMoney(res.total), res.currency, [
  for (final i in res.items ?? const [])
    OwedItem(
      habitName: i.habitName ?? 'Habit',
      date: DateTime.tryParse(i.localDate ?? ''),
      amount: parseMoney(i.amount),
      currency: i.currency ?? res.currency,
      charityName: i.charityName,
      state: i.state == 'couldNotCharge'
          ? OwedState.couldntCharge
          : OwedState.charging,
      reason: switch (i.reason) {
        'noCard' => OwedReason.noCard,
        'chargeFailed' => OwedReason.chargeFailed,
        _ => null,
      },
    ),
]);

/// "$5" or "$5.50" (or "EUR 5" for other currencies).
String formatMoney(double amount, String? currency, {bool cents = false}) {
  final text = !cents && amount == amount.roundToDouble()
      ? amount.toStringAsFixed(0)
      : amount.toStringAsFixed(2);
  return currency == null || currency == 'USD' ? '\$$text' : '$currency $text';
}
