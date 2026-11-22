// The app speed changes: Today stays on screen while it refreshes, one token
// refresh for all callers, a saved Today that survives overlapping writes and
// shows on any day, a loader that waits 300 ms, and one shared zinc client.
import 'dart:async';
import 'dart:io';

import 'package:alcohol_neon/auth/auth_service.dart';
import 'package:alcohol_neon/config/app_config.dart';
import 'package:alcohol_neon/core/navigation.dart';
import 'package:alcohol_neon/features/dashboard/dashboard_controller.dart';
import 'package:alcohol_neon/features/dashboard/dashboard_view.dart';
import 'package:alcohol_neon/features/dashboard/today_layout.dart';
import 'package:alcohol_neon/generated/zinc/models/configuration_principal_res.dart';
import 'package:alcohol_neon/generated/zinc/models/habit_overview_response.dart';
import 'package:alcohol_neon/session/session_cache.dart';
import 'package:alcohol_neon/session/session_controller.dart';
import 'package:alcohol_neon/theme/app_theme.dart';
import 'package:alcohol_neon/widgets/app_loader.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:logto_dart_sdk/logto_dart_sdk.dart';
import 'package:lottie/lottie.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';

import 'support/session_harness.dart';

/// Like [_GatedLogto], with one gate per token request.
class _ManyGatesLogto extends LogtoClient {
  _ManyGatesLogto()
    : super(
        config: const LogtoConfig(endpoint: 'https://l.test', appId: 'a'),
      );
  final gates = <Completer<void>>[];
  final events = <String>[];
  @override
  Future<bool> get isAuthenticated async => true;
  @override
  Future<AccessToken?> getAccessToken({
    String? resource,
    String? organizationId,
  }) async {
    final gate = Completer<void>();
    gates.add(gate);
    await gate.future;
    events.add('refresh-landed');
    return null;
  }

  @override
  Future<void> signOut(String redirectUri) async => events.add('cleared');
}

/// A signed-in Logto client whose token arrives when [gate] completes.
class _GatedLogto extends LogtoClient {
  _GatedLogto()
    : super(
        config: const LogtoConfig(endpoint: 'https://l.test', appId: 'a'),
      );
  final gate = Completer<void>();
  final events = <String>[];
  @override
  Future<bool> get isAuthenticated async => true;
  @override
  Future<AccessToken?> getAccessToken({
    String? resource,
    String? organizationId,
  }) async {
    await gate.future;
    events.add('refresh-landed');
    return AccessToken(
      token: 'token-of-the-old-session',
      scope: '',
      expiresAt: DateTime.now().add(const Duration(hours: 1)),
    );
  }

  @override
  Future<void> signOut(String redirectUri) async => events.add('cleared');
}

/// A signed-in Logto client whose access token is expired: every
/// `getAccessToken` that reaches it is one refresh with Logto.
class _ExpiredTokenLogto extends LogtoClient {
  _ExpiredTokenLogto()
    : super(
        config: const LogtoConfig(endpoint: 'https://l.test', appId: 'a'),
      );
  int refreshes = 0;
  @override
  Future<bool> get isAuthenticated async => true;
  @override
  Future<AccessToken?> getAccessToken({
    String? resource,
    String? organizationId,
  }) async {
    refreshes++;
    await Future<void>.delayed(const Duration(milliseconds: 20));
    return null;
  }
}

final _config = ConfigurationPrincipalRes.fromJson({
  'id': 'cfg1',
  'timezone': 'Asia/Singapore',
  'defaultCharityId': 'ch1',
});

HabitOverviewResponse _overview() =>
    HabitOverviewResponse.fromJson({...overviewBody()});

