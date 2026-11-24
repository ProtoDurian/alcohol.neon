import 'dart:async';
import 'dart:ui';

import 'package:flutter/cupertino.dart' show CupertinoSliverRefreshControl;
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart' show CustomSemanticsAction;
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../config/app_config.dart';
import '../../core/launch_timeline.dart';
import '../../core/navigation.dart';
import '../../core/problem.dart';
import '../../generated/zinc/models/habit_overview_habit_res.dart';
import '../../session/session_controller.dart';
import '../../theme/app_theme.dart';
import '../../theme/glass.dart';
import '../../widgets/glass_list.dart';
import '../../widgets/glass_modal.dart';
import '../../widgets/app_loader.dart';
import '../habit/habit_editor_view.dart';
import '../inbox/inbox_bell.dart';
import '../nfc/nfc_service.dart';
import '../nfc/tap_complete_view.dart';
import '../profile/profile_view.dart';
import '../vacation/vacation_list_view.dart';
import 'buffers_controller.dart';
import 'dashboard_controller.dart';
import 'owed.dart';
import 'owed_view.dart';
import 'today_layout.dart';
import 'today_plan.dart';

/// Opens the habit editor (create when [habitId] is null, else edit) and reloads
/// the dashboard if it reports a change.
Future<void> _openEditor(
  BuildContext context,
  DashboardController c, {
  String? habitId,
  bool enabled = true,
}) async {
  // New habit is a task to finish or cancel, so it opens as a modal; Edit
  // goes deeper into one habit, so it's pushed.
  final changed = habitId == null
      ? await showGlassModal<bool>(context, (_) => const HabitEditorView())
      : await Navigator.of(context).push<bool>(
          MaterialPageRoute(
            builder: (_) =>
                HabitEditorView(habitId: habitId, initialEnabled: enabled),
          ),
        );
  if (changed == true) c.load(quiet: true);
}

void _openHabit(BuildContext context, DashboardController c, TodayItem item) {
  final id = item.habit.id;
  if (id == null) return;
  _openEditor(context, c, habitId: id, enabled: item.habit.enabled);
}

/// "1 h 55 m left", counted down from the item's deadline.
String _timeLeft(DateTime? deadline, DateTime now) {
  if (deadline == null) return '';
  final minutes = deadline.difference(now).inMinutes;
  if (minutes <= 0) return 'Ending now';
  final h = minutes ~/ 60, m = minutes % 60;
  if (h == 0) return '$m m left';
  return m == 0 ? '$h h left' : '$h h $m m left';
}

const _weekdayNames = [
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
  'Sunday',
];
const _monthNames = [
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];

String _dateCaption(DateTime d) =>
    '${_weekdayNames[d.weekday - 1]}, ${d.day} ${_monthNames[d.month - 1]}';

/// "Mon 23 Nov", the title of a past day.
String _shortDay(DateTime d) =>
    '${_weekdayNames[d.weekday - 1].substring(0, 3)} ${d.day} '
    '${_monthNames[d.month - 1].substring(0, 3)}';

Future<void> _complete(DashboardController c, HabitOverviewHabitRes h) {
  HapticFeedback.mediumImpact();
  return c.complete(h);
}

Future<void> _skip(DashboardController c, HabitOverviewHabitRes h) {
  HapticFeedback.selectionClick();
  return c.skip(h);
}

/// The one check action for every proof: an NFC habit scans its tag, any
/// other habit checks in (a Strava habit can still be checked in by hand).
Future<void> _check(
  BuildContext context,
  DashboardController c,
  HabitOverviewHabitRes h,
) async {
  if (h.proof != 'nfc') return _complete(c, h);
  HapticFeedback.mediumImpact();
  final res = await NfcService().scan(base: AppConfig.current.nfcTagBaseUrl);
  if (!context.mounted) return;
  switch (res) {
    case Ok(value: NfcScanResult(kind: NfcTagKind.lazytax, :final tagId?)):
      // Today reloads when the tap screen closes (didPopNext).
      await Navigator.of(
        context,
      ).push(MaterialPageRoute(builder: (_) => TapCompleteView(tagId: tagId)));
    case Ok():
      showGlassToast(
        context,
        'That isn’t a LazyTax tag. Scan the tag for ${h.name ?? 'this habit'}.',
      );
    case Err(:final problem):
      showGlassToast(context, problem.displayMessage);
  }
}

IconData _proofIcon(HabitOverviewHabitRes h) => switch (h.proof) {
  'strava' => Icons.directions_run_rounded,
  'nfc' => Icons.nfc_rounded,
  _ => Icons.task_alt_rounded,
};

/// A row's second line: the time (a clock for a habit time, a bell for a
/// reminder time) or Anytime, then the proof and the stake.
Widget _meta(
  BuildContext context,
  HabitOverviewHabitRes h, {
  TextStyle? style,
}) {
  final t = GlassTokens.of(context);
  final base = (style ?? Theme.of(context).textTheme.bodySmall)?.copyWith(
    color: t.muted,
  );
  final time = sortTimeLabel(h);
  final reminderOnly = time != null && parseClockMinutes(h.habitTime) == null;
  return Text.rich(
    TextSpan(
      style: base,
      children: [
        if (time != null) ...[
          WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: Icon(
              reminderOnly
                  ? Icons.notifications_none_rounded
                  : Icons.schedule_rounded,
              size: (base?.fontSize ?? 12) + 2,
              color: t.muted,
            ),
          ),
          TextSpan(text: ' $time'),
        ] else
          const TextSpan(text: 'Anytime'),
        for (final part in [?proofLabel(h), ?stakeShort(h)])
          TextSpan(text: ' · $part'),
      ],
    ),
    maxLines: 1,
    overflow: TextOverflow.ellipsis,
  );
}

