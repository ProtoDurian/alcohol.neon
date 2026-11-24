import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/navigation.dart';
import '../../core/problem.dart';
import '../../data/penalty_repository.dart';
import '../../session/session_controller.dart';
import '../../theme/app_theme.dart';
import '../../theme/glass.dart';
import '../../widgets/app_loader.dart';
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

/// What the user owes, from zinc's owed list: the total, each missed day with
/// its charge state, and Add a card or Fix card when zinc couldn't charge.
/// zinc charges on its own, so there is no Pay button. Reloads when it comes
/// back into view. Pops `true` when a card was saved, so Today reloads.
class OwedView extends StatefulWidget {
  const OwedView({super.key});

  @override
  State<OwedView> createState() => _OwedViewState();
}

class _OwedViewState extends State<OwedView>
    with RouteAware, WidgetsBindingObserver {
  Owed? _owed;
  Problem? _loadError;
  bool _busy = false;
  bool _changed = false;
  Problem? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route != null) routeObserver.subscribe(this, route);
  }

  @override
  void dispose() {
    routeObserver.unsubscribe(this);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didPopNext() => _load();

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) _load();
  }

  Future<void> _load() async {
    final session = context.read<SessionController>();
    final uid = session.userId;
    if (uid == null) return;
    final res = await PenaltyRepository(session.auth.makeApiClient()).owed(uid);
    if (!mounted) return;
    setState(() {
      switch (res) {
        case Ok(:final value):
          _owed = owedFromRes(value);
          _loadError = null;
        case Err(:final problem):
          _loadError = problem;
      }
    });
  }

  Future<void> _fixCard() async {
    final session = context.read<SessionController>();
    setState(() {
      _busy = true;
      _error = null;
    });
    // A card on file that zinc couldn't charge is replaced with a new one.
    final res = await ConsentService(
      session,
    ).ensureConsent(context, replace: session.hasPaymentConsent);
    if (!mounted) return;
    switch (res) {
      case Ok():
        _changed = true;
        setState(() => _busy = false);
        showGlassToast(context, 'Card saved. We’ll try again soon.');
        await _load();
      case Err(:final problem):
        setState(() {
          _busy = false;
          _error = problem;
        });
    }
  }

  @override
  Widget build(BuildContext context) {
    final owed = _owed;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.of(context).pop(_changed);
      },
      child: GlassPage(
        title: 'Owed',
        onRefresh: _load,
        children: [
          if (_error != null)
            GlassBanner(
              icon: Icons.error_outline_rounded,
              title: _error!.displayMessage,
              error: true,
            ),
          if (_loadError != null)
            GlassBanner(
              icon: Icons.cloud_off_rounded,
              title: 'Could not load what you owe',
              body: _loadError!.displayMessage,
              error: true,
              action: GlassTextButton(label: 'Retry', onPressed: _load),
            ),
          if (owed == null && _loadError == null)
            const SizedBox(height: 240, child: AppLoader())
          else if (owed != null)
            ..._content(context, owed),
        ],
      ),
    );
  }

  List<Widget> _content(BuildContext context, Owed owed) {
    final theme = Theme.of(context);
    final t = GlassTokens.of(context);
    final failed = owed.couldntCharge.length;
    final count = owed.items.length;
    return [
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
                  color: count == 0 ? null : AppColors.fail,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                count == 0
                    ? 'Nothing owed. Nice work.'
                    : count == 1
                    ? 'From 1 missed day. It goes to the charity you '
                          'picked for that habit.'
                    : 'From $count missed days. It goes to the charity '
                          'you picked for each habit.',
                style: theme.textTheme.bodyMedium?.copyWith(color: t.muted),
              ),
            ],
          ),
        ),
      ),
      if (failed > 0)
        Padding(
          padding: const EdgeInsets.only(top: 10),
          child: Glass(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Couldn’t charge',
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: AppColors.fail,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  owed.needsCard
                      ? 'Add a card so we can pay your charities.'
                      : 'Your card was declined for $failed '
                            '${failed == 1 ? 'penalty' : 'penalties'}. '
                            'Fix your card and we’ll try again.',
                  style: theme.textTheme.bodyMedium?.copyWith(color: t.muted),
                ),
                const SizedBox(height: 16),
                GlassButton(
                  label: owed.needsCard ? 'Add a card' : 'Fix card',
                  busy: _busy,
                  onPressed: _fixCard,
                ),
              ],
            ),
          ),
        ),
      if (count > 0)
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
    ];
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
