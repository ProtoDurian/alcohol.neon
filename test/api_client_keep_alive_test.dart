// Real sockets: no Flutter test binding here (it would answer every request
// with a fake 400 instead of opening a connection).
import 'dart:io';

import 'package:alcohol_neon/core/problem.dart';
import 'package:alcohol_neon/networking/api_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  group('keep-alive zinc client', () {
    late HttpServer server;
    late Uri base;
    final ports = <int>[];
    // Connections the server stops answering on (dead after the background).
    final dead = <int>{};

    setUp(() async {
      ports.clear();
      dead.clear();
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      base = Uri.parse('http://127.0.0.1:${server.port}');
      server.listen((r) {
        // The client's port tells which connection the request came on.
        final port = r.connectionInfo!.remotePort;
        ports.add(port);
        if (dead.contains(port)) return; // never answers
        r.response
          ..headers.contentType = ContentType.json
          ..write('{"ok":true}')
          ..close();
      });
    });
    tearDown(() => server.close(force: true));

    ApiClient api(http.Client client) => ApiClient(
      baseUrl: base,
      tokenProvider: () async => 'token',
      client: client,
    );

    test('keeps idle connections 70 s, under the server\'s 75 s', () {
      final c = ApiClient.keepAliveHttpClient();
      expect(c.idleTimeout, const Duration(seconds: 70));
      c.close(force: true);
    });

    test('callers sharing one client reuse one connection', () async {
      final shared = ApiClient.keepAliveClient();
      final dashboard = api(shared);
      final inbox = api(shared);
      for (final a in [dashboard, inbox, dashboard]) {
        expect(await a.get('/x', (j) => j), isA<Ok<dynamic>>());
      }
      expect(ports.toSet(), hasLength(1));
      shared.close();
    });

    test('a client per caller opens a connection per caller', () async {
      final a = ApiClient.keepAliveClient();
      final b = ApiClient.keepAliveClient();
      await api(a).get('/x', (j) => j);
      await api(b).get('/x', (j) => j);
      expect(ports.toSet(), hasLength(2));
      a.close();
      b.close();
    });

    test('after resetConnections, a dead idle socket is not reused', () async {
      final own = ApiClient(baseUrl: base, tokenProvider: () async => 'token');
      await own.get('/x', (j) => j);
      dead.addAll(ports);
      own.resetConnections();
      final r = await own
          .get('/x', (j) => j)
          .timeout(const Duration(seconds: 5));
      expect(r, isA<Ok<dynamic>>());
      expect(ports.toSet(), hasLength(2));
    });

    test('warmUp opens the connection the next call reuses', () async {
      final shared = ApiClient.keepAliveClient();
      await api(shared).warmUp();
      await api(shared).get('/x', (j) => j);
      expect(ports, hasLength(2));
      expect(ports.toSet(), hasLength(1));
      shared.close();
    });
  });

  group('a dead kept-alive connection', () {
    ApiClient failingOnce(List<http.Request> seen) {
      var failed = false;
      return ApiClient(
        baseUrl: Uri.parse('https://zinc.test'),
        tokenProvider: () async => 'token',
        client: MockClient((r) async {
          seen.add(r);
          if (!failed) {
            failed = true;
            throw http.ClientException('Connection closed', r.url);
          }
          return http.Response('{}', 200);
        }),
      );
    }

    test('a GET is sent again once', () async {
      final seen = <http.Request>[];
      final r = await failingOnce(seen).get('/x', (j) => j);
      expect(r, isA<Ok<dynamic>>());
      expect(seen, hasLength(2));
    });

    test('a write is not sent again', () async {
      final seen = <http.Request>[];
      final r = await failingOnce(seen).post('/x', null, (j) => j);
      expect(r, isA<Err<dynamic>>());
      expect(seen, hasLength(1));
    });

    test('a GET that fails twice is one network error', () async {
      final seen = <http.Request>[];
      final api = ApiClient(
        baseUrl: Uri.parse('https://zinc.test'),
        tokenProvider: () async => 'token',
        client: MockClient((r) async {
          seen.add(r);
          throw http.ClientException('offline', r.url);
        }),
      );
      expect(await api.get('/x', (j) => j), isA<Err<dynamic>>());
      expect(seen, hasLength(2));
    });

    test('warmUp never fails and sends no token', () async {
      final seen = <http.Request>[];
      final api = ApiClient(
        baseUrl: Uri.parse('https://zinc.test'),
        tokenProvider: () async => 'token',
        client: MockClient((r) async {
          seen.add(r);
          throw http.ClientException('offline', r.url);
        }),
      );
      await api.warmUp();
      expect(seen.single.url.path, '/');
      expect(seen.single.headers.containsKey('Authorization'), isFalse);
    });
  });
}