/// The daily loop: today's habits with complete/skip, from
/// `GET /Habit/{userId}/overview`. Leads with the next habit to do ("Next up")
/// or with the day's progress ("Progress list"), as chosen in Profile.
class DashboardView extends StatelessWidget {
  const DashboardView({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(
          create: (ctx) =>
              // Quiet: a saved Today stays on screen while the fresh one loads.
              DashboardController(ctx.read<SessionController>())
                ..load(quiet: true),
        ),
        // Freezes and vacation for the safety nets — a light, separate fetch
        // so the daily-loop controller stays clean.
        ChangeNotifierProvider(
          create: (ctx) =>
              BuffersController(ctx.read<SessionController>())..load(),
        ),
      ],
      child: const _DashboardScaffold(),
    );
  }
}

class _DashboardScaffold extends StatefulWidget {
  const _DashboardScaffold();

  @override
  State<_DashboardScaffold> createState() => _DashboardScaffoldState();
}

class _DashboardScaffoldState extends State<_DashboardScaffold>
    with WidgetsBindingObserver, RouteAware {
  late final SessionController _session;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // A timezone sync can settle days that already ended in the new timezone;
    // tell the user once. Bootstrap syncs before this screen exists, so also
    // check after the first frame.
    _session = context.read<SessionController>()
      ..addListener(_showTimezoneNotice)
      ..addListener(_reloadOnTimezoneChange);
    _timezone = _session.config?.timezone;
    WidgetsBinding.instance.addPostFrameCallback((_) => _showTimezoneNotice());
  }

  String? _timezone;

  /// Today may come from the saved overview before bootstrap has the fresh
  /// configuration; if that moved the timezone, Today's checks moved too.
  void _reloadOnTimezoneChange() {
    final tz = _session.config?.timezone;
    if (tz == _timezone) return;
    final had = _timezone != null;
    _timezone = tz;
    if (had && tz != null && mounted) {
      context.read<DashboardController>().load(quiet: true);
    }
  }

  void _showTimezoneNotice() {
    if (!mounted) return;
    final notice = _session.takeTimezoneNotice();
    if (notice == null) return;
    showGlassToast(context, notice, duration: const Duration(seconds: 8));
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route != null) routeObserver.subscribe(this, route);
  }

  @override
  void didPopNext() {
    // Includes a warm NFC link: no app-resume event is required on return.
    // Quiet: Today stays on screen while it refreshes (a loud load swapped
    // it for the full-screen loader after every screen, sheet or dialog).
    if (!mounted) return;
    context.read<DashboardController>().load(quiet: true);
    context.read<BuffersController>().load();
  }

  @override
  void dispose() {
    _session
      ..removeListener(_showTimezoneNotice)
      ..removeListener(_reloadOnTimezoneChange);
    routeObserver.unsubscribe(this);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Returning to the foreground: refetch so completions made on the home-screen
    // widget (which the app isn't notified of) get tallied here too.
    if (state == AppLifecycleState.resumed && mounted) {
      _onResumed();
    }
  }

  /// Follow the phone first (the user may have travelled while away), so the
  /// reload — which also re-plans reminders, dropping today's for habits
  /// completed meanwhile (e.g. on the home-screen widget) — sees the new
  /// timezone.
  Future<void> _onResumed() async {
    final dashboard = context.read<DashboardController>();
    // Idle connections may have died in the background: start a new pool,
    // and open a connection now, while the calls below wait for the token
    // (a Logto refresh when it is over an hour old), so they skip the
    // TCP + TLS handshake.
    final api = context.read<SessionController>().auth.makeApiClient()
      ..resetConnections();
    unawaited(api.warmUp());
    context.read<BuffersController>().load();
    await context.read<SessionController>().syncDeviceTimezone();
    // Quiet: Today stays on screen while it refreshes.
    if (mounted) dashboard.load(quiet: true);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.watch<DashboardController>();
    return AmbientBackdrop(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: switch (c.phase) {
          DashboardPhase.loading => const AppLoader(),
          DashboardPhase.error => _ErrorRetry(
            message: c.error?.displayMessage ?? 'Could not load habits',
            onRetry: c.load,
          ),
          DashboardPhase.ready => ValueListenableBuilder<TodayLayout>(
            valueListenable: TodayLayoutSetting.instance,
            builder: (_, layout, _) => _Today(c: c, layout: layout),
          ),
        },
      ),
    );
  }
}

/// The scrolling Today screen: a large title that collapses into a frosted
/// bar, the chosen layout, the time-of-day tabs and one list, the safety
/// nets, and the date strip at the bottom. Rebuilds every 30 s so countdowns
/// stay live.
class _Today extends StatefulWidget {
  final DashboardController c;
  final TodayLayout layout;
  const _Today({required this.c, required this.layout});

  @override
  State<_Today> createState() => _TodayState();
}

class _TodayState extends State<_Today> {
  late final Timer _tick;
  TodayTab _tab = TodayTab.all;

