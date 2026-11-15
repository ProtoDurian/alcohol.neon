import 'package:flutter/foundation.dart';

import '../../core/problem.dart';
import '../../data/friend_repository.dart';
import '../../data/inbox_repository.dart';

enum InboxPhase { loading, ready, error }

/// State for the inbox screen: newest-first pages, mark read, and the inline
/// friend-request answers.
class InboxController extends ChangeNotifier {
  final InboxRepository _inbox;
  final FriendRepository _friends;
  final String _userId;

  static const pageSize = 20;

  InboxController(this._inbox, this._friends, this._userId);

  InboxPhase _phase = InboxPhase.loading;
  Problem? _error;
  Problem? _actionError;
  List<InboxNotificationRes> _items = const [];
  bool _hasMore = false;
  bool _loadingMore = false;
  final _busy = <String>{};
  final _retry = <String>{};
  // Only authoritative terminal results, to keep late Pending reads from
  // undoing an immutable decision. New controllers still fetch server truth.
  final _resolved = <String, FriendRequestState>{};
  int _loadSeq = 0;
  bool _disposed = false;

  InboxPhase get phase => _phase;
  Problem? get error => _error;
  Problem? get actionError => _actionError;
  List<InboxNotificationRes> get items => _items;
  bool get hasMore => _hasMore;
  bool get loadingMore => _loadingMore;
  bool get hasUnread => _items.any((n) => !n.read);
  bool isBusy(String id) => _busy.contains(id);

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  void clearActionError() {
    _actionError = null;
    _notify();
  }

  Future<void> load() async {
    final seq = ++_loadSeq;
    _error = null;
    _notify();
    final res = await _inbox.list(_userId, limit: pageSize, skip: 0);
    if (_disposed || seq != _loadSeq) return;
    switch (res) {
      case Ok(:final value):
        _items = value.map(_reconcile).toList();
        _hasMore = value.length == pageSize;
        _phase = InboxPhase.ready;
      case Err(:final problem):
        if (_phase == InboxPhase.ready) {
          _actionError = problem;
        } else {
          _phase = InboxPhase.error;
          _error = problem;
        }
    }
    _notify();
  }

  Future<void> loadMore() async {
    if (_loadingMore || !_hasMore) return;
    final seq = _loadSeq;
    _loadingMore = true;
    _notify();
    final res = await _inbox.list(
      _userId,
      limit: pageSize,
      skip: _items.length,
    );
    _loadingMore = false;
    if (_disposed) return;
    if (seq != _loadSeq) {
      _notify();
      return;
    }
    switch (res) {
      case Ok(:final value):
        final page = {for (final n in value) n.id: _reconcile(n)};
        _items = [
          for (final n in _items) page.remove(n.id) ?? _reconcile(n),
          ...page.values,
        ];
        _hasMore = value.length == pageSize;
      case Err(:final problem):
        _actionError = problem;
    }
    _notify();
  }

  void _setRead(String id) {
    final now = DateTime.now().toUtc();
    _items = [
      for (final n in _items)
        n.id == id && !n.read ? n.copyWith(readAtUtc: now) : n,
    ];
  }

  Future<void> markRead(InboxNotificationRes n) async {
    if (n.read) return;
    _setRead(n.id);
    _notify();
    final res = await _inbox.markRead(_userId, n.id);
    if (res case Err(:final problem)) {
      _actionError = problem;
      _notify();
    }
  }

  Future<void> markAllRead() async {
    final res = await _inbox.markAllRead(_userId);
    switch (res) {
      case Ok():
        for (final n in _items) {
          _setRead(n.id);
        }
      case Err(:final problem):
        _actionError = problem;
    }
    _notify();
  }

  InboxNotificationRes _reconcile(InboxNotificationRes n) {
    final state = n.friendRequest;
    if (state == null) return n;
    final known = _resolved[state.requestId];
    if (known != null) return n.copyWith(friendRequest: known);
    if (state.terminal) _resolved[state.requestId!] = state;
    return n;
  }

  void _setRequest(String id, FriendRequestState state) {
    if (state.terminal) _resolved[id] = state;
    _items = [
      for (final n in _items)
        n.friendRequest?.requestId == id ? n.copyWith(friendRequest: state) : n,
    ];
  }

  /// Accepts or declines this occurrence only. A failed attempt is revalidated
  /// by exact ID before retry; 404/409 never resolves a replacement request.
  Future<void> answer(InboxNotificationRes n, {required bool accept}) async {
    final state = n.friendRequest;
    final id = state?.requestId;
    if (id == null ||
        !state!.pending ||
        _resolved.containsKey(id) ||
        !_busy.add(id)) {
      return;
    }
    _actionError = null;
    _notify();
    if (_retry.contains(id)) {
      final current = await _friends.request(_userId, id);
      if (_disposed) return;
      switch (current) {
        case Ok(:final value) when value.pending:
          _retry.remove(id);
        case Ok(:final value):
          _setRequest(id, value);
          _busy.remove(id);
          _notify();
          await load();
          return;
        case Err(:final problem):
          if (problem.status == 404) {
            _setRequest(id, FriendRequestState.unavailable);
          }
          _actionError = problem;
          _busy.remove(id);
          _notify();
          return;
      }
    }
    final res = await _friends.resolve(
      _userId,
      id,
      accept ? FriendRequestDecision.accept : FriendRequestDecision.decline,
    );
    if (_disposed) return;
    switch (res) {
      case Ok(:final value):
        _retry.remove(id);
        _setRequest(id, value);
        _notify();
        await markRead(n);
        await load();
      case Err(:final problem):
        _retry.add(id);
        if (problem.status == 404 || problem.status == 409) {
          final current = await _friends.request(_userId, id);
          if (_disposed) return;
          switch (current) {
            case Ok(:final value):
              _setRequest(id, value);
            case Err():
              _setRequest(id, FriendRequestState.unavailable);
          }
        }
        _actionError = problem;
    }
    _busy.remove(id);
    _notify();
  }
}
