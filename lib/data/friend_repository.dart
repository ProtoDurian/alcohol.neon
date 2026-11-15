import '../core/problem.dart';
import '../networking/api_client.dart';

enum FriendRequestDecision { accept, decline, cancel }

enum FriendRequestStatus {
  pending,
  accepted,
  declined,
  cancelled,
  unavailable;

  String get label => switch (this) {
    pending => 'Pending',
    accepted => 'Accepted',
    declined => 'Declined',
    cancelled => 'Cancelled',
    unavailable => 'Request unavailable',
  };
}

/// An authoritative occurrence, also projected onto request notifications.
/// Missing identity on an older server is unavailable, never a pair lookup.
class FriendRequestState {
  final String? requestId;
  final FriendRequestStatus status;
  final DateTime? createdAtUtc;
  final DateTime? resolvedAtUtc;

  const FriendRequestState({
    required this.requestId,
    required this.status,
    this.createdAtUtc,
    this.resolvedAtUtc,
  });

  static const unavailable = FriendRequestState(
    requestId: null,
    status: FriendRequestStatus.unavailable,
  );

  static final _idPattern = RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
  );

  static String? idFrom(Object? value) =>
      value is String && _idPattern.hasMatch(value) ? value : null;

  bool get pending =>
      requestId != null && status == FriendRequestStatus.pending;
  bool get terminal => switch (status) {
    FriendRequestStatus.accepted ||
    FriendRequestStatus.declined ||
    FriendRequestStatus.cancelled => true,
    _ => false,
  };

  factory FriendRequestState.fromJson(Map<String, Object?> json) {
    final id = idFrom(json['requestId']);
    final status = switch (json['status']) {
      'pending' => FriendRequestStatus.pending,
      'accepted' => FriendRequestStatus.accepted,
      'declined' => FriendRequestStatus.declined,
      'cancelled' => FriendRequestStatus.cancelled,
      _ => FriendRequestStatus.unavailable,
    };
    return FriendRequestState(
      requestId: id,
      status: id == null ? FriendRequestStatus.unavailable : status,
      createdAtUtc: DateTime.tryParse(json['createdAtUtc'] as String? ?? ''),
      resolvedAtUtc: DateTime.tryParse(json['resolvedAtUtc'] as String? ?? ''),
    );
  }
}

// Hand-rolled models (not `generated/zinc`): pichu's checked-in OpenAPI spec
// predates the Friend endpoints (zinc ≥ 1.39). Fold into the generated models
// on the next `swagger_parser` regeneration.

/// A search hit. [relation] is `none` | `friend` | `outgoing` (you asked them)
/// | `incoming` (they asked you).
class FriendCandidateRes {
  final String userId;
  final String username;
  final String relation;

  const FriendCandidateRes({
    required this.userId,
    required this.username,
    required this.relation,
  });

  factory FriendCandidateRes.fromJson(Map<String, Object?> json) =>
      FriendCandidateRes(
        userId: json['userId'] as String,
        username: json['username'] as String? ?? '',
        relation: json['relation'] as String? ?? 'none',
      );
}

class FriendRes {
  final String userId;
  final String username;
  final DateTime? sinceUtc;

  const FriendRes({
    required this.userId,
    required this.username,
    this.sinceUtc,
  });

  factory FriendRes.fromJson(Map<String, Object?> json) => FriendRes(
    userId: json['userId'] as String,
    username: json['username'] as String? ?? '',
    sinceUtc: DateTime.tryParse(json['sinceUtc'] as String? ?? ''),
  );
}

/// The other person on a request: the sender for incoming, the recipient for
/// outgoing.
class FriendRequestRes {
  final String? requestId;
  final String userId;
  final String username;
  final DateTime? createdAtUtc;

  const FriendRequestRes({
    this.requestId,
    required this.userId,
    required this.username,
    this.createdAtUtc,
  });

  factory FriendRequestRes.fromJson(Map<String, Object?> json) =>
      FriendRequestRes(
        requestId: FriendRequestState.idFrom(json['requestId']),
        userId: json['userId'] as String,
        username: json['username'] as String? ?? '',
        createdAtUtc: DateTime.tryParse(json['createdAtUtc'] as String? ?? ''),
      );
}

class FriendRequestsRes {
  final List<FriendRequestRes> incoming;
  final List<FriendRequestRes> outgoing;

  const FriendRequestsRes({required this.incoming, required this.outgoing});

