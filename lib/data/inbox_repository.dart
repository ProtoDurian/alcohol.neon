import '../core/problem.dart';
import '../networking/api_client.dart';
import 'friend_repository.dart';

/// One inbox notification. [data] is the JSON text the app uses for the tap
/// action (its shape depends on [kind]).
///
/// Hand-rolled (not `generated/zinc`): pichu's checked-in OpenAPI spec predates
/// the Inbox endpoints (zinc ≥ 1.39). Fold into the generated models on the
/// next `swagger_parser` regeneration.
class InboxNotificationRes {
  final String id;
  final String kind;
  final String title;
  final String body;
  final String? actorUserId;
  final String? data;
  final DateTime? createdAtUtc;
  final DateTime? readAtUtc;
  final FriendRequestState? friendRequest;

  const InboxNotificationRes({
    required this.id,
    required this.kind,
    required this.title,
    required this.body,
    this.actorUserId,
    this.data,
    this.createdAtUtc,
    this.readAtUtc,
    this.friendRequest,
  });

  bool get read => readAtUtc != null;

  InboxNotificationRes copyWith({
    DateTime? readAtUtc,
    FriendRequestState? friendRequest,
  }) => InboxNotificationRes(
    id: id,
    kind: kind,
    title: title,
    body: body,
    actorUserId: actorUserId,
    data: data,
    createdAtUtc: createdAtUtc,
    readAtUtc: readAtUtc ?? this.readAtUtc,
    friendRequest: friendRequest ?? this.friendRequest,
  );

  factory InboxNotificationRes.fromJson(Map<String, Object?> json) =>
      InboxNotificationRes(
        id: json['id'] as String,
        kind: json['kind'] as String? ?? '',
        title: json['title'] as String? ?? '',
        body: json['body'] as String? ?? '',
        actorUserId: json['actorUserId'] as String?,
        data: json['data'] as String?,
        createdAtUtc: DateTime.tryParse(json['createdAtUtc'] as String? ?? ''),
        readAtUtc: DateTime.tryParse(json['readAtUtc'] as String? ?? ''),
        friendRequest: switch (json['friendRequest']) {
          final Map<String, Object?> value => FriendRequestState.fromJson(
            value,
          ),
          _ => null,
        },
      );
}

/// zinc `/Inbox` endpoints (newest first; `limit` 1..50).
class InboxRepository {
  final ApiClient _api;
  InboxRepository(this._api);

  static const _base = '/api/v1.0/Inbox';

  Future<Result<List<InboxNotificationRes>>> list(
    String userId, {
    bool? unreadOnly,
    int? limit,
    int? skip,
  }) {
    return _api.get(
      '$_base/$userId',
      (j) => (j as List<dynamic>)
          .map((e) => InboxNotificationRes.fromJson(e as Map<String, Object?>))
          .toList(),
      query: {'unreadOnly': unreadOnly, 'limit': limit, 'skip': skip},
    );
  }

  Future<Result<int>> unreadCount(String userId) {
    return _api.get(
      '$_base/$userId/unread-count',
      (j) => ((j as Map<String, Object?>)['count'] as num?)?.toInt() ?? 0,
    );
  }

  /// 204 (also when already read).
  Future<Result<void>> markRead(String userId, String id) {
    return _api.post('$_base/$userId/$id/read', null, (_) {});
  }

  /// Returns how many were unread and are now read.
  Future<Result<int>> markAllRead(String userId) {
    return _api.post(
      '$_base/$userId/read-all',
      null,
      (j) => ((j as Map<String, Object?>?)?['count'] as num?)?.toInt() ?? 0,
    );
  }
}
