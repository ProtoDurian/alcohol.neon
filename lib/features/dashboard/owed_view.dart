import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/problem.dart';
import '../../session/session_controller.dart';
import '../../theme/app_theme.dart';
import '../../theme/glass.dart';
import '../../widgets/glass_list.dart';
import '../../widgets/glass_modal.dart';
import '../../widgets/glass_page.dart';
import '../payment/consent_service.dart';
import 'owed.dart';

const _months = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];
const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

String _day(DateTime d) =>
    '${_weekdays[d.weekday - 1]} ${d.day} ${_months[d.month - 1]}';

/// What the user owes: the total, each missed habit with its charge state,
/// and a card to add or fix. zinc charges on its own, so there is no Pay
/// button. Pops `true` when a card was added, so Today reloads.
class OwedView extends StatefulWidget {
  final Owed owed;
  const OwedView({super.key, required this.owed});

  @override
  State<OwedView> createState() => _OwedViewState();
}

class _OwedViewState extends State<OwedView> {
  bool _busy = false;
  bool _changed = false;
  Problem? _error;

  Future<void> _fixCard({required bool replace}) async {
    final session = context.read<SessionController>();
    setState(() {
      _busy = true;
      _error = null;
    });
    final res = await ConsentService(
      session,
    ).ensureConsent(context, replace: replace);
    if (!mounted) return;
    switch (res) {
      case Ok():
        _changed = true;
        setState(() => _busy = false);
        showGlassToast(context, 'Card saved. We’ll try again soon.');
      case Err(:final problem):
        setState(() {
          _busy = false;
          _error = problem;
        });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final t = GlassTokens.of(context);
    final owed = widget.owed;
    final hasCard = context.watch<SessionController>().hasPaymentConsent;
    final failed = owed.items
        .where((i) => i.state == OwedState.couldntCharge)
        .length;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.of(context).pop(_changed);
      },
      child: GlassPage(
        title: 'Owed',
        children: [
          if (_error != null)
            GlassBanner(
              icon: Icons.error_outline_rounded,
              title: _error!.displayMessage,
              error: true,
            ),
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Glass(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Total',
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: t.muted,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    formatMoney(owed.total, owed.currency, cents: true),
                    style: theme.textTheme.displaySmall?.copyWith(
                      color: AppColors.fail,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    owed.items.length == 1
                        ? 'From 1 missed habit. It goes to the charity you '
                              'picked for it.'
                        : 'From ${owed.items.length} missed habits. It goes '
                              'to the charity you picked for each habit.',
                    style: theme.textTheme.bodyMedium?.copyWith(color: t.muted),
                  ),
                ],
              ),
            ),
          ),
          if (!hasCard || failed > 0)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Glass(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      hasCard ? 'Couldn’t charge' : 'No card yet',
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: AppColors.fail,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      hasCard
                          ? 'Your card was declined for $failed '
                                '${failed == 1 ? 'penalty' : 'penalties'}. '
                                'Fix your card and we’ll try again.'
                          : 'Add a card so we can pay your charities.',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: t.muted,
                      ),
                    ),
                    const SizedBox(height: 16),
                    GlassButton(
                      label: hasCard ? 'Fix card' : 'Add a card',
                      busy: _busy,
                      onPressed: () => _fixCard(replace: hasCard),
                    ),
                  ],
                ),
              ),
            ),
          GlassSection(
            title: 'Missed habits',
            children: [
              for (final i in owed.items)
                GlassRow(
                  leading: const Icon(Icons.close_rounded),
                  title:
                      '${i.habitName} · '
                      '${formatMoney(i.amount, i.currency, cents: true)}',
                  subtitle: [
                    if (i.date case final d?) _day(d),
                    'to ${i.charityName ?? 'charity'}',
                  ].join(' · '),
                  trailing: _StateChip(i.state),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StateChip extends StatelessWidget {
  final OwedState state;
  const _StateChip(this.state);

  @override
  Widget build(BuildContext context) {
    final t = GlassTokens.of(context);
    final bad = state == OwedState.couldntCharge;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: t.track,
        borderRadius: const BorderRadius.all(Radius.circular(999)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        child: Text(
          bad ? 'Couldn’t charge' : 'Charging',
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
            fontWeight: FontWeight.w600,
            color: bad ? AppColors.fail : t.muted,
          ),
        ),
      ),
    );
  }
}