  /// A past day picked on the date strip; null for today.
  DateTime? _day;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => LaunchTimeline.todayShown(widget.c.fromCache ? 'cache' : 'server'),
    );
    _tick = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick.cancel();
    super.dispose();
  }

  void _pickDay(DateTime day, {required bool isToday}) {
    HapticFeedback.selectionClick();
    setState(() => _day = isToday ? null : day);
    if (!isToday) widget.c.loadDay(day);
  }

  Future<void> _openOwed(Owed owed) async {
    final changed = await Navigator.of(
      context,
    ).push<bool>(MaterialPageRoute(builder: (_) => OwedView(owed: owed)));
    if (changed == true && mounted) widget.c.load(quiet: true);
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.c;
    final buffers = context.watch<BuffersController>();
    final hasCard = context.select<SessionController, bool>(
      (s) => s.hasPaymentConsent,
    );
    final plan = c.plan;
    final now = DateTime.now();
    final nextUp = widget.layout == TodayLayout.nextUp;
    final owed = owedFromOverview(c.overview, hasCard: hasCard);
    final day = _day;
    final executions = day == null ? null : c.executionsOn(day);
    final items = day == null
        ? plan.items
        : executions == null
        ? const <TodayItem>[]
        : pastItems(c.habits, day, executions);

    // Banners stay tappable while a saved Today from an earlier day is
    // dimmed below them (Retry must work when today's fails to load).
    final banners = <Widget>[
      if (c.stale)
        const GlassBanner(
          icon: Icons.sync,
          title: 'Updating Today…',
          body: "Showing your last saved list until today's loads.",
        ),
      if (c.refreshError != null)
        GlassBanner(
          icon: Icons.sync_problem,
          title: 'Could not refresh the dashboard',
          body:
              'Saved actions are kept. Totals may be out of date. '
              'Retry refresh — do not submit the action again.',
          action: GlassTextButton(
            label: 'Retry',
            onPressed: () => c.load(quiet: true),
          ),
        ),
      if (c.actionError != null)
        GlassBanner(
          icon: Icons.error_outline,
          title: c.actionError!.displayMessage,
          error: true,
          action: IconButton(
            icon: const Icon(Icons.close),
            onPressed: c.clearActionError,
          ),
        ),
    ];
    final shown = [
      for (final i in items)
        if (_tab.includes(i.habit)) i,
    ];
    final sections = <Widget>[
      ...banners,
      if (c.habits.isEmpty)
        _EmptyState(onCreate: () => _openEditor(context, c))
      else ...[
        if (day != null)
          _PastNote(c: c, day: day)
        else if (nextUp)
          _nextUpCard(context, c, plan, now)
        else
          _ProgressCard(plan: plan, now: now),
        _Tabs(items: items, tab: _tab, onTab: (t) => setState(() => _tab = t)),
        if (day != null && executions == null)
          const SizedBox.shrink()
        else if (shown.isEmpty)
          const _EmptyTab()
        else
          _Section(items: shown, c: c, now: now, readOnly: day != null),
        _SafetyNets(c: c, buffers: buffers),
      ],
    ];

    final scroll = CustomScrollView(
      physics: const AlwaysScrollableScrollPhysics(
        parent: BouncingScrollPhysics(),
      ),
      slivers: [
        SliverPersistentHeader(
          pinned: true,
          delegate: _LargeTitle(
            top: MediaQuery.paddingOf(context).top,
            caption: _dateCaption(day ?? now),
            title: day == null ? 'Today' : _shortDay(day),
            owedLabel: owed.any
                ? '${formatMoney(owed.total, owed.currency)} owed'
                : null,
            onOwed: () => _openOwed(owed),
            onProfile: () => Navigator.of(
              context,
            ).push(MaterialPageRoute(builder: (_) => const ProfileView())),
          ),
        ),
        // Pull-to-refresh reloads both the overview and the safety nets.
        CupertinoSliverRefreshControl(
          onRefresh: () => Future.wait([c.load(quiet: true), buffers.load()]),
        ),
        // One scroll view for every section, so dragging a row to an edge
        // scrolls Today.
        SliverPadding(
          padding: EdgeInsets.fromLTRB(
            16,
            4,
            16,
            170 + MediaQuery.paddingOf(context).bottom,
          ),
          sliver: SliverMainAxisGroup(
            slivers: [
              for (var i = 0; i < sections.length; i++)
                _dimWhenStale(
                  c.stale && i >= banners.length,
                  sections[i] is _Section
                      ? Appear(index: i, sliver: true, child: sections[i])
                      : SliverToBoxAdapter(
                          child: Appear(index: i, child: sections[i]),
                        ),
                ),
            ],
          ),
        ),
      ],
    );

    return Stack(
      children: [
        Positioned.fill(child: scroll),
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (day == null && !c.stale)
                Padding(
                  padding: const EdgeInsets.fromLTRB(0, 0, 16, 12),
                  child: _AddButton(onTap: () => _openEditor(context, c)),
                ),
              if (c.habits.isNotEmpty)
                _DateStrip(today: c.today, selected: day, onPick: _pickDay),
            ],
          ),
        ),
      ],
    );
  }

  Widget _nextUpCard(
    BuildContext context,
    DashboardController c,
    TodayPlan plan,
    DateTime now,
  ) {
    final next = plan.next;
    return AnimatedSwitcher(
      duration: GlassMotion.of(context, GlassMotion.slow),
      switchInCurve: GlassMotion.curve,
      switchOutCurve: GlassMotion.curve,
      transitionBuilder: (child, a) => FadeTransition(
        opacity: a,
        child: ScaleTransition(
          scale: Tween(begin: 0.96, end: 1.0).animate(a),
          child: child,
        ),
      ),
      child: next == null
          ? _AllClear(key: const ValueKey('clear'), plan: plan)
          : _NextUpCard(
              key: ValueKey(next.habit.id ?? next.habit.name),
              item: next,
              c: c,
              now: now,
            ),
    );
  }
}

