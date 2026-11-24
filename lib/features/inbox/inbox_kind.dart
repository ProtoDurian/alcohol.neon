import 'dart:convert';

import '../../data/friend_repository.dart';
import '../../data/inbox_repository.dart';

/// What a notification lets the user do, decoded from its `kind` and its
/// `data` JSON text. Unknown kinds or unreadable data are [PlainNotice].
sealed class InboxKind {
  const InboxKind();
}

/// Both request kinds use the server's linked occurrence, never sender data.
class FriendRequestNotice extends InboxKind {
  final FriendRequestState state;
  const FriendRequestNotice(this.state);
}

/// `friend_accepted` `{ friendUserId }`.
class FriendAcceptedNotice extends InboxKind {
  final String friendUserId;
  const FriendAcceptedNotice(this.friendUserId);
}

/// `friend_missed` `{ habitId, userId, localDate }`.
class FriendMissedNotice extends InboxKind {
  final String userId;
  final String? habitId;
  final String? localDate;
  const FriendMissedNotice(this.userId, {this.habitId, this.localDate});
}

class PlainNotice extends InboxKind {
  const PlainNotice();
}

InboxKind inboxKindOf(InboxNotificationRes n) {
  Map<String, Object?> data;
  try {
    final decoded = n.data == null ? null : jsonDecode(n.data!);
    data = decoded is Map<String, Object?> ? decoded : const {};
  } catch (_) {
    data = const {};
  }
  String? str(String key) {
    final v = data[key];
    return v is String && v.isNotEmpty ? v : null;
  }

  switch (n.kind) {
    case 'friend_request':
    case 'friend_request_resolved':
      return FriendRequestNotice(
        n.friendRequest ?? FriendRequestState.unavailable,
      );
    case 'friend_accepted':
      final friend = str('friendUserId') ?? n.actorUserId;
      return friend == null
          ? const PlainNotice()
          : FriendAcceptedNotice(friend);
    case 'friend_missed':
      final user = str('userId') ?? n.actorUserId;
      return user == null
          ? const PlainNotice()
          : FriendMissedNotice(
              user,
              habitId: str('habitId'),
              localDate: str('localDate'),
            );
    default:
      return const PlainNotice();
  }
}