  static List<FriendRequestRes> _list(Object? raw) => [
    for (final e in (raw as List<dynamic>? ?? const []))
      FriendRequestRes.fromJson(e as Map<String, Object?>),
  ];

  factory FriendRequestsRes.fromJson(Map<String, Object?> json) =>
      FriendRequestsRes(
        incoming: _list(json['incoming']),
        outgoing: _list(json['outgoing']),
      );
}

/// The user's permanent invite. The app builds the link:
/// `https://t.lazytax.club/f/{code}`.
class FriendInviteRes {
  final String code;

  const FriendInviteRes({required this.code});

  factory FriendInviteRes.fromJson(Map<String, Object?> json) =>
      FriendInviteRes(code: json['code'] as String);
}

/// zinc `/Friend` endpoints, all scoped to the signed-in user.
class FriendRepository {
  final ApiClient _api;
  FriendRepository(this._api);

  static const _base = '/api/v1.0/Friend';

  /// Usernames starting with [q] (2+ characters, case-insensitive).
  Future<Result<List<FriendCandidateRes>>> search(
    String userId,
    String q, {
    int limit = 20,
  }) {
    return _api.get(
      '$_base/$userId/search',
      (j) => (j as List<dynamic>)
          .map((e) => FriendCandidateRes.fromJson(e as Map<String, Object?>))
          .toList(),
      query: {'q': q, 'limit': limit},
    );
  }

  Future<Result<List<FriendRes>>> friends(String userId) {
    return _api.get(
      '$_base/$userId',
      (j) => (j as List<dynamic>)
          .map((e) => FriendRes.fromJson(e as Map<String, Object?>))
          .toList(),
    );
  }

  Future<Result<void>> remove(String userId, String friendUserId) {
    return _api.delete('$_base/$userId/$friendUserId');
  }

  Future<Result<FriendRequestsRes>> requests(String userId) {
    return _api.get(
      '$_base/$userId/requests',
      (j) => FriendRequestsRes.fromJson(j as Map<String, Object?>),
    );
  }

  /// Sends a request; returns the new relation (`friend` when they had
  /// already asked you, which accepts theirs).
  Future<Result<String>> sendRequest(String userId, String toUserId) {
    return _api.post('$_base/$userId/requests', {
      'toUserId': toUserId,
    }, (j) => (j as Map<String, Object?>)['relation'] as String? ?? 'outgoing');
  }

  Future<Result<FriendRequestState>> request(String userId, String requestId) =>
      _api.get(
        '$_base/$userId/requests/$requestId',
        (j) => _occurrence(j, requestId),
      );

  Future<Result<FriendRequestState>> resolve(
    String userId,
    String requestId,
    FriendRequestDecision decision,
  ) => _api.post(
    '$_base/$userId/requests/$requestId/resolve',
    {'decision': decision.name},
    (j) {
      final state = _occurrence(j, requestId);
      final expected = switch (decision) {
        FriendRequestDecision.accept => FriendRequestStatus.accepted,
        FriendRequestDecision.decline => FriendRequestStatus.declined,
        FriendRequestDecision.cancel => FriendRequestStatus.cancelled,
      };
      if (state.status != expected) {
        throw const FormatException('Unexpected friend request decision');
      }
      return state;
    },
  );

  static FriendRequestState _occurrence(Object? json, String requestId) {
    final state = FriendRequestState.fromJson(json as Map<String, Object?>);
    if (state.requestId != requestId ||
        state.status == FriendRequestStatus.unavailable) {
      throw const FormatException('Unexpected friend request identity');
    }
    return state;
  }

  Future<Result<FriendInviteRes>> createInvite(String userId) {
    return _api.post(
      '$_base/$userId/invites',
      null,
      (j) => FriendInviteRes.fromJson(j as Map<String, Object?>),
    );
  }

  /// 404 for an unknown or expired code, 400 for your own.
  /// Uses someone's invite: sends its owner a friend request. Returns the
  /// relation like [sendRequest]: `outgoing` (request sent) or `friend` (they
  /// had already asked you). Older zinc befriends straight away and returns a
  /// FriendRes without `relation`, which reads as `friend`.
  Future<Result<String>> acceptInvite(String userId, String code) {
    return _api.post(
      '$_base/$userId/invites/${Uri.encodeComponent(code)}/accept',
      null,
      (j) => (j as Map<String, Object?>?)?['relation'] as String? ?? 'friend',
    );
  }
}
