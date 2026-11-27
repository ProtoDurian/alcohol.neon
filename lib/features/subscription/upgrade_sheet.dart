import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../generated/zinc/models/plan_res.dart';
import '../../services/storefront_service.dart';
import '../../session/session_controller.dart';
import '../../theme/glass.dart';
import '../../widgets/glass_list.dart';
import '../../widgets/glass_modal.dart';
import 'subscription_controller.dart';
import 'tier.dart';

/// The plan limits that can stop the user.
enum PlanLimit { skips, vacations, vacationLength }

/// What [next] gives for [limit], such as "Pro gives 5 skips a month.". Null
/// when it gives no more than [current].
String? upgradeLine(PlanLimit limit, PlanRes? current, PlanRes next) {
  final name = tierLabel(next.key ?? '');
  switch (limit) {
    case PlanLimit.skips:
      final n = next.skipsMonthly;
      if (current != null && n <= current.skipsMonthly) return null;
      return '$name gives $n skip${n == 1 ? '' : 's'} a month.';
    case PlanLimit.vacations:
      final n = next.vacationWindowsYearly;
      if (current != null && n <= current.vacationWindowsYearly) return null;
      final days = next.vacationMaxDays;
      return '$name gives $n vacation${n == 1 ? '' : 's'} a year'
          '${days == null ? '' : ', up to $days days each'}.';
    case PlanLimit.vacationLength:
      final days = next.vacationMaxDays;
      if (days == null) return null;
      if (current?.vacationMaxDays case final have? when days <= have) {
        return null;
      }
      return '$name allows up to $days days per vacation.';
  }
}

/// Tells the user they hit [limit] and offers the upgrade. What it may offer
/// follows the subscription screen's storefront rules: an upgrade on the web
/// where zinc allows it, manage on the web for subscribers, and no plan
/// comparison or button where the store forbids it.
Future<void> showUpgradeSheet(
  BuildContext context, {
  required PlanLimit limit,
  required String title,
  required String message,
}) {
  return showGlassSheet<void>(
    context,
    (_) => UpgradeSheet(limit: limit, title: title, message: message),
  );
}

class UpgradeSheet extends StatefulWidget {
  final PlanLimit limit;
  final String title;
  final String message;

  /// Test seam: when provided, the sheet renders this controller as-is.
  @visibleForTesting
  final SubscriptionController? controller;

  const UpgradeSheet({
    super.key,
    required this.limit,
    required this.title,
    required this.message,
    this.controller,
  });

  @override
  State<UpgradeSheet> createState() => _UpgradeSheetState();
}

class _UpgradeSheetState extends State<UpgradeSheet> {
  SubscriptionController? _controller;
  bool _owned = false;

  @override
  void initState() {
    super.initState();
    if (widget.controller case final c?) {
      _controller = c;
      return;
    }
    final session = context.read<SessionController>();
    final userId = session.userId;
    if (userId == null) return;
    _owned = true;
    _controller = SubscriptionController(
      repository: session.subscriptions,
      storefront: StoreStorefrontService(),
      userId: userId,
    )..load();
  }

  @override
  void dispose() {
    if (_owned) _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = _controller;
    return c == null
        ? _body(context, null)
        : ListenableBuilder(
            listenable: c,
            builder: (context, _) => _body(context, c),
          );
  }

  Widget _body(BuildContext context, SubscriptionController? c) {
    final theme = Theme.of(context);
    final t = GlassTokens.of(context);
    final ready = c != null && !c.loading && c.error == null;
    final variant = ready ? c.variant : SubscriptionCtaVariant.neutral;
    final next = variant == SubscriptionCtaVariant.subscribe
        ? c?.nextPlan
        : null;
    final line = next == null ? null : upgradeLine(widget.limit, c?.plan, next);
    final action = switch (variant) {
      SubscriptionCtaVariant.subscribe => 'Upgrade on the web',
      SubscriptionCtaVariant.manage => 'Manage subscription',
      SubscriptionCtaVariant.neutral => null,
    };
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Icon(Icons.workspace_premium_rounded, size: 48, color: t.accent),
            const SizedBox(height: 12),
            Text(
              widget.title,
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              widget.message,
              textAlign: TextAlign.center,
              style: TextStyle(color: t.muted),
            ),
            if (line != null) ...[
              const SizedBox(height: 12),
              Text(
                line,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: t.accent,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
            if (c?.openError case final e?) ...[
              const SizedBox(height: 12),
              Text(
                e.displayMessage,
                textAlign: TextAlign.center,
                style: TextStyle(color: theme.colorScheme.error),
              ),
            ],
            const SizedBox(height: 20),
            if (c != null && c.loading)
              const GlassButton(label: 'Upgrade on the web', busy: true)
            else if (action != null) ...[
              GlassButton(
                label: action,
                busy: c!.opening,
                onPressed: c.openPortal,
              ),
              const SizedBox(height: 4),
              Text(
                'Opens in your browser',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(color: t.muted),
              ),
            ],
            GlassTextButton(
              label: action == null && !(c?.loading ?? false)
                  ? 'OK'
                  : 'Not now',
              muted: true,
              onPressed: () => Navigator.pop(context),
            ),
          ],
        ),
      ),
    );
  }
}
