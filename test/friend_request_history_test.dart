import 'dart:async';
import 'dart:convert';

import 'package:alcohol_neon/core/problem.dart';
import 'package:alcohol_neon/data/friend_repository.dart';
import 'package:alcohol_neon/data/inbox_repository.dart';
import 'package:alcohol_neon/features/friends/friends_controller.dart';
import 'package:alcohol_neon/features/inbox/inbox_controller.dart';
import 'package:alcohol_neon/networking/api_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'support/session_harness.dart' show jsonResponse;

const first = '11111111-1111-1111-1111-111111111111';
const second = '22222222-2222-2222-2222-222222222222';

Map<String, Object?> occurrence(String id, String status) => {
  'requestId': id,
  'status': status,
  'createdAtUtc': '2026-11-13T08:00:00Z',
  'resolvedAtUtc': status == 'pending' ? null : '2026-11-13T09:00:00Z',
};

Map<String, Object?> notification(String id, String status) => {
  'id': 'notice-$id',
  'kind': status == 'pending' ? 'friend_request' : 'friend_request_resolved',
  'title': 'Friend request',
  'body': 'Alice wants to be friends',
  'actorUserId': 'alice',
  'data': jsonEncode({'requestId': id, 'fromUserId': 'alice'}),
  'friendRequest': occurrence(id, status),
};

ApiClient apiFor(Future<http.Response> Function(http.Request) respond) {
  final client = MockClient(respond);
  addTearDown(client.close);
  return ApiClient(
    baseUrl: Uri.parse('https://zinc.test'),
    tokenProvider: () async => 'token',
    client: client,
  );
}

InboxController inboxFor(ApiClient api) {
  final controller = InboxController(
    InboxRepository(api),
    FriendRepository(api),
    'bob',
  );
  addTearDown(controller.dispose);
  return controller;
}

http.Response conflict() => jsonResponse({
  'type': 'https://errors.test/api/v1/friend_request_resolved',
  'title': 'Friend Request Resolved',
  'status': 409,
  'detail': 'This friend request has already been resolved.',
}, 409);

