import '../../generated/zinc/models/habit_overview_response.dart';

/// Where a penalty stands. zinc charges penalties on its own every 15
/// minutes; one it couldn't charge (no card, or 5 failed tries) waits until
/// the card is fixed.
enum OwedState { charging, couldntCharge }

/// One missed habit the user owes for.
class OwedItem {
  final String habitName;

  /// The missed day; null while the data comes from the overview, which only
  /// has a total per habit.
  final DateTime? date;
  final double amount;
  final String? currency;
  final String? charityName;
  final OwedState state;

  const OwedItem({
    required this.habitName,
    required this.amount,
    required this.state,
    this.date,
    this.currency,
    this.charityName,
  });
}

/// What the Owed screen lists, and why there is no card action yet.
class Owed {
  final double total;
  final String? currency;
  final List<OwedItem> items;

  const Owed(this.total, this.currency, this.items);

  bool get any => total > 0;
  bool get anyCouldntCharge =>
      items.any((i) => i.state == OwedState.couldntCharge);
}

/// zinc's money strings ("12.50") as a number; 0 when unreadable.
double parseMoney(String? value) => double.tryParse(value ?? '') ?? 0;

/// The owed list from today's overview: one item per habit with debt.
///
/// SEAM: zinc is adding an owed-list route that returns each missed day with
/// its date, amount, charity and charge state ("Charging" or "Couldn't
/// charge"). Until it lands, the overview only has each habit's total, so
/// there's no date, and the state is guessed from the card: without a card
/// nothing can be charged. Replace this function's body with that route's
/// mapping; the Owed screen only reads [Owed].
Owed owedFromOverview(
  HabitOverviewResponse? overview, {
  required bool hasCard,
}) {
  final habits = overview?.habits ?? const [];
  final items = [
    for (final h in habits)
      if (parseMoney(h.totalDebt) > 0)
        OwedItem(
          habitName: h.name ?? 'Habit',
          amount: parseMoney(h.totalDebt),
          currency: h.stake.currency,
          charityName: h.charity?.name,
          state: hasCard ? OwedState.charging : OwedState.couldntCharge,
        ),
  ];
  final currency = items.isEmpty ? null : items.first.currency;
  return Owed(parseMoney(overview?.totalDebt), currency, items);
}

/// "$5" or "$5.50" (or "EUR 5" for other currencies).
String formatMoney(double amount, String? currency, {bool cents = false}) {
  final text = !cents && amount == amount.roundToDouble()
      ? amount.toStringAsFixed(0)
      : amount.toStringAsFixed(2);
  return currency == null || currency == 'USD' ? '\$$text' : '$currency $text';
}