/// iOS-style large title: the date and "Today" scroll away and a small title
/// fades in on a frosted bar. Only that bar uses a real backdrop blur. The
/// red owed button sits next to Profile while anything is owed.
class _LargeTitle extends SliverPersistentHeaderDelegate {
  final double top;
  final String caption;
  final String title;
  final String? owedLabel;
  final VoidCallback onOwed;
  final VoidCallback onProfile;

  const _LargeTitle({
    required this.top,
    required this.caption,
    required this.title,
    required this.owedLabel,
    required this.onOwed,
    required this.onProfile,
  });

  static const _bar = 52.0;

  @override
  double get minExtent => top + _bar;

  @override
  double get maxExtent => top + _bar + 56;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlaps) {
    final theme = Theme.of(context);
    final t = GlassTokens.of(context);
    final p = (shrinkOffset / (maxExtent - minExtent)).clamp(0.0, 1.0);
    final barOpacity = ((p - 0.5) / 0.5).clamp(0.0, 1.0);
    final owed = owedLabel;
    return Stack(
      fit: StackFit.expand,
      children: [
        if (barOpacity > 0)
          Opacity(
            opacity: barOpacity,
            child: ClipRect(
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: t.strongFill,
                    border: Border(
                      bottom: BorderSide(color: t.separator, width: 0.5),
                    ),
                  ),
                ),
              ),
            ),
          ),
        Positioned(
          top: top,
          left: 0,
          right: 0,
          height: _bar,
          child: Opacity(
            opacity: barOpacity,
            child: Center(
              child: Text(
                title,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ),
        Positioned(
          top: top + 8,
          right: 16,
          child: Row(
            children: [
              if (owed != null) ...[
                Pressable(
                  onTap: onOwed,
                  child: Semantics(
                    button: true,
                    label: owed,
                    excludeSemantics: true,
                    child: Glass(
                      blur: true,
                      radius: const BorderRadius.all(Radius.circular(18)),
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: SizedBox(
                        height: 36,
                        child: Center(
                          widthFactor: 1,
                          child: Text(
                            owed,
                            style: theme.textTheme.labelLarge?.copyWith(
                              color: AppColors.fail,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
              ],
              const InboxBell(),
              const SizedBox(width: 10),
              Pressable(
                onTap: onProfile,
                child: Semantics(
                  button: true,
                  label: 'Profile',
                  child: Glass(
                    blur: true,
                    radius: const BorderRadius.all(Radius.circular(18)),
                    child: const SizedBox.square(
                      dimension: 36,
                      child: Icon(Icons.person_rounded, size: 20),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        Positioned(
          left: 20,
          right: 20,
          bottom: 6,
          child: Opacity(
            opacity: (1 - p * 1.8).clamp(0.0, 1.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  caption,
                  style: theme.textTheme.labelLarge?.copyWith(color: t.muted),
                ),
                Text(
                  title,
                  style: theme.textTheme.displaySmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    fontSize: 34,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  @override
  bool shouldRebuild(_LargeTitle old) => true;
}

/// The first open habit by time, with its countdown, stake and the one
/// action to take.
class _NextUpCard extends StatelessWidget {
  final TodayItem item;
  final DashboardController c;
  final DateTime now;
  const _NextUpCard({
    super.key,
    required this.item,
    required this.c,
    required this.now,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final t = GlassTokens.of(context);
    final h = item.habit;
    final busy = c.isBusy(h);
    final stake = stakeLine(h);
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Pressable(
        onTap: () => _openHabit(context, c, item),
        scale: 0.985,
        child: Glass(
          radius: const BorderRadius.all(Radius.circular(28)),
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    'Next up',
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: t.accent,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    _timeLeft(item.deadline, now),
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: t.muted,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      h.name ?? 'Habit',
                      style: theme.textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        height: 1.1,
                      ),
                    ),
                  ),
                  if (h.status.currentStreak > 0)
                    _Streak(h.status.currentStreak),
                ],
              ),
              const SizedBox(height: 6),
              _meta(context, h, style: theme.textTheme.bodyMedium),
              if (stake != null) ...[
                const SizedBox(height: 4),
                Text(
                  stake,
                  style: theme.textTheme.bodySmall?.copyWith(color: t.muted),
                ),
              ],
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: GlassButton(
                      label: 'Complete',
                      busy: busy,
                      onPressed: () => _check(context, c, h),
                    ),
                  ),
                  const SizedBox(width: 8),
                  GlassButton(
                    label: 'Skip',
                    secondary: true,
                    onPressed: busy || c.skipsLeft <= 0
                        ? null
                        : () => _skip(c, h),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Shown in place of Next up once nothing is left to do today.
class _AllClear extends StatelessWidget {
  final TodayPlan plan;
  const _AllClear({super.key, required this.plan});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final t = GlassTokens.of(context);
    final none = plan.scheduled == 0;
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Glass(
        radius: const BorderRadius.all(Radius.circular(28)),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 28),
        child: Column(
          children: [
            Icon(
              none ? Icons.bedtime_outlined : Icons.check_circle_rounded,
              size: 44,
              color: none ? t.muted : t.accent,
            ),
            const SizedBox(height: 12),
            Text(
              none ? 'Nothing due today' : 'All done for today',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              none
                  ? 'Enjoy the rest.'
                  : '${plan.done.length} of ${plan.scheduled} settled. See you tomorrow.',
              style: theme.textTheme.bodyMedium?.copyWith(color: t.muted),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

/// Progress list's header: today's ring and what's next.
class _ProgressCard extends StatelessWidget {
  final TodayPlan plan;
  final DateTime now;
  const _ProgressCard({required this.plan, required this.now});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final t = GlassTokens.of(context);
    final next = plan.next;
    final done = plan.done.length, total = plan.scheduled;
    final when = next == null
        ? null
        : sortTimeLabel(next.habit) ?? _timeLeft(next.deadline, now);
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Glass(
        radius: const BorderRadius.all(Radius.circular(28)),
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            ProgressRing(
              value: total == 0 ? 0 : done / total,
              size: 68,
              stroke: 7,
              child: Text(
                '$done/$total',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    total == 0
                        ? 'Nothing due today'
                        : next == null
                        ? 'All done for today'
                        : '$done of $total done',
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    next == null
                        ? 'See you tomorrow.'
                        : 'Next: ${next.habit.name ?? 'Habit'} · $when',
                    style: theme.textTheme.bodyMedium?.copyWith(color: t.muted),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Above a past day's list: it is read only, and loading or failing.
class _PastNote extends StatelessWidget {
  final DashboardController c;
  final DateTime day;
  const _PastNote({required this.c, required this.day});

  @override
  Widget build(BuildContext context) {
    final t = GlassTokens.of(context);
    final error = c.pastError(day);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 10, 4, 0),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'A past day. You can look, not change.',
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: t.muted),
                ),
              ),
              if (c.pastLoading(day))
                SizedBox.square(
                  dimension: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: t.muted,
                  ),
                ),
            ],
          ),
        ),
        if (error != null)
          GlassBanner(
            icon: Icons.cloud_off_rounded,
            title: 'Could not load this day',
            body: error.displayMessage,
            error: true,
            action: GlassTextButton(
              label: 'Retry',
              onPressed: () => c.loadDay(day),
            ),
          ),
      ],
    );
  }
}

/// All, Morning, Afternoon, Evening and Anytime, each with its count.
class _Tabs extends StatelessWidget {
  final List<TodayItem> items;
  final TodayTab tab;
  final ValueChanged<TodayTab> onTab;
  const _Tabs({required this.items, required this.tab, required this.onTab});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final t = GlassTokens.of(context);
    final fg = theme.colorScheme.onSurface;
    final bg = theme.colorScheme.surface;
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        clipBehavior: Clip.none,
        child: Row(
          children: [
            for (final k in TodayTab.values)
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: _tab(context, k, fg, bg, t),
              ),
          ],
        ),
      ),
    );
  }

  Widget _tab(
    BuildContext context,
    TodayTab k,
    Color fg,
    Color bg,
    GlassTokens t,
  ) {
    final on = k == tab;
    final count = items.where((i) => k.includes(i.habit)).length;
    final style = Theme.of(context).textTheme.labelLarge;
    return Semantics(
      button: true,
      selected: on,
      label: '${k.label}, $count',
      excludeSemantics: true,
      child: Pressable(
        onTap: () {
          HapticFeedback.selectionClick();
          onTab(k);
        },
        child: AnimatedContainer(
          duration: GlassMotion.of(context, GlassMotion.fast),
          height: 34,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          alignment: Alignment.center,
          decoration: ShapeDecoration(
            shape: StadiumBorder(
              side: on
                  ? BorderSide.none
                  : BorderSide(color: t.edge, width: 0.5),
            ),
            color: on ? fg : t.strongFill,
          ),
          child: Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: k.label,
                  style: style?.copyWith(
                    color: on ? bg : fg,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                TextSpan(
                  text: '  $count',
                  style: style?.copyWith(
                    color: on ? bg.withValues(alpha: 0.6) : t.muted,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _EmptyTab extends StatelessWidget {
  const _EmptyTab();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Glass(
        radius: const BorderRadius.all(Radius.circular(22)),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
        child: SizedBox(
          width: double.infinity,
          child: Text(
            'Nothing in this part of the day.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: GlassTokens.of(context).muted,
            ),
          ),
        ),
      ),
    );
  }
}

/// The day's habits in one glass group, as a sliver of Today's scroll view.
/// Long-press a row and drag it to reorder habits planned for the same time
/// (when zinc keeps an order); a drop saves the new order.
class _Section extends StatefulWidget {
  final List<TodayItem> items;
  final DashboardController c;
  final DateTime now;

  /// A past day: no actions and no dragging.
  final bool readOnly;
  const _Section({
    required this.items,
    required this.c,
    required this.now,
    this.readOnly = false,
  });

  @override
  State<_Section> createState() => _SectionState();
}

class _SectionState extends State<_Section> {
  static const _radius = BorderRadius.all(Radius.circular(22));

  // The rows as they were when a drag started: a load landing mid-drag must
  // not move rows under the finger (or end the drag). It applies on drop.
  List<TodayItem>? _frozen;
  List<TodayItem> get _items => _frozen ?? widget.items;

  // For the tick as the lifted row passes another row.
  final _rowKeys = <String, GlobalKey>{};
  List<double> _centers = const [];
  int _dragIndex = 0, _slot = 0;
  double _downY = 0;

  String _id(TodayItem i) => i.habit.id ?? i.habit.name ?? '';

  /// The rows the row at [index] may move among, as [start, end): the rows
  /// next to it with the same sort time. Time decides the rest of the order.
  (int, int) _group(int index) {
    final time = sortTimeOf(_items[index].habit);
    var start = index, end = index + 1;
    while (start > 0 && sortTimeOf(_items[start - 1].habit) == time) {
      start--;
    }
    while (end < _items.length && sortTimeOf(_items[end].habit) == time) {
      end++;
    }
    return (start, end);
  }

  bool _canMove(int index) {
    if (widget.readOnly || !widget.c.canReorder) return false;
    final (start, end) = _group(index);
    return end - start > 1;
  }

  void _move(int from, int to) {
    final (start, end) = _group(from);
    // A drop past the group's edge lands at the nearest allowed place.
    final target = to.clamp(start, end - 1);
    final ids = [for (final i in _items.sublist(start, end)) _id(i)];
    ids.insert(target - start, ids.removeAt(from - start));
    setState(() => _frozen = null);
    // Only this group's habits trade places; the rest keep theirs.
    if (target != from) widget.c.reorder(ids);
  }

  void _onStart(int index) {
    HapticFeedback.mediumImpact();
    _dragIndex = _slot = index;
    // Rebuilt so the row under a lifted first row drops its divider.
    setState(() => _frozen = widget.items);
    _centers = [
      for (final i in _items)
        switch (_rowKeys[_id(i)]?.currentContext?.findRenderObject()) {
          final RenderBox box when box.hasSize =>
            box.localToGlobal(box.size.center(Offset.zero)).dy,
          _ => double.nan,
        },
    ];
  }

  void _onPointerMove(PointerMoveEvent e) {
    if (_frozen == null || _dragIndex >= _centers.length) return;
    final y = _centers[_dragIndex] + e.position.dy - _downY;
    var slot = 0;
    for (var i = 0; i < _centers.length; i++) {
      if (i != _dragIndex && _centers[i] < y) slot++;
    }
    if (slot != _slot) {
      _slot = slot;
      HapticFeedback.selectionClick();
    }
  }

  Widget _row(int index, {bool lifted = false}) {
    final item = _items[index];
    final id = _id(item);
    final first = index == 0, last = index == _items.length - 1;
    // While the first row is lifted, the next one leads the group.
    final divider =
        !first && !(_frozen != null && _dragIndex == 0 && index == 1);
    Widget row = _HabitRow(
      item: item,
      c: widget.c,
      now: widget.now,
      readOnly: widget.readOnly,
    );
    if (lifted) return row;
    final movable = _canMove(index);
    final (start, end) = _group(index);
    row = Semantics(
      customSemanticsActions: movable
          ? {
              if (index > start)
                const CustomSemanticsAction(label: 'Move up'): () =>
                    _move(index, index - 1),
              if (index < end - 1)
                const CustomSemanticsAction(label: 'Move down'): () =>
                    _move(index, index + 1),
            }
          : null,
      child: row,
    );
    return Listener(
      key: ValueKey(id),
      onPointerDown: (e) => _downY = e.position.dy,
      onPointerMove: _onPointerMove,
      // A drag the system cancels drops no row, so nothing calls onReorder.
      onPointerCancel: (_) {
        if (_frozen != null) setState(() => _frozen = null);
      },
      child: ReorderableDelayedDragStartListener(
        index: index,
        enabled: movable,
        child: ClipRRect(
          borderRadius: BorderRadius.vertical(
            top: first ? _radius.topLeft : Radius.zero,
            bottom: last ? _radius.bottomLeft : Radius.zero,
          ),
          child: Column(
            key: _rowKeys.putIfAbsent(id, GlobalKey.new),
            mainAxisSize: MainAxisSize.min,
            children: [
              if (divider)
                Padding(
                  padding: const EdgeInsets.only(left: 62),
                  child: Divider(
                    height: 0.5,
                    color: GlassTokens.of(context).separator,
                  ),
                ),
              row,
            ],
          ),
        ),
      ),
    );
  }

  /// The lifted row: its own glass raised off the group, with a soft shadow
  /// and a slight scale-up (none under Reduce Motion), and no dividers.
  Widget _lifted(Widget _, int index, Animation<double> a) {
    final still = MediaQuery.of(context).disableAnimations;
    return AnimatedBuilder(
      animation: a,
      builder: (context, child) {
        final t = Curves.easeOut.transform(a.value);
        return Transform.scale(
          scale: still ? 1 : 1 + 0.03 * t,
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: _radius,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.18 * t),
                  blurRadius: 24 * t,
                  offset: Offset(0, 8 * t),
                ),
              ],
            ),
            child: child,
          ),
        );
      },
      child: Material(
        type: MaterialType.transparency,
        child: Glass(
          blur: true,
          strong: true,
          child: _row(index, lifted: true),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = GlassTokens.of(context);
    final items = _items;
    _rowKeys.removeWhere((id, _) => !items.any((i) => _id(i) == id));
    return SliverMainAxisGroup(
      slivers: [
        const SliverToBoxAdapter(child: SizedBox(height: 10)),
        DecoratedSliver(
          decoration: BoxDecoration(
            color: t.fill,
            borderRadius: _radius,
            border: Border.all(color: t.edge, width: 0.5),
          ),
          sliver: SliverReorderableList(
            itemCount: items.length,
            itemBuilder: (_, i) => _row(i),
            proxyDecorator: _lifted,
            onReorderStart: _onStart,
            onReorderEnd: (_) => HapticFeedback.lightImpact(),
            onReorderItem: _move,
          ),
        ),
      ],
    );
  }
}

/// One habit: its icon, name and time · proof · stake, then the round check
/// button while it's open, or a chip with how the day went. Swipe an open
/// habit left to skip it.
class _HabitRow extends StatelessWidget {
  final TodayItem item;
  final DashboardController c;
  final DateTime now;
  final bool readOnly;
  const _HabitRow({
    required this.item,
    required this.c,
    required this.now,
    this.readOnly = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final t = GlassTokens.of(context);
    final h = item.habit;
    final open = item.open && !readOnly;
    final busy = c.isBusy(h);
    final (IconData icon, Color? fill) = switch (item.state) {
      TodayState.done => (Icons.check_rounded, t.accent),
      TodayState.settled => (Icons.close_rounded, null),
      TodayState.skipped => (Icons.fast_forward_rounded, null),
      TodayState.frozen => (Icons.ac_unit_rounded, null),
      TodayState.vacation => (Icons.beach_access_rounded, null),
      TodayState.paused => (Icons.pause_rounded, null),
      _ => (_proofIcon(h), null),
    };
    final (String? chip, Color? chipColor) = switch (item.state) {
      TodayState.done => ('Done', t.accent),
      TodayState.settled => ('Missed', AppColors.fail),
      TodayState.skipped => ('Skipped', null),
      TodayState.frozen => ('Frozen', null),
      TodayState.vacation => ('Vacation', null),
      TodayState.paused => ('Paused', null),
      TodayState.todo when readOnly => ('Open', null),
      TodayState.unknown => (readOnly ? 'No result' : 'Unavailable', null),
      _ => (null, null),
    };

    final row = Pressable(
      onTap: readOnly ? null : () => _openHabit(context, c, item),
      scale: 0.99,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 11, 12, 11),
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: fill ?? t.track,
              ),
              child: Icon(
                icon,
                size: 18,
                color: fill == null ? t.muted : t.onAccent,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    h.name ?? 'Habit',
                    style: theme.textTheme.bodyLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: item.open ? null : t.muted,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  _meta(context, h),
                ],
              ),
            ),
            const SizedBox(width: 8),
            if (open)
              _CheckButton(
                name: h.name ?? 'habit',
                nfc: h.proof == 'nfc',
                busy: busy,
                onTap: busy ? null : () => _check(context, c, h),
              )
            else if (chip != null)
              _Chip(label: chip, color: chipColor),
          ],
        ),
      ),
    );
    if (!open || h.id == null) return row;
    final canSkip = c.skipsLeft > 0 && !busy;
    return Dismissible(
      key: ValueKey('skip-${h.id}'),
      direction: canSkip ? DismissDirection.endToStart : DismissDirection.none,
      // The row stays; the reload marks it skipped once the skip lands.
      confirmDismiss: (_) async {
        unawaited(_skip(c, h));
        return false;
      },
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        color: t.track,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.fast_forward_rounded, size: 18, color: t.muted),
            const SizedBox(width: 6),
            Text(
              'Skip · ${c.skipsLeft} left',
              style: theme.textTheme.labelLarge?.copyWith(color: t.muted),
            ),
          ],
        ),
      ),
      child: row,
    );
  }
}

/// The round check button: one for every proof (NFC habits scan their tag).
class _CheckButton extends StatelessWidget {
  final String name;
  final bool nfc;
  final bool busy;
  final VoidCallback? onTap;
  const _CheckButton({
    required this.name,
    required this.nfc,
    required this.busy,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final t = GlassTokens.of(context);
    return Semantics(
      button: true,
      label: nfc ? 'Scan the tag for $name' : 'Complete $name',
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: AnimatedSwitcher(
            duration: GlassMotion.of(context, GlassMotion.fast),
            child: busy
                ? SizedBox.square(
                    key: const ValueKey('busy'),
                    dimension: 34,
                    child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: t.muted,
                      ),
                    ),
                  )
                : Container(
                    key: const ValueKey('check'),
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: t.muted, width: 1.6),
                    ),
                    child: Icon(Icons.check_rounded, size: 18, color: t.muted),
                  ),
          ),
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final String label;
  final Color? color;
  const _Chip({required this.label, this.color});

  @override
  Widget build(BuildContext context) {
    final t = GlassTokens.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: t.track,
        borderRadius: const BorderRadius.all(Radius.circular(999)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        child: Text(
          label,
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
            fontWeight: FontWeight.w600,
            color: color ?? t.muted,
          ),
        ),
      ),
    );
  }
}

/// The end of the page: freezes, skips and vacation as 3 equal boxes. Freezes
/// and skips explain themselves; Vacation opens the vacation list.
class _SafetyNets extends StatelessWidget {
  final DashboardController c;
  final BuffersController buffers;
  const _SafetyNets({required this.c, required this.buffers});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final t = GlassTokens.of(context);
    final balance = buffers.balance;
    final freezes = balance == null
        ? (buffers.loading ? '…' : '—')
        : '${balance.balance}/${balance.cap}';
    final vacation = switch (buffers.vacationOn) {
      null => buffers.loading ? '…' : '—',
      true => 'On',
      false => 'Off',
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 24, 4, 8),
          child: Text(
            'Safety nets',
            style: theme.textTheme.labelLarge?.copyWith(
              color: t.muted,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _NetBox(
                icon: Icons.ac_unit_rounded,
                color: AppColors.freeze,
                value: freezes,
                label: 'Freezes',
                onTap: () => _showSafetyNets(context),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _NetBox(
                icon: Icons.fast_forward_rounded,
                value: '${c.skipsLeft}/${c.totalSkip}',
                label: 'Skips',
                onTap: () => _showSafetyNets(context),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _NetBox(
                icon: Icons.beach_access_rounded,
                color: AppColors.vacation,
                value: vacation,
                label: 'Vacation',
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const VacationListView()),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _NetBox extends StatelessWidget {
  final IconData icon;
  final Color? color;
  final String value;
  final String label;
  final VoidCallback onTap;
  const _NetBox({
    required this.icon,
    required this.value,
    required this.label,
    required this.onTap,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final t = GlassTokens.of(context);
    return Semantics(
      button: true,
      label: '$label, $value',
      excludeSemantics: true,
      child: Pressable(
        onTap: onTap,
        child: Glass(
          strong: true,
          radius: const BorderRadius.all(Radius.circular(18)),
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: 18, color: color ?? t.muted),
              const SizedBox(height: 6),
              Text(
                value,
                maxLines: 1,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: t.muted,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The last 7 days, today last and picked by default. A past day opens read
/// only.
class _DateStrip extends StatelessWidget {
  final DateTime today;
  final DateTime? selected;
  final void Function(DateTime day, {required bool isToday}) onPick;
  const _DateStrip({
    required this.today,
    required this.selected,
    required this.onPick,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final t = GlassTokens.of(context);
    final fg = theme.colorScheme.onSurface;
    final bg = theme.colorScheme.surface;
    return SafeArea(
      top: false,
      minimum: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Glass(
          blur: true,
          strong: true,
          radius: const BorderRadius.all(Radius.circular(26)),
          padding: const EdgeInsets.all(4),
          child: Row(
            children: [
              for (var back = 6; back >= 0; back--)
                Expanded(
                  child: _day(
                    context,
                    DateTime(today.year, today.month, today.day - back),
                    isToday: back == 0,
                    fg: fg,
                    bg: bg,
                    t: t,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _day(
    BuildContext context,
    DateTime day, {
    required bool isToday,
    required Color fg,
    required Color bg,
    required GlassTokens t,
  }) {
    final on = isToday ? selected == null : selected == day;
    final theme = Theme.of(context);
    return Semantics(
      button: true,
      selected: on,
      label: isToday ? 'Today' : _dateCaption(day),
      excludeSemantics: true,
      child: Pressable(
        onTap: () => onPick(day, isToday: isToday),
        child: AnimatedContainer(
          duration: GlassMotion.of(context, GlassMotion.fast),
          height: 44,
          decoration: ShapeDecoration(
            shape: const StadiumBorder(),
            color: on ? fg : Colors.transparent,
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                isToday
                    ? 'Today'
                    : _weekdayNames[day.weekday - 1].substring(0, 3),
                style: theme.textTheme.labelSmall?.copyWith(
                  fontSize: 10,
                  color: on ? bg.withValues(alpha: 0.7) : t.muted,
                ),
              ),
              Text(
                '${day.day}',
                style: theme.textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: on ? bg : fg,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Streak extends StatelessWidget {
  final int days;
  const _Streak(this.days);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 8, top: 2),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.local_fire_department_rounded,
            size: 16,
            color: AppColors.streak,
          ),
          const SizedBox(width: 2),
          Text(
            '$days',
            style: Theme.of(
              context,
            ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

void _showSafetyNets(BuildContext context) {
  showGlassSheet<void>(
    context,
    (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Your safety nets',
              style: Theme.of(
                ctx,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 16),
            _infoRow(
              ctx,
              Icons.ac_unit_rounded,
              AppColors.freeze,
              'Freezes',
              'Automatic. If you miss a scheduled day, a freeze is spent for '
                  'you — your streak survives and you’re not charged. You earn '
                  'them over time, and the cap grows as your streak grows.',
            ),
            _infoRow(
              ctx,
              Icons.fast_forward_rounded,
              null,
              'Skips',
              'You choose these. Tap Skip, or swipe a habit left, when you '
                  'know you won’t do it today — it won’t break your streak or '
                  'charge you. Limited to a monthly allowance.',
            ),
            _infoRow(
              ctx,
              Icons.beach_access_rounded,
              AppColors.vacation,
              'Vacation',
              'Pause all habits for a date range, for longer breaks. No misses '
                  'and no charges while a vacation is active. Tap Vacation to plan one.',
            ),
          ],
        ),
      ),
    ),
  );
}

Widget _infoRow(
  BuildContext context,
  IconData icon,
  Color? color,
  String title,
  String body,
) {
  final theme = Theme.of(context);
  final t = GlassTokens.of(context);
  return Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: color ?? t.muted, size: 22),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                body,
                style: theme.textTheme.bodySmall?.copyWith(color: t.muted),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

/// The frosted "+" that creates a habit.
class _AddButton extends StatelessWidget {
  final VoidCallback onTap;
  const _AddButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: () {
        HapticFeedback.lightImpact();
        onTap();
      },
      scale: 0.92,
      child: Semantics(
        button: true,
        label: 'New habit',
        child: Glass(
          blur: true,
          strong: true,
          radius: const BorderRadius.all(Radius.circular(28)),
          child: const SizedBox.square(
            dimension: 56,
            child: Icon(Icons.add_rounded, size: 28),
          ),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final VoidCallback onCreate;
  const _EmptyState({required this.onCreate});

  @override
  Widget build(BuildContext context) {
    final followsPhone = context.watch<SessionController>().followPhoneTimezone;
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: GlassMessage(
        icon: Icons.task_alt_rounded,
        tint: GlassTokens.of(context).accent,
        title: 'Make your first habit',
        body: followsPhone
            ? 'Choose what to do and on which days. Your timezone '
                  'already follows your phone.'
            : 'Choose what to do and on which days.',
        actions: [GlassButton(label: 'Create a habit', onPressed: onCreate)],
      ),
    );
  }
}

class _ErrorRetry extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _ErrorRetry({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: GlassMessage(
            icon: Icons.cloud_off_rounded,
            tint: Theme.of(context).colorScheme.error,
            title: 'Could not load Today',
            body: message,
            actions: [GlassButton(label: 'Retry', onPressed: onRetry)],
          ),
        ),
      ),
    );
  }
}

/// A saved Today from an earlier day: dimmed and not tappable until today's
/// arrives (instead of a full-screen loader).
Widget _dimWhenStale(bool stale, Widget sliver) => SliverIgnorePointer(
  ignoring: stale,
  sliver: SliverOpacity(opacity: stale ? 0.55 : 1, sliver: sliver),
);