void main() {
  test(
    'pagination reconciles overlapping terminal occurrence without duplicating its notice',
    () async {
      var page = 0;
      final c = inboxFor(
        apiFor(
          (_) async => jsonResponse(
            ++page == 1
                ? [
                    notification(first, 'pending'),
                    for (var i = 0; i < 19; i++)
                      {'id': 'other-$i', 'kind': 'plain'},
                  ]
                : [
                    notification(first, 'declined'),
                    notification(second, 'pending'),
                  ],
          ),
        ),
      );
      await c.load();
      await c.loadMore();
      expect(c.items, hasLength(21));
      expect(c.items.first.friendRequest!.status, FriendRequestStatus.declined);
      expect(c.items.last.friendRequest!.requestId, second);
    },
  );

  test(
    'Friends declines and cancels the captured occurrence, not another request for the same person',
    () async {
      final posted = <Map<String, Object?>>[];
      final api = apiFor((r) async {
        if (r.url.path.endsWith('/requests')) {
          return jsonResponse({
            'incoming': [
              {'requestId': first, 'userId': 'alice', 'username': 'Alice'},
            ],
            'outgoing': [
              {'requestId': second, 'userId': 'alice', 'username': 'Alice'},
            ],
          });
        }
        if (r.url.path.endsWith('/resolve')) {
          posted.add({'path': r.url.path, 'body': jsonDecode(r.body)});
          return jsonResponse(
            r.url.path.contains(first)
                ? occurrence(first, 'declined')
                : occurrence(second, 'cancelled'),
          );
        }
        return jsonResponse([]);
      });
      final c = FriendsController(FriendRepository(api), 'bob');
      addTearDown(c.dispose);
      await c.load();
      final incoming = c.requests.incoming.single;
      final outgoing = c.requests.outgoing.single;
      await c.resolve(incoming, FriendRequestDecision.decline);
      expect(c.requests.incoming, isEmpty);
      expect(c.requests.outgoing.single.requestId, second);
      await c.resolve(outgoing, FriendRequestDecision.cancel);
      expect(c.requests.outgoing, isEmpty);
      expect(posted, [
        {
          'path': '/api/v1.0/Friend/bob/requests/$first/resolve',
          'body': {'decision': 'decline'},
        },
        {
          'path': '/api/v1.0/Friend/bob/requests/$second/resolve',
          'body': {'decision': 'cancel'},
        },
      ]);
    },
  );

  test(
    'public wire contract: each decision posts its exact ID and reads authoritative identity',
    () async {
      final bodies = <Object?>[];
      final paths = <String>[];
      final repo = FriendRepository(
        apiFor((r) async {
          paths.add('${r.method} ${r.url.path}');
          if (r.method == 'GET') {
            return jsonResponse(occurrence(first, 'pending'));
          }
          bodies.add(jsonDecode(r.body));
          return jsonResponse(
            occurrence(first, switch (bodies.length) {
              1 => 'accepted',
              2 => 'declined',
              _ => 'cancelled',
            }),
          );
        }),
      );
      final read = await repo.request('bob', first);
      expect((read as Ok<FriendRequestState>).value.pending, isTrue);
      for (final decision in FriendRequestDecision.values) {
        final result = await repo.resolve('bob', first, decision);
        expect(result, isA<Ok<FriendRequestState>>());
      }
      expect(paths, [
        'GET /api/v1.0/Friend/bob/requests/$first',
        for (var i = 0; i < 3; i++)
          'POST /api/v1.0/Friend/bob/requests/$first/resolve',
      ]);
      expect(bodies, [
        {'decision': 'accept'},
        {'decision': 'decline'},
        {'decision': 'cancel'},
      ]);
    },
  );

  test(
    'a success payload for a replacement ID or wrong decision is not success',
    () async {
      for (final body in [
        occurrence(second, 'accepted'),
        occurrence(first, 'pending'),
      ]) {
        final repo = FriendRepository(apiFor((_) async => jsonResponse(body)));
        expect(
          await repo.resolve('bob', first, FriendRequestDecision.accept),
          isA<Err<FriendRequestState>>(),
        );
      }
    },
  );

  test('PendingSubmit_DisablesBothAndCoalescesDoubleTap', () async {
    final response = Completer<http.Response>();
    var writes = 0;
    final c = inboxFor(
      apiFor((r) async {
        if (r.url.path.endsWith('/resolve')) {
          writes++;
          return response.future;
        }
        if (r.method == 'GET') {
          return jsonResponse([notification(first, 'pending')]);
        }
        return http.Response('', 204);
      }),
    );
    await c.load();
    final n = c.items.single;
    final action = c.answer(n, accept: true);
    expect(c.isBusy(first), isTrue);
    await c.answer(n, accept: false);
    response.complete(jsonResponse(occurrence(first, 'accepted')));
    await action;
    expect(writes, 1);
    expect(c.isBusy(first), isFalse);
    expect(c.items.single.friendRequest!.status, FriendRequestStatus.accepted);
  });

  test(
    'ResolveFailure_RemainsRetryableWithoutFalseSuccess and revalidates SAME occurrence',
    () async {
      final wire = <String>[];
      var posts = 0;
      final c = inboxFor(
        apiFor((r) async {
          wire.add('${r.method} ${r.url.path}');
          if (r.url.path.endsWith('/resolve')) {
            posts++;
            return posts == 1
                ? jsonResponse({'title': 'Unavailable', 'status': 503}, 503)
                : jsonResponse(occurrence(first, 'declined'));
          }
          if (r.url.path.endsWith('/requests/$first')) {
            return jsonResponse(occurrence(first, 'pending'));
          }
          if (r.method == 'GET') {
            return jsonResponse([notification(first, 'pending')]);
          }
          return http.Response('', 204);
        }),
      );
      await c.load();
      await c.answer(c.items.single, accept: false);
      expect(c.items.single.friendRequest!.pending, isTrue);
      expect(c.actionError!.status, 503);
      await c.answer(c.items.single, accept: false);
      expect(
        c.items.single.friendRequest!.status,
        FriendRequestStatus.declined,
      );
      final retry = wire.indexOf('GET /api/v1.0/Friend/bob/requests/$first');
      expect(retry, greaterThan(1));
      expect(
        wire[retry + 1],
        'POST /api/v1.0/Friend/bob/requests/$first/resolve',
      );
      expect(posts, 2);
    },
  );

  test(
    'uncertain commit revalidates Accepted before retry; never repeats mutation',
    () async {
      var posts = 0;
      final c = inboxFor(
        apiFor((r) async {
          if (r.url.path.endsWith('/resolve')) {
            posts++;
            throw http.ClientException('connection lost after commit');
          }
          if (r.url.path.endsWith('/requests/$first')) {
            return jsonResponse(occurrence(first, 'accepted'));
          }
          if (r.method == 'GET') {
            return jsonResponse([
              notification(first, 'pending'),
              notification(second, 'pending'),
            ]);
          }
          return http.Response('', 204);
        }),
      );
      await c.load();
      await c.answer(c.items.first, accept: true);
      expect(c.items.first.friendRequest!.pending, isTrue);
      await c.answer(c.items.first, accept: true);
      expect(posts, 1);
      expect(c.items.first.friendRequest!.status, FriendRequestStatus.accepted);
      expect(c.items.last.friendRequest!.pending, isTrue);
    },
  );

  test(
    'cancelled opposite occurrence conflict refreshes exact ID, never a newer Pending',
    () async {
      final reads = <String>[];
      final c = inboxFor(
        apiFor((r) async {
          if (r.url.path.endsWith('/resolve')) return conflict();
          reads.add(r.url.path);
          if (r.url.path.endsWith('/requests/$first')) {
            return jsonResponse(occurrence(first, 'cancelled'));
          }
          return jsonResponse([
            notification(first, 'pending'),
            notification(second, 'pending'),
          ]);
        }),
      );
      await c.load();
      await c.answer(c.items.first, accept: true);
      expect(
        c.items.first.friendRequest!.status,
        FriendRequestStatus.cancelled,
      );
      expect(c.items.last.friendRequest!.pending, isTrue);
      expect(c.actionError!.type, endsWith('/v1/friend_request_resolved'));
      expect(reads.last, '/api/v1.0/Friend/bob/requests/$first');
    },
  );

  test(
    'missing occurrence becomes unavailable, not an inferred historical decision',
    () async {
      final c = inboxFor(
        apiFor((r) async {
          if (r.url.path.contains('/requests/')) {
            return jsonResponse({'status': 404, 'title': 'Missing'}, 404);
          }
          return jsonResponse([
            notification(first, 'pending'),
            notification(second, 'pending'),
          ]);
        }),
      );
      await c.load();
      await c.answer(c.items.first, accept: true);
      expect(
        c.items.first.friendRequest!.status,
        FriendRequestStatus.unavailable,
      );
      expect(c.items.last.friendRequest!.pending, isTrue);
    },
  );

  test(
    'LatePendingFetch_CannotUndoTerminal and MarkReadFailure_DoesNotUndoResolution',
    () async {
      final late = Completer<http.Response>();
      var lists = 0;
      final c = inboxFor(
        apiFor((r) async {
          if (r.url.path.endsWith('/resolve')) {
            return jsonResponse(occurrence(first, 'accepted'));
          }
          if (r.url.path.endsWith('/read')) {
            return jsonResponse({'status': 503, 'title': 'Read failed'}, 503);
          }
          if (++lists == 2) return late.future;
          return jsonResponse([notification(first, 'pending')]);
        }),
      );
      await c.load();
      final oldFetch = c.load();
      await Future<void>.delayed(Duration.zero);
      await c.answer(c.items.single, accept: true);
      late.complete(jsonResponse([notification(first, 'pending')]));
      await oldFetch;
      expect(
        c.items.single.friendRequest!.status,
        FriendRequestStatus.accepted,
      );
      expect(c.actionError!.displayMessage, 'Read failed');
    },
  );

  test(
    'Friends re-fetch removes accepted incoming AND cancelled opposite outgoing; stale reads cannot restore either',
    () async {
      final late = Completer<http.Response>();
      var lists = 0;
      var accepted = false;
      final api = apiFor((r) async {
        if (r.url.path.endsWith('/resolve')) {
          expect(r.url.path, endsWith('/requests/$first/resolve'));
          accepted = true;
          return jsonResponse(occurrence(first, 'accepted'));
        }
        if (r.url.path.endsWith('/requests')) {
          if (++lists == 2) return late.future;
          return jsonResponse({
            'incoming': accepted
                ? []
                : [
                    {
                      'requestId': first,
                      'userId': 'alice',
                      'username': 'Alice',
                    },
                  ],
            'outgoing': accepted
                ? []
                : [
                    {
                      'requestId': second,
                      'userId': 'alice',
                      'username': 'Alice',
                    },
                  ],
          });
        }
        return jsonResponse([]);
      });
      final c = FriendsController(FriendRepository(api), 'bob');
      addTearDown(c.dispose);
      await c.load();
      final oldFetch = c.load();
      await Future<void>.delayed(Duration.zero);
      await c.resolve(c.requests.incoming.single, FriendRequestDecision.accept);
      late.complete(
        jsonResponse({
          'incoming': [
            {'requestId': first, 'userId': 'alice', 'username': 'Alice'},
          ],
          'outgoing': [
            {'requestId': second, 'userId': 'alice', 'username': 'Alice'},
          ],
        }),
      );
      await oldFetch;
      expect(c.requests.incoming, isEmpty);
      expect(c.requests.outgoing, isEmpty);
    },
  );
}
