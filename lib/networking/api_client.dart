import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

import '../core/launch_timeline.dart';

import '../core/problem.dart';

/// Minimal async HTTP client for the zinc REST API. Every call returns `Result<T>`
/// (no throwing across boundaries). Bearer tokens are supplied lazily via
/// [tokenProvider], which mints a Logto access token for the zinc resource on demand.
class ApiClient {
  final Uri baseUrl;
  final Future<String?> Function() tokenProvider;
  late http.Client _client;

  /// The dart:io pool under [_client] when this client made its own.
  HttpClient? _io;

  /// How long a request may take before it fails as a network error. Without
  /// it a stalled connection (captive Wi-Fi, a dropped mobile link) never
  /// completes, and a screen waiting on it shows its loader forever.
  static const timeout = Duration(seconds: 20);

  /// How long an idle connection to zinc is kept for reuse. Dart's default
  /// is 15 s, so a call 15 s after the last one paid a new TCP + TLS
  /// handshake (3 round trips to Singapore instead of 1). The load balancer
  /// closes idle connections after 75 s; staying under it avoids reusing a
  /// socket the server is closing at that moment.
  static const keepIdle = Duration(seconds: 70);

  /// The HTTP client zinc calls go through: one connection pool kept
  /// [keepIdle]. Share one per app (see [AuthService.makeApiClient]) so every
  /// caller reuses the same warm connections.
  static http.Client keepAliveClient() => IOClient(keepAliveHttpClient());

  /// The dart:io client under [keepAliveClient].
  @visibleForTesting
  static HttpClient keepAliveHttpClient() =>
      HttpClient()..idleTimeout = keepIdle;

  ApiClient({
    required this.baseUrl,
    required this.tokenProvider,
    http.Client? client,
  }) {
    if (client != null) {
      _client = client;
    } else {
      final io = _io = keepAliveHttpClient();
      _client = IOClient(io);
    }
  }

  /// Starts a new connection pool, so later calls never pick an idle socket
  /// from before. Call on resume: after the phone was in the background
  /// those may be dead without a close, and a call on one waits for
  /// [timeout]. The old pool is not closed (closing cancels a call still
  /// connecting); its idle sockets close themselves after [keepIdle].
  void resetConnections() {
    if (_io == null) return;
    final io = _io = keepAliveHttpClient();
    _client = IOClient(io);
  }

  /// Opens a connection to zinc ahead of the real calls (an unauthenticated
  /// GET of the root info, no database). Called on resume: the first real
  /// calls wait for the token (a Logto refresh when it is over an hour old),
  /// and meanwhile this pays the TCP + TLS handshake, so they find a warm
  /// connection. Best-effort; never fails.
  Future<void> warmUp() async {
    try {
      await _client.get(baseUrl.resolve('/')).timeout(timeout);
    } catch (_) {
      // Only costs the next call its warm connection.
    }
  }

  Future<Result<T>> get<T>(
    String path,
    T Function(dynamic json) decode, {
    bool requiresAuth = true,
    Map<String, dynamic>? query,
  }) => _send(
    'GET',
    path,
    null,
    decode,
    requiresAuth: requiresAuth,
    query: query,
  );

  Future<Result<T>> post<T>(
    String path,
    Object? body,
    T Function(dynamic json) decode, {
    bool requiresAuth = true,
  }) => _send('POST', path, body, decode, requiresAuth: requiresAuth);

  Future<Result<T>> put<T>(
    String path,
    Object? body,
    T Function(dynamic json) decode, {
    bool requiresAuth = true,
  }) => _send('PUT', path, body, decode, requiresAuth: requiresAuth);

  Future<Result<T>> patch<T>(
    String path,
    Object? body,
    T Function(dynamic json) decode, {
    bool requiresAuth = true,
  }) => _send('PATCH', path, body, decode, requiresAuth: requiresAuth);

  /// DELETE — most zinc deletes return no body, so this resolves to `Result<void>`
  /// (success carries no value). Handled separately since there's nothing to decode.
  Future<Result<void>> delete(
    String path, {
    Object? body,
    bool requiresAuth = true,
  }) async {
    final headers = await _headers(requiresAuth: requiresAuth);
    if (headers == null) return const Err(Problem.unauthenticated);
    final encoded = body == null ? null : jsonEncode(body);
    if (encoded != null) headers['Content-Type'] = 'application/json';

    http.Response res;
    try {
      res = await _client
          .delete(baseUrl.resolve(path), headers: headers, body: encoded)
          .timeout(timeout);
    } catch (e) {
      return Err(Problem.network(e));
    }
    if (res.statusCode < 200 || res.statusCode >= 300) {
      return Err(_problemFrom(res));
    }
    return const Ok(null);
  }