void main() {
  final messenger =
      TestWidgetsFlutterBinding.ensureInitialized().defaultBinaryMessenger;
  const timezoneChannel = MethodChannel('flutter_timezone');
  const widgetChannel = MethodChannel('home_widget');

  setUpAll(loadHarnessConfig);
  setUp(() {
    PackageInfo.setMockInitialValues(
      appName: 'LazyTax',
      packageName: 'cloud.durian.pichu.alcohol.neon.app',
      version: '1',
      buildNumber: '1',
      buildSignature: '',
    );
    messenger.setMockMethodCallHandler(timezoneChannel, (_) async {
      throw PlatformException(code: 'unavailable');
    });
    messenger.setMockMethodCallHandler(widgetChannel, (_) async => true);
  });
  tearDown(() {
    messenger.setMockMethodCallHandler(timezoneChannel, null);
    messenger.setMockMethodCallHandler(widgetChannel, null);
    TodayLayoutSetting.instance.value = TodayLayout.nextUp;
  });

  /// zinc with the overview held while [hold] is set.
  Completer<void>? hold;
  var overviews = 0;
  var failOverviews = 0;
  Future<http.Response?> respond(http.Request r) async {
    if (r.url.path.endsWith('/overview')) {
      overviews++;
      await hold?.future;
      if (failOverviews > 0) {
        failOverviews--;
        return jsonResponse({'title': 'Down', 'status': 503}, 503);
      }
    }
    return null;
  }

  Future<SessionHarness> pumpToday(
    WidgetTester tester, {
    SessionSnapshot? saved,
    bool settle = true,
  }) async {
    hold = null;
    overviews = 0;
    final h = SessionHarness(respond: respond);
    h.cache.snapshot = saved;
    await h.start();
    tester.view.physicalSize = const Size(390, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ChangeNotifierProvider<SessionController>.value(
        value: h.session,
        child: MaterialApp(
          theme: AppTheme.light,
          navigatorObservers: [routeObserver],
          home: const DashboardView(),
        ),
      ),
    );
    if (settle) await tester.pumpAndSettle();
    return h;
  }

  Future<void> done(WidgetTester tester, SessionHarness h) async {
    if (hold?.isCompleted == false) hold!.complete();
    await tester.pumpWidget(const SizedBox.shrink());
    h.dispose();
  }

  /// Today is on screen and no full-screen loader replaced it.
  void expectTodayShown() {
    expect(find.byType(AppLoader), findsNothing);
    expect(find.text('Read a chapter'), findsWidgets);
  }

  group('Today stays on screen while it refreshes', () {
    testWidgets('coming back to the app', (tester) async {
      final h = await pumpToday(tester);
      expectTodayShown();
      final before = overviews;
      hold = Completer();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(overviews, greaterThan(before), reason: 'it does refresh');
      expectTodayShown();
      hold!.complete();
      await tester.pumpAndSettle();
      expectTodayShown();
      await done(tester, h);
    });

    testWidgets('closing a dialog over Today', (tester) async {
      final h = await pumpToday(tester);
      unawaited(
        showDialog<void>(
          context: tester.element(find.byType(DashboardView)),
          builder: (_) => const AlertDialog(content: Text('Hi')),
        ),
      );
      await tester.pumpAndSettle();
      final before = overviews;
      hold = Completer();
      Navigator.of(tester.element(find.text('Hi'))).pop();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(overviews, greaterThan(before), reason: 'it does refresh');
      expectTodayShown();
      await done(tester, h);
    });

    testWidgets('coming back opens a zinc connection first (warm-up)', (
      tester,
    ) async {
      final h = await pumpToday(tester);
      final before = h.requests.length;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      final after = h.requests.skip(before).toList();
      expect(after.first.url.path, '/');
      expect(after.first.headers.containsKey('Authorization'), isFalse);
      await done(tester, h);
    });
  });

  group('a saved Today from an earlier day', () {
    SessionSnapshot yesterday() => SessionSnapshot(
      _config,
      _overview(),
      DateTime.now().subtract(const Duration(days: 1)),
    );

    testWidgets('shows dimmed at once, then today\'s replaces it', (
      tester,
    ) async {
      hold = Completer();
      final h = SessionHarness(respond: respond);
      h.cache.snapshot = yesterday();
      final held = hold!;
      await h.start();
      expect(h.session.cachedOverviewStale, isTrue);
      tester.view.physicalSize = const Size(390, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        ChangeNotifierProvider<SessionController>.value(
          value: h.session,
          child: MaterialApp(
            theme: AppTheme.light,
            navigatorObservers: [routeObserver],
            home: const DashboardView(),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 500));
      expectTodayShown();
      expect(find.text('Updating Today…'), findsOneWidget);
      held.complete();
      await tester.pumpAndSettle();
      expect(find.text('Updating Today…'), findsNothing);
      expectTodayShown();
      await done(tester, h);
    });

    testWidgets('Retry stays tappable and quiet when today\'s fails', (
      tester,
    ) async {
      hold = null;
      overviews = 0;
      failOverviews = 1;
      final h = SessionHarness(respond: respond);
      h.cache.snapshot = yesterday();
      await h.start();
      tester.view.physicalSize = const Size(390, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        ChangeNotifierProvider<SessionController>.value(
          value: h.session,
          child: MaterialApp(
            theme: AppTheme.light,
            navigatorObservers: [routeObserver],
            home: const DashboardView(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Could not refresh the dashboard'), findsOneWidget);
      expect(find.text('Updating Today…'), findsOneWidget);
      expect(
        find.byWidgetPredicate((w) => w.runtimeType.toString() == '_AddButton'),
        findsNothing,
        reason: 'no new habit on yesterday\'s list',
      );
      final before = overviews;
      hold = Completer();
      await tester.tap(find.text('Retry'));
      await tester.pump(const Duration(milliseconds: 500));
      expect(overviews, before + 1);
      expectTodayShown();
      hold!.complete();
      await tester.pumpAndSettle();
      expect(find.text('Updating Today…'), findsNothing);
      expect(find.text('Could not refresh the dashboard'), findsNothing);
      await done(tester, h);
    });

    test('cannot be completed until today\'s arrives', () async {
      hold = null;
      final h = SessionHarness(respond: respond);
      h.cache.snapshot = yesterday();
      await h.start();
      final c = DashboardController(h.session);
      expect(c.stale, isTrue);
      final habit = c.overview!.habits!.first;
      await c.complete(habit);
      expect(
        h.requests.where((r) => r.method == 'POST'),
        isEmpty,
        reason: "yesterday's list is read-only",
      );
      await c.load();
      expect(c.stale, isFalse);
      c.dispose();
      h.dispose();
    });

    test('a same-day save is not stale', () async {
      final h = SessionHarness(respond: respond);
      h.cache.snapshot = SessionSnapshot(_config, _overview(), DateTime.now());
      await h.start();
      expect(h.session.cachedOverviewStale, isFalse);
      h.dispose();
    });
  });

  group('saved Today on disk', () {
    late Directory dir;
    setUp(() async => dir = await Directory.systemTemp.createTemp('speed'));
    tearDown(() => dir.delete(recursive: true));

    test('survives its two halves being saved at the same moment', () async {
      for (var i = 0; i < 20; i++) {
        final cache = SessionCache(dir: () async => dir);
        await cache.clear();
        // Not awaited one by one: launch saves both about a frame apart.
        await Future.wait([
          cache.saveConfig('u1', _config),
          cache.saveOverview('u1', _overview()),
        ]);
        expect(await cache.load('u1'), isNotNull, reason: 'run $i');
      }
    });

    test('a sign-out clear wins over saves queued before it', () async {
      final cache = SessionCache(dir: () async => dir);
      final saves = [
        cache.saveConfig('u1', _config),
        cache.saveOverview('u1', _overview()),
      ];
      await cache.clear();
      await Future.wait(saves);
      expect(await cache.load('u1'), isNull);
    });

    test('saves its time in UTC', () async {
      final cache = SessionCache(dir: () async => dir);
      await cache.saveConfig('u1', _config);
      await cache.saveOverview('u1', _overview());
      final raw = await File('${dir.path}/session_cache.json').readAsString();
      expect(RegExp(r'"savedAt":"[^"]+Z"').hasMatch(raw), isTrue);
    });
  });

  group('one token refresh', () {
    test('a token started before sign-out never reaches anyone', () async {
      final logto = _GatedLogto();
      final auth = AuthService(AppConfig.current, client: logto);
      await pumpEventQueue();
      expect(auth.status, AuthStatus.authenticated);
      final early = auth.zincAccessToken();
      await pumpEventQueue();
      final out = auth.signOut();
      final late = auth.zincAccessToken();
      await pumpEventQueue();
      expect(logto.events, isEmpty, reason: 'the clear waits for the refresh');
      logto.gate.complete();
      await out;
      expect(await early, isNull);
      expect(await late, isNull);
      // The refresh's writes land before the clear, so the clear wipes them.
      expect(logto.events, ['refresh-landed', 'cleared']);
    });

    test('4 callers at once share one refresh with Logto', () async {
      final logto = _ExpiredTokenLogto();
      final auth = AuthService(AppConfig.current, client: logto);
      await pumpEventQueue();
      expect(auth.status, AuthStatus.authenticated);
      await Future.wait([for (var i = 0; i < 4; i++) auth.zincAccessToken()]);
      expect(logto.refreshes, 1);
      // Once settled, the next ask starts a new request.
      await auth.zincAccessToken();
      expect(logto.refreshes, 2);
    });

    testWidgets('sign-out waits for every SDK refresh still running', (
      tester,
    ) async {
      final logto = _ManyGatesLogto();
      final auth = AuthService(AppConfig.current, client: logto);
      await tester.pump();
      final first = auth.zincAccessToken();
      await tester.pump(AuthService.tokenTimeout + const Duration(seconds: 1));
      expect(await first, isNull, reason: 'timed out; the SDK keeps going');
      unawaited(auth.zincAccessToken());
      await tester.pump();
      expect(logto.gates, hasLength(2));
      logto.gates[1].complete();
      await tester.pump();
      final out = auth.signOut();
      await tester.pump();
      expect(logto.events, ['refresh-landed'], reason: 'first still running');
      logto.gates[0].complete();
      await tester.pump();
      await out;
      expect(logto.events, ['refresh-landed', 'refresh-landed', 'cleared']);
    });

    test('every caller gets the same zinc client', () async {
      final auth = AuthService(AppConfig.current, client: _ExpiredTokenLogto());
      expect(identical(auth.makeApiClient(), auth.makeApiClient()), isTrue);
    });
  });

  group('the loader', () {
    testWidgets('shows nothing for the first 300 ms, then the sloth', (
      tester,
    ) async {
      await tester.pumpWidget(const MaterialApp(home: AppLoader()));
      expect(find.byType(Lottie), findsNothing);
      await tester.pump(const Duration(milliseconds: 290));
      expect(find.byType(Lottie), findsNothing);
      await tester.pump(const Duration(milliseconds: 20));
      expect(find.byType(Lottie), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('a wait under 300 ms leaves no timer running', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: AppLoader()));
      await tester.pump(const Duration(milliseconds: 200));
      // The test framework fails on a timer still pending at the end.
      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      expect(find.byType(Lottie), findsNothing);
    });
  });
}