  Future<Result<T>> _send<T>(
    String method,
    String path,
    Object? body,
    T Function(dynamic json) decode, {
    bool requiresAuth = true,
    Map<String, dynamic>? query,
  }) async {
    var uri = baseUrl.resolve(path);
    if (query != null && query.isNotEmpty) {
      uri = uri.replace(
        queryParameters: {
          ...uri.queryParameters,
          for (final e in query.entries)
            if (e.value != null) e.key: '${e.value}',
        },
      );
    }

    final started = Stopwatch()..start();
    final headers = await _headers(requiresAuth: requiresAuth);
    final tokenMs = started.elapsedMilliseconds;
    if (headers == null) return const Err(Problem.unauthenticated);
    // zinc actions bind [FromBody]; a bodyless POST/PUT/PATCH (e.g. optional-notes
    // complete/skip) must still send application/json or the server returns 415.
    // Send an empty object in that case.
    final hasBodyVerb =
        method == 'POST' || method == 'PUT' || method == 'PATCH';
    final encoded = body != null
        ? jsonEncode(body)
        : (hasBodyVerb ? '{}' : null);
    if (encoded != null) headers['Content-Type'] = 'application/json';

    Future<http.Response> call() => switch (method) {
      'GET' => _client.get(uri, headers: headers),
      'POST' => _client.post(uri, headers: headers, body: encoded),
      'PUT' => _client.put(uri, headers: headers, body: encoded),
      'PATCH' => _client.patch(uri, headers: headers, body: encoded),
      'DELETE' => _client.delete(uri, headers: headers, body: encoded),
      _ => throw ArgumentError('Unsupported method: $method'),
    }.timeout(timeout);

    http.Response res;
    try {
      res = await call();
    } on http.ClientException catch (e) {
      // A kept-alive connection can be dead on reuse (the phone dropped it
      // in the background, or the network changed). A GET is safe to send
      // again once, on a new connection; a write is not.
      if (method != 'GET') return Err(Problem.network(e));
      try {
        res = await call();
      } catch (e) {
        return Err(Problem.network(e));
      }
    } catch (e) {
      return Err(Problem.network(e));
    }
    LaunchTimeline.mark(
      '$method ${uri.path} ${res.statusCode} '
      '${started.elapsedMilliseconds}ms (token ${tokenMs}ms)',
    );
    return _handle(res, decode);
  }

  /// Builds request headers, injecting a Bearer token when [requiresAuth].
  /// Returns null if a token is required but unavailable (caller maps to a Problem).
  Future<Map<String, String>?> _headers({required bool requiresAuth}) async {
    final headers = <String, String>{'Accept': 'application/json'};
    if (requiresAuth) {
      final token = await tokenProvider();
      if (token == null) return null;
      headers['Authorization'] = 'Bearer $token';
    }
    return headers;
  }

  /// Maps an HTTP response into `Result<T>`: non-2xx → `Err(Problem)` (preferring
  /// the server's RFC 7807 body), 2xx → decode, decode failure → `Err`.
  Result<T> _handle<T>(http.Response res, T Function(dynamic json) decode) {
    if (res.statusCode < 200 || res.statusCode >= 300) {
      return Err(_problemFrom(res));
    }
    try {
      final json = res.body.isEmpty ? null : jsonDecode(res.body);
      return Ok(decode(json));
    } catch (e) {
      return Err(Problem.decoding(e));
    }
  }

  /// A non-2xx response as a [Problem]: zinc's RFC 7807 body when it sent one.
  /// Anything else (a proxy's HTML error page, plain text) never reaches the
  /// user verbatim; it becomes a plain sentence with the status code.
  static Problem _problemFrom(http.Response res) {
    try {
      return Problem.fromJson(jsonDecode(res.body) as Map<String, dynamic>);
    } catch (_) {
      return Problem.local(
        'Request failed',
        status: res.statusCode,
        detail:
            'The server sent an unexpected response (HTTP ${res.statusCode}). '
            'Try again in a moment.',
      );
    }
  }
}
